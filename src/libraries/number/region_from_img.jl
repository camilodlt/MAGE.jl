""" Region-statistics functions from image to Float64

Local image-to-scalar reducers over fixed-size patches centered at normalized
coordinates in `[0, 1]`.

Exports :

- **bundle\\_number\\_regionFromImg** :
    - `region_mean`
    - `region_std`
    - `region_min`
    - `region_max`
    - `region_sum`
    - `region_median`
    - `region_range`
    - `region_contrast`
    - `region_energy`
    - `region_entropy`
"""
module number_regionFromImg

using Statistics: mean, median, std
using ..UTCGP: FunctionBundle, append_method!
using ..UTCGP: SImageND, IntensityPixel, BinaryPixel, SegmentPixel
using ..number_imgRegionCommon:
    _image_numeric,
    _normalized_index,
    _region_bounds,
    _region_window

fallback(args...) = return 0.0
bundle_number_regionFromImg = FunctionBundle(fallback)

const _REGION_HALF_SIZE = 1
const _REGION_CONTRAST_OUTER_HALF_SIZE = 2
const _REGION_ENTROPY_BINS = 8
const _REGION_PERCENT_SCALES = (
    (:_5p, 0.05),
    (:_10p, 0.10),
    (:_20p, 0.20),
)

function _region_reduce(reducer::F, from::SImageND, cx::Number, cy::Number; half_size::Int = _REGION_HALF_SIZE) where {F<:Function}
    patch = _region_window(from, cx, cy, half_size)
    return Float64(reducer(patch))
end

function _region_half_size_from_percent(from::SImageND, pct::Float64)
    h, w = size(from)
    max_side = min(h, w)
    kernel_size = max(round(Int, pct * max_side), 1)
    if iseven(kernel_size)
        kernel_size += 1
    end
    kernel_size = min(kernel_size, max_side)
    if iseven(kernel_size) && kernel_size > 1
        kernel_size -= 1
    end
    return fld(kernel_size - 1, 2)
end

function _region_entropy_impl(from::SImageND, cx::Number, cy::Number)
    patch = vec(Float64.(collect(_region_window(from, cx, cy, _REGION_HALF_SIZE))))
    isempty(patch) && return 0.0
    minv = minimum(patch)
    maxv = maximum(patch)
    maxv == minv && return 0.0

    counts = zeros(Int, _REGION_ENTROPY_BINS)
    for value in patch
        scaled = (value - minv) / (maxv - minv)
        idx = clamp(floor(Int, scaled * _REGION_ENTROPY_BINS) + 1, 1, _REGION_ENTROPY_BINS)
        counts[idx] += 1
    end

    total = length(patch)
    entropy = 0.0
    for count in counts
        count == 0 && continue
        p = count / total
        entropy -= p * log2(p)
    end
    return entropy
end

function _region_contrast_outer_half_size(from::SImageND, half_size::Int)
    return max(half_size + 1, min(2 * half_size + 1, fld(min(size(from)...) - 1, 2)))
end

function _region_contrast_bounds(from::SImageND, cx::Number, cy::Number, half_size::Int)
    outer_half_size = _region_contrast_outer_half_size(from, half_size)
    return _region_bounds(from, cx, cy, outer_half_size)
end

function _region_contrast_impl(from::SImageND, cx::Number, cy::Number)
    inner = _region_window(from, cx, cy, _REGION_HALF_SIZE)
    outer = _region_window(from, cx, cy, _REGION_CONTRAST_OUTER_HALF_SIZE)
    inner_h, inner_w = size(inner)
    outer_h, outer_w = size(outer)
    row_offset = fld(outer_h - inner_h, 2)
    col_offset = fld(outer_w - inner_w, 2)
    ring_mask = trues(outer_h, outer_w)
    ring_mask[row_offset + 1:row_offset + inner_h, col_offset + 1:col_offset + inner_w] .= false
    ring_values = outer[ring_mask]
    isempty(ring_values) && return 0.0
    return Float64(mean(inner) - mean(ring_values))
end

function _region_contrast_impl(from::SImageND, cx::Number, cy::Number, half_size::Int)
    outer_half_size = _region_contrast_outer_half_size(from, half_size)
    inner = _region_window(from, cx, cy, half_size)
    outer = _region_window(from, cx, cy, outer_half_size)
    inner_h, inner_w = size(inner)
    outer_h, outer_w = size(outer)
    row_offset = fld(outer_h - inner_h, 2)
    col_offset = fld(outer_w - inner_w, 2)
    ring_mask = trues(outer_h, outer_w)
    ring_mask[row_offset + 1:row_offset + inner_h, col_offset + 1:col_offset + inner_w] .= false
    ring_values = outer[ring_mask]
    isempty(ring_values) && return 0.0
    return Float64(mean(inner) - mean(ring_values))
end

