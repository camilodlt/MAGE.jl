"""
Block pooling: cut the image into a grid of `k × k` blocks, reduce each block
to one value, and write that value back over the whole block. The output has
the same size as the input (a blocky, "pixelated" version of it).

# How it is computed

Blocks do not overlap, so every pixel is read once. For each block, the
reducer (`mean`, `maximum`, `minimum`, or the mode for label maps) reads the
block in place (the `_cross_` variants first gather the block's centre row and
column into a reused buffer), and the resulting pixel is written over the
block. Nothing is allocated per block; the image's values and the buffer come
from task scratch. Results are those of the original implementation.

Call tree:

    <pool>(img, k; out)
    └── _pool_blocks_into!(pixels, image_pixels, k, reducer, shape)
        ├── _block_size(k, image_pixels)
        ├── pixel_values!(values, image_pixels)                pooling_common.jl
        └── _pool_blocks!(pixels, values, k, reducer, shape, buffer)
            └── per block: _reduce_block(reducer, shape, block, buffer)
                           → _block_pixel(P, T, value), written with fill!

# Bundles

- [`bundle_image2DIntensity_pool_factory`](@ref)
- [`bundle_image2DBinary_pool_factory`](@ref)
- [`bundle_image2DSegment_pool_factory`](@ref)

The exhaustive, always-current list of operators in each bundle is on the
[Bundle Catalogue](@ref) page.
"""
module image_pool

using ..UTCGP: _factory_type_symbol, @serialized_factory

using Statistics: mean
using ..UTCGP: FunctionBundle, append_method!
import UTCGP:
    CONSTRAINED,
    MIN_INT,
    MAX_INT,
    MIN_FLOAT,
    MAX_FLOAT,
    _positive_params,
    _ceil_positive_params
using ..UTCGP:
    SizedImage, SizedImage2D, SImageND, _get_image_tuple_size, _get_image_type,
    _validate_factory_type, _get_image_pixel_type, IntensityPixel, BinaryPixel, SegmentPixel,
    output_pixels, image_result, scratch
using ..image_pooling_common: pixel_values!, mode!, pooled_pixel

fallback(args...) = return nothing
"""
    bundle_image2DIntensity_pool_factory

Block pooling of intensity images: the image is cut into a grid of
non-overlapping `k × k` blocks (from the top-left; the last row and column of
blocks may be smaller), each block is reduced to one value, and the value is
written back over the block. The output keeps the input's size and pixel type.

`avgpool_blocks`, `maxpool_blocks`, `minpool_blocks` reduce the whole block;
the `_cross_` variants reduce only the block's centre row and centre column
(a "+" shape). Call `op(img, k)` (`k` rounded, clamped to `1` … the image
side; default `2`) or `op(img)`.

This is a *factory* bundle: each entry is a function of a type that returns the
method specialised for it, so the same operator can be instantiated for several
image or element types. See [Libraries](@ref) for how factories are specialised
into a library.
"""
bundle_image2DIntensity_pool_factory = FunctionBundle(fallback)
"""
    bundle_image2DBinary_pool_factory

Block pooling of masks. See [`bundle_image2DIntensity_pool_factory`](@ref).
The average operators set a block when at least half of it is set (majority).

This is a *factory* bundle: each entry is a function of a type that returns the
method specialised for it, so the same operator can be instantiated for several
image or element types. See [Libraries](@ref) for how factories are specialised
into a library.
"""
bundle_image2DBinary_pool_factory = FunctionBundle(fallback)
"""
    bundle_image2DSegment_pool_factory

Block pooling of label maps. See
[`bundle_image2DIntensity_pool_factory`](@ref). Labels are categories, so the
"average" operators return the most frequent label of the block (ties: the
smallest), never a label that is not in the block; max and min compare label
numbers.

This is a *factory* bundle: each entry is a function of a type that returns the
method specialised for it, so the same operator can be instantiated for several
image or element types. See [Libraries](@ref) for how factories are specialised
into a library.
"""
bundle_image2DSegment_pool_factory = FunctionBundle(fallback)

