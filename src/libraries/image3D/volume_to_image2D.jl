"""
Volume → 2D image operators: projections and slices, the bridge from 3D
volumes to every 2D image library.

# Bundles

- bundle_image2DIntensity_fromVolume_factory
- bundle_image2DBinary_fromVolume_factory

The exhaustive operator list is on the Bundle Catalogue page.

# How this file is organised

Each operator is a *kernel* `kernel(vol, extra...) -> Matrix` (`Float64` for
intensity outputs, `Bool` for masks) wrapped by `_bridge_factory`. The
factory is a function of the 2D output type `I`; it defines methods accepting
any volume whose two remaining axes match `I`'s size (the collapsed axis can
have any length), then converts the matrix into pixels of `I`.

Each operator lists the *method forms* it supports (see `_bridge_factory`):
which pixel kind the volume may have and whether a scalar or a mask follows.
"""
module image3D_to_image2D

using ..UTCGP: FunctionBundle, append_method!
using ..UTCGP:
    BinaryPixel,
    IntensityPixel,
    SImageND,
    SizedImage,
    SizedImage2D,
    _get_image_pixel_type,
    _get_image_tuple_size,
    _get_image_type,
    _validate_factory_type
using ..image2D_object_common: clamp_unit, pixel_value, IsSet, AtLeast
using ..image2D_zoom: to_storage
using ..image3D_volume_common: voxel_values, voxel_foreground

fallback(args...) = return nothing

const _AXES_DOC = """
Axis `y` is dimension 1 (rows), `x` dimension 2 (columns), `z` dimension 3
(slices). Collapsing an axis leaves the other two in order: a `_z` result is
`(y, x)`, a `_y` result `(x, z)`, a `_x` result `(y, z)`. The factory is
specialised on the 2D output type and accepts any volume whose remaining axes
have that size, so non-cubic volumes work. Masks are binary volumes, or
intensity volumes thresholded at `0.5`; positions `s` are in `[0, 1]`.
"""

"""
    bundle_image2DIntensity_fromVolume_factory

Intensity images from intensity volumes.

- Projections: `proj_max_<a>` (maximum intensity projection), `proj_min_<a>`,
  `proj_mean_<a>`, `proj_std_<a>` (twice the standard deviation),
  `proj_argmax_<a>` (where along the axis the maximum is, `0` to `1`).
- Masked projections `(vol, mask)`: `proj_max_masked_<a>`,
  `proj_mean_masked_<a>` (only voxels inside the mask; `0` where none).
- Slices: `slice_center_<a>`, `slice_at_<a>(vol, s)`, `slice_brightest_<a>`
  (through the brightest voxel), `slice_centroid_<a>(vol, mask)` (through the
  mask's centroid), `slice_largest_<a>(vol, mask)` (where the mask's
  cross-section is largest).

`<a>` is `x`, `y` or `z`.

$_AXES_DOC
"""
const bundle_image2DIntensity_fromVolume_factory = FunctionBundle(fallback)

"""
    bundle_image2DBinary_fromVolume_factory

Masks from volumes.

- `proj_any_<a>`: a pixel is set when any voxel along the axis is (the
  silhouette); `proj_all_<a>`: when all are.
- `slice_center_<a>`, `slice_at_<a>(mask, s)`, `slice_largest_<a>`
  (largest cross-section).

Intensity volumes are thresholded at `0.5`, or at a threshold given as the
last argument of `proj_any_<a>(vol, t)`.

$_AXES_DOC
"""
const bundle_image2DBinary_fromVolume_factory = FunctionBundle(fallback)

# ---------------------------------------------------------------------------
# Kernels: 3D arrays → Float64 / Bool matrices
# ---------------------------------------------------------------------------

"Size of the 2D result when `axis` of a volume of size `dims` is collapsed."
_out_size(dims, axis) = axis == 1 ? (dims[2], dims[3]) : axis == 2 ? (dims[1], dims[3]) : (dims[1], dims[2])
"Position in the 2D result of voxel `(r, c, s)` when `axis` is collapsed."
@inline _plane(r, c, s, axis) = axis == 1 ? (c, s) : axis == 2 ? (r, s) : (r, c)
"Index of voxel `(r, c, s)` along `axis`."
@inline _along(r, c, s, axis) = axis == 1 ? r : axis == 2 ? c : s

