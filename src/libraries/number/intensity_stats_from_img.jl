"""
Intensity-distribution statistics of an image, over the whole image, inside a
region of interest, outside it, or as the inside − outside difference.

# Bundles

- [`bundle_number_intensityStatsFromImg`](@ref)

The exhaustive, always-current list of operators in each bundle is on the
[Bundle Catalogue](@ref) page.
"""
module number_intensityStatsFromImg

using Statistics: quantile!
using ImageCore: N0f8, N0f16
using ..UTCGP: FunctionBundle, append_method!
using ..UTCGP: SImageND, IntensityPixel, BinaryPixel
using ..image2D_object_common: clamp_unit, pixel_value, scratch

fallback(args...) = return 0.0

"""
    bundle_number_intensityStatsFromImg

Position-free statistics of pixel intensities (first-order radiomics):
quantiles `stat_q05`, `stat_q25`, `stat_q50`, `stat_q75`, `stat_q95`,
`stat_iqr`, `stat_mean`, `stat_std`, `stat_mad` (mean absolute deviation),
`stat_skewness`, `stat_kurtosis` (excess), `stat_entropy` and
`stat_uniformity` (32-bin histogram), `stat_bimodality` (bimodality
coefficient), `stat_otsu_threshold`, `stat_otsu_separability` (between-class
over total variance at the Otsu threshold) and `stat_frac_above`.

Each statistic comes in three forms:

- `stat_x(img)` over the whole image, or `stat_x(img, roi)` over the pixels
  inside a region of interest;
- `stat_x_out(img, roi)` over the pixels outside it;
- `stat_x_diff(img, roi)`: inside minus outside, e.g. how much brighter or more
  textured an object is than its surroundings.

All statistics work on 2D images and on 3D volumes alike; `roi` is a binary
mask, or an intensity map thresholded at `0.5`, of the same size.
`stat_frac_above` takes the threshold as its last argument (default `0.5`).
An empty selection gives `0.0`.
"""
bundle_number_intensityStatsFromImg = FunctionBundle(fallback)

"Intensity image of any dimension (2D images and 3D volumes)."
const _Img = SImageND{S,T,N,C} where {S,T<:IntensityPixel,N,C}
"Binary mask of any dimension."
const _Mask = SImageND{S,T,N,C} where {S,T<:BinaryPixel,N,C}
"Bins of the histogram behind `stat_entropy` and `stat_uniformity`."
const _ENTROPY_BINS = 32

# ---------------------------------------------------------------------------
# Selection: which pixels are summarised
#
# A selection is a small struct; `_selected(selection, i)` says whether pixel
# `i` (linear index) takes part. Dispatching on the struct type lets the
# compiler drop the test entirely for `_All`.
# ---------------------------------------------------------------------------

"Every pixel."
struct _All end
"Pixels whose ROI pixel `mask[i]` satisfies `is_in`."
struct _Inside{M,P}
    mask::M
    is_in::P
end
"Pixels whose ROI pixel `mask[i]` does not satisfy `is_in`."
struct _Outside{M,P}
    mask::M
    is_in::P
end
@inline _selected(::_All, i) = true
@inline _selected(s::_Inside, i) = @inbounds s.is_in(s.mask[i])
@inline _selected(s::_Outside, i) = @inbounds !s.is_in(s.mask[i])

"ROI membership of a binary pixel."
@inline _is_set(p) = p.pixel == true
"ROI membership of an intensity pixel (at or above `0.5`)."
@inline _at_half(p) = Float64(p) >= 0.5
"`(roi_pixels, is_in)`: the ROI's pixel array and its membership test."
_roi(mask::_Mask) = (mask.img, _is_set)
_roi(mask::_Img) = (mask.img, _at_half)

# ---------------------------------------------------------------------------
# Summary of the selected pixels
# ---------------------------------------------------------------------------

"256-level bin of a pixel: the raw byte for 8-bit images, `round(255 v)` otherwise."
@inline _level(p) = clamp(round(Int, clamp(pixel_value(p), 0.0, 1.0) * 255), 0, 255) + 1
@inline _level(p::IntensityPixel{N0f8}) = Int(reinterpret(p.pixel)) + 1

