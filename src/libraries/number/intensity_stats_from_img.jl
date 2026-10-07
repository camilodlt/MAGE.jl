"""
Intensity-distribution statistics of an image, over the whole image, inside a
region of interest, outside it, or as the inside − outside difference.

# Bundles

- [`bundle_number_intensityStatsFromImg`](@ref)

The exhaustive, always-current list of operators in each bundle is on the
[Bundle Catalogue](@ref) page.

# How this file is organised

1. A *selection* (`_All`, `_Inside`, `_Outside`) says which pixels count.
2. `_summary` walks the selected pixels once and gathers everything the
   statistics need (count, mean, central moments, histogram, values) in a
   `_Summary`.
3. Each statistic is a small function of the summary (`_std`, `_quantile`,
   `_entropy`, …), listed in `_STATISTICS`.
4. The registration loop turns each statistic into three operators:
   `stat_<name>`, `stat_<name>_out`, `stat_<name>_diff`.

# Example

```julia
using UTCGP, ImageCore
img = SImageND(IntensityPixel{N0f8}.([0.2 0.2; 0.8 0.8]))
roi = SImageND(BinaryPixel.([false false; true true]))      # bottom row
S = UTCGP.number_intensityStatsFromImg

S.stat_mean(img)             # 0.5: the whole image
S.stat_mean(img, roi)        # 0.8: inside the region
S.stat_mean_out(img, roi)    # 0.2: outside it
S.stat_mean_diff(img, roi)   # 0.6: the region is 0.6 brighter than its surroundings
S.stat_frac_above(img)       # 0.5: half the pixels are ≥ 0.5
```
"""
module number_intensityStatsFromImg

using Statistics: quantile!
using ImageCore: N0f8, N0f16
using ..UTCGP: FunctionBundle, append_method!
using ..UTCGP: SImageND, IntensityPixel, BinaryPixel
using ..image2D_object_common: clamp_unit, pixel_value, scratch

# Returned by the bundle when no method matches the inputs.
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

# Type aliases matching any size and any number of dimensions `N` (2D images, 3D volumes).
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
#
# Example: with roi = [false true], `_Inside(roi_pixels, _is_set)` selects
# pixel 2 only, `_Outside(…)` pixel 1 only, `_All()` both.
# ---------------------------------------------------------------------------

"Every pixel."
struct _All end
"Pixels whose ROI pixel `mask[i]` satisfies `is_in`."
struct _Inside{M,P}
    mask::M          # the ROI's pixel array (same size as the image)
    is_in::P         # pixel -> Bool: whether a ROI pixel counts as inside
end
"Pixels whose ROI pixel `mask[i]` does not satisfy `is_in`."
struct _Outside{M,P}
    mask::M          # the ROI's pixel array
    is_in::P         # pixel -> Bool: whether a ROI pixel counts as inside
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

"""
256-level bin of a pixel: the raw byte for 8-bit images, `round(255 v)` otherwise.

Returned 1-based: value `0.0` → bin 1, `1.0` → bin 256. For `N0f8` pixels the
stored byte *is* the level (byte 128 = value 128/255 → bin 129), so no
arithmetic is needed.
"""
@inline _level(p) = clamp(round(Int, clamp(pixel_value(p), 0.0, 1.0) * 255), 0, 255) + 1
@inline _level(p::IntensityPixel{N0f8}) = Int(reinterpret(p.pixel)) + 1

# How quantiles are computed, by pixel storage type (`_Summary.kind`):
"8-bit pixels: the 256-level histogram is exact, quantiles are read from it."
const _KIND_HIST8 = 8
"16-bit pixels: raw values are kept, quantiles by exact radix selection (no sort)."
const _KIND_RAW16 = 16
"Other storage: `Float64` values are kept, quantiles by partial sort."
const _KIND_VALUES = 0

# Pick the kind from the pixel type (resolved at compile time).
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