"""
    _project(values, axis, init, step, finish) -> Matrix

Reduce `values` along `axis`: each output pixel starts at `init`, folds every
voxel of its line with `acc = step(acc, voxel)`, and ends as
`finish(acc, line_length)`. The loop runs over the volume in memory order
whatever the axis.
"""
function _project(values::Array{Float64,3}, axis::Int, init, step::S, finish::F) where {S,F}
    out = fill(init, _out_size(size(values), axis))
    h, w, d = size(values)
    @inbounds for s in 1:d, c in 1:w, r in 1:h
        i, j = _plane(r, c, s, axis)
        out[i, j] = step(out[i, j], values[r, c, s])
    end
    n = size(values, axis)
    return [finish(x, n) for x in out]
end

"Maximum along the axis."
_proj_max(v, axis) = _project(v, axis, -Inf, max, (x, n) -> x)
"Minimum along the axis."
_proj_min(v, axis) = _project(v, axis, Inf, min, (x, n) -> x)
"Mean along the axis."
_proj_mean(v, axis) = _project(v, axis, 0.0, +, (x, n) -> x / n)

"Twice the standard deviation along the axis (from the mean and the mean of squares)."
function _proj_std(v, axis)
    mean = _proj_mean(v, axis)
    mean_of_squares = _project(v, axis, 0.0, (acc, x) -> acc + x * x, (x, n) -> x / n)
    return map((m, m2) -> 2.0 * sqrt(max(m2 - m^2, 0.0)), mean, mean_of_squares)
end

"Normalised position (`0` = first, `1` = last voxel) of the maximum along the axis; first maximum on ties."
function _proj_argmax(v, axis)
    dims = size(v)
    best = fill(-Inf, _out_size(dims, axis))
    best_index = zeros(Int, _out_size(dims, axis))
    @inbounds for s in 1:dims[3], c in 1:dims[2], r in 1:dims[1]
        i, j = _plane(r, c, s, axis)
        x = v[r, c, s]
        if x > best[i, j]
            best[i, j] = x
            best_index[i, j] = _along(r, c, s, axis)
        end
    end
    n = dims[axis]
    return n <= 1 ? fill(0.5, size(best)) : (best_index .- 1) ./ (n - 1)
end

"Maximum (`mode = :max`) or mean (`:mean`) along the axis over the voxels inside `fg`; `0` where a line has none."
function _proj_masked(v, fg, axis, mode::Symbol)
    dims = size(v)
    acc = fill(mode === :max ? -Inf : 0.0, _out_size(dims, axis))
    count = zeros(Int, _out_size(dims, axis))
    @inbounds for s in 1:dims[3], c in 1:dims[2], r in 1:dims[1]
        fg[r, c, s] || continue
        i, j = _plane(r, c, s, axis)
        x = v[r, c, s]
        acc[i, j] = mode === :max ? max(acc[i, j], x) : acc[i, j] + x
        count[i, j] += 1
    end
    return map((a, n) -> n == 0 ? 0.0 : (mode === :max ? a : a / n), acc, count)
end

"Index of the slice at normalised position `u` (`0` = first, `1` = last) among `n`."
_slice_index(n, u) = clamp(round(Int, 1 + u * (n - 1)), 1, n)

"Slice `k` of a 3D array across `axis` (a copy)."
function _slice(a::AbstractArray{T,3}, axis::Int, k::Int) where {T}
    return axis == 1 ? a[k, :, :] : axis == 2 ? a[:, k, :] : a[:, :, k]
end

"Index along `axis` of the brightest voxel (first one on ties)."
function _brightest_index(v, axis)
    index = argmax(v)
    return Tuple(index)[axis]
end