# How quantiles are computed, by pixel storage type (`_Summary.kind`):
"8-bit pixels: the 256-level histogram is exact, quantiles are read from it."
const _KIND_HIST8 = 8
"16-bit pixels: raw values are kept, quantiles by exact radix selection (no sort)."
const _KIND_RAW16 = 16
"Other storage: `Float64` values are kept, quantiles by partial sort."
const _KIND_VALUES = 0

_kind(::Type{IntensityPixel{N0f8}}) = _KIND_HIST8
_kind(::Type{IntensityPixel{N0f16}}) = _KIND_RAW16
_kind(::Type) = _KIND_VALUES

"""
    _Summary

Everything the statistics need about the selected pixels, gathered in one
pass by `_summary`.

| Field | Meaning |
|:--|:--|
| `n` | number of selected pixels |
| `mean` | mean value |
| `m2`, `m3`, `m4` | central moments (population: divided by `n`) |
| `mad` | mean absolute deviation from the mean |
| `hist` | 256-level histogram (`_level`) |
| `values` | the values (only for `_KIND_VALUES`, else empty) |
| `raw16` | the raw 16-bit values (only for `_KIND_RAW16`, else empty) |
| `kind` | `_KIND_HIST8`, `_KIND_RAW16` or `_KIND_VALUES` |

The vectors are per-task scratch buffers, valid until the next `_summary`.
"""
struct _Summary
    n::Int
    mean::Float64
    m2::Float64
    m3::Float64
    m4::Float64
    mad::Float64
    hist::Vector{Int}
    values::Vector{Float64}
    raw16::Vector{UInt16}
    kind::Int
end

"Summarise the pixels picked by `selection` (see `_Summary`): one pass to collect, one over the values (or the histogram) for the moments."
function _summary(pixels::AbstractArray{P}, selection) where {P}
    kind = _kind(P)
    hist = fill!(scratch(:stats_hist, Int, 256), 0)
    values = scratch(:stats_values, Float64, 0)
    raw16 = scratch(:stats_raw16, UInt16, 0)
    kind == _KIND_VALUES && resize!(values, length(pixels))
    kind == _KIND_RAW16 && resize!(raw16, length(pixels))
    n = 0
    total = 0.0
    @inbounds for i in eachindex(pixels)
        _selected(selection, i) || continue
        p = pixels[i]
        v = pixel_value(p)
        n += 1
        total += v
        hist[_level(p)] += 1
        if kind == _KIND_VALUES
            values[n] = v
        elseif kind == _KIND_RAW16
            raw16[n] = _raw16(p)
        end
    end
    kind == _KIND_VALUES ? resize!(values, n) : empty!(values)
    kind == _KIND_RAW16 ? resize!(raw16, n) : empty!(raw16)
    n == 0 && return _Summary(0, 0.0, 0.0, 0.0, 0.0, 0.0, hist, values, raw16, kind)
    mean = total / n
    m2 = m3 = m4 = mad = 0.0
    if kind == _KIND_HIST8
        # Moments from the histogram, with an integer level sum so the
        # deviations are exact (0 for a constant region). d = level/255 − mean.
        level_sum = 0
        @inbounds for k in 1:256
            level_sum += hist[k] * (k - 1)
        end
        scale = 1.0 / (255 * n)
        @inbounds for k in 1:256
            c = hist[k]
            c == 0 && continue
            d = ((k - 1) * n - level_sum) * scale
            d2 = d * d
            m2 += c * d2
            m3 += c * d2 * d
            m4 += c * d2 * d2
            mad += c * abs(d)
        end
    else
        @inbounds for i in 1:n
            v = kind == _KIND_RAW16 ? raw16[i] / 65535 : values[i]
            d = v - mean
            d2 = d * d
            m2 += d2
            m3 += d2 * d
            m4 += d2 * d2
            mad += abs(d)
        end
    end
    return _Summary(n, mean, m2 / n, m3 / n, m4 / n, mad / n, hist, values, raw16, kind)
end

"Raw 16-bit storage of an `N0f16` pixel (unused placeholder for other types)."
@inline _raw16(p) = UInt16(0)
@inline _raw16(p::IntensityPixel{N0f16}) = reinterpret(p.pixel)

