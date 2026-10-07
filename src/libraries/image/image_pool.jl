"""
Block pooling: cut the image into a grid of `k × k` blocks, reduce each block
to one value, and write that value back over the whole block. The output has
the same size as the input (a blocky, "pixelated" version of it).

# Bundles

- [`bundle_image2DIntensity_pool_factory`](@ref)
- [`bundle_image2DBinary_pool_factory`](@ref)
- [`bundle_image2DSegment_pool_factory`](@ref)

The exhaustive, always-current list of operators in each bundle is on the
[Bundle Catalogue](@ref) page.
"""
module image_pool

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
    _validate_factory_type, _get_image_pixel_type, IntensityPixel, BinaryPixel, SegmentPixel

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
"""
function _block_size(k::Number, img::AbstractMatrix)
    kf = Float64(k)
    isfinite(kf) || return 2
    return round(Int, clamp(kf, 1.0, Float64(maximum(size(img)))))
end

"""
Most frequent value of a window (ties: the smallest). The "average" of a
label map: unlike the mean of label numbers, it never invents a label.
Example: labels `[1, 1, 3, 3, 3]` → `3`; `[1, 3]` → `1`.
"""
function _mode(window)
    counts = Dict{eltype(window),Int}()
    for v in window
        counts[v] = get(counts, v, 0) + 1
    end
    best_count = maximum(values(counts))
    return minimum(k for (k, c) in counts if c == best_count)
end

"The average reducer for a pixel type: `_mode` for label maps, `mean` otherwise."
_average_reducer(::Type{<:SegmentPixel}) = _mode
_average_reducer(::Type) = mean

"""
Reduce every non-overlapping `k × k` block with `pool_fn` and write the result
over the block. Example (`k = 2`, mean) on a 2 × 4 image `[1 3 5 5; 1 3 5 5]`
→ `[2 2 5 5; 2 2 5 5]`.
"""
function _block_pool_same_size(img::AbstractMatrix, k::Integer, pool_fn::F) where {F<:Function}
    h, w = size(img)
    out = similar(float.(img))
    k_ = max(k, 1)

    @inbounds for row_start = 1:k_:h
        row_end = min(row_start + k_ - 1, h)
        for col_start = 1:k_:w
            col_end = min(col_start + k_ - 1, w)
            pooled_value = pool_fn(@view img[row_start:row_end, col_start:col_end])
            out[row_start:row_end, col_start:col_end] .= pooled_value
        end
    end

    return out
end

"""
Reduce the "+" of a block: its centre row and centre column (centre = `cld`
of the side, so the upper-left of the two middles for even sides).
"""
function _cross_reduce(window::AbstractMatrix, pool_fn::F) where {F<:Function}
    h, w = size(window)
    row_idx = cld(h, 2)
    col_idx = cld(w, 2)
    vals = eltype(window)[]
    append!(vals, vec(@view window[row_idx, :]))
    for i in 1:h
        if i != row_idx
            push!(vals, window[i, col_idx])
        end
    end
    return pool_fn(vals)
end

"Same as `_block_pool_same_size`, reducing only each block's centre row and column."
function _block_cross_pool_same_size(img::AbstractMatrix, k::Integer, pool_fn::F) where {F<:Function}
    h, w = size(img)
    out = similar(float.(img))
    k_ = max(k, 1)

    @inbounds for row_start = 1:k_:h
        row_end = min(row_start + k_ - 1, h)
        for col_start = 1:k_:w
            col_end = min(col_start + k_ - 1, w)
            pooled_value = _cross_reduce(view(img, row_start:row_end, col_start:col_end), pool_fn)
            out[row_start:row_end, col_start:col_end] .= pooled_value
        end
    end

    return out
end

# Pooled values back to the pixel kind: masks by majority (≥ 0.5), labels rounded.
_pool_cast(::Type{<:BinaryPixel}, pooled) = pooled .>= 0.5
_pool_cast(::Type{<:IntensityPixel}, pooled) = pooled
_pool_cast(::Type{<:SegmentPixel}, pooled) = round.(pooled)

"""
    avgpool_blocks_image2D_factory(i::Type{I}) where {I<:SizedImage2D}

Create average-pooling methods specialized on the given image type.

The output preserves the original image size by average-pooling block windows and
writing the pooled value back over each source block.
"""
function avgpool_blocks_image2D_factory(i::Type{I}) where {I <: SizedImage2D}
    IT, PT, S = _get_image_type(I), _get_image_pixel_type(I), _get_image_tuple_size(I)
    _validate_factory_type(IT)
    FUNCTION_NAME = Symbol(:avgpool_blocks_image2D, :_, Symbol(I))

    f = @eval function $FUNCTION_NAME(img::CONCT, k::Number, args::Vararg{Any}) where {CONCT <: $I}
        k_int = _block_size(k, img.img)
        pooled = _block_pool_same_size(reinterpret(img.img), k_int, $(_average_reducer(PT)))
        casted = _pool_cast($PT, pooled)
        return SImageND($PT.($IT.(casted)), $S)
    end

    @eval function $FUNCTION_NAME(img::CONCT, args::Vararg{Any}) where {CONCT <: $I}
        return $FUNCTION_NAME(img, 2, args...)
    end

    return f
end

"""
    avgpool_cross_blocks_image2D_factory(i::Type{I}) where {I<:SizedImage2D}

Create cross-shaped average-pooling methods specialized on the given image type.

