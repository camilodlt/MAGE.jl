""" Sliding-window image poolers

Exports :

- **bundle\\_image2DIntensity\\_pooler\\_factory** :
    - `meanpool`
    - `maxpool`
    - `minpool`
    - `stdpool`
    - `medianpool`
    - `uniquecountpool`
    - `argmaxcountpool`
    - `argmincountpool`
    - `iqrpool`
- **bundle\\_image2DBinary\\_pooler\\_factory** :
    - `meanpool`
    - `maxpool`
    - `minpool`
    - `stdpool`
    - `medianpool`
    - `uniquecountpool`
    - `argmaxcountpool`
    - `argmincountpool`
    - `iqrpool`
- **bundle\\_image2DSegment\\_pooler\\_factory** :
    - `meanpool`
    - `maxpool`
    - `minpool`
    - `stdpool`
    - `medianpool`
    - `uniquecountpool`
    - `argmaxcountpool`
    - `argmincountpool`
    - `iqrpool`
"""
module image_pooler

using Statistics: mean, median, std, quantile
using ..UTCGP: FunctionBundle, append_method!
using ..UTCGP:
    SizedImage2D, SImageND, _get_image_type, _validate_factory_type, _get_image_pixel_type,
    IntensityPixel, BinaryPixel, SegmentPixel

fallback(args...) = return nothing
bundle_image2DIntensity_pooler_factory = FunctionBundle(fallback)
bundle_image2DBinary_pooler_factory = FunctionBundle(fallback)
bundle_image2DSegment_pooler_factory = FunctionBundle(fallback)

_pooler_cast(::Type{<:BinaryPixel}, pooled) = pooled .>= 0.5
_pooler_cast(::Type{<:IntensityPixel}, pooled) = pooled
_pooler_cast(::Type{<:SegmentPixel}, pooled) = round.(pooled)

function _resize_nearest_same_size(src::AbstractMatrix, out_h::Int, out_w::Int)
    src_h, src_w = size(src)
    out = Matrix{eltype(src)}(undef, out_h, out_w)

    @inbounds for i in 1:out_h
        src_i = clamp(round(Int, (i - 0.5) * src_h / out_h + 0.5), 1, src_h)
        for j in 1:out_w
            src_j = clamp(round(Int, (j - 0.5) * src_w / out_w + 0.5), 1, src_w)
            out[i, j] = src[src_i, src_j]
        end
    end

    return out
end

function _sliding_reduce_resize_same_size(
    img::AbstractMatrix,
    k::Integer,
    stride::Integer,
    reducer::F
) where {F<:Function}
    h, w = size(img)
    k_ = clamp(k, 1, min(h, w))
    stride_ = max(stride, 1)

    row_starts = collect(1:stride_:(h - k_ + 1))
    col_starts = collect(1:stride_:(w - k_ + 1))
    reduced = Matrix{Float64}(undef, length(row_starts), length(col_starts))

    @inbounds for (ri, row_start) in pairs(row_starts)
        row_end = row_start + k_ - 1
        for (ci, col_start) in pairs(col_starts)
            col_end = col_start + k_ - 1
            reduced[ri, ci] = Float64(reducer(@view img[row_start:row_end, col_start:col_end]))
        end
    end

    return _resize_nearest_same_size(reduced, h, w)
end

_identity_postprocess(x) = x
function _normalize01_postprocess(x::AbstractMatrix)
    minv = minimum(x)
    maxv = maximum(x)
    if maxv == minv
        return zeros(Float64, size(x))
    end
    return (x .- minv) ./ (maxv - minv)
end