"""
    region_mean(from::SImageND, cx::Number, cy::Number, args...)

Return the mean intensity inside a fixed 3×3 patch centered at normalized
coordinates `(cx, cy)`.
"""
function region_mean(from::SImageND{S,T,2,C}, cx::Number, cy::Number, args...) where {S,T<:Union{IntensityPixel,BinaryPixel,SegmentPixel},C}
    return _region_reduce(mean, from, cx, cy)
end

"""
    region_std(from::SImageND, cx::Number, cy::Number, args...)

Return the standard deviation inside a fixed 3×3 patch centered at normalized
coordinates `(cx, cy)`.
"""
function region_std(from::SImageND{S,T,2,C}, cx::Number, cy::Number, args...) where {S,T<:Union{IntensityPixel,BinaryPixel,SegmentPixel},C}
    return _region_reduce(std, from, cx, cy)
end

"""
    region_min(from::SImageND, cx::Number, cy::Number, args...)

Return the minimum value inside a fixed 3×3 patch centered at normalized
coordinates `(cx, cy)`.
"""
function region_min(from::SImageND{S,T,2,C}, cx::Number, cy::Number, args...) where {S,T<:Union{IntensityPixel,BinaryPixel,SegmentPixel},C}
    return _region_reduce(minimum, from, cx, cy)
end

"""
    region_max(from::SImageND, cx::Number, cy::Number, args...)

Return the maximum value inside a fixed 3×3 patch centered at normalized
coordinates `(cx, cy)`.
"""
function region_max(from::SImageND{S,T,2,C}, cx::Number, cy::Number, args...) where {S,T<:Union{IntensityPixel,BinaryPixel,SegmentPixel},C}
    return _region_reduce(maximum, from, cx, cy)
end

"""
    region_sum(from::SImageND, cx::Number, cy::Number, args...)

Return the sum of values inside a fixed 3×3 patch centered at normalized
coordinates `(cx, cy)`.
"""
function region_sum(from::SImageND{S,T,2,C}, cx::Number, cy::Number, args...) where {S,T<:Union{IntensityPixel,BinaryPixel,SegmentPixel},C}
    return _region_reduce(sum, from, cx, cy)
end

"""
    region_median(from::SImageND, cx::Number, cy::Number, args...)

Return the median value inside a fixed 3×3 patch centered at normalized
coordinates `(cx, cy)`.
"""
function region_median(from::SImageND{S,T,2,C}, cx::Number, cy::Number, args...) where {S,T<:Union{IntensityPixel,BinaryPixel,SegmentPixel},C}
    return _region_reduce(median, from, cx, cy)
end

"""
    region_range(from::SImageND, cx::Number, cy::Number, args...)

Return the local value range inside a fixed 3×3 patch centered at normalized
coordinates `(cx, cy)`.
"""
function region_range(from::SImageND{S,T,2,C}, cx::Number, cy::Number, args...) where {S,T<:Union{IntensityPixel,BinaryPixel,SegmentPixel},C}
    return _region_reduce(x -> maximum(x) - minimum(x), from, cx, cy)
end

"""
    region_contrast(from::SImageND, cx::Number, cy::Number, args...)

Return the difference between the mean of a fixed 3×3 center patch and the mean
of its surrounding 5×5 ring.
"""
function region_contrast(from::SImageND{S,T,2,C}, cx::Number, cy::Number, args...) where {S,T<:Union{IntensityPixel,BinaryPixel,SegmentPixel},C}
    return _region_contrast_impl(from, cx, cy)
end

"""
    region_energy(from::SImageND, cx::Number, cy::Number, args...)

Return the mean squared value inside a fixed 3×3 patch centered at normalized
coordinates `(cx, cy)`.
"""
function region_energy(from::SImageND{S,T,2,C}, cx::Number, cy::Number, args...) where {S,T<:Union{IntensityPixel,BinaryPixel,SegmentPixel},C}
    return _region_reduce(x -> mean(abs2, x), from, cx, cy)
end

"""
    region_entropy(from::SImageND, cx::Number, cy::Number, args...)

Return a cheap 8-bin entropy estimate inside a fixed 3×3 patch centered at
normalized coordinates `(cx, cy)`.
"""
function region_entropy(from::SImageND{S,T,2,C}, cx::Number, cy::Number, args...) where {S,T<:Union{IntensityPixel,BinaryPixel,SegmentPixel},C}
    return _region_entropy_impl(from, cx, cy)
end

