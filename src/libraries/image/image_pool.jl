""" Image pooling functions

Exports :

- **bundle\\_image2DIntensity\\_pool\\_factory** :
    - `avgpool_resize`
    - `maxpool_resize`
- **bundle\\_image2DBinary\\_pool\\_factory** :
    - `avgpool_resize`
    - `maxpool_resize`
- **bundle\\_image2DSegment\\_pool\\_factory** :
    - `avgpool_resize`
    - `maxpool_resize`
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

_pool_cast(::Type{<:BinaryPixel}, pooled) = pooled .>= 0.5
_pool_cast(::Type{<:IntensityPixel}, pooled) = pooled
_pool_cast(::Type{<:SegmentPixel}, pooled) = round.(pooled)

"""
    avgpool_resize_image2D_factory(i::Type{I}) where {I<:SizedImage2D}

Create average-pooling methods specialized on the given image type.

The output preserves the original image size by average-pooling block windows and
writing the pooled value back over each source block.
"""
function avgpool_resize_image2D_factory(i::Type{I}) where {I <: SizedImage2D}
    IT, PT, S = _get_image_type(I), _get_image_pixel_type(I), _get_image_tuple_size(I)
    _validate_factory_type(IT)
    FUNCTION_NAME = Symbol(:avgpool_resize_image2D, :_, Symbol(I))

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
    maxpool_resize_image2D_factory(i::Type{I}) where {I<:SizedImage2D}

Create max-pooling methods specialized on the given image type.

The output preserves the original image size by max-pooling block windows and
writing the pooled value back over each source block.
"""
function maxpool_resize_image2D_factory(i::Type{I}) where {I <: SizedImage2D}
    IT, PT, S = _get_image_type(I), _get_image_pixel_type(I), _get_image_tuple_size(I)
    _validate_factory_type(IT)
    FUNCTION_NAME = Symbol(:maxpool_resize_image2D, :_, Symbol(I))

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

append_method!(
    bundle_image2DIntensity_pool_factory,
    avgpool_resize_image2D_factory,
    :avgpool_resize,
)
append_method!(
    bundle_image2DBinary_pool_factory,
    avgpool_resize_image2D_factory,
    :avgpool_resize,
)
append_method!(
    bundle_image2DSegment_pool_factory,
    avgpool_resize_image2D_factory,
    :avgpool_resize,
)
append_method!(
    bundle_image2DIntensity_pool_factory,
    maxpool_resize_image2D_factory,
    :maxpool_resize,
)
append_method!(
    bundle_image2DBinary_pool_factory,
    maxpool_resize_image2D_factory,
    :maxpool_resize,
)
append_method!(
    bundle_image2DSegment_pool_factory,
    maxpool_resize_image2D_factory,
    :maxpool_resize,
)

end