function _make_pooler_factory(
    i::Type{I},
    reducer::F,
    function_symbol::Symbol,
    postprocess::P = _identity_postprocess
) where {I<:SizedImage2D,F<:Function,P<:Function}
    IT, PT = _get_image_type(I), _get_image_pixel_type(I)
    _validate_factory_type(IT)
    FUNCTION_NAME = Symbol(function_symbol, :_image2D_, Symbol(I))

    f = @eval function $FUNCTION_NAME(
        img::CONCT,
        k::Number,
        stride::Number,
        args::Vararg{Any}
    ) where {CONCT <: $I}
        k_int = round(Int, k)
        stride_int = round(Int, stride)
        pooled = _sliding_reduce_resize_same_size(reinterpret(img.img), k_int, stride_int, $reducer)
        pooled = $postprocess(pooled)
        casted = _pooler_cast($PT, pooled)
        return SImageND($PT.($IT.(casted)))
    end

    @eval function $FUNCTION_NAME(img::CONCT, k::Number, args::Vararg{Any}) where {CONCT <: $I}
        return $FUNCTION_NAME(img, k, 1, args...)
    end

    @eval function $FUNCTION_NAME(img::CONCT, args::Vararg{Any}) where {CONCT <: $I}
        return $FUNCTION_NAME(img, 2, 1, args...)
    end

    return f
end

_unique_count(window) = length(unique(window))
_argmax_count(window) = count(==(maximum(window)), window)
_argmin_count(window) = count(==(minimum(window)), window)
function _iqr(window)
    vals = Float64.(vec(collect(window)))
    q1 = quantile(vals, 0.25)
    q3 = quantile(vals, 0.75)
    return q3 - q1
end

"""
    meanpool_image2D_factory(i::Type{I}) where {I<:SizedImage2D}

Create mean sliding-window pooling methods specialized on the given image type.

The image is reduced over full `k × k` windows using the provided `stride`,
without padding, then nearest-neighbor resized back to the original image size.
"""
meanpool_image2D_factory(i::Type{I}) where {I<:SizedImage2D} =
    _make_pooler_factory(i, mean, :meanpool)

"""
    maxpool_image2D_factory(i::Type{I}) where {I<:SizedImage2D}

Create max sliding-window pooling methods specialized on the given image type.

The image is reduced over full `k × k` windows using the provided `stride`,
without padding, then nearest-neighbor resized back to the original image size.
"""
maxpool_image2D_factory(i::Type{I}) where {I<:SizedImage2D} =
    _make_pooler_factory(i, maximum, :maxpool)

"""
    minpool_image2D_factory(i::Type{I}) where {I<:SizedImage2D}

Create min sliding-window pooling methods specialized on the given image type.

The image is reduced over full `k × k` windows using the provided `stride`,
without padding, then nearest-neighbor resized back to the original image size.
"""
minpool_image2D_factory(i::Type{I}) where {I<:SizedImage2D} =
    _make_pooler_factory(i, minimum, :minpool)

"""
    stdpool_image2D_factory(i::Type{I}) where {I<:SizedImage2D}

Create std sliding-window pooling methods specialized on the given image type.

The image is reduced over full `k × k` windows using the provided `stride`,
without padding, then nearest-neighbor resized back to the original image size.
"""
stdpool_image2D_factory(i::Type{I}) where {I<:SizedImage2D} =
    _make_pooler_factory(i, std, :stdpool)

"""
    medianpool_image2D_factory(i::Type{I}) where {I<:SizedImage2D}

Create median sliding-window pooling methods specialized on the given image type.

The image is reduced over full `k × k` windows using the provided `stride`,
without padding, then nearest-neighbor resized back to the original image size.
"""
medianpool_image2D_factory(i::Type{I}) where {I<:SizedImage2D} =
    _make_pooler_factory(i, median, :medianpool)

"""
    uniquecountpool_image2D_factory(i::Type{I}) where {I<:SizedImage2D}

Create unique-count sliding-window pooling methods specialized on the given image type.

The image is reduced over full `k × k` windows using the provided `stride`,
without padding, then nearest-neighbor resized back to the original image size.
"""
uniquecountpool_image2D_factory(i::Type{I}) where {I<:SizedImage2D} =
    _make_pooler_factory(i, _unique_count, :uniquecountpool, _normalize01_postprocess)

"""
    argmaxcountpool_image2D_factory(i::Type{I}) where {I<:SizedImage2D}

Create argmax-count sliding-window pooling methods specialized on the given image type.

The image is reduced over full `k × k` windows using the provided `stride`,
without padding, then nearest-neighbor resized back to the original image size.
"""
argmaxcountpool_image2D_factory(i::Type{I}) where {I<:SizedImage2D} =
    _make_pooler_factory(i, _argmax_count, :argmaxcountpool, _normalize01_postprocess)

