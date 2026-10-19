"""
Volume → 2D image operators: projections and slices, the bridge from 3D
volumes to every 2D image library.

# Bundles

- bundle_image2DIntensity_fromVolume_factory
- bundle_image2DBinary_fromVolume_factory

The exhaustive operator list is on the Bundle Catalogue page.

# How this file is organised

Each operator is a destination-first kernel `kernel!(destination, vol, extra...)`
wrapped by `_bridge_factory`. The
factory is a function of the 2D output type `I`; it defines methods accepting
any volume whose two remaining axes match `I`'s size (the collapsed axis can
have any length), and writes pixels of `I` directly into the destination.

Each operator lists the *method forms* it supports (see `_bridge_factory`):
which pixel kind the volume may have and whether a scalar or a mask follows.

# Example

```julia
using UTCGP, ImageCore
vol = SImageND(IntensityPixel{N0f8}.(rand(28, 28, 16)))   # (y, x, z)
I2 = typeof(SImageND(IntensityPixel{N0f8}.(rand(28, 28))))  # 2D output type (y, x)

mip = bundle_image2DIntensity_fromVolume_factory[:proj_max_z].fn(I2)
mip(vol)          # 28 × 28 image: the brightest voxel of each (y, x) column across the 16 slices

slice = bundle_image2DIntensity_fromVolume_factory[:slice_at_z].fn(I2)
slice(vol, 0.0)   # slice 1;  slice(vol, 1.0) is slice 16, slice(vol, 0.5) slice 8 (round(8.5) = 8)
```
"""
module image3D_to_image2D

using ..UTCGP: image_result, scratch
using ImageCore: Normed
using FixedPointNumbers: rawtype

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

# Returned by the bundles when no method matches the inputs (MAGE then skips the node).
fallback(args...) = return nothing

# Shared paragraph appended to both bundle docstrings below.
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
# Kernels: 3D arrays → destination pixels
#
# `axis` is the axis being collapsed: 1 (y), 2 (x) or 3 (z).
# ---------------------------------------------------------------------------

"""
Size of the 2D result when `axis` of a volume of size `dims` is collapsed.

Example: `dims = (28, 24, 16)` → axis 1: `(24, 16)`, axis 2: `(28, 16)`,
axis 3: `(28, 24)`.
"""
_out_size(dims, axis) = axis == 1 ? (dims[2], dims[3]) : axis == 2 ? (dims[1], dims[3]) : (dims[1], dims[2])
"""
Position in the 2D result of voxel `(r, c, s)` when `axis` is collapsed: the
two coordinates other than `axis`, in order. Example: `_plane(5, 7, 2, 3) == (5, 7)`.
"""
@inline _plane(r, c, s, axis) = axis == 1 ? (c, s) : axis == 2 ? (r, s) : (r, c)
"Index of voxel `(r, c, s)` along `axis` (the coordinate that is collapsed). Example: `_along(5, 7, 2, 3) == 2`."
@inline _along(r, c, s, axis) = axis == 1 ? r : axis == 2 ? c : s

"""
    _project!(destination, values, axis, init, step, finish)

Reduce `values` along `axis`: each output pixel starts at `init`, folds every
voxel of its line with `acc = step(acc, voxel)`, and ends as
`finish(acc, line_length)`. Each line is traversed in its original reduction order.

Example: the mean projection is `init = 0.0`, `step = +`,
`finish = (sum, n) -> sum / n`.
"""
@inline _voxel(row, col, k, axis) = axis == 1 ? (k, row, col) : axis == 2 ? (row, k, col) : (row, col, k)

@inline function _store!(destination::AbstractMatrix{IntensityPixel{T}}, row, col, value) where {T}
    destination[row, col] = IntensityPixel{T}(to_storage(T, Float64(value)))
end
@inline function _store!(destination::AbstractMatrix{BinaryPixel{T}}, row, col, value) where {T}
    destination[row, col] = BinaryPixel{T}(value)
end

# Projections read the volume in memory order (fastest for a column-major array),
# with running values per output pixel in task scratch. Each line still sees its
# voxels in order along the axis, so results are those of the original code. The
# accumulation runs in a separate function (a barrier): the hot loop is several
# times faster when its working arrays arrive as arguments than when fetched from
# scratch in the same function.