"Index along `axis` of the mask's centroid; the middle slice for an empty mask."
function _centroid_index(fg, axis)
    total = 0
    weighted = 0
    @inbounds for idx in CartesianIndices(fg)
        fg[idx] || continue
        total += 1
        weighted += Tuple(idx)[axis]
    end
    return total == 0 ? cld(size(fg, axis), 2) : round(Int, weighted / total)
end

"Index along `axis` of the slice with the most mask voxels; the middle slice for an empty mask."
function _largest_index(fg, axis)
    n = size(fg, axis)
    counts = zeros(Int, n)
    @inbounds for idx in CartesianIndices(fg)
        fg[idx] && (counts[Tuple(idx)[axis]] += 1)
    end
    return maximum(counts) == 0 ? cld(n, 2) : argmax(counts)
end

"Any / all voxels set along the axis (2D result)."
_proj_any(fg, axis) = dropdims(any(fg; dims = axis); dims = axis)
_proj_all(fg, axis) = dropdims(all(fg; dims = axis); dims = axis)

# Volume → kernel input (scratch buffers, valid until the next call in the same task).
"Voxel values of an intensity volume."
_values(vol) = voxel_values(:bridge_values, vol.img)
"Foreground of a volume: binary voxels as they are, intensity voxels at or above `t`."
_fg(vol::SizedImage{S,<:BinaryPixel}) where {S} = voxel_foreground(:bridge_fg, vol.img, IsSet())
_fg(vol::SizedImage{S,<:IntensityPixel}, t = 0.5) where {S} = voxel_foreground(:bridge_fg, vol.img, AtLeast(t))

# ---------------------------------------------------------------------------
# Factories
# ---------------------------------------------------------------------------

"Convert a kernel result into a pixel matrix of the output type."
_to_image(::Type{IntensityPixel{T}}, m::AbstractMatrix{Float64}) where {T} = [IntensityPixel{T}(to_storage(T, x)) for x in m]
_to_image(::Type{BinaryPixel{T}}, m::AbstractMatrix{Bool}) where {T} = BinaryPixel{T}.(m)

"""
Size pattern (an expression) of the volumes accepted when `axis` is
collapsed into an `(A, B)` image: the collapsed axis is the free type
variable `N`, e.g. `Tuple{A,B,N}` for `axis = 3`.
"""
function _volume_pattern(axis::Int, A, B)
    axis == 1 && return :(Tuple{N,$A,$B})
    axis == 2 && return :(Tuple{$A,N,$B})
    return :(Tuple{$A,$B,N})
end

"""
    _factory_setup(I, operator) -> (pixel_type, size_type, A, B, function_name)

Validate the 2D output type `I` and return its pixel type, its size as a
tuple type, its two sizes `A × B`, and the name of the specialised function.
"""
function _factory_setup(::Type{I}, operator::Symbol) where {I}
    _validate_factory_type(_get_image_type(I))
    size_type = _get_image_tuple_size(I)
    A, B = size_type.parameters
    return _get_image_pixel_type(I), size_type, A, B, Symbol(operator, :_, Symbol(I))
end

