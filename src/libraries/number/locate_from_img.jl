"""
Mask-free locators: image → normalised coordinate in `[0, 1]`.

# Bundles

- [`bundle_number_locateFromImg`](@ref)

The exhaustive, always-current list of operators in each bundle is on the
[Bundle Catalogue](@ref) page.

# How this file is organised

Most locators share one recipe:

1. pick a *weight* per pixel (a functor such as `_Above(t)`: the pixel value
   when at least `t`, else 0);
2. sum the weights per column (for `x`) or per row (for `y`) into a short
   *profile* vector (`_projection`);
3. read a statistic off the profile (centre of mass, median, peak, …) and
   convert its position to `[0, 1]` (`position_to_unit`: first pixel → 0,
   last pixel → 1).

# Example

```julia
using UTCGP, ImageCore
m = zeros(5, 11); m[2, 9] = 1.0                 # one bright pixel: row 2, column 9
img = SImageND(IntensityPixel{N0f8}.(m))
L = UTCGP.number_locateFromImg

L.com_x(img)        # (9 − 1) / (11 − 1) = 0.8
L.com_y(img)        # (2 − 1) / (5 − 1) = 0.25
L.argmax_x(img)     # 0.8 as well
L.refine_x_25p(img, 0.7, 0.3)   # snaps x = 0.7 onto the bright pixel nearby: 0.8
```
"""
module number_locateFromImg

using ImageCore: N0f8
using ..UTCGP: FunctionBundle, append_method!
using ..UTCGP: SImageND, IntensityPixel, BinaryPixel
using ..image2D_object_common: clamp_unit, position_to_unit, unit_to_position, pixel_value

# Returned by the bundle when no method matches: the image centre.
fallback(args...) = return 0.5

"""
    bundle_number_locateFromImg

Mask-free locators returning where something is in an image, as normalised
coordinates in `[0, 1]` (`x` = column, `y` = row, same convention as the
`region_*` operators so outputs can be wired straight into them).

All operators make one or two passes over the pixels and allocate at most a
few small vectors. Empty selections return `0.5` (the image centre).

- `com_*`, `median_*`, `spread_*`: weighted centre, weighted median and
  weighted spread of the pixel mass, optionally above a threshold.
- `argmax_*`, `argmin_*`: brightest / darkest pixel.
- `projpeak_*`: column (row) with the greatest summed mass.
- `first_*`, `last_*`: extreme foreground pixels along an axis.
- `contrast_*`, `odd_*`, `rare_*`: centre of the pixels that differ from the
  mean, from the dominant (background) value, or that carry rare values.
- `motion_*`: centre of mass of the absolute difference of two images.
- `refine_*_<p>`, `peak_*_<p>`: centre of mass (or argmax) inside a window of
  `p` of the image around a given point. Feeding a rough coordinate through a
  `refine` snaps it onto the nearest mass; chaining refines converges further.

Operators taking a point accept `(img, s)`, meaning `x = y = s`, or
`(img, x, y)`.
"""
bundle_number_locateFromImg = FunctionBundle(fallback)

"Pixel kinds the locators accept."
const LocatablePixel = Union{IntensityPixel,BinaryPixel}
"Bins of the value histogram used by `odd_*` and `rare_*`."
const _HISTOGRAM_BINS = 256
"Default `fraction` of `rare_*`: a value is rare when at most 5% of the pixels carry it."
const _RARE_DEFAULT_FRACTION = 0.05
"Window sizes of `refine_*` and `peak_*`: (name suffix, fraction of the image)."
const _WINDOWS = ((:_10p, 0.10), (:_25p, 0.25), (:_50p, 0.50))

# ---------------------------------------------------------------------------
# Kernels
#
# `axis` selects the returned coordinate: 1 → x (column), 2 → y (row). Note
# this is the reverse of array dimensions; it follows the `_x` / `_y` suffixes.
#
# A *weight* is a functor `pixel -> Float64` giving each pixel's mass. It
# takes the pixel itself (not its value) so that 8-bit images can use their
# raw byte where that is exact (histogram bins).
# ---------------------------------------------------------------------------

"""
Weight: the pixel value when at or above `threshold`, else `0` (negative values weigh `0`).

Example: `_Above(0.5)` gives `0.3 → 0`, `0.7 → 0.7`.
"""
struct _Above
    threshold::Float64       # pixels below it weigh nothing
end
@inline (w::_Above)(p) = (v = pixel_value(p); ifelse(v >= w.threshold, max(v, 0.0), 0.0))