"Reduce each line along `axis` with `step` from `init`, then store `finish(value, n)`."
function _project!(destination, values, axis, init, step::S, finish::F) where {S,F}
    accumulator = scratch(:bridge_projection, Float64, size(destination)...)
    _accumulate_projection!(accumulator, values, axis, init, step)
    n = size(values, axis)
    @inbounds for col in axes(destination, 2), row in axes(destination, 1)
        _store!(destination, row, col, finish(accumulator[row, col], n))
    end
    return destination
end

function _accumulate_projection!(accumulator, values, axis, init, step::S) where {S}
    fill!(accumulator, init)
    dims = size(values)
    @inbounds for s in 1:dims[3], c in 1:dims[2], r in 1:dims[1]
        i, j = _plane(r, c, s, axis)
        accumulator[i, j] = step(accumulator[i, j], Float64(values[r, c, s]))
    end
    return nothing
end

_proj_max!(destination, v, axis) = _project!(destination, v, axis, -Inf, max, (x, n) -> x)
_proj_min!(destination, v, axis) = _project!(destination, v, axis, Inf, min, (x, n) -> x)
_proj_mean!(destination, v, axis) = _project!(destination, v, axis, 0.0, +, (x, n) -> x / n)

"Twice the standard deviation along the axis, from the mean and the mean of squares."
function _proj_std!(destination, values, axis)
    total = scratch(:bridge_std_total, Float64, size(destination)...)
    squares = scratch(:bridge_std_squares, Float64, size(destination)...)
    _accumulate_projection!(total, values, axis, 0.0, +)
    _accumulate_projection!(squares, values, axis, 0.0, (acc, x) -> acc + x * x)
    n = size(values, axis)
    @inbounds for col in axes(destination, 2), row in axes(destination, 1)
        mean = total[row, col] / n
        mean_of_squares = squares[row, col] / n
        _store!(destination, row, col, 2.0 * sqrt(max(mean_of_squares - mean^2, 0.0)))
    end
    return destination
end

"""
Normalised position (`0` = first, `1` = last voxel) of the maximum along the
axis; the first maximum on ties.
"""
function _proj_argmax!(destination, values, axis)
    best = scratch(:bridge_argmax_value, Float64, size(destination)...)
    best_index = scratch(:bridge_argmax_index, Int, size(destination)...)
    _accumulate_argmax!(best, best_index, values, axis)
    n = size(values, axis)
    @inbounds for col in axes(destination, 2), row in axes(destination, 1)
        _store!(destination, row, col, _argmax_position(best_index[row, col], n))
    end
    return destination
end

function _accumulate_argmax!(best, best_index, values, axis)
    fill!(best, -Inf)
    fill!(best_index, 0)
    dims = size(values)
    @inbounds for s in 1:dims[3], c in 1:dims[2], r in 1:dims[1]
        i, j = _plane(r, c, s, axis)
        x = Float64(values[r, c, s])
        if x > best[i, j]                                # strict: keeps the first maximum
            best[i, j] = x
            best_index[i, j] = _along(r, c, s, axis)
        end
    end
    return nothing
end

"Normalised position of index `k` among `n` (`0.5` when there is a single voxel)."
function _argmax_position(k::Int, n::Int)
    if n <= 1
        return 0.5
    end
    return (k - 1) / (n - 1)
end

"""
Maximum (`mode = :max`) or mean (`:mean`) along the axis over the voxels inside
`foreground`; `0` where a line has none.

The volume is read in memory order (fastest for a column-major array), with one
running value and one count per output pixel in task scratch. Each line still
sees its voxels in order along the axis, so results are those of the original.
"""
function _proj_masked!(destination, values, foreground, axis, mode::Symbol)
    accumulator = scratch(:bridge_masked_accumulator, Float64, size(destination)...)
    count = scratch(:bridge_masked_count, Int, size(destination)...)
    # Separate function (a barrier): the hot loop runs several times faster when its
    # working arrays arrive as arguments than when fetched from scratch in the same function.
    _accumulate_masked!(accumulator, count, values, foreground, axis, mode)
    @inbounds for col in axes(destination, 2), row in axes(destination, 1)
        _store!(destination, row, col, _masked_value(accumulator[row, col], count[row, col], mode))
    end
    return destination
end