"k-th order statistic (1-based) from an exact 256-level histogram."
function _order_statistic(hist::Vector{Int}, k::Int)
    running = 0
    @inbounds for b in 1:256
        running += hist[b]
        running >= k && return (b - 1) / 255
    end
    return 1.0
end

"""
Order statistics `k` and `k + 1` (1-based) of raw 16-bit values, exactly and
without sorting: count high bytes to find the bins holding ranks `k` and
`k + 1`, then count low bytes inside those bins.
"""
function _order_pair16(raw::Vector{UInt16}, k::Int)
    n = length(raw)
    coarse = fill!(scratch(:stats_radix, Int, 256), 0)
    @inbounds for x in raw
        coarse[(x >> 8) + 1] += 1
    end
    # (high byte, rank within that high-byte bin) of the value of rank `rank`.
    function locate(rank)
        running = 0
        @inbounds for b in 1:256
            running + coarse[b] >= rank && return b - 1, rank - running
            running += coarse[b]
        end
        return 255, rank - running
    end
    high_a, rank_a = locate(k)
    high_b, rank_b = locate(min(k + 1, n))
    fine_a = fill!(scratch(:stats_radix_a, Int, 256), 0)
    fine_b = fill!(scratch(:stats_radix_b, Int, 256), 0)
    @inbounds for x in raw
        high = x >> 8
        high == high_a && (fine_a[(x & 0xff) + 1] += 1)
        high == high_b && (fine_b[(x & 0xff) + 1] += 1)
    end
    # Value of rank `rank` within the bin `high`, from its low-byte counts `fine`.
    function pick(high, fine, rank)
        running = 0
        @inbounds for b in 1:256
            running += fine[b]
            running >= rank && return ((high << 8) | (b - 1)) / 65535
        end
        return 1.0
    end
    return pick(high_a, fine_a, rank_a), pick(high_b, fine_b, rank_b)
end

"Quantile `p` with linear interpolation between order statistics (as `Statistics.quantile`)."
function _quantile(s::_Summary, p::Float64)
    s.n == 0 && return 0.0
    s.kind == _KIND_VALUES && return quantile!(s.values, p)
    position = (s.n - 1) * p + 1
    k = floor(Int, position)
    fraction = position - k
    if s.kind == _KIND_HIST8
        low = _order_statistic(s.hist, k)
        fraction == 0.0 && return low
        high = _order_statistic(s.hist, k + 1)
    else
        low, high = _order_pair16(s.raw16, k)
        fraction == 0.0 && return low
    end
    return low + fraction * (high - low)
end

"Population standard deviation."
_std(s::_Summary) = sqrt(s.m2)
"Skewness `m3 / m2^1.5`; `0` for a constant selection."
_skewness(s::_Summary) = s.m2 <= 1e-14 ? 0.0 : s.m3 / s.m2^1.5
"Excess kurtosis `m4 / m2² − 3`; `0` for a constant selection."
_kurtosis(s::_Summary) = s.m2 <= 1e-14 ? 0.0 : s.m4 / s.m2^2 - 3.0

"Bimodality coefficient `(g² + 1) / (k + 3)` (population form); above 5/9 suggests two modes."
function _bimodality(s::_Summary)
    s.n == 0 && return 0.0
    s.m2 <= 1e-14 && return 0.0
    return (_skewness(s)^2 + 1) / (_kurtosis(s) + 3.0)
end

"The 256-level histogram merged into 32 bins, as probabilities."
function _coarse_probabilities(s::_Summary)
    p = zeros(_ENTROPY_BINS)
    @inbounds for b in 1:256
        p[(b - 1) * _ENTROPY_BINS ÷ 256 + 1] += s.hist[b]
    end
    return p ./ s.n
end

"Shannon entropy of the 32-bin histogram, divided by its maximum (`log2 32`)."
function _entropy(s::_Summary)
    s.n == 0 && return 0.0
    e = 0.0
    for q in _coarse_probabilities(s)
        q > 0 && (e -= q * log2(q))
    end
    return e / log2(_ENTROPY_BINS)