"""
Weight: distance of the pixel value from `center`.

Example: `_AbsDeviation(0.5)` gives `0.2 → 0.3`, `0.9 → 0.4`.
"""
struct _AbsDeviation
    center::Float64          # reference value (e.g. the image mean)
end
@inline (w::_AbsDeviation)(p) = abs(pixel_value(p) - w.center)

"Threshold argument clamped to `[0, 1]`, `NaN` → `0`."
@inline _threshold(t::Real) = clamp_unit(t, 0.0)

"""
Weighted mass statistics over an index window:
`(mass, Σ w·r, Σ w·c, Σ w·r², Σ w·c²)` with `w = weight(pixel)`.

The centre of mass is `(Σ w·r / mass, Σ w·c / mass)`.
"""
@inline function _mass_moments(weight::F, pixels::AbstractMatrix, rows, cols) where {F}
    mass = 0.0
    sum_r = 0.0
    sum_c = 0.0
    sum_rr = 0.0
    sum_cc = 0.0
    @inbounds for c in cols
        fc = Float64(c)
        for r in rows
            w = weight(pixels[r, c])
            w > 0.0 || continue          # weightless pixels change nothing
            fr = Float64(r)
            mass += w
            sum_r += w * fr
            sum_c += w * fc
            sum_rr += w * fr * fr
            sum_cc += w * fc * fc
        end
    end
    return mass, sum_r, sum_c, sum_rr, sum_cc
end

"""
Weighted mass profile for coordinate `axis`: the total weight of each column
(`axis = 1`, x) or of each row (`axis = 2`, y). One SIMD pass; every
mask-free statistic is then computed from this short vector.

Example with `weight = _Above(0)` on `[0 1 0; 0 1 1]`: `axis = 1` gives
column sums `[0, 2, 1]`, `axis = 2` row sums `[1, 2]`.
"""
function _projection(axis::Int, pixels::AbstractMatrix, weight::F) where {F}
    h, w = size(pixels)
    if axis == 1
        # One sum per column: a contiguous loop down each column.
        cols = Vector{Float64}(undef, w)
        @inbounds for c in 1:w
            acc = 0.0
            @simd for r in 1:h
                acc += weight(pixels[r, c])
            end
            cols[c] = acc
        end
        return cols
    end
    # One sum per row: still walk down columns (memory order), adding into rows[r].
    rows = zeros(Float64, h)
    @inbounds for c in 1:w
        @simd for r in 1:h
            rows[r] += weight(pixels[r, c])
        end
    end
    return rows
end

"`(Σ p, Σ i·p, Σ i²·p)` of a profile `p`, positions 1-based."
function _profile_moments(profile::Vector{Float64})
    mass = 0.0
    s1 = 0.0                             # Σ position · weight
    s2 = 0.0                             # Σ position² · weight
    @inbounds for i in eachindex(profile)
        x = profile[i]
        mass += x
        s1 += x * i
        s2 += x * i * i
    end
    return mass, s1, s2
end

"""
Weighted centre of mass along `axis`, normalised; `0.5` when the mass is zero.

Example: profile `[0, 2, 1]` → mean position `(2·2 + 1·3) / 3 = 7/3`, so
`(7/3 − 1) / 2 ≈ 0.67`.
"""
function _com(axis::Int, pixels::AbstractMatrix, weight::F) where {F}
    profile = _projection(axis, pixels, weight)
    mass, s1, _ = _profile_moments(profile)
    mass > 0.0 || return 0.5
    return position_to_unit(s1 / mass, length(profile))
end

"""
Weighted standard deviation along `axis` over the image extent (`n − 1`), clamped to `[0, 1]`; `0` when empty.

Small for a compact object, large when the mass is spread over the image.
"""
function _spread(axis::Int, pixels::AbstractMatrix, weight::F) where {F}
    profile = _projection(axis, pixels, weight)
    mass, s1, s2 = _profile_moments(profile)
    mass > 0.0 || return 0.0
    n = length(profile)
    n <= 1 && return 0.0
    mean = s1 / mass
    # sqrt(E[i²] − E[i]²): the spread in pixels, divided by the axis length in pixels.
    return clamp(sqrt(max(s2 / mass - mean * mean, 0.0)) / (n - 1), 0.0, 1.0)
end