"""
    argmincountpool_image2D_factory(i::Type{I}) where {I<:SizedImage2D}

Create argmin-count sliding-window pooling methods specialized on the given image type.

The image is reduced over full `k × k` windows using the provided `stride`,
without padding, then nearest-neighbor resized back to the original image size.
"""
argmincountpool_image2D_factory(i::Type{I}) where {I<:SizedImage2D} =
    _make_pooler_factory(i, _argmin_count, :argmincountpool, _normalize01_postprocess)

"""
    iqrpool_image2D_factory(i::Type{I}) where {I<:SizedImage2D}

Create interquartile-range sliding-window pooling methods specialized on the given image type.

The image is reduced over full `k × k` windows using the provided `stride`,
without padding, then nearest-neighbor resized back to the original image size.
"""
iqrpool_image2D_factory(i::Type{I}) where {I<:SizedImage2D} =
    _make_pooler_factory(i, _iqr, :iqrpool)

for (bundle, factory, name) in (
    (bundle_image2DIntensity_pooler_factory, meanpool_image2D_factory, :meanpool),
    (bundle_image2DBinary_pooler_factory, meanpool_image2D_factory, :meanpool),
    (bundle_image2DSegment_pooler_factory, meanpool_image2D_factory, :meanpool),
    (bundle_image2DIntensity_pooler_factory, maxpool_image2D_factory, :maxpool),
    (bundle_image2DBinary_pooler_factory, maxpool_image2D_factory, :maxpool),
    (bundle_image2DSegment_pooler_factory, maxpool_image2D_factory, :maxpool),
    (bundle_image2DIntensity_pooler_factory, minpool_image2D_factory, :minpool),
    (bundle_image2DBinary_pooler_factory, minpool_image2D_factory, :minpool),
    (bundle_image2DSegment_pooler_factory, minpool_image2D_factory, :minpool),
    (bundle_image2DIntensity_pooler_factory, stdpool_image2D_factory, :stdpool),
    (bundle_image2DBinary_pooler_factory, stdpool_image2D_factory, :stdpool),
    (bundle_image2DSegment_pooler_factory, stdpool_image2D_factory, :stdpool),
    (bundle_image2DIntensity_pooler_factory, medianpool_image2D_factory, :medianpool),
    (bundle_image2DBinary_pooler_factory, medianpool_image2D_factory, :medianpool),
    (bundle_image2DSegment_pooler_factory, medianpool_image2D_factory, :medianpool),
    (bundle_image2DIntensity_pooler_factory, uniquecountpool_image2D_factory, :uniquecountpool),
    (bundle_image2DBinary_pooler_factory, uniquecountpool_image2D_factory, :uniquecountpool),
    (bundle_image2DSegment_pooler_factory, uniquecountpool_image2D_factory, :uniquecountpool),
    (bundle_image2DIntensity_pooler_factory, argmaxcountpool_image2D_factory, :argmaxcountpool),
    (bundle_image2DBinary_pooler_factory, argmaxcountpool_image2D_factory, :argmaxcountpool),
    (bundle_image2DSegment_pooler_factory, argmaxcountpool_image2D_factory, :argmaxcountpool),
    (bundle_image2DIntensity_pooler_factory, argmincountpool_image2D_factory, :argmincountpool),
    (bundle_image2DBinary_pooler_factory, argmincountpool_image2D_factory, :argmincountpool),
    (bundle_image2DSegment_pooler_factory, argmincountpool_image2D_factory, :argmincountpool),
    (bundle_image2DIntensity_pooler_factory, iqrpool_image2D_factory, :iqrpool),
    (bundle_image2DBinary_pooler_factory, iqrpool_image2D_factory, :iqrpool),
    (bundle_image2DSegment_pooler_factory, iqrpool_image2D_factory, :iqrpool),
)
    append_method!(bundle, factory, name)
end

end