"Running maximum or sum, and count, of the masked voxels of each line (see `_proj_masked!`)."
function _accumulate_masked!(accumulator, count, values, foreground, axis, mode::Symbol)
    dims = size(values)
    if mode === :max
        fill!(accumulator, -Inf)
    else
        fill!(accumulator, 0.0)
    end
    fill!(count, 0)
    @inbounds for s in 1:dims[3], c in 1:dims[2], r in 1:dims[1]
        foreground[r, c, s] || continue                 # voxel outside the mask
        i, j = _plane(r, c, s, axis)
        x = Float64(values[r, c, s])
        if mode === :max
            accumulator[i, j] = max(accumulator[i, j], x)
        else
            accumulator[i, j] += x
        end
        count[i, j] += 1
    end
    return nothing
end

"A line's masked projection: `0` without mask voxels, else its maximum or mean."
function _masked_value(accumulator::Float64, count::Int, mode::Symbol)
    if count == 0
        return 0.0
    end
    if mode === :max
        return accumulator
    end
    return accumulator / count
end

"""
Index of the slice at normalised position `u` (`0` = first, `1` = last) among `n`.

Example with `n = 16`: `u = 0 → 1`, `u = 0.5 → round(8.5) = 8`, `u = 1 → 16`.
"""
_slice_index(n, u) = clamp(round(Int, 1 + u * (n - 1)), 1, n)

"Write slice `k` across `axis` into the destination (one loop per axis: no axis test per pixel)."
function _slice!(destination, source, axis::Int, k::Int)
    if axis == 1
        @inbounds for col in axes(destination, 2), row in axes(destination, 1)
            _store_voxel!(destination, row, col, source[k, row, col])
        end
    elseif axis == 2
        @inbounds for col in axes(destination, 2), row in axes(destination, 1)
            _store_voxel!(destination, row, col, source[row, k, col])
        end
    else
        @inbounds for col in axes(destination, 2), row in axes(destination, 1)
            _store_voxel!(destination, row, col, source[row, col, k])
        end
    end
    return destination
end

"Store one voxel value: fixed-point values as they are, other values through `_store!`."
@inline function _store_voxel!(destination::AbstractMatrix{IntensityPixel{T}}, row, col, value::T) where {T<:Normed}
    destination[row, col] = IntensityPixel{T}(value)
end
@inline _store_voxel!(destination, row, col, value) = _store!(destination, row, col, value)

"Index along `axis` of the brightest voxel (first one on ties)."
function _brightest_index(v, axis)
    index = argmax(v)                         # CartesianIndex (r, c, s) of the maximum
    return Tuple(index)[axis]
end

"Index along `axis` of the mask's centroid; the middle slice for an empty mask."
function _centroid_index(fg, axis)
    total = 0                                 # mask voxels
    weighted = 0                              # Σ index along `axis` of the mask voxels
    @inbounds for idx in CartesianIndices(fg)
        fg[idx] || continue
        total += 1
        weighted += Tuple(idx)[axis]
    end
    return total == 0 ? cld(size(fg, axis), 2) : round(Int, weighted / total)
end

"""
Index along `axis` of the slice with the most mask voxels; the middle slice for an empty mask.

Example: for a tumour mask, `slice_largest_z` picks the slice where the
tumour's cross-section is biggest.
"""
function _largest_index(fg, axis)
    n = size(fg, axis)
    counts = scratch(:bridge_slice_counts, Int, n)
    fill!(counts, 0)                    # counts[k] = mask voxels in slice k
    @inbounds for idx in CartesianIndices(fg)
        fg[idx] && (counts[Tuple(idx)[axis]] += 1)
    end
    return maximum(counts) == 0 ? cld(n, 2) : argmax(counts)
end

"""
Any (`every = false`) / all (`every = true`) voxels set along the axis, with
Base's vectorised in-place reductions into task scratch.
"""
function _proj_boolean!(destination, foreground, axis, every::Bool)
    state = scratch(:bridge_boolean_projection, Bool, size(destination)...)
    _reduce_boolean!(state, foreground, axis, every)     # barrier, as in _proj_masked!
    @inbounds for col in axes(destination, 2), row in axes(destination, 1)
        _store!(destination, row, col, state[row, col])
    end
    return destination
end