end

"Sum of squared 32-bin probabilities: `1` for a constant region."
_uniformity(s::_Summary) = s.n == 0 ? 0.0 : sum(abs2, _coarse_probabilities(s))

"""
Otsu on the 256-level histogram: `(threshold, separability)`. The threshold
maximises the between-class variance `w0 (1 − w0) (m0 − m1)²` (class weight
`w0`, class means `m0`, `m1`); separability is that variance over the total
variance. A constant selection gives `(its value, 0)`.
"""
function _otsu(s::_Summary)
    s.n == 0 && return 0.0, 0.0
    total_sum = 0.0
    total_sq = 0.0
    @inbounds for b in 1:256
        v = (b - 1) / 255
        total_sum += s.hist[b] * v
        total_sq += s.hist[b] * v * v
    end
    total_var = total_sq / s.n - (total_sum / s.n)^2
    total_var <= 1e-14 && return clamp(total_sum / s.n, 0.0, 1.0), 0.0
    best = -1.0
    best_b = 1
    weight = 0                                     # pixels at levels ≤ b (dark class)
    partial = 0.0                                  # their intensity sum
    @inbounds for b in 1:255
        weight += s.hist[b]
        partial += s.hist[b] * (b - 1) / 255
        (weight == 0 || weight == s.n) && continue
        w0 = weight / s.n
        m0 = partial / weight
        m1 = (total_sum - partial) / (s.n - weight)
        between = w0 * (1 - w0) * (m0 - m1)^2
        if between > best
            best = between
            best_b = b
        end
    end
    # Foreground is `v > threshold`: the threshold is the last level of the dark class.
    return (best_b - 1) / 255, clamp(max(best, 0.0) / total_var, 0.0, 1.0)
end

"Fraction of the selected pixels at or above `threshold`; `0` when none is selected."
function _frac_above(pixels::AbstractArray, selection, threshold::Float64)
    n = 0
    above = 0
    @inbounds for i in eachindex(pixels)
        _selected(selection, i) || continue
        n += 1
        above += pixel_value(pixels[i]) >= threshold
    end
    return n == 0 ? 0.0 : above / n
end

# (name, statistic(summary), wording): each becomes stat_<name>, stat_<name>_out and stat_<name>_diff.
const _STATISTICS = (
    (:q05, s -> _quantile(s, 0.05), "5th percentile"),
    (:q25, s -> _quantile(s, 0.25), "first quartile"),
    (:q50, s -> _quantile(s, 0.50), "median"),
    (:q75, s -> _quantile(s, 0.75), "third quartile"),
    (:q95, s -> _quantile(s, 0.95), "95th percentile"),
    (:iqr, s -> _quantile(s, 0.75) - _quantile(s, 0.25), "interquartile range"),
    (:mean, s -> s.mean, "mean"),
    (:std, _std, "standard deviation"),
    (:mad, s -> s.mad, "mean absolute deviation"),
    (:skewness, _skewness, "skewness"),
    (:kurtosis, _kurtosis, "excess kurtosis"),
    (:entropy, _entropy, "normalised 32-bin entropy"),
    (:uniformity, _uniformity, "32-bin uniformity (sum of squared probabilities)"),
    (:bimodality, _bimodality, "bimodality coefficient"),
    (:otsu_threshold, s -> _otsu(s)[1], "Otsu threshold"),
    (:otsu_separability, s -> _otsu(s)[2], "Otsu separability (between-class / total variance)"),
)

"Throw a `DimensionMismatch` unless the image and the ROI have the same size."
function _check_same_size(img, roi)
    size(img) == size(roi) || throw(DimensionMismatch("image and region must have the same size"))
    return nothing
end

"`statistic` of the selected pixels; `0` when none is selected."
@inline function _stat(statistic::F, pixels, selection) where {F}
    s = _summary(pixels, selection)
    s.n == 0 && return 0.0
    return Float64(statistic(s))
end

"Attach `doc` to the function `name` and register it in the bundle."
function _register!(name::Symbol, description::String, doc::String)
    @eval @doc $doc $name
    append_method!(bundle_number_intensityStatsFromImg, getfield(@__MODULE__, name), name;
        description = description)