"""
Normalised position of the column (row) with the largest total weight; `0.5` when empty.

Example: profile `[0, 2, 1]` → column 2 → `0.5`.
"""
function _projpeak(axis::Int, pixels::AbstractMatrix, weight::F) where {F}
    profile = _projection(axis, pixels, weight)
    best = argmax(profile)                   # first maximum
    @inbounds profile[best] > 0.0 || return 0.5
    return position_to_unit(Float64(best), length(profile))
end

"""
Weighted median along `axis`: the first line where the cumulative weight reaches half the total.

Example: profile `[1, 0, 0, 3]` (total 4, half 2) → cumulative `1, 1, 1, 4`
reaches 2 at line 4 → `1.0`. Less sensitive to small far-away specks than
the centre of mass.
"""
function _median(axis::Int, pixels::AbstractMatrix, weight::F) where {F}
    profile = _projection(axis, pixels, weight)
    total = sum(profile)
    total > 0.0 || return 0.5
    half = total / 2
    running = 0.0                            # weight of lines 1:i
    @inbounds for i in eachindex(profile)
        running += profile[i]
        running >= half && return position_to_unit(Float64(i), length(profile))
    end
    return 0.5
end

"""
Normalised position of the first (`from_end = false`) or last line along `axis` holding a pixel at or above `threshold`; `0.5` when none.

Example: `first_y` gives the top edge of the foreground, `last_y` its bottom edge.
"""
function _extreme(axis::Int, from_end::Bool, pixels::AbstractMatrix, threshold::Float64)
    profile = _projection(axis, pixels, _Above(threshold))   # > 0 on lines holding a bright pixel
    n = length(profile)
    range = from_end ? (n:-1:1) : (1:n)      # scan from the end for `last_*`
    @inbounds for i in range
        profile[i] > 0.0 && return position_to_unit(Float64(i), n)
    end
    return 0.5
end

"Normalised position along `axis` of the brightest pixel (`direction = 1`) or the darkest (`-1`); first in column-major order on ties."
function _argext(axis::Int, pixels::AbstractMatrix, direction::Float64)
    best_r, best_c = 1, 1
    best = -Inf
    h, w = size(pixels)
    @inbounds for c in 1:w, r in 1:h
        # Multiplying by −1 turns "darkest" into "largest", so one loop serves both.
        v = direction * pixel_value(pixels[r, c])
        if v > best                          # strict: keeps the first one on ties
            best = v
            best_r, best_c = r, c
        end
    end
    return axis == 1 ? position_to_unit(Float64(best_c), w) : position_to_unit(Float64(best_r), h)
end

"Mean pixel value."
function _mean_value(pixels::AbstractMatrix)
    total = 0.0
    @inbounds @simd for i in eachindex(pixels)
        total += pixel_value(pixels[i])
    end
    return total / length(pixels)
end

"""
Histogram bin (1 to 256) of a value in `[0, 1]`: equal-width bins, `1.0` in the last.

Example: `0.0 → 1`, `0.5 → 129`, `1.0 → 256` (`trunc(256 v)` would give 257,
hence the `min`).
"""
@inline _bin(v::Float64) = min(unsafe_trunc(Int, clamp(v, 0.0, 1.0) * _HISTOGRAM_BINS), _HISTOGRAM_BINS - 1) + 1
@inline _pixel_bin(p) = _bin(pixel_value(p))
# For 8-bit pixels the 256-bin index is the raw byte (identical to `_bin`).
@inline _pixel_bin(p::IntensityPixel{N0f8}) = Int(reinterpret(p.pixel)) + 1

"Pixel count per histogram bin."
function _histogram(pixels::AbstractMatrix)
    counts = zeros(Int, _HISTOGRAM_BINS)
    @inbounds for p in pixels
        counts[_pixel_bin(p)] += 1
    end
    return counts
end

"""
Weight: deviation from the dominant value `center`; pixels in the dominant histogram `bin` weigh zero.

Example: on a game screen whose background is uniformly `0.1`, the
background weighs 0 and every sprite weighs its contrast with `0.1`, whether
the sprite is brighter or darker.
"""
struct _OffMode
    bin::Int                 # most populated histogram bin (the background)
    center::Float64          # value at the centre of that bin
end
@inline (w::_OffMode)(p) = ifelse(_pixel_bin(p) == w.bin, 0.0, abs(pixel_value(p) - w.center))

"`_OffMode` weight for an image: its most populated bin, and that bin's centre value."
function _off_mode_weight(pixels::AbstractMatrix)
    bin = argmax(_histogram(pixels))
    return _OffMode(bin, (bin - 0.5) / _HISTOGRAM_BINS)   # bin k covers [(k−1)/256, k/256): centre (k − 0.5)/256
