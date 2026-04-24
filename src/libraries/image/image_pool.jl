""" Image pooling functions

Exports :

- **bundle\\_image2DIntensity\\_pool\\_factory** :
    - `avgpool_blocks`
    - `avgpool_cross_blocks`
    - `maxpool_blocks`
    - `maxpool_cross_blocks`
    - `minpool_blocks`
    - `minpool_cross_blocks`
- **bundle\\_image2DBinary\\_pool\\_factory** :
    - `avgpool_blocks`
    - `avgpool_cross_blocks`
    - `maxpool_blocks`
    - `maxpool_cross_blocks`
    - `minpool_blocks`
    - `minpool_cross_blocks`
- **bundle\\_image2DSegment\\_pool\\_factory** :
    - `avgpool_blocks`
    - `avgpool_cross_blocks`
    - `maxpool_blocks`
    - `maxpool_cross_blocks`
    - `minpool_blocks`
    - `minpool_cross_blocks`
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
bundle_image2DIntensity_pool_factory = FunctionBundle(fallback)
bundle_image2DBinary_pool_factory = FunctionBundle(fallback)
bundle_image2DSegment_pool_factory = FunctionBundle(fallback)

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
        k_int = round(Int, k)
        pooled = _block_pool_same_size(reinterpret(img.img), k_int, mean)
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
        k_int = round(Int, k)
        pooled = _block_cross_pool_same_size(reinterpret(img.img), k_int, mean)
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
        k_int = round(Int, k)
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
        k_int = round(Int, k)
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
        k_int = round(Int, k)
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
        k_int = round(Int, k)
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
        return "Pools each non-overlapping block by mean and broadcasts that value within the block."
    elseif name === :avgpool_cross_blocks
        return "Pools each non-overlapping block by averaging its center row and column."
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