"`state` (the projected image) = any/all of `foreground` along `axis`."
function _reduce_boolean!(state, foreground, axis, every::Bool)
    # Seen as an array with a singleton dimension at `axis`, `state` receives the reduction.
    reduced = reshape(state, ntuple(d -> d == axis ? 1 : size(foreground, d), 3))
    if every
        all!(reduced, foreground)
    else
        any!(reduced, foreground)
    end
    return nothing
end
_proj_any!(destination, fg, axis) = _proj_boolean!(destination, fg, axis, false)
_proj_all!(destination, fg, axis) = _proj_boolean!(destination, fg, axis, true)

# Volume → kernel input (scratch buffers, valid until the next call in the same task).
"""
Voxel values of an intensity volume, as a Float64 array in task scratch (no
allocation per call). Kernels then read a plain array: reading the voxels through
`reinterpret` is several times slower.
"""
_values(vol) = voxel_values(:bridge_values, vol.img)
"Foreground of a volume: binary voxels as they are, intensity voxels at or above `t`."
_fg(vol::SizedImage{S,<:BinaryPixel}) where {S} = voxel_foreground(:bridge_fg, vol.img, IsSet())
_fg(vol::SizedImage{S,<:IntensityPixel}, t = 0.5) where {S} = voxel_foreground(:bridge_fg, vol.img, AtLeast(t))

# ---------------------------------------------------------------------------
# Factories
# ---------------------------------------------------------------------------

"""
Size pattern (an expression) of the volumes accepted when `axis` is
collapsed into an `(A, B)` image: the collapsed axis is the free type
variable `N`, e.g. `Tuple{A,B,N}` for `axis = 3`.

Example: for a `28 × 28` output and `axis = 3`, the pattern `Tuple{28,28,N}`
accepts `28 × 28 × 16` and `28 × 28 × 64` volumes alike.
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
    _validate_factory_type(_get_image_type(I))         # throws for unsupported storage types
    size_type = _get_image_tuple_size(I)               # e.g. Tuple{28,28}
    A, B = size_type.parameters                        # e.g. 28, 28
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

Example: `slice_at_z` for masks uses `forms = (:binary_scalar,
:intensity_scalar)`, so it accepts `(mask, s)` and `(vol, s)`.
"""
function _bridge_factory(::Type{I}, operator::Symbol, axis::Int, kernel::K, forms) where {I,K}
    pixel_type, size_type, A, B, name = _factory_setup(I, operator)
    volume_size = _volume_pattern(axis, A, B)          # spliced into each method's signature
    fn = nothing
    for form in forms
        f = if form === :intensity
            # op(intensity_vol, extra...)
            @eval function $name(vol::Vol, args::Vararg{Any}; out = nothing) where {N,VolStorage,Vol<:SizedImage{$volume_size,IntensityPixel{VolStorage}}}
                pixels = out === nothing ? Matrix{$pixel_type}(undef, $A, $B) : out.img
                $kernel(pixels, vol)
                return image_result(out, pixels, $size_type)
            end
        elseif form === :binary
            # op(binary_vol, extra...)
            @eval function $name(vol::Vol, args::Vararg{Any}; out = nothing) where {N,VolBool,Vol<:SizedImage{$volume_size,BinaryPixel{VolBool}}}
                pixels = out === nothing ? Matrix{$pixel_type}(undef, $A, $B) : out.img
                $kernel(pixels, vol)
                return image_result(out, pixels, $size_type)
            end
        elseif form === :intensity_scalar
            # op(intensity_vol, u, extra...), u clamped to [0, 1]
            @eval function $name(vol::Vol, u::Real, args::Vararg{Any}; out = nothing) where {N,VolStorage,Vol<:SizedImage{$volume_size,IntensityPixel{VolStorage}}}
                pixels = out === nothing ? Matrix{$pixel_type}(undef, $A, $B) : out.img
                $kernel(pixels, vol, clamp_unit(u))
                return image_result(out, pixels, $size_type)
            end
        elseif form === :binary_scalar
            # op(binary_vol, u, extra...)
            @eval function $name(vol::Vol, u::Real, args::Vararg{Any}; out = nothing) where {N,VolBool,Vol<:SizedImage{$volume_size,BinaryPixel{VolBool}}}
                pixels = out === nothing ? Matrix{$pixel_type}(undef, $A, $B) : out.img
                $kernel(pixels, vol, clamp_unit(u))
                return image_result(out, pixels, $size_type)
            end
        elseif form === :intensity_mask
            # The size pattern lets the volume and mask differ along the collapsed axis, hence the check.
            # op(intensity_vol, binary_mask, extra...)
            @eval function $name(vol::Vol, mask::Mask, args::Vararg{Any}; out = nothing) where {N,VolStorage,Vol<:SizedImage{$volume_size,IntensityPixel{VolStorage}},MaskBool,Mask<:SizedImage{$volume_size,BinaryPixel{MaskBool}}}
                size(vol) == size(mask) || throw(DimensionMismatch("volume and mask must have the same size"))
                pixels = out === nothing ? Matrix{$pixel_type}(undef, $A, $B) : out.img
                $kernel(pixels, vol, voxel_foreground(:bridge_mask, mask.img, IsSet()))
                return image_result(out, pixels, $size_type)
            end
            # op(intensity_vol, intensity_mask, extra...): mask voxels ≥ 0.5 are inside
            @eval function $name(vol::Vol, mask::Mask, args::Vararg{Any}; out = nothing) where {N,VolStorage,Vol<:SizedImage{$volume_size,IntensityPixel{VolStorage}},MaskStorage,Mask<:SizedImage{$volume_size,IntensityPixel{MaskStorage}}}
                size(vol) == size(mask) || throw(DimensionMismatch("volume and mask must have the same size"))
                pixels = out === nothing ? Matrix{$pixel_type}(undef, $A, $B) : out.img
                $kernel(pixels, vol, voxel_foreground(:bridge_mask, mask.img, AtLeast(0.5)))
                return image_result(out, pixels, $size_type)
            end
        end
        fn === nothing && (fn = f)                     # return the function (all forms share it)
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