"""
    _bridge_factory(I, operator, axis, kernel, forms) -> Function

Define the methods of `operator` for the 2D output type `I`; the volume's
other axes must match `I`'s size. `forms` selects the methods:

| Form | Method | Kernel call |
|:--|:--|:--|
| `:intensity` | `op(intensity_vol)` | `kernel(vol)` |
| `:binary` | `op(binary_vol)` | `kernel(vol)` |
| `:intensity_scalar` | `op(intensity_vol, u)` | `kernel(vol, clamp_unit(u))` |
| `:binary_scalar` | `op(binary_vol, u)` | `kernel(vol, clamp_unit(u))` |
| `:intensity_mask` | `op(intensity_vol, mask)`, mask binary or intensity (at `0.5`) of the same size | `kernel(vol, fg)` |

Calling it again for the same `I` adds methods to the same function, which
is how an operator gets forms with different kernels.
"""
function _bridge_factory(::Type{I}, operator::Symbol, axis::Int, kernel::K, forms) where {I,K}
    pixel_type, size_type, A, B, name = _factory_setup(I, operator)
    volume_size = _volume_pattern(axis, A, B)
    fn = nothing
    for form in forms
        f = if form === :intensity
            @eval function $name(vol::Vol, args::Vararg{Any}) where {N,VolStorage,Vol<:SizedImage{$volume_size,IntensityPixel{VolStorage}}}
                return SImageND(_to_image($pixel_type, $kernel(vol)), $size_type)
            end
        elseif form === :binary
            @eval function $name(vol::Vol, args::Vararg{Any}) where {N,VolBool,Vol<:SizedImage{$volume_size,BinaryPixel{VolBool}}}
                return SImageND(_to_image($pixel_type, $kernel(vol)), $size_type)
            end
        elseif form === :intensity_scalar
            @eval function $name(vol::Vol, u::Real, args::Vararg{Any}) where {N,VolStorage,Vol<:SizedImage{$volume_size,IntensityPixel{VolStorage}}}
                return SImageND(_to_image($pixel_type, $kernel(vol, clamp_unit(u))), $size_type)
            end
        elseif form === :binary_scalar
            @eval function $name(vol::Vol, u::Real, args::Vararg{Any}) where {N,VolBool,Vol<:SizedImage{$volume_size,BinaryPixel{VolBool}}}
                return SImageND(_to_image($pixel_type, $kernel(vol, clamp_unit(u))), $size_type)
            end
        elseif form === :intensity_mask
            # The size pattern lets the volume and mask differ along the collapsed axis, hence the check.
            @eval function $name(vol::Vol, mask::Mask, args::Vararg{Any}) where {N,VolStorage,Vol<:SizedImage{$volume_size,IntensityPixel{VolStorage}},MaskBool,Mask<:SizedImage{$volume_size,BinaryPixel{MaskBool}}}
                size(vol) == size(mask) || throw(DimensionMismatch("volume and mask must have the same size"))
                return SImageND(_to_image($pixel_type, $kernel(vol, voxel_foreground(:bridge_mask, mask.img, IsSet()))), $size_type)
            end
            @eval function $name(vol::Vol, mask::Mask, args::Vararg{Any}) where {N,VolStorage,Vol<:SizedImage{$volume_size,IntensityPixel{VolStorage}},MaskStorage,Mask<:SizedImage{$volume_size,IntensityPixel{MaskStorage}}}
                size(vol) == size(mask) || throw(DimensionMismatch("volume and mask must have the same size"))
                return SImageND(_to_image($pixel_type, $kernel(vol, voxel_foreground(:bridge_mask, mask.img, AtLeast(0.5)))), $size_type)
            end
        end
        fn === nothing && (fn = f)
    end
    return fn
end

# ---------------------------------------------------------------------------
# Registration
# ---------------------------------------------------------------------------

"""
    _define!(bundle, kind, operator, builder, description)

Define the factory `<operator>_<kind>_image2D_factory(I) = builder(I)`,
document it and register it in `bundle`.
"""
function _define!(bundle, kind::Symbol, operator::Symbol, builder, description::String)
    factory_name = Symbol(operator, :_, kind, :_image2D_factory)
    @eval function $factory_name(output_type::Type{I}) where {S1,S2,P,I<:SizedImage2D{S1,S2,P}}
        return $builder(output_type)
    end
    doc = """
        $(factory_name)(::Type{I})

    Specialises `$operator`. $description
    """
    @eval @doc $doc $factory_name
    append_method!(bundle, getfield(@__MODULE__, factory_name), operator; description = description)
end

# Builders return `output_type -> factory(output_type, …)`. They are functions,
# not inline closures, so each closure captures its own arguments: `op` is
# reassigned several times in the loop body below, and an inline closure
# would see its last value.
"Builder for an operator with a single kernel."
_builder(op, axis, kernel, forms) = I -> _bridge_factory(I, op, axis, kernel, forms)
"Builder for `proj_any`: thresholds at `0.5` with one argument, at `t` with `(vol, t)`."
_proj_any_builder(op, axis) = I -> begin
    fn = _bridge_factory(I, op, axis, vol -> _proj_any(_fg(vol), axis), (:binary, :intensity))
    _bridge_factory(I, op, axis, (vol, t) -> _proj_any(_fg(vol, t), axis), (:intensity_scalar,))
    fn
