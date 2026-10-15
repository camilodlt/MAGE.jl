"""
Statistics over a rectangular patch of an image, centred on normalised
coordinates in `[0, 1]`.

# Bundles

- [`bundle_number_regionFromImg`](@ref)

The exhaustive, always-current list of operators in each bundle is on the
[Bundle Catalogue](@ref) page.
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
"""
    bundle_number_regionFromImg

Statistics over a rectangular region of an image, located by relative
coordinates.

Ten statistics — `region_mean`, `region_std`, `region_min`, `region_max`,
`region_sum`, `region_median`, `region_range`, `region_contrast`,
`region_energy`, `region_entropy` — each in four window sizes: a fixed `3 × 3`
window (no suffix), and the `_5p`, `_10p` and `_20p` variants whose side is
5%, 10% and 20% of the image's shorter side (odd, at least 3 pixels).

Every operator takes `(img, cx, cy)`: the window's centre as normalised
coordinates (`cx` = column, `cy` = row, `0` to `1`). Windows are clipped at
the image border.

`region_contrast` is the mean of the window minus the mean of the ring
around it: the `5 × 5` window without the `3 × 3` one, or for the `_<pct>p`
variants a window of half-width `2 · half + 1` (at most half the image).
"""
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

"""
Half-width of the `_<pct>p` windows: the window side is `pct` of the shorter
image side, made odd, and at least 3 pixels (half-width `≥ 1`). Example:
`pct = 0.2` on a `30 × 30` image → side 6 → 7 → half-width 3; `pct = 0.05` on
`28 × 28` → side 1 → 3 (a 1-pixel window would make `std` undefined).
"""
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
    return max(fld(kernel_size - 1, 2), 1)
end

function _region_entropy_impl(
        from::SImageND,
        cx::Number,
        cy::Number;
        half_size::Int = _REGION_HALF_SIZE,
    )
    patch = vec(Float64.(collect(_region_window(from, cx, cy, half_size))))
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

"""
Mean of the inner window minus mean of the ring around it (the outer window
without the inner one), both centred on `(cx, cy)` and clipped at the border.
The ring is taken from the actual clipped bounds, so it stays correct next to
any border. `0` when the ring is empty.
"""
function _ring_contrast(from::SImageND, cx::Number, cy::Number, inner_half::Int, outer_half::Int)
    img = _image_numeric(from)
    i_r0, i_r1, i_c0, i_c1 = _region_bounds(from, cx, cy, inner_half)
    o_r0, o_r1, o_c0, o_c1 = _region_bounds(from, cx, cy, outer_half)
    inner_sum = 0.0
    ring_sum = 0.0
    ring_count = 0
    @inbounds for c in o_c0:o_c1, r in o_r0:o_r1
        if i_r0 <= r <= i_r1 && i_c0 <= c <= i_c1
            inner_sum += img[r, c]
        else
            ring_sum += img[r, c]
            ring_count += 1
        end
    end
    ring_count == 0 && return 0.0
    inner_count = (i_r1 - i_r0 + 1) * (i_c1 - i_c0 + 1)
    return inner_sum / inner_count - ring_sum / ring_count
end

"`region_contrast`: 3 × 3 centre against the ring of the 5 × 5 window around it."
_region_contrast_impl(from::SImageND, cx::Number, cy::Number) =
    _ring_contrast(from, cx, cy, _REGION_HALF_SIZE, _REGION_CONTRAST_OUTER_HALF_SIZE)

"`region_contrast_<pct>p`: centre window of half-width `half_size` against its ring (outer half-width from `_region_contrast_outer_half_size`)."
_region_contrast_impl(from::SImageND, cx::Number, cy::Number, half_size::Int) =
    _ring_contrast(from, cx, cy, half_size, _region_contrast_outer_half_size(from, half_size))

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
            half_size = _region_half_size_from_percent(from, $pct)
            return _region_entropy_impl(from, cx, cy; half_size = half_size)
        end
    end
end

append_method!(
    bundle_number_regionFromImg,
    region_mean;
    description = "Computes local mean intensity inside a patch centered at normalized coordinates.",
)
append_method!(
    bundle_number_regionFromImg,
    region_std;
    description = "Computes local standard deviation inside a patch centered at normalized coordinates.",
)
append_method!(
    bundle_number_regionFromImg,
    region_min;
    description = "Computes the minimum local value inside a centered patch.",
)
append_method!(
    bundle_number_regionFromImg,
    region_max;
    description = "Computes the maximum local value inside a centered patch.",
)
append_method!(
    bundle_number_regionFromImg,
    region_sum;
    description = "Computes the local sum of values inside a centered patch.",
)
append_method!(
    bundle_number_regionFromImg,
    region_median;
    description = "Computes the local median value inside a centered patch.",
)
append_method!(
    bundle_number_regionFromImg,
    region_range;
    description = "Computes local range as max minus min inside a centered patch.",
)
append_method!(
    bundle_number_regionFromImg,
    region_contrast;
    description = "Computes local contrast between a center patch and its surrounding ring.",
)
append_method!(
    bundle_number_regionFromImg,
    region_energy;
    description = "Computes local energy as the mean squared value inside a centered patch.",
)
append_method!(
    bundle_number_regionFromImg,
    region_entropy;
    description = "Computes local entropy from a coarse histogram inside a centered patch.",
)

for (suffix, _) in _REGION_PERCENT_SCALES
    append_method!(
        bundle_number_regionFromImg,
        getfield(@__MODULE__, Symbol(:region_mean, suffix));
        description = "Computes local mean intensity using a percentage-sized patch centered at normalized coordinates.",
    )
    append_method!(
        bundle_number_regionFromImg,
        getfield(@__MODULE__, Symbol(:region_std, suffix));
        description = "Computes local standard deviation using a percentage-sized patch centered at normalized coordinates.",
    )
    append_method!(
        bundle_number_regionFromImg,
        getfield(@__MODULE__, Symbol(:region_min, suffix));
        description = "Computes the local minimum using a percentage-sized patch centered at normalized coordinates.",
    )
    append_method!(
        bundle_number_regionFromImg,
        getfield(@__MODULE__, Symbol(:region_max, suffix));
        description = "Computes the local maximum using a percentage-sized patch centered at normalized coordinates.",
    )
    append_method!(
        bundle_number_regionFromImg,
        getfield(@__MODULE__, Symbol(:region_sum, suffix));
        description = "Computes local sum using a percentage-sized patch centered at normalized coordinates.",
    )
    append_method!(
        bundle_number_regionFromImg,
        getfield(@__MODULE__, Symbol(:region_median, suffix));
        description = "Computes local median using a percentage-sized patch centered at normalized coordinates.",
    )
    append_method!(
        bundle_number_regionFromImg,
        getfield(@__MODULE__, Symbol(:region_range, suffix));
        description = "Computes local range using a percentage-sized patch centered at normalized coordinates.",
    )
    append_method!(
        bundle_number_regionFromImg,
        getfield(@__MODULE__, Symbol(:region_contrast, suffix));
        description = "Computes center-versus-ring local contrast using a percentage-sized patch.",
    )
    append_method!(
        bundle_number_regionFromImg,
        getfield(@__MODULE__, Symbol(:region_energy, suffix));
        description = "Computes local energy using a percentage-sized patch centered at normalized coordinates.",
    )
    append_method!(
        bundle_number_regionFromImg,
        getfield(@__MODULE__, Symbol(:region_entropy, suffix));
        description = "Computes local entropy from histogram bins in a percentage-sized patch.",
    )
end

end