Example: `_define!(_BINARY, :binary, :proj_any_z, …)` defines
`proj_any_z_binary_image2D_factory`.
"""
function _define!(bundle, kind::Symbol, operator::Symbol, builder, description::String)
    factory_name = Symbol(operator, :_, kind, :_image2D_factory)
    # The factory accepts any 2D image type and forwards it to the builder.
    # Keep the generic function returned by eval; its new global binding may
    # not be visible in this frame's world on Julia 1.12.
    factory = @eval function $factory_name(output_type::Type{I}) where {S1,S2,P,I<:SizedImage2D{S1,S2,P}}
        return $builder(output_type)
    end
    doc = """
        $(factory_name)(::Type{I})

    Specialises `$operator`. $description
    """
    @eval @doc $doc $factory_name
    append_method!(bundle, factory, operator; description = description)
end

# Builders return `output_type -> factory(output_type, …)`. They are functions,
# not inline closures, so each closure captures its own arguments: `op` is
# reassigned several times in the loop body below, and an inline closure
# would see its last value.
"Builder for an operator with a single kernel."
_builder(op, axis, kernel, forms) = I -> _bridge_factory(I, op, axis, kernel, forms)
"Builder for `proj_any`: thresholds at `0.5` with one argument, at `t` with `(vol, t)`."
_proj_any_builder(op, axis) = I -> begin
    # (mask) and (intensity_vol) forms, intensity at 0.5 …
    fn = _bridge_factory(I, op, axis, (destination, vol) -> _proj_any!(destination, _fg(vol), axis), (:binary, :intensity))
    # … plus (intensity_vol, t) on the same function, thresholded at t.
    _bridge_factory(I, op, axis, (destination, vol, t) -> _proj_any!(destination, _fg(vol, t), axis), (:intensity_scalar,))
    fn
end

const _INTENSITY = bundle_image2DIntensity_fromVolume_factory
const _BINARY = bundle_image2DBinary_fromVolume_factory

# Every operator exists once per axis: <name>_y, <name>_x and <name>_z.
for (axis, letter) in ((1, :y), (2, :x), (3, :z))
    # --- Intensity: projections and slices of the volume alone.
    #
    # Each entry is (name stem, kernel(vol) -> Matrix{Float64}, wording for the
    # description); the operator is named <stem>_<letter>, e.g. proj_max_z,
    # and takes (intensity_vol). The kernels capture `axis` from the loop.
    for (stem, kernel, what) in (
            (:proj_max, (destination, vol) -> _proj_max!(destination, _values(vol), axis), "maximum intensity projection"),
            (:proj_min, (destination, vol) -> _proj_min!(destination, _values(vol), axis), "minimum intensity projection"),
            (:proj_mean, (destination, vol) -> _proj_mean!(destination, _values(vol), axis), "mean intensity projection"),
            (:proj_std, (destination, vol) -> _proj_std!(destination, _values(vol), axis), "twice the standard deviation along the axis"),
            (:proj_argmax, (destination, vol) -> _proj_argmax!(destination, _values(vol), axis), "position (0 to 1) of the maximum along the axis"),
            # cld(n, 2): the middle slice (slice 8 of 16, slice 14 of 28)
            (:slice_center, (destination, vol) -> _slice!(destination, _values(vol), axis, cld(size(vol, axis), 2)), "central slice"),
            (:slice_brightest, (destination, vol) -> (v = _values(vol); _slice!(destination, v, axis, _brightest_index(v, axis))), "slice through the brightest voxel"),
        )
        op = Symbol(stem, :_, letter)
        _define!(_INTENSITY, :intensity, op, _builder(op, axis, kernel, (:intensity,)), "The $what along $letter.")
    end
    # slice_at_<letter>(vol, s): the slice at normalised position s.
    op = Symbol(:slice_at_, letter)
    _define!(_INTENSITY, :intensity, op,
        _builder(op, axis, (destination, vol, u) -> _slice!(destination, _values(vol), axis, _slice_index(size(vol, axis), u)), (:intensity_scalar,)),
        "The slice at normalised position s along $letter.")

    # --- Intensity: guided by a mask.
    #
    # Each entry is (name stem, kernel(destination, vol, fg) -> Matrix{Float64}, wording);
    # the operator takes (intensity_vol, mask), `fg` being the mask's foreground.
    for (stem, kernel, what) in (
            (:proj_max_masked, (destination, vol, fg) -> _proj_masked!(destination, _values(vol), fg, axis, :max), "maximum projection over the mask's voxels"),
            (:proj_mean_masked, (destination, vol, fg) -> _proj_masked!(destination, _values(vol), fg, axis, :mean), "mean projection over the mask's voxels"),
            (:slice_centroid, (destination, vol, fg) -> _slice!(destination, _values(vol), axis, _centroid_index(fg, axis)), "slice through the mask's centroid"),
            (:slice_largest, (destination, vol, fg) -> _slice!(destination, _values(vol), axis, _largest_index(fg, axis)), "slice where the mask's cross-section is largest"),
        )
        op = Symbol(stem, :_, letter)
        _define!(_INTENSITY, :intensity, op, _builder(op, axis, kernel, (:intensity_mask,)), "The $what, along $letter.")
    end

    # --- Binary: projections and slices of masks (intensity volumes thresholded at 0.5).
    # Kernels receive the volume and call _fg(vol) for its foreground.
    op = Symbol(:proj_any_, letter)
    _define!(_BINARY, :binary, op, _proj_any_builder(op, axis),
        "Silhouette along $letter: set where any voxel is (intensity at 0.5 or a given threshold).")
    op = Symbol(:proj_all_, letter)
    _define!(_BINARY, :binary, op,
        _builder(op, axis, (destination, vol) -> _proj_all!(destination, _fg(vol), axis), (:binary, :intensity)),
        "Set where every voxel along $letter is.")
    op = Symbol(:slice_center_, letter)
    _define!(_BINARY, :binary, op,
        _builder(op, axis, (destination, vol) -> _slice!(destination, _fg(vol), axis, cld(size(vol, axis), 2)), (:binary, :intensity)),
        "Central slice of the mask along $letter.")
    op = Symbol(:slice_at_, letter)
    _define!(_BINARY, :binary, op,
        _builder(op, axis, (destination, vol, u) -> _slice!(destination, _fg(vol), axis, _slice_index(size(vol, axis), u)), (:binary_scalar, :intensity_scalar)),
        "Slice of the mask at normalised position s along $letter.")
    op = Symbol(:slice_largest_, letter)
    _define!(_BINARY, :binary, op,
        _builder(op, axis, (destination, vol) -> (fg = _fg(vol); _slice!(destination, fg, axis, _largest_index(fg, axis))), (:binary, :intensity)),
        "Largest cross-section of the mask along $letter.")
end

end