"""
Block size from the evolved parameter `k`: rounded and clamped to `1` … the
image's longer side; `NaN` and `±Inf` give the default `2`.

Example on a 28 × 28 image: `3.4 → 3`, `100 → 28`, `NaN → 2`.
"""
function _block_size(k::Number, img::AbstractMatrix)
    kf = Float64(k)
    if !isfinite(kf)
        return 2
    end
    return round(Int, clamp(kf, 1.0, Float64(maximum(size(img)))))
end

# ---------------------------------------------------------------------------
# Which pixels of a block are reduced
# ---------------------------------------------------------------------------

"The whole block is reduced."
struct WholeBlock end
"Only the block's centre row and centre column (a `+` shape) are reduced."
struct CrossOfBlock end

"""
    _gather_cross!(buffer, block) -> number of values gathered

Copy the `+` of `block` into `buffer`: its centre row (left to right), then its
centre column (top to bottom) without the centre pixel already taken. The
centre is the upper-left of the two middles for an even side (`cld`).

Example, block `[1 2 3; 4 5 6; 7 8 9]` → `buffer[1:5] = [4, 5, 6, 2, 8]`.
"""
function _gather_cross!(buffer, block)
    h, w = size(block)
    centre_row = cld(h, 2)
    centre_col = cld(w, 2)
    n = 0
    @inbounds for c in 1:w
        n += 1
        buffer[n] = block[centre_row, c]
    end
    @inbounds for r in 1:h
        if r != centre_row
            n += 1
            buffer[n] = block[r, centre_col]
        end
    end
    return n
end

# ---------------------------------------------------------------------------
# Reducing one block
# ---------------------------------------------------------------------------

"""
    _reduce_block(reducer, shape, block, buffer) -> value

The block's value. Whole blocks are read in place; the mode sorts, so it works
on a copy in `buffer`. Crosses are gathered into `buffer` first.

Example (`mean`, `WholeBlock()`): block `[1 3; 1 3]` → `2.0`.
"""
_reduce_block(reducer::F, ::WholeBlock, block, buffer) where {F} = _reduce_in_place(reducer, block, buffer)

function _reduce_block(reducer::F, ::CrossOfBlock, block, buffer) where {F}
    n = _gather_cross!(buffer, block)
    return reducer(view(buffer, 1:n))         # the buffer is ours: even mode! may sort it
end

"`mean`, `maximum`, `minimum` read the block where it is."
_reduce_in_place(reducer::F, block, buffer) where {F} = reducer(block)
"The mode sorts its input: copy the block into the buffer first."
_reduce_in_place(::typeof(mode!), block, buffer) = mode!(copyto!(view(buffer, 1:length(block)), block))

"""
    _block_pixel(P, T, value) -> P

The pixel written over a block. The value passes through `float(T)` (e.g.
Float32 for `N0f8`), the element type of the original intermediate image, so
results are unchanged; then `pooled_pixel` (majority for masks, rounding for
labels). Example: `_block_pixel(BinaryPixel{Bool}, Bool, 0.75) == BinaryPixel(true)`.
"""
_block_pixel(::Type{P}, ::Type{T}, value) where {P,T} = pooled_pixel(P, convert(float(T), value))

# ---------------------------------------------------------------------------
# The pooler
# ---------------------------------------------------------------------------

"""
    _pool_blocks_into!(pixels, image_pixels, k, reducer, shape) -> pixels

Block pooling of `image_pixels` into `pixels` (the output, or a new array).

Example (`k = 2`, `mean`, `WholeBlock()`) on the 2 × 4 image
`[1 3 5 5; 1 3 5 5]` → `[2 2 5 5; 2 2 5 5]`.
"""
function _pool_blocks_into!(pixels, image_pixels, k::Number, reducer::F, shape) where {F}
    k_int = _block_size(k, image_pixels)
    h, w = size(image_pixels)
    T = fieldtype(eltype(image_pixels), 1)
    values = scratch(:pool_values, T, h, w)
    pixel_values!(values, image_pixels)
    buffer = scratch(:pool_block_buffer, T, k_int * k_int)
    return _pool_blocks!(pixels, values, k_int, reducer, shape, buffer)