Example for the values `0.2, 0.2, 0.8, 0.8`: `n = 4`, `mean = 0.5`,
`m2 = 0.09` (variance, std 0.3), `m3 = 0` (symmetric), `m4 = 0.0081`,
`mad = 0.3`.
"""
struct _Summary
    n::Int                       # number of selected pixels
    mean::Float64                # mean value
    m2::Float64                  # mean of (v − mean)²: the variance
    m3::Float64                  # mean of (v − mean)³: sign of the asymmetry
    m4::Float64                  # mean of (v − mean)⁴: weight of the tails
    mad::Float64                 # mean of |v − mean|: mean absolute deviation
    hist::Vector{Int}            # hist[k] = pixels at level k (value (k − 1)/255)
    values::Vector{Float64}      # the selected values (only for _KIND_VALUES)
    raw16::Vector{UInt16}        # the selected raw 16-bit values (only for _KIND_RAW16)
    kind::Int                    # how quantiles are computed: _KIND_HIST8, _KIND_RAW16 or _KIND_VALUES
end

"Summarise the pixels picked by `selection` (see `_Summary`): one pass to collect, one over the values (or the histogram) for the moments."
function _summary(pixels::AbstractArray{P}, selection) where {P}
    kind = _kind(P)
    hist = fill!(scratch(:stats_hist, Int, 256), 0)
    values = scratch(:stats_values, Float64, 0)
    raw16 = scratch(:stats_raw16, UInt16, 0)
    # Room for every pixel; shrunk to the selected count after the loop.
    kind == _KIND_VALUES && resize!(values, length(pixels))
    kind == _KIND_RAW16 && resize!(raw16, length(pixels))
    n = 0
    total = 0.0
    # Pass 1: count, sum and histogram of the selected pixels; keep their values if needed.
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
    # Pass 2: central moments.
    if kind == _KIND_HIST8
        # Moments from the histogram, with an integer level sum so the
        # deviations are exact (0 for a constant region). d = level/255 − mean.
        level_sum = 0
        @inbounds for k in 1:256
            level_sum += hist[k] * (k - 1)
        end
        scale = 1.0 / (255 * n)
        @inbounds for k in 1:256
            c = hist[k]                          # pixels at this level
            c == 0 && continue
            # (k − 1)/255 − level_sum/(255 n), computed as one integer difference times a scale.
            d = ((k - 1) * n - level_sum) * scale
            d2 = d * d
            m2 += c * d2
            m3 += c * d2 * d
            m4 += c * d2 * d2
            mad += c * abs(d)
        end
    else
        @inbounds for i in 1:n
            v = kind == _KIND_RAW16 ? raw16[i] / 65535 : values[i]   # raw 16-bit → value in [0, 1]
            d = v - mean
            d2 = d * d
            m2 += d2
            m3 += d2 * d
            m4 += d2 * d2
            mad += abs(d)
        end
    end
    # Sums → means (population moments, divided by n).
    return _Summary(n, mean, m2 / n, m3 / n, m4 / n, mad / n, hist, values, raw16, kind)
end

"Raw 16-bit storage of an `N0f16` pixel (unused placeholder for other types)."
@inline _raw16(p) = UInt16(0)
@inline _raw16(p::IntensityPixel{N0f16}) = reinterpret(p.pixel)

"""
k-th order statistic (1-based) from an exact 256-level histogram.

The k-th smallest value: walk the levels from dark to bright until `k` pixels
have been counted. Example: `hist` with 3 pixels at level 1 and 2 at level
256 → `k = 3` gives `0.0`, `k = 4` gives `1.0`.
"""
function _order_statistic(hist::Vector{Int}, k::Int)
    running = 0                                  # pixels at or below the current level
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

Example: the value `0x12AB` has high byte `0x12` and low byte `0xAB`. The
first pass finds which of the 256 high-byte bins holds rank `k`; the second
pass counts low bytes only for values in that bin, giving the exact value.
"""
function _order_pair16(raw::Vector{UInt16}, k::Int)
    n = length(raw)
    coarse = fill!(scratch(:stats_radix, Int, 256), 0)
    @inbounds for x in raw
        coarse[(x >> 8) + 1] += 1               # histogram of high bytes
    end
    # (high byte, rank within that high-byte bin) of the value of rank `rank`.
    function locate(rank)
        running = 0                              # values in the bins before b
        @inbounds for b in 1:256
            running + coarse[b] >= rank && return b - 1, rank - running
            running += coarse[b]
        end
        return 255, rank - running
    end
    high_a, rank_a = locate(k)
    high_b, rank_b = locate(min(k + 1, n))
    # Low-byte histograms of the values in the two high-byte bins found.
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
            running >= rank && return ((high << 8) | (b - 1)) / 65535   # rebuild the 16-bit value, scale to [0, 1]
        end
        return 1.0
    end
    return pick(high_a, fine_a, rank_a), pick(high_b, fine_b, rank_b)