Within each block window, only the center row and center column are averaged.
The pooled value is then written back over the full source block.
"""
function avgpool_cross_blocks_image2D_factory(i::Type{I}) where {I <: SizedImage2D}
    IT, PT, S = _get_image_type(I), _get_image_pixel_type(I), _get_image_tuple_size(I)
    _validate_factory_type(IT)
    FUNCTION_NAME = Symbol(:avgpool_cross_blocks_image2D, :_, Symbol(I))

    f = @eval function $FUNCTION_NAME(img::CONCT, k::Number, args::Vararg{Any}) where {CONCT <: $I}
        k_int = _block_size(k, img.img)
        pooled = _block_cross_pool_same_size(reinterpret(img.img), k_int, $(_average_reducer(PT)))
        casted = _pool_cast($PT, pooled)
        return SImageND($PT.($IT.(casted)), $S)
    end

    @eval function $FUNCTION_NAME(img::CONCT, args::Vararg{Any}) where {CONCT <: $I}
        return $FUNCTION_NAME(img, 2, args...)
    end

    return f
end

"""
    maxpool_blocks_image2D_factory(i::Type{I}) where {I<:SizedImage2D}

Create max-pooling methods specialized on the given image type.

The output preserves the original image size by max-pooling block windows and
writing the pooled value back over each source block.
"""
function maxpool_blocks_image2D_factory(i::Type{I}) where {I <: SizedImage2D}
    IT, PT, S = _get_image_type(I), _get_image_pixel_type(I), _get_image_tuple_size(I)
    _validate_factory_type(IT)
    FUNCTION_NAME = Symbol(:maxpool_blocks_image2D, :_, Symbol(I))

    f = @eval function $FUNCTION_NAME(img::CONCT, k::Number, args::Vararg{Any}) where {CONCT <: $I}
        k_int = _block_size(k, img.img)
        pooled = _block_pool_same_size(reinterpret(img.img), k_int, maximum)
        casted = _pool_cast($PT, pooled)
        return SImageND($PT.($IT.(casted)), $S)
    end

    @eval function $FUNCTION_NAME(img::CONCT, args::Vararg{Any}) where {CONCT <: $I}
        return $FUNCTION_NAME(img, 2, args...)
    end

    return f
end

"""
    maxpool_cross_blocks_image2D_factory(i::Type{I}) where {I<:SizedImage2D}

Create cross-shaped max-pooling methods specialized on the given image type.

Within each block window, only the center row and center column are reduced.
The pooled value is then written back over the full source block.
"""
function maxpool_cross_blocks_image2D_factory(i::Type{I}) where {I <: SizedImage2D}
    IT, PT, S = _get_image_type(I), _get_image_pixel_type(I), _get_image_tuple_size(I)
    _validate_factory_type(IT)
    FUNCTION_NAME = Symbol(:maxpool_cross_blocks_image2D, :_, Symbol(I))

    f = @eval function $FUNCTION_NAME(img::CONCT, k::Number, args::Vararg{Any}) where {CONCT <: $I}
        k_int = _block_size(k, img.img)
        pooled = _block_cross_pool_same_size(reinterpret(img.img), k_int, maximum)
        casted = _pool_cast($PT, pooled)
        return SImageND($PT.($IT.(casted)), $S)
    end

    @eval function $FUNCTION_NAME(img::CONCT, args::Vararg{Any}) where {CONCT <: $I}
        return $FUNCTION_NAME(img, 2, args...)
    end

    return f
end

"""
    minpool_blocks_image2D_factory(i::Type{I}) where {I<:SizedImage2D}

Create min-pooling methods specialized on the given image type.

The output preserves the original image size by min-pooling block windows and
writing the pooled value back over each source block.
"""
function minpool_blocks_image2D_factory(i::Type{I}) where {I <: SizedImage2D}
    IT, PT, S = _get_image_type(I), _get_image_pixel_type(I), _get_image_tuple_size(I)
    _validate_factory_type(IT)
    FUNCTION_NAME = Symbol(:minpool_blocks_image2D, :_, Symbol(I))

    f = @eval function $FUNCTION_NAME(img::CONCT, k::Number, args::Vararg{Any}) where {CONCT <: $I}
        k_int = _block_size(k, img.img)
        pooled = _block_pool_same_size(reinterpret(img.img), k_int, minimum)
        casted = _pool_cast($PT, pooled)
        return SImageND($PT.($IT.(casted)), $S)
    end

    @eval function $FUNCTION_NAME(img::CONCT, args::Vararg{Any}) where {CONCT <: $I}
        return $FUNCTION_NAME(img, 2, args...)
    end

    return f
end

"""
    minpool_cross_blocks_image2D_factory(i::Type{I}) where {I<:SizedImage2D}

Create cross-shaped min-pooling methods specialized on the given image type.

Within each block window, only the center row and center column are reduced.
The pooled value is then written back over the full source block.
"""
function minpool_cross_blocks_image2D_factory(i::Type{I}) where {I <: SizedImage2D}
    IT, PT, S = _get_image_type(I), _get_image_pixel_type(I), _get_image_tuple_size(I)
    _validate_factory_type(IT)
    FUNCTION_NAME = Symbol(:minpool_cross_blocks_image2D, :_, Symbol(I))

    f = @eval function $FUNCTION_NAME(img::CONCT, k::Number, args::Vararg{Any}) where {CONCT <: $I}
        k_int = _block_size(k, img.img)
        pooled = _block_cross_pool_same_size(reinterpret(img.img), k_int, minimum)
        casted = _pool_cast($PT, pooled)
        return SImageND($PT.($IT.(casted)), $S)
    end

    @eval function $FUNCTION_NAME(img::CONCT, args::Vararg{Any}) where {CONCT <: $I}
        return $FUNCTION_NAME(img, 2, args...)
    end

    return f
end

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