for (suffix, pct) in _REGION_PERCENT_SCALES
    mean_name = Symbol(:region_mean, suffix)
    std_name = Symbol(:region_std, suffix)
    min_name = Symbol(:region_min, suffix)
    max_name = Symbol(:region_max, suffix)
    sum_name = Symbol(:region_sum, suffix)
    median_name = Symbol(:region_median, suffix)
    range_name = Symbol(:region_range, suffix)
    contrast_name = Symbol(:region_contrast, suffix)
    energy_name = Symbol(:region_energy, suffix)
    entropy_name = Symbol(:region_entropy, suffix)

    @eval begin
        function $mean_name(from::SImageND{S,T,2,C}, cx::Number, cy::Number, args...) where {S,T<:Union{IntensityPixel,BinaryPixel,SegmentPixel},C}
            half_size = _region_half_size_from_percent(from, $pct)
            return _region_reduce(mean, from, cx, cy; half_size = half_size)
        end

        function $std_name(from::SImageND{S,T,2,C}, cx::Number, cy::Number, args...) where {S,T<:Union{IntensityPixel,BinaryPixel,SegmentPixel},C}
            half_size = _region_half_size_from_percent(from, $pct)
            return _region_reduce(std, from, cx, cy; half_size = half_size)
        end

        function $min_name(from::SImageND{S,T,2,C}, cx::Number, cy::Number, args...) where {S,T<:Union{IntensityPixel,BinaryPixel,SegmentPixel},C}
            half_size = _region_half_size_from_percent(from, $pct)
            return _region_reduce(minimum, from, cx, cy; half_size = half_size)
        end

        function $max_name(from::SImageND{S,T,2,C}, cx::Number, cy::Number, args...) where {S,T<:Union{IntensityPixel,BinaryPixel,SegmentPixel},C}
            half_size = _region_half_size_from_percent(from, $pct)
            return _region_reduce(maximum, from, cx, cy; half_size = half_size)
        end

        function $sum_name(from::SImageND{S,T,2,C}, cx::Number, cy::Number, args...) where {S,T<:Union{IntensityPixel,BinaryPixel,SegmentPixel},C}
            half_size = _region_half_size_from_percent(from, $pct)
            return _region_reduce(sum, from, cx, cy; half_size = half_size)
        end

        function $median_name(from::SImageND{S,T,2,C}, cx::Number, cy::Number, args...) where {S,T<:Union{IntensityPixel,BinaryPixel,SegmentPixel},C}
            half_size = _region_half_size_from_percent(from, $pct)
            return _region_reduce(median, from, cx, cy; half_size = half_size)
        end

        function $range_name(from::SImageND{S,T,2,C}, cx::Number, cy::Number, args...) where {S,T<:Union{IntensityPixel,BinaryPixel,SegmentPixel},C}
            half_size = _region_half_size_from_percent(from, $pct)
            return _region_reduce(x -> maximum(x) - minimum(x), from, cx, cy; half_size = half_size)
        end

        function $contrast_name(from::SImageND{S,T,2,C}, cx::Number, cy::Number, args...) where {S,T<:Union{IntensityPixel,BinaryPixel,SegmentPixel},C}
            half_size = _region_half_size_from_percent(from, $pct)
            return _region_contrast_impl(from, cx, cy, half_size)
        end

        function $energy_name(from::SImageND{S,T,2,C}, cx::Number, cy::Number, args...) where {S,T<:Union{IntensityPixel,BinaryPixel,SegmentPixel},C}
            half_size = _region_half_size_from_percent(from, $pct)
            return _region_reduce(x -> mean(abs2, x), from, cx, cy; half_size = half_size)
        end

        function $entropy_name(from::SImageND{S,T,2,C}, cx::Number, cy::Number, args...) where {S,T<:Union{IntensityPixel,BinaryPixel,SegmentPixel},C}
            return _region_entropy_impl(from, cx, cy)
        end
    end
end

append_method!(bundle_number_regionFromImg, region_mean)
append_method!(bundle_number_regionFromImg, region_std)
append_method!(bundle_number_regionFromImg, region_min)
append_method!(bundle_number_regionFromImg, region_max)
append_method!(bundle_number_regionFromImg, region_sum)
append_method!(bundle_number_regionFromImg, region_median)
append_method!(bundle_number_regionFromImg, region_range)
append_method!(bundle_number_regionFromImg, region_contrast)
append_method!(bundle_number_regionFromImg, region_energy)
append_method!(bundle_number_regionFromImg, region_entropy)

for (suffix, _) in _REGION_PERCENT_SCALES
    append_method!(bundle_number_regionFromImg, getfield(@__MODULE__, Symbol(:region_mean, suffix)))
    append_method!(bundle_number_regionFromImg, getfield(@__MODULE__, Symbol(:region_std, suffix)))
    append_method!(bundle_number_regionFromImg, getfield(@__MODULE__, Symbol(:region_min, suffix)))
    append_method!(bundle_number_regionFromImg, getfield(@__MODULE__, Symbol(:region_max, suffix)))
    append_method!(bundle_number_regionFromImg, getfield(@__MODULE__, Symbol(:region_sum, suffix)))
    append_method!(bundle_number_regionFromImg, getfield(@__MODULE__, Symbol(:region_median, suffix)))
    append_method!(bundle_number_regionFromImg, getfield(@__MODULE__, Symbol(:region_range, suffix)))
    append_method!(bundle_number_regionFromImg, getfield(@__MODULE__, Symbol(:region_contrast, suffix)))
    append_method!(bundle_number_regionFromImg, getfield(@__MODULE__, Symbol(:region_energy, suffix)))
    append_method!(bundle_number_regionFromImg, getfield(@__MODULE__, Symbol(:region_entropy, suffix)))
end

end
