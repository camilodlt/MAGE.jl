"""
Volume → 2D image operators: projections and slices, the bridge from 3D
volumes to every 2D image library.

# Bundles

- bundle_image2DIntensity_fromVolume_factory
- bundle_image2DBinary_fromVolume_factory

The exhaustive operator list is on the Bundle Catalogue page.
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
using ..image2D_object_common: _unit, _value, IsSet, AtLeast
using ..image2D_zoom: _store
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

_out_size(dims, axis) = axis == 1 ? (dims[2], dims[3]) : axis == 2 ? (dims[1], dims[3]) : (dims[1], dims[2])
@inline _plane(r, c, s, axis) = axis == 1 ? (c, s) : axis == 2 ? (r, s) : (r, c)
@inline _along(r, c, s, axis) = axis == 1 ? r : axis == 2 ? c : s

"Reduce `values` along `axis` with `init`, `step(acc, v)` and `finish(acc, n)`."
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

_proj_max(v, axis) = _project(v, axis, -Inf, max, (x, n) -> x)
_proj_min(v, axis) = _project(v, axis, Inf, min, (x, n) -> x)
_proj_mean(v, axis) = _project(v, axis, 0.0, +, (x, n) -> x / n)

function _proj_std(v, axis)
    m = _proj_mean(v, axis)
    sq = _project(v, axis, 0.0, (acc, x) -> acc + x * x, (x, n) -> x / n)
    return map((x, y) -> 2.0 * sqrt(max(y - x^2, 0.0)), m, sq)
end

function _proj_argmax(v, axis)
    dims = size(v)
    best = fill(-Inf, _out_size(dims, axis))
    where_ = zeros(Int, _out_size(dims, axis))
    @inbounds for s in 1:dims[3], c in 1:dims[2], r in 1:dims[1]
        i, j = _plane(r, c, s, axis)
        x = v[r, c, s]
        if x > best[i, j]
            best[i, j] = x
            where_[i, j] = _along(r, c, s, axis)
        end
    end
    n = dims[axis]
    return n <= 1 ? fill(0.5, size(best)) : (where_ .- 1) ./ (n - 1)
end

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

"Index of the slice along `axis` at normalised position `u`."
_slice_index(n, u) = clamp(round(Int, 1 + u * (n - 1)), 1, n)

function _slice(a::AbstractArray{T,3}, axis::Int, k::Int) where {T}
    return axis == 1 ? a[k, :, :] : axis == 2 ? a[:, k, :] : a[:, :, k]
end

function _brightest_index(v, axis)
    index = argmax(v)
    return Tuple(index)[axis]
end

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

function _largest_index(fg, axis)
    n = size(fg, axis)
    counts = zeros(Int, n)
    @inbounds for idx in CartesianIndices(fg)
        fg[idx] && (counts[Tuple(idx)[axis]] += 1)
    end
    return maximum(counts) == 0 ? cld(n, 2) : argmax(counts)
end

# ---------------------------------------------------------------------------
# Factories
# ---------------------------------------------------------------------------

_to_image(::Type{IntensityPixel{T}}, m::AbstractMatrix{Float64}) where {T} = [IntensityPixel{T}(_store(T, x)) for x in m]
_to_image(::Type{BinaryPixel{T}}, m::AbstractMatrix{Bool}) where {T} = BinaryPixel{T}.(m)

"Volume type patterns whose remaining axes are `(A, B)` after removing `axis`."
function _volume_pattern(axis::Int, A, B)
    axis == 1 && return :(Tuple{N,$A,$B})
    axis == 2 && return :(Tuple{$A,N,$B})
    return :(Tuple{$A,$B,N})
end

function _prelude(::Type{I}, operator::Symbol) where {I}
    IT = _get_image_type(I)
    _validate_factory_type(IT)
    S = _get_image_tuple_size(I)
    A, B = S.parameters
    return _get_image_pixel_type(I), S, A, B, Symbol(operator, :_, Symbol(I))
end

"""
Specialise a volume → 2D operator. `kernel(vol::SizedImage, extra...)`
returns a matrix; `forms` lists the method shapes to define.
"""
function _bridge_factory(::Type{I}, operator::Symbol, axis::Int, kernel::K, forms) where {I,K}
    PT, S, A, B, name = _prelude(I, operator)
    V = _volume_pattern(axis, A, B)
    fn = nothing
    for form in forms
        f = if form === :intensity
            @eval function $name(vol::VOL, args::Vararg{Any}) where {N,T,VOL<:SizedImage{$V,IntensityPixel{T}}}
                return SImageND(_to_image($PT, $kernel(vol)), $S)
            end
        elseif form === :binary
            @eval function $name(vol::VOL, args::Vararg{Any}) where {N,T,VOL<:SizedImage{$V,BinaryPixel{T}}}
                return SImageND(_to_image($PT, $kernel(vol)), $S)
            end
        elseif form === :intensity_scalar
            @eval function $name(vol::VOL, u::Real, args::Vararg{Any}) where {N,T,VOL<:SizedImage{$V,IntensityPixel{T}}}
                return SImageND(_to_image($PT, $kernel(vol, _unit(u))), $S)
            end
        elseif form === :binary_scalar
            @eval function $name(vol::VOL, u::Real, args::Vararg{Any}) where {N,T,VOL<:SizedImage{$V,BinaryPixel{T}}}
                return SImageND(_to_image($PT, $kernel(vol, _unit(u))), $S)
            end
        elseif form === :intensity_mask
            @eval function $name(vol::VOL, mask::M, args::Vararg{Any}) where {N,T,VOL<:SizedImage{$V,IntensityPixel{T}},BT,M<:SizedImage{$V,BinaryPixel{BT}}}
                size(vol) == size(mask) || throw(DimensionMismatch("volume and mask must have the same size"))
                return SImageND(_to_image($PT, $kernel(vol, voxel_foreground(:bridge_mask, mask.img, IsSet()))), $S)
            end
            @eval function $name(vol::VOL, mask::M, args::Vararg{Any}) where {N,T,VOL<:SizedImage{$V,IntensityPixel{T}},ST,M<:SizedImage{$V,IntensityPixel{ST}}}
                size(vol) == size(mask) || throw(DimensionMismatch("volume and mask must have the same size"))
                return SImageND(_to_image($PT, $kernel(vol, voxel_foreground(:bridge_mask, mask.img, AtLeast(0.5)))), $S)
            end
        end
        fn === nothing && (fn = f)
    end
    return fn
end

_values(vol) = voxel_values(:bridge_values, vol.img)
_fg(vol::SizedImage{S,<:BinaryPixel}) where {S} = voxel_foreground(:bridge_fg, vol.img, IsSet())
_fg(vol::SizedImage{S,<:IntensityPixel}, t = 0.5) where {S} = voxel_foreground(:bridge_fg, vol.img, AtLeast(t))

_builder(op, axis, kernel, forms) = I -> _bridge_factory(I, op, axis, kernel, forms)

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

const _INTENSITY = bundle_image2DIntensity_fromVolume_factory
const _BINARY = bundle_image2DBinary_fromVolume_factory

for (axis, letter) in ((1, :y), (2, :x), (3, :z))
    # Intensity projections and slices.
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
    for (stem, kernel, what) in (
            (:proj_max_masked, (vol, fg) -> _proj_masked(_values(vol), fg, axis, :max), "maximum projection over the mask's voxels"),
            (:proj_mean_masked, (vol, fg) -> _proj_masked(_values(vol), fg, axis, :mean), "mean projection over the mask's voxels"),
            (:slice_centroid, (vol, fg) -> _slice(_values(vol), axis, _centroid_index(fg, axis)), "slice through the mask's centroid"),
            (:slice_largest, (vol, fg) -> _slice(_values(vol), axis, _largest_index(fg, axis)), "slice where the mask's cross-section is largest"),
        )
        op = Symbol(stem, :_, letter)
        _define!(_INTENSITY, :intensity, op, _builder(op, axis, kernel, (:intensity_mask,)), "The $what, along $letter.")
    end

    # Binary projections and slices.
    op = Symbol(:proj_any_, letter)
    _define!(_BINARY, :binary, op,
        I -> begin
            f = _bridge_factory(I, op, axis, vol -> dropdims(any(_fg(vol); dims = axis); dims = axis), (:binary, :intensity))
            _bridge_factory(I, op, axis, (vol, t) -> dropdims(any(_fg(vol, t); dims = axis); dims = axis), (:intensity_scalar,))
            f
        end,
        "Silhouette along $letter: set where any voxel is (intensity at 0.5 or a given threshold).")
    op = Symbol(:proj_all_, letter)
    _define!(_BINARY, :binary, op,
        _builder(op, axis, vol -> dropdims(all(_fg(vol); dims = axis); dims = axis), (:binary, :intensity)),
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