end

"""
Weight: `1` for pixels whose histogram bin is rare, `0` otherwise (looked up in a per-bin table).

Example with `fraction = 0.05` on a 100-pixel image: values carried by at
most 5 pixels weigh 1 (a small sprite), common values weigh 0 (backgrounds,
large areas), whatever their brightness.
"""
struct _Rare
    weights::Vector{Float64}  # weights[bin] = 1.0 if the bin is rare, else 0.0
end
@inline (w::_Rare)(p) = @inbounds w.weights[_pixel_bin(p)]

"`_Rare` weight for an image: bins holding at most `fraction` of the pixels are rare."
function _rare_weight(pixels::AbstractMatrix, fraction::Float64)
    limit = fraction * length(pixels)        # largest pixel count still considered rare
    return _Rare([count <= limit ? 1.0 : 0.0 for count in _histogram(pixels)])
end

"""
Centre of mass along `axis` of `|a − b|`, counting differences at or above `threshold`; `0.5` when none.

Example: two consecutive frames where only a ball moved from column 3 to
column 5: the difference is non-zero at columns 3 and 5, so `motion_x` points
between them, at column 4.
"""
function _motion_com(axis::Int, a::AbstractMatrix, b::AbstractMatrix, threshold::Float64)
    size(a) == size(b) || throw(DimensionMismatch("motion inputs must have the same size"))
    h, w = size(a)
    mass = 0.0
    weighted_position = 0.0                     # Σ difference · (column or row)
    @inbounds for c in 1:w
        acc_mass = 0.0                          # this column's mass, and Σ mass · row
        acc_r = 0.0
        @simd for r in 1:h
            d = abs(pixel_value(a[r, c]) - pixel_value(b[r, c]))
            x = ifelse(d >= threshold, d, 0.0)  # ignore differences below the threshold (noise)
            acc_mass += x
            acc_r += x * r
        end
        mass += acc_mass
        # For x: the whole column sits at position c; for y: use the per-row sum.
        weighted_position += axis == 1 ? acc_mass * c : acc_r
    end
    mass > 0.0 || return 0.5
    return axis == 1 ? position_to_unit(weighted_position / mass, w) : position_to_unit(weighted_position / mass, h)
end

"""
Index window of `fraction` of the image centred on normalised `(x, y)`.

Example: a `100 × 100` image, `fraction = 0.1`, `(x, y) = (0.5, 0.5)` → rows
and columns `45:55` (centre pixel 50 ± 5), clipped at the image border.
"""
function _window(pixels::AbstractMatrix, x::Float64, y::Float64, fraction::Float64)
    h, w = size(pixels)
    half_r = max(round(Int, fraction * h / 2), 1)          # half-height in pixels (at least 1)
    half_c = max(round(Int, fraction * w / 2), 1)          # half-width
    centre_r = round(Int, unit_to_position(y, h))          # y ∈ [0, 1] → row 1…h
    centre_c = round(Int, unit_to_position(x, w))          # x ∈ [0, 1] → column 1…w
    return max(centre_r - half_r, 1):min(centre_r + half_r, h), max(centre_c - half_c, 1):min(centre_c + half_c, w)
end

"Centre of mass inside the window around `(x, y)`; the input coordinate when the window is black."
function _refine(axis::Int, pixels::AbstractMatrix, x::Float64, y::Float64, fraction::Float64)
    rows, cols = _window(pixels, x, y, fraction)
    mass, sum_r, sum_c, _, _ = _mass_moments(_Above(0.0), pixels, rows, cols)
    h, w = size(pixels)
    mass > 0.0 || return axis == 1 ? x : y       # nothing to snap to: keep the input
    return axis == 1 ? position_to_unit(sum_c / mass, w) : position_to_unit(sum_r / mass, h)
end

"Brightest pixel inside the window around `(x, y)` (first in column-major order on ties)."
function _peak(axis::Int, pixels::AbstractMatrix, x::Float64, y::Float64, fraction::Float64)
    rows, cols = _window(pixels, x, y, fraction)
    best = -Inf
    best_r, best_c = first(rows), first(cols)
    @inbounds for c in cols, r in rows
        v = pixel_value(pixels[r, c])
        if v > best
            best = v
            best_r, best_c = r, c
        end
    end
    h, w = size(pixels)
    return axis == 1 ? position_to_unit(Float64(best_c), w) : position_to_unit(Float64(best_r), h)
end

