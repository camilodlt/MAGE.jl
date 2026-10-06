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
using ..image2D_object_common: _unit, _value, scratch

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

`roi` is a binary mask, or an intensity map thresholded at `0.5`.
`stat_frac_above` takes the threshold as its last argument (default `0.5`).
An empty selection gives `0.0`.
"""
bundle_number_intensityStatsFromImg = FunctionBundle(fallback)

const _Img = SImageND{S,T,2,C} where {S,T<:IntensityPixel,C}
const _Mask = SImageND{S,T,2,C} where {S,T<:BinaryPixel,C}
const _ENTROPY_BINS = 32

# ---------------------------------------------------------------------------
# Selection: which pixels are summarised
# ---------------------------------------------------------------------------

struct _All end
struct _Inside{M,P}
    mask::M
    is_in::P
end
struct _Outside{M,P}
    mask::M
    is_in::P
end
@inline _selected(::_All, i) = true
@inline _selected(s::_Inside, i) = @inbounds s.is_in(s.mask[i])
@inline _selected(s::_Outside, i) = @inbounds !s.is_in(s.mask[i])

@inline _is_set(p) = p.pixel == true
@inline _at_half(p) = Float64(p) >= 0.5
_roi(mask::_Mask) = (mask.img, _is_set)
_roi(mask::_Img) = (mask.img, _at_half)

# ---------------------------------------------------------------------------
# Summary of the selected pixels
# ---------------------------------------------------------------------------

"256-level bin of a pixel: the raw byte for 8-bit images, `round(255 v)` otherwise."
@inline _level(p) = clamp(round(Int, clamp(_value(p), 0.0, 1.0) * 255), 0, 255) + 1
@inline _level(p::IntensityPixel{N0f8}) = Int(reinterpret(p.pixel)) + 1

"""
Moments and 256-level histogram of the selected pixels, plus what quantiles
need: nothing more for 8-bit images (the histogram is exact), the raw 16-bit
values for `N0f16` images (exact radix selection, no sort), the values
themselves otherwise (partial sort).
"""
struct _Summary
    n::Int
    mean::Float64
    m2::Float64          # central moments (population)
    m3::Float64
    m4::Float64
    mad::Float64
    hist::Vector{Int}
    values::Vector{Float64}
    raw16::Vector{UInt16}
    kind::Int            # 8: exact histogram, 16: raw values, 0: values
end

_kind(::Type{IntensityPixel{N0f8}}) = 8
_kind(::Type{IntensityPixel{N0f16}}) = 16
_kind(::Type) = 0

function _summary(pixels::AbstractMatrix{P}, selection) where {P}
    kind = _kind(P)
    hist = fill!(scratch(:stats_hist, Int, 256), 0)
    values = scratch(:stats_values, Float64, 0)
    raw16 = scratch(:stats_raw16, UInt16, 0)
    kind == 0 && resize!(values, length(pixels))
    kind == 16 && resize!(raw16, length(pixels))
    n = 0
    total = 0.0
    @inbounds for i in eachindex(pixels)
        _selected(selection, i) || continue
        p = pixels[i]
        v = _value(p)
        n += 1
        total += v
        hist[_level(p)] += 1
        if kind == 0
            values[n] = v
        elseif kind == 16
            raw16[n] = _raw16(p)
        end
    end
    kind == 0 ? resize!(values, n) : empty!(values)
    kind == 16 ? resize!(raw16, n) : empty!(raw16)
    n == 0 && return _Summary(0, 0.0, 0.0, 0.0, 0.0, 0.0, hist, values, raw16, kind)
    mean = total / n
    m2 = m3 = m4 = mad = 0.0
    if kind == 8
        # Integer level sum, so deviations are exact (0 for a constant region).
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
            v = kind == 16 ? raw16[i] / 65535 : values[i]
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
    s.kind == 0 && return quantile!(s.values, p)
    position = (s.n - 1) * p + 1
    k = floor(Int, position)
    fraction = position - k
    if s.kind == 8
        low = _order_statistic(s.hist, k)
        fraction == 0.0 && return low
        high = _order_statistic(s.hist, k + 1)
    else
        low, high = _order_pair16(s.raw16, k)
        fraction == 0.0 && return low
    end
    return low + fraction * (high - low)
end

_std(s::_Summary) = sqrt(s.m2)
_skewness(s::_Summary) = s.m2 <= 1e-14 ? 0.0 : s.m3 / s.m2^1.5
_kurtosis(s::_Summary) = s.m2 <= 1e-14 ? 0.0 : s.m4 / s.m2^2 - 3.0

"Bimodality coefficient `(g² + 1) / (k + 3)` (population form); above 5/9 suggests two modes."
function _bimodality(s::_Summary)
    s.n == 0 && return 0.0
    s.m2 <= 1e-14 && return 0.0
    return (_skewness(s)^2 + 1) / (_kurtosis(s) + 3.0)
end

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

"Otsu on the 256-level histogram: `(threshold, separability)`."
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
    weight = 0
    partial = 0.0
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

function _frac_above(pixels::AbstractMatrix, selection, threshold::Float64)
    n = 0
    above = 0
    @inbounds for i in eachindex(pixels)
        _selected(selection, i) || continue
        n += 1
        above += _value(pixels[i]) >= threshold
    end
    return n == 0 ? 0.0 : above / n
end

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

function _check(img, roi)
    size(img) == size(roi) || throw(DimensionMismatch("image and region must have the same size"))
    return nothing
end

@inline function _stat(statistic::F, pixels, selection) where {F}
    s = _summary(pixels, selection)
    s.n == 0 && return 0.0
    return Float64(statistic(s))
end

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
            _check(img, roi)
            return _stat($statistic, img.img, _Inside(_roi(roi)...))
        end
        function $outside(img::_Img, roi::Union{_Mask,_Img}, args...)
            _check(img, roi)
            return _stat($statistic, img.img, _Outside(_roi(roi)...))
        end
        function $diff(img::_Img, roi::Union{_Mask,_Img}, args...)
            _check(img, roi)
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
stat_frac_above(img::_Img, t::Number, args...) = _frac_above(img.img, _All(), _unit(t))
stat_frac_above(img::_Img, roi::Union{_Mask,_Img}, args...) =
    (_check(img, roi); _frac_above(img.img, _Inside(_roi(roi)...), 0.5))
stat_frac_above(img::_Img, roi::Union{_Mask,_Img}, t::Number, args...) =
    (_check(img, roi); _frac_above(img.img, _Inside(_roi(roi)...), _unit(t)))
stat_frac_above_out(img::_Img, roi::Union{_Mask,_Img}, args...) =
    (_check(img, roi); _frac_above(img.img, _Outside(_roi(roi)...), 0.5))
stat_frac_above_out(img::_Img, roi::Union{_Mask,_Img}, t::Number, args...) =
    (_check(img, roi); _frac_above(img.img, _Outside(_roi(roi)...), _unit(t)))
function stat_frac_above_diff(img::_Img, roi::Union{_Mask,_Img}, t::Number, args...)
    _check(img, roi)
    mask, is_in = _roi(roi)
    return _frac_above(img.img, _Inside(mask, is_in), _unit(t)) -
           _frac_above(img.img, _Outside(mask, is_in), _unit(t))
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