end

"""
Quantile `p` with linear interpolation between order statistics (as `Statistics.quantile`).

The quantile sits at position `(n − 1) p + 1` in the sorted values; a
fractional position interpolates between its two neighbours. Example: 5
values, `p = 0.25` → position 2, the 2nd smallest value; `p = 0.3` →
position 2.2, `0.8 · v₂ + 0.2 · v₃`.
"""
function _quantile(s::_Summary, p::Float64)
    s.n == 0 && return 0.0
    s.kind == _KIND_VALUES && return quantile!(s.values, p)     # partial sort of the kept values
    position = (s.n - 1) * p + 1
    k = floor(Int, position)                     # lower neighbour (rank)
    fraction = position - k                      # weight of the upper neighbour
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
"Skewness `m3 / m2^1.5`; `0` for a constant selection. Positive: a long bright tail; negative: a long dark tail."
_skewness(s::_Summary) = s.m2 <= 1e-14 ? 0.0 : s.m3 / s.m2^1.5
"Excess kurtosis `m4 / m2² − 3`; `0` for a constant selection. `0` for a normal distribution, negative for flat or two-peaked ones."
_kurtosis(s::_Summary) = s.m2 <= 1e-14 ? 0.0 : s.m4 / s.m2^2 - 3.0

"""
Bimodality coefficient `(g² + 1) / (k + 3)` (population form); above 5/9 suggests two modes.

`g` is the skewness and `k` the excess kurtosis. Example: two equal peaks
(half the pixels at 0.2, half at 0.8) give `g = 0`, `k = −2`, so `1 / 1 = 1`.
"""
function _bimodality(s::_Summary)
    s.n == 0 && return 0.0
    s.m2 <= 1e-14 && return 0.0                  # constant selection
    return (_skewness(s)^2 + 1) / (_kurtosis(s) + 3.0)
end

"""
The 256-level histogram merged into 32 bins, as probabilities.

Levels 1–8 go to bin 1, 9–16 to bin 2, …, 249–256 to bin 32.
"""
function _coarse_probabilities(s::_Summary)
    p = zeros(_ENTROPY_BINS)
    @inbounds for b in 1:256
        p[(b - 1) * _ENTROPY_BINS ÷ 256 + 1] += s.hist[b]     # 256 / 32 = 8 levels per bin
    end
    return p ./ s.n                              # counts → probabilities
end

"""
Shannon entropy of the 32-bin histogram, divided by its maximum (`log2 32`).

`0` when every pixel falls in one bin (a flat region), `1` when the pixels
are spread evenly over the 32 bins (maximal disorder).
"""
function _entropy(s::_Summary)
    s.n == 0 && return 0.0
    e = 0.0
    for q in _coarse_probabilities(s)
        q > 0 && (e -= q * log2(q))              # empty bins contribute 0 (lim q→0 of q log q)
    end
    return e / log2(_ENTROPY_BINS)
end

"Sum of squared 32-bin probabilities: `1` for a constant region, `1/32` for pixels spread evenly over the bins."
_uniformity(s::_Summary) = s.n == 0 ? 0.0 : sum(abs2, _coarse_probabilities(s))

"""
Otsu on the 256-level histogram: `(threshold, separability)`. The threshold
maximises the between-class variance `w0 (1 − w0) (m0 − m1)²` (class weight
`w0`, class means `m0`, `m1`); separability is that variance over the total
variance. A constant selection gives `(its value, 0)`.

Example: half the pixels at 0.2 and half at 0.8 → threshold `0.2` (pixels
`> 0.2` are the bright class) and separability `1` (the two classes explain
all the variance).
"""
function _otsu(s::_Summary)
    s.n == 0 && return 0.0, 0.0
    # Total sum and sum of squares of the values, from the histogram.
    total_sum = 0.0
    total_sq = 0.0
    @inbounds for b in 1:256
        v = (b - 1) / 255
        total_sum += s.hist[b] * v
        total_sq += s.hist[b] * v * v
    end
    total_var = total_sq / s.n - (total_sum / s.n)^2
    total_var <= 1e-14 && return clamp(total_sum / s.n, 0.0, 1.0), 0.0   # constant: no split possible
    best = -1.0                                    # best between-class variance so far
    best_b = 1                                     # level achieving it
    weight = 0                                     # pixels at levels ≤ b (dark class)
    partial = 0.0                                  # their intensity sum
    @inbounds for b in 1:255
        weight += s.hist[b]
        partial += s.hist[b] * (b - 1) / 255
        (weight == 0 || weight == s.n) && continue  # one class empty: not a split
        w0 = weight / s.n                          # share of pixels in the dark class
        m0 = partial / weight                      # mean of the dark class
        m1 = (total_sum - partial) / (s.n - weight)   # mean of the bright class
        between = w0 * (1 - w0) * (m0 - m1)^2
        if between > best
            best = between
            best_b = b
        end
    end
    # Foreground is `v > threshold`: the threshold is the last level of the dark class.
    return (best_b - 1) / 255, clamp(max(best, 0.0) / total_var, 0.0, 1.0)