# ---------------------------------------------------------------------------
# Operators
#
# Every operator exists for x and y: <name>_x calls its kernel with axis = 1,
# <name>_y with axis = 2. Inside `@eval`, `$name`, `$axis`, … splice the loop
# values into the generated code; `$($name)` does the same inside the
# docstring (a string within the quoted code).
# ---------------------------------------------------------------------------

"(name suffix, `axis` passed to the kernels, wording for docs)."
const _AXES = ((:_x, 1, "column (x)"), (:_y, 2, "row (y)"))

"Register the function `name` in the bundle."
function _register!(name::Symbol, description::String)
    append_method!(bundle_number_locateFromImg, getfield(@__MODULE__, name), name;
        description = description)
end

for (suffix, axis, axis_doc) in _AXES
    # --- Thresholded mass statistics: (img), (img, t).
    # Each entry is (name stem, kernel function name, default threshold, wording),
    # e.g. (:com, :_com, 0.0, …) defines com_x and com_y.
    for (stem, kernel, default_t, doc) in (
            (:com, :_com, 0.0, "intensity-weighted centre of mass"),
            (:median, :_median, 0.0, "intensity-weighted median position"),
            (:projpeak, :_projpeak, 0.0, "peak of the intensity projection"),
        )
        name = Symbol(stem, suffix)
        @eval begin
            """
                $($name)(img, [threshold], args...)

            Normalised $($axis_doc) of the $($doc). Only pixels at or above
            `threshold` (default `$($default_t)`) contribute. Empty → `0.5`.
            """
            function $name(img::SImageND{S,T,2,C}, args...) where {S,T<:LocatablePixel,C}
                return $kernel($axis, img.img, _Above($default_t))
            end
            function $name(img::SImageND{S,T,2,C}, threshold::Number, args...) where {S,T<:LocatablePixel,C}
                return $kernel($axis, img.img, _Above(_threshold(threshold)))
            end
        end
        _register!(name, "Normalised $axis_doc of the $doc above an optional threshold.")
    end

    # --- spread_x / spread_y: (img), (img, t). Empty gives 0, not 0.5.
    name = Symbol(:spread, suffix)
    @eval begin
        """
            $($name)(img, [threshold], args...)

        Weighted standard deviation of the pixel mass along the $($axis_doc)
        axis, as a fraction of the image extent. Empty → `0.0`.
        """
        function $name(img::SImageND{S,T,2,C}, args...) where {S,T<:LocatablePixel,C}
            return _spread($axis, img.img, _Above(0.0))
        end
        function $name(img::SImageND{S,T,2,C}, threshold::Number, args...) where {S,T<:LocatablePixel,C}
            return _spread($axis, img.img, _Above(_threshold(threshold)))
        end
    end
    _register!(name, "Weighted spread of the pixel mass along the $axis_doc axis.")

    # --- argmax / argmin: (name stem, direction passed to _argext, wording).
    for (stem, direction, doc) in ((:argmax, 1.0, "brightest"), (:argmin, -1.0, "darkest"))
        name = Symbol(stem, suffix)
        @eval begin
            """
                $($name)(img, args...)

            Normalised $($axis_doc) of the $($doc) pixel (first in
            column-major order on ties).
            """
            function $name(img::SImageND{S,T,2,C}, args...) where {S,T<:LocatablePixel,C}
                return _argext($axis, img.img, $direction)
            end
        end
        _register!(name, "Normalised $axis_doc of the $doc pixel.")
    end

    # --- first / last foreground line: (name stem, scan from the end?, wording).
    for (stem, from_end, doc) in ((:first, false, "first"), (:last, true, "last"))
        name = Symbol(stem, suffix)
        @eval begin
            """
                $($name)(img, [threshold], args...)

            Normalised $($axis_doc) of the $($doc) line containing a pixel at or
            above `threshold` (default `0.5`). Empty → `0.5`.
            """
            function $name(img::SImageND{S,T,2,C}, args...) where {S,T<:LocatablePixel,C}
                return _extreme($axis, $from_end, img.img, 0.5)
            end
            function $name(img::SImageND{S,T,2,C}, threshold::Number, args...) where {S,T<:LocatablePixel,C}
                return _extreme($axis, $from_end, img.img, clamp_unit(threshold))
            end
        end
        _register!(name, "Normalised $axis_doc of the $doc foreground line.")
    end

    # --- contrast: centre of mass of |v − image mean|.
    name = Symbol(:contrast, suffix)
    @eval begin
        """
            $($name)(img, args...)

        Normalised $($axis_doc) of the centre of mass of `|v − mean(img)|`:
        where the image departs from its average.
        """
        function $name(img::SImageND{S,T,2,C}, args...) where {S,T<:LocatablePixel,C}
            return _com($axis, img.img, _AbsDeviation(_mean_value(img.img)))
        end
    end
    _register!(name, "Centre ($axis_doc) of the pixels departing from the image mean.")

    # --- odd: centre of mass of the pixels that differ from the dominant value.
    name = Symbol(:odd, suffix)
    @eval begin
        """
            $($name)(img, args...)

        Normalised $($axis_doc) of the centre of mass of `|v − mode(img)|` over the
        pixels outside the dominant (background) value of a 256-bin histogram.
        """
        function $name(img::SImageND{S,T,2,C}, args...) where {S,T<:LocatablePixel,C}
            return _com($axis, img.img, _off_mode_weight(img.img))
        end
    end
    _register!(name, "Centre ($axis_doc) of the pixels departing from the dominant value.")

    # --- rare: centroid of the pixels carrying rare values; (img), (img, fraction).
    name = Symbol(:rare, suffix)
    @eval begin
        """
            $($name)(img, [fraction], args...)

        Normalised $($axis_doc) of the centroid of pixels whose value (256-bin
        histogram) covers at most `fraction` of the image (default `0.05`):
        sprites rather than backgrounds, whatever their colour. Empty → `0.5`.
        """
        function $name(img::SImageND{S,T,2,C}, args...) where {S,T<:LocatablePixel,C}
            return _com($axis, img.img, _rare_weight(img.img, $_RARE_DEFAULT_FRACTION))
        end
        function $name(img::SImageND{S,T,2,C}, fraction::Number, args...) where {S,T<:LocatablePixel,C}
            return _com($axis, img.img, _rare_weight(img.img, clamp_unit(fraction, $_RARE_DEFAULT_FRACTION)))
        end
    end
    _register!(name, "Centre ($axis_doc) of the pixels carrying rare values.")

    # --- motion: two images (any locatable pixel kinds), optional threshold.
    name = Symbol(:motion, suffix)
    @eval begin
        """
            $($name)(a, b, [threshold], args...)

        Normalised $($axis_doc) of the centre of mass of `|a − b|`, counting
        differences at or above `threshold` (default `0`). With two consecutive
        frames this locates what moved. Empty → `0.5`.
        """
        function $name(a::SImageND{S,T,2,C}, b::SImageND{S2,T2,2,C2}, args...) where {
                S,T<:LocatablePixel,C,S2,T2<:LocatablePixel,C2}
            return _motion_com($axis, a.img, b.img, 0.0)
        end
        function $name(a::SImageND{S,T,2,C}, b::SImageND{S2,T2,2,C2}, threshold::Number, args...) where {
                S,T<:LocatablePixel,C,S2,T2<:LocatablePixel,C2}
            return _motion_com($axis, a.img, b.img, _threshold(threshold))
        end
    end
    _register!(name, "Centre ($axis_doc) of the absolute difference of two images.")

    # --- Windowed operators around a point: for every window size (10%, 25%, 50%),
    # refine_<axis>_<p> (centre of mass) and peak_<axis>_<p> (brightest pixel),
    # e.g. refine_x_25p. Each entry is (name stem, kernel function name, wording).
    for (window_suffix, fraction) in _WINDOWS
        for (stem, kernel, doc) in (
                (:refine, :_refine, "centre of mass"),
                (:peak, :_peak, "brightest pixel"),
            )
            name = Symbol(stem, suffix, window_suffix)
            pct = round(Int, 100fraction)        # 10, 25 or 50, for the docs
            @eval begin
                """
                    $($name)(img, s, args...)
                    $($name)(img, x, y, args...)

                Normalised $($axis_doc) of the $($doc) inside a window of
                $($pct)% of the image centred on `(x, y)` (or `(s, s)`). An
                empty window returns the input coordinate unchanged.
                """
                function $name(img::SImageND{S,T,2,C}, s::Number, args...) where {S,T<:LocatablePixel,C}
                    u = clamp_unit(s)
                    return $kernel($axis, img.img, u, u, $fraction)
                end
                function $name(img::SImageND{S,T,2,C}, x::Number, y::Number, args...) where {S,T<:LocatablePixel,C}
                    return $kernel($axis, img.img, clamp_unit(x), clamp_unit(y), $fraction)
                end
            end
            _register!(name, "Normalised $axis_doc of the $doc in a $pct% window around a point.")
        end
    end
end

end