end

"""
Reduce every non-overlapping `k × k` block (the last row and column of blocks
may be smaller) and write its pixel over the block.
"""
function _pool_blocks!(pixels::AbstractMatrix{P}, values, k::Int, reducer::F, shape, buffer) where {P,F}
    h, w = size(values)
    T = eltype(values)
    for col_start in 1:k:w, row_start in 1:k:h
        rows = row_start:min(row_start + k - 1, h)
        cols = col_start:min(col_start + k - 1, w)
        value = _reduce_block(reducer, shape, view(values, rows, cols), buffer)
        fill!(view(pixels, rows, cols), _block_pixel(P, T, value))
    end
    return pixels
end

# ---------------------------------------------------------------------------
# Factories
# ---------------------------------------------------------------------------

"The average of a pixel type: the mode for label maps (it never invents a label), the mean otherwise."
_average_reducer(::Type{<:SegmentPixel}) = mode!
_average_reducer(::Type) = mean

"""
    _make_block_pool_factory(I, reducer, shape, name) -> Function

Define `name` for the image type `I`, with the methods `(img, k)` and `(img)`
(`k = 2`), each accepting `out`.
"""
@serialized_factory function _make_block_pool_factory(::Type{I}, reducer::F, shape, name::Symbol) where {I<:SizedImage2D,F}
    IT, S = _get_image_type(I), _get_image_tuple_size(I)
    _validate_factory_type(IT)
    function_name = Symbol(name, :_image2D_, _factory_type_symbol(I))
    isdefined(@__MODULE__, function_name) && return Base.invokelatest(getfield, @__MODULE__, function_name)
    f = @eval function $function_name(img::Image, k::Number, args::Vararg{Any}; out = nothing) where {Image<:$I}
        pixels = output_pixels(out, img)
        _pool_blocks_into!(pixels, img.img, k, $reducer, $shape)
        return image_result(out, pixels, $S)
    end
    @eval function $function_name(img::Image, args::Vararg{Any}; out = nothing) where {Image<:$I}
        return $function_name(img, 2, args...; out)
    end
    return f
end

"""
    avgpool_blocks_image2D_factory(i::Type{I}) where {I<:SizedImage2D}

Mean of each `k × k` block (labels: the most frequent label), written over the
block. Example (`k = 2`): `[1 3 5 5; 1 3 5 5]` → `[2 2 5 5; 2 2 5 5]`.
"""
avgpool_blocks_image2D_factory(i::Type{I}) where {I<:SizedImage2D} =
    _make_block_pool_factory(I, _average_reducer(_get_image_pixel_type(I)), WholeBlock(), :avgpool_blocks)

"""
    avgpool_cross_blocks_image2D_factory(i::Type{I}) where {I<:SizedImage2D}

Mean of the centre row and centre column of each `k × k` block (labels: the
most frequent label), written over the block. Example (`k = 3`): block
`[1 2 3; 4 5 6; 7 8 9]` → mean of `[4, 5, 6, 2, 8]` = 5.
"""
avgpool_cross_blocks_image2D_factory(i::Type{I}) where {I<:SizedImage2D} =
    _make_block_pool_factory(I, _average_reducer(_get_image_pixel_type(I)), CrossOfBlock(), :avgpool_cross_blocks)

"""
    maxpool_blocks_image2D_factory(i::Type{I}) where {I<:SizedImage2D}

Maximum of each `k × k` block, written over the block.
Example (`k = 2`): `[1 3 5 0; 2 0 5 9]` → `[3 3 9 9; 3 3 9 9]`.
"""
maxpool_blocks_image2D_factory(i::Type{I}) where {I<:SizedImage2D} =
    _make_block_pool_factory(I, maximum, WholeBlock(), :maxpool_blocks)