end

for (stat, statistic, what) in _STATISTICS
    inside = Symbol(:stat_, stat)
    outside = Symbol(:stat_, stat, :_out)
    diff = Symbol(:stat_, stat, :_diff)
    @eval begin
        $inside(img::_Img, args...) = _stat($statistic, img.img, _All())
        function $inside(img::_Img, roi::Union{_Mask,_Img}, args...)
            _check_same_size(img, roi)
            return _stat($statistic, img.img, _Inside(_roi(roi)...))
        end
        function $outside(img::_Img, roi::Union{_Mask,_Img}, args...)
            _check_same_size(img, roi)
            return _stat($statistic, img.img, _Outside(_roi(roi)...))
        end
        function $diff(img::_Img, roi::Union{_Mask,_Img}, args...)
            _check_same_size(img, roi)
            mask, is_in = _roi(roi)
            return _stat($statistic, img.img, _Inside(mask, is_in)) -
                   _stat($statistic, img.img, _Outside(mask, is_in))
        end
    end
    _register!(inside, "Intensity $what, over the image or inside a ROI.", """
        $inside(img, args...)
        $inside(img, roi, args...)

    Intensity $what over the whole image, or over the pixels inside `roi`
    (binary mask, or intensity map at `0.5`). Empty selection → `0.0`.
    """)
    _register!(outside, "Intensity $what outside a ROI.", """
        $outside(img, roi, args...)

    Intensity $what over the pixels outside `roi`. Empty selection → `0.0`.
    """)
    _register!(diff, "Intensity $what inside a ROI minus outside it.", """
        $diff(img, roi, args...)

    `$inside(img, roi) − $outside(img, roi)`: how the region differs from its
    surroundings.
    """)
end

stat_frac_above(img::_Img, args...) = _frac_above(img.img, _All(), 0.5)
stat_frac_above(img::_Img, t::Number, args...) = _frac_above(img.img, _All(), clamp_unit(t))
stat_frac_above(img::_Img, roi::Union{_Mask,_Img}, args...) =
    (_check_same_size(img, roi); _frac_above(img.img, _Inside(_roi(roi)...), 0.5))
stat_frac_above(img::_Img, roi::Union{_Mask,_Img}, t::Number, args...) =
    (_check_same_size(img, roi); _frac_above(img.img, _Inside(_roi(roi)...), clamp_unit(t)))
stat_frac_above_out(img::_Img, roi::Union{_Mask,_Img}, args...) =
    (_check_same_size(img, roi); _frac_above(img.img, _Outside(_roi(roi)...), 0.5))
stat_frac_above_out(img::_Img, roi::Union{_Mask,_Img}, t::Number, args...) =
    (_check_same_size(img, roi); _frac_above(img.img, _Outside(_roi(roi)...), clamp_unit(t)))
function stat_frac_above_diff(img::_Img, roi::Union{_Mask,_Img}, t::Number, args...)
    _check_same_size(img, roi)
    mask, is_in = _roi(roi)
    return _frac_above(img.img, _Inside(mask, is_in), clamp_unit(t)) -
           _frac_above(img.img, _Outside(mask, is_in), clamp_unit(t))
end
stat_frac_above_diff(img::_Img, roi::Union{_Mask,_Img}, args...) = stat_frac_above_diff(img, roi, 0.5)

_register!(:stat_frac_above, "Fraction of pixels at or above a threshold (default 0.5).", """
    stat_frac_above(img, [roi], [threshold], args...)

Fraction of the selected pixels with intensity at or above `threshold`
(default `0.5`).
""")
_register!(:stat_frac_above_out, "Fraction of pixels outside a ROI at or above a threshold.", """
    stat_frac_above_out(img, roi, [threshold], args...)

Fraction of the pixels outside `roi` at or above `threshold` (default `0.5`).
""")
_register!(:stat_frac_above_diff, "Inside minus outside fraction of pixels above a threshold.", """
    stat_frac_above_diff(img, roi, [threshold], args...)

`stat_frac_above(img, roi, t) − stat_frac_above_out(img, roi, t)`.
""")

end