end

const _INTENSITY = bundle_image2DIntensity_fromVolume_factory
const _BINARY = bundle_image2DBinary_fromVolume_factory

for (axis, letter) in ((1, :y), (2, :x), (3, :z))
    # --- Intensity: projections and slices of the volume alone.
    for (stem, kernel, what) in (
            (:proj_max, vol -> _proj_max(_values(vol), axis), "maximum intensity projection"),
            (:proj_min, vol -> _proj_min(_values(vol), axis), "minimum intensity projection"),
            (:proj_mean, vol -> _proj_mean(_values(vol), axis), "mean intensity projection"),
            (:proj_std, vol -> _proj_std(_values(vol), axis), "twice the standard deviation along the axis"),
            (:proj_argmax, vol -> _proj_argmax(_values(vol), axis), "position (0 to 1) of the maximum along the axis"),
            (:slice_center, vol -> _slice(_values(vol), axis, cld(size(vol, axis), 2)), "central slice"),
            (:slice_brightest, vol -> (v = _values(vol); _slice(v, axis, _brightest_index(v, axis))), "slice through the brightest voxel"),
        )
        op = Symbol(stem, :_, letter)
        _define!(_INTENSITY, :intensity, op, _builder(op, axis, kernel, (:intensity,)), "The $what along $letter.")
    end
    op = Symbol(:slice_at_, letter)
    _define!(_INTENSITY, :intensity, op,
        _builder(op, axis, (vol, u) -> _slice(_values(vol), axis, _slice_index(size(vol, axis), u)), (:intensity_scalar,)),
        "The slice at normalised position s along $letter.")

    # --- Intensity: guided by a mask.
    for (stem, kernel, what) in (
            (:proj_max_masked, (vol, fg) -> _proj_masked(_values(vol), fg, axis, :max), "maximum projection over the mask's voxels"),
            (:proj_mean_masked, (vol, fg) -> _proj_masked(_values(vol), fg, axis, :mean), "mean projection over the mask's voxels"),
            (:slice_centroid, (vol, fg) -> _slice(_values(vol), axis, _centroid_index(fg, axis)), "slice through the mask's centroid"),
            (:slice_largest, (vol, fg) -> _slice(_values(vol), axis, _largest_index(fg, axis)), "slice where the mask's cross-section is largest"),
        )
        op = Symbol(stem, :_, letter)
        _define!(_INTENSITY, :intensity, op, _builder(op, axis, kernel, (:intensity_mask,)), "The $what, along $letter.")
    end

    # --- Binary: projections and slices of masks (intensity volumes thresholded at 0.5).
    op = Symbol(:proj_any_, letter)
    _define!(_BINARY, :binary, op, _proj_any_builder(op, axis),
        "Silhouette along $letter: set where any voxel is (intensity at 0.5 or a given threshold).")
    op = Symbol(:proj_all_, letter)
    _define!(_BINARY, :binary, op,
        _builder(op, axis, vol -> _proj_all(_fg(vol), axis), (:binary, :intensity)),
        "Set where every voxel along $letter is.")
    op = Symbol(:slice_center_, letter)
    _define!(_BINARY, :binary, op,
        _builder(op, axis, vol -> _slice(_fg(vol), axis, cld(size(vol, axis), 2)), (:binary, :intensity)),
        "Central slice of the mask along $letter.")
    op = Symbol(:slice_at_, letter)
    _define!(_BINARY, :binary, op,
        _builder(op, axis, (vol, u) -> _slice(_fg(vol), axis, _slice_index(size(vol, axis), u)), (:binary_scalar, :intensity_scalar)),
        "Slice of the mask at normalised position s along $letter.")
    op = Symbol(:slice_largest_, letter)
    _define!(_BINARY, :binary, op,
        _builder(op, axis, vol -> (fg = _fg(vol); _slice(fg, axis, _largest_index(fg, axis))), (:binary, :intensity)),
        "Largest cross-section of the mask along $letter.")
end

end