"""
    maxpool_cross_blocks_image2D_factory(i::Type{I}) where {I<:SizedImage2D}

Maximum of the centre row and centre column of each `k × k` block.
Example (`k = 3`): block `[1 2 3; 4 5 6; 7 8 9]` → max of `[4, 5, 6, 2, 8]` = 8.
"""
maxpool_cross_blocks_image2D_factory(i::Type{I}) where {I<:SizedImage2D} =
    _make_block_pool_factory(I, maximum, CrossOfBlock(), :maxpool_cross_blocks)

"""
    minpool_blocks_image2D_factory(i::Type{I}) where {I<:SizedImage2D}

Minimum of each `k × k` block, written over the block.
Example (`k = 2`): `[1 3 5 0; 2 0 5 9]` → `[0 0 0 0; 0 0 0 0]`.
"""
minpool_blocks_image2D_factory(i::Type{I}) where {I<:SizedImage2D} =
    _make_block_pool_factory(I, minimum, WholeBlock(), :minpool_blocks)

"""
    minpool_cross_blocks_image2D_factory(i::Type{I}) where {I<:SizedImage2D}

Minimum of the centre row and centre column of each `k × k` block.
Example (`k = 3`): block `[1 2 3; 4 5 6; 7 8 9]` → min of `[4, 5, 6, 2, 8]` = 2.
"""
minpool_cross_blocks_image2D_factory(i::Type{I}) where {I<:SizedImage2D} =
    _make_block_pool_factory(I, minimum, CrossOfBlock(), :minpool_cross_blocks)

function _pool_blocks_description(name::Symbol)::String
    if name === :avgpool_blocks
        return "Pools each non-overlapping block by mean (labels: most frequent) and broadcasts that value within the block."
    elseif name === :avgpool_cross_blocks
        return "Pools each non-overlapping block by averaging its center row and column (labels: most frequent)."
    elseif name === :maxpool_blocks
        return "Pools each non-overlapping block by maximum and broadcasts that value within the block."
    elseif name === :maxpool_cross_blocks
        return "Pools each non-overlapping block by max over its center row and column."
    elseif name === :minpool_blocks
        return "Pools each non-overlapping block by minimum and broadcasts that value within the block."
    elseif name === :minpool_cross_blocks
        return "Pools each non-overlapping block by min over its center row and column."
    end
    return "Applies block-wise pooling to the input image."
end

for bundle in (
    bundle_image2DIntensity_pool_factory,
    bundle_image2DBinary_pool_factory,
    bundle_image2DSegment_pool_factory,
)
    append_method!(
        bundle,
        avgpool_blocks_image2D_factory,
        :avgpool_blocks;
        description = _pool_blocks_description(:avgpool_blocks),
    )
    append_method!(
        bundle,
        avgpool_cross_blocks_image2D_factory,
        :avgpool_cross_blocks;
        description = _pool_blocks_description(:avgpool_cross_blocks),
    )
    append_method!(
        bundle,
        maxpool_blocks_image2D_factory,
        :maxpool_blocks;
        description = _pool_blocks_description(:maxpool_blocks),
    )
    append_method!(
        bundle,
        maxpool_cross_blocks_image2D_factory,
        :maxpool_cross_blocks;
        description = _pool_blocks_description(:maxpool_cross_blocks),
    )
    append_method!(
        bundle,
        minpool_blocks_image2D_factory,
        :minpool_blocks;
        description = _pool_blocks_description(:minpool_blocks),
    )
    append_method!(
        bundle,
        minpool_cross_blocks_image2D_factory,
        :minpool_cross_blocks;
        description = _pool_blocks_description(:minpool_cross_blocks),
    )
end

end