end

"""
Fraction of the selected pixels at or above `threshold`; `0` when none is selected.

Example: values `0.2, 0.4, 0.6, 0.8` and `threshold = 0.5` → `2 / 4 = 0.5`.
"""
function _frac_above(pixels::AbstractArray, selection, threshold::Float64)
    n = 0                                          # selected pixels
    above = 0                                      # selected pixels ≥ threshold
    @inbounds for i in eachindex(pixels)
        _selected(selection, i) || continue
        n += 1
        above += pixel_value(pixels[i]) >= threshold   # Bool adds as 0 or 1
    end
    return n == 0 ? 0.0 : above / n
end

# (name, statistic(summary), wording): each becomes stat_<name>, stat_<name>_out and stat_<name>_diff.
# Example: (:mean, s -> s.mean, "mean") defines stat_mean, stat_mean_out and stat_mean_diff.
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

# For each statistic, define and register three operators (e.g. for :mean):
#   stat_mean(img)             over every pixel
#   stat_mean(img, roi)        over the pixels inside roi
#   stat_mean_out(img, roi)    over the pixels outside roi
#   stat_mean_diff(img, roi)   inside minus outside
for (stat, statistic, what) in _STATISTICS
    inside = Symbol(:stat_, stat)
    outside = Symbol(:stat_, stat, :_out)
    diff = Symbol(:stat_, stat, :_diff)
    @eval begin
        $inside(img::_Img, args...) = _stat($statistic, img.img, _All())
        function $inside(img::_Img, roi::Union{_Mask,_Img}, args...)
            _check_same_size(img, roi)
            # _roi(roi)... expands to (roi pixel array, membership test).
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

# stat_frac_above does not fit the summary pattern (it takes a threshold), so its
# methods are written out. `_All()` selects every pixel, `_Inside(…)` / `_Outside(…)`
# the pixels inside / outside the region; the last number is the threshold.
stat_frac_above(img::_Img, args...) = _frac_above(img.img, _All(), 0.5)                            # whole image, threshold 0.5
stat_frac_above(img::_Img, t::Number, args...) = _frac_above(img.img, _All(), clamp_unit(t))       # whole image, threshold t
stat_frac_above(img::_Img, roi::Union{_Mask,_Img}, args...) =                                       # inside roi, threshold 0.5
    (_check_same_size(img, roi); _frac_above(img.img, _Inside(_roi(roi)...), 0.5))
stat_frac_above(img::_Img, roi::Union{_Mask,_Img}, t::Number, args...) =                            # inside roi, threshold t
    (_check_same_size(img, roi); _frac_above(img.img, _Inside(_roi(roi)...), clamp_unit(t)))
stat_frac_above_out(img::_Img, roi::Union{_Mask,_Img}, args...) =                                   # outside roi, threshold 0.5
    (_check_same_size(img, roi); _frac_above(img.img, _Outside(_roi(roi)...), 0.5))
stat_frac_above_out(img::_Img, roi::Union{_Mask,_Img}, t::Number, args...) =                        # outside roi, threshold t
    (_check_same_size(img, roi); _frac_above(img.img, _Outside(_roi(roi)...), clamp_unit(t)))
# Inside minus outside, threshold t …
function stat_frac_above_diff(img::_Img, roi::Union{_Mask,_Img}, t::Number, args...)
    _check_same_size(img, roi)
    mask, is_in = _roi(roi)
    return _frac_above(img.img, _Inside(mask, is_in), clamp_unit(t)) -
           _frac_above(img.img, _Outside(mask, is_in), clamp_unit(t))
end
# … or threshold 0.5.
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
