"""
Mask-free locators: image → normalised coordinate in `[0, 1]`.

# Bundles

- [`bundle_number_locateFromImg`](@ref)

The exhaustive, always-current list of operators in each bundle is on the
[Bundle Catalogue](@ref) page.
"""
module number_locateFromImg

using ImageCore: N0f8
using ..UTCGP: FunctionBundle, append_method!
using ..UTCGP: SImageND, IntensityPixel, BinaryPixel
using ..image2D_object_common: _unit, _to_unit, _to_position, _value

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

const LocatablePixel = Union{IntensityPixel,BinaryPixel}
const _HISTOGRAM_BINS = 256
const _RARE_DEFAULT_FRACTION = 0.05
const _WINDOWS = ((:_10p, 0.10), (:_25p, 0.25), (:_50p, 0.50))

# ---------------------------------------------------------------------------
# Kernels
# ---------------------------------------------------------------------------

# Weight functors take the pixel itself, so 8-bit images can use their raw
# byte where that is exact (histogram bins).

struct _Above
    threshold::Float64
end
@inline (w::_Above)(p) = (v = _value(p); ifelse(v >= w.threshold, max(v, 0.0), 0.0))

struct _AbsDeviation
    center::Float64
end
@inline (w::_AbsDeviation)(p) = abs(_value(p) - w.center)

@inline _threshold(t::Real) = _unit(t, 0.0)

"""
Weighted mass statistics over an index window: `(mass, Σ w r, Σ w c, Σ w r², Σ w c²)`.
"""
@inline function _mass_moments(weight::F, pixels::AbstractMatrix, rows, cols) where {F}
    mass = 0.0
    sr = 0.0
    sc = 0.0
    srr = 0.0
    scc = 0.0
    @inbounds for c in cols
        fc = Float64(c)
        for r in rows
            w = weight(pixels[r, c])
            w > 0.0 || continue
            fr = Float64(r)
            mass += w
            sr += w * fr
            sc += w * fc
            srr += w * fr * fr
            scc += w * fc * fc
        end
    end
    return mass, sr, sc, srr, scc
end

"""
Weighted mass profile along `axis`: per column (`axis = 1`) or per row
(`axis = 2`). One SIMD pass; every mask-free statistic is then computed from
this short vector.
"""
function _projection(axis::Int, pixels::AbstractMatrix, weight::F) where {F}
    h, w = size(pixels)
    if axis == 1
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
    rows = zeros(Float64, h)
    @inbounds for c in 1:w
        @simd for r in 1:h
            rows[r] += weight(pixels[r, c])
        end
    end
    return rows
end

"`(Σ p, Σ i p, Σ i² p)` of a profile `p`, positions 1-based."
function _profile_moments(profile::Vector{Float64})
    m = 0.0
    s1 = 0.0
    s2 = 0.0
    @inbounds for i in eachindex(profile)
        x = profile[i]
        m += x
        s1 += x * i
        s2 += x * i * i
    end
    return m, s1, s2
end

function _com(axis::Int, pixels::AbstractMatrix, weight::F) where {F}
    profile = _projection(axis, pixels, weight)
    mass, s1, _ = _profile_moments(profile)
    mass > 0.0 || return 0.5
    return _to_unit(s1 / mass, length(profile))
end

function _spread(axis::Int, pixels::AbstractMatrix, weight::F) where {F}
    profile = _projection(axis, pixels, weight)
    mass, s1, s2 = _profile_moments(profile)
    mass > 0.0 || return 0.0
    n = length(profile)
    n <= 1 && return 0.0
    m = s1 / mass
    return clamp(sqrt(max(s2 / mass - m * m, 0.0)) / (n - 1), 0.0, 1.0)
end

function _projpeak(axis::Int, pixels::AbstractMatrix, weight::F) where {F}
    profile = _projection(axis, pixels, weight)
    best = argmax(profile)
    @inbounds profile[best] > 0.0 || return 0.5
    return _to_unit(Float64(best), length(profile))
end

function _median(axis::Int, pixels::AbstractMatrix, weight::F) where {F}
    profile = _projection(axis, pixels, weight)
    total = sum(profile)
    total > 0.0 || return 0.5
    half = total / 2
    running = 0.0
    @inbounds for i in eachindex(profile)
        running += profile[i]
        running >= half && return _to_unit(Float64(i), length(profile))
    end
    return 0.5
end

"First (`from_end = false`) or last foreground index along an axis."
function _extreme(axis::Int, from_end::Bool, pixels::AbstractMatrix, threshold::Float64)
    profile = _projection(axis, pixels, _Above(threshold))
    n = length(profile)
    range = from_end ? (n:-1:1) : (1:n)
    @inbounds for i in range
        profile[i] > 0.0 && return _to_unit(Float64(i), n)
    end
    return 0.5
end

function _argext(axis::Int, pixels::AbstractMatrix, direction::Float64)
    best_r, best_c = 1, 1
    best = -Inf
    h, w = size(pixels)
    @inbounds for c in 1:w, r in 1:h
        v = direction * _value(pixels[r, c])
        if v > best
            best = v
            best_r, best_c = r, c
        end
    end
    return axis == 1 ? _to_unit(Float64(best_c), w) : _to_unit(Float64(best_r), h)
end

function _mean_value(pixels::AbstractMatrix)
    total = 0.0
    @inbounds @simd for i in eachindex(pixels)
        total += _value(pixels[i])
    end
    return total / length(pixels)
end

@inline _bin(v::Float64) = min(unsafe_trunc(Int, clamp(v, 0.0, 1.0) * _HISTOGRAM_BINS), _HISTOGRAM_BINS - 1) + 1
@inline _pixel_bin(p) = _bin(_value(p))
# For 8-bit pixels the 256-bin index is the raw byte (identical to `_bin`).
@inline _pixel_bin(p::IntensityPixel{N0f8}) = Int(reinterpret(p.pixel)) + 1

function _histogram(pixels::AbstractMatrix)
    counts = zeros(Int, _HISTOGRAM_BINS)
    @inbounds for p in pixels
        counts[_pixel_bin(p)] += 1
    end
    return counts
end

"Deviation from the dominant value; pixels in the dominant bin weigh zero."
struct _OffMode
    bin::Int
    center::Float64
end
@inline (w::_OffMode)(p) = ifelse(_pixel_bin(p) == w.bin, 0.0, abs(_value(p) - w.center))

function _off_mode_weight(pixels::AbstractMatrix)
    bin = argmax(_histogram(pixels))
    return _OffMode(bin, (bin - 0.5) / _HISTOGRAM_BINS)
end

"Weight 1 for pixels whose histogram bin is rare, 0 otherwise (a per-bin table)."
struct _Rare
    weights::Vector{Float64}
end
@inline (w::_Rare)(p) = @inbounds w.weights[_pixel_bin(p)]

function _rare_weight(pixels::AbstractMatrix, fraction::Float64)
    limit = fraction * length(pixels)
    return _Rare([count <= limit ? 1.0 : 0.0 for count in _histogram(pixels)])
end

function _motion_com(axis::Int, a::AbstractMatrix, b::AbstractMatrix, threshold::Float64)
    size(a) == size(b) || throw(DimensionMismatch("motion inputs must have the same size"))
    h, w = size(a)
    mass = 0.0
    s = 0.0
    @inbounds for c in 1:w
        acc_mass = 0.0
        acc_r = 0.0
        @simd for r in 1:h
            d = abs(_value(a[r, c]) - _value(b[r, c]))
            x = ifelse(d >= threshold, d, 0.0)
            acc_mass += x
            acc_r += x * r
        end
        mass += acc_mass
        s += axis == 1 ? acc_mass * c : acc_r
    end
    mass > 0.0 || return 0.5
    return axis == 1 ? _to_unit(s / mass, w) : _to_unit(s / mass, h)
end

"Index window of `fraction` of the image centred on normalised `(x, y)`."
function _window(pixels::AbstractMatrix, x::Float64, y::Float64, fraction::Float64)
    h, w = size(pixels)
    half_r = max(round(Int, fraction * h / 2), 1)
    half_c = max(round(Int, fraction * w / 2), 1)
    cr = round(Int, _to_position(y, h))
    cc = round(Int, _to_position(x, w))
    return max(cr - half_r, 1):min(cr + half_r, h), max(cc - half_c, 1):min(cc + half_c, w)
end

function _refine(axis::Int, pixels::AbstractMatrix, x::Float64, y::Float64, fraction::Float64)
    rows, cols = _window(pixels, x, y, fraction)
    mass, sr, sc, _, _ = _mass_moments(_Above(0.0), pixels, rows, cols)
    h, w = size(pixels)
    mass > 0.0 || return axis == 1 ? x : y
    return axis == 1 ? _to_unit(sc / mass, w) : _to_unit(sr / mass, h)
end

function _peak(axis::Int, pixels::AbstractMatrix, x::Float64, y::Float64, fraction::Float64)
    rows, cols = _window(pixels, x, y, fraction)
    best = -Inf
    best_r, best_c = first(rows), first(cols)
    @inbounds for c in cols, r in rows
        v = _value(pixels[r, c])
        if v > best
            best = v
            best_r, best_c = r, c
        end
    end
    h, w = size(pixels)
    return axis == 1 ? _to_unit(Float64(best_c), w) : _to_unit(Float64(best_r), h)
end

# ---------------------------------------------------------------------------
# Operators
# ---------------------------------------------------------------------------

const _AXES = ((:_x, 1, "column (x)"), (:_y, 2, "row (y)"))

function _register!(name::Symbol, description::String)
    append_method!(bundle_number_locateFromImg, getfield(@__MODULE__, name), name;
        description = description)
end

for (suffix, axis, axis_doc) in _AXES
    # --- thresholded mass statistics: (img), (img, t)
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
                return _extreme($axis, $from_end, img.img, _unit(threshold))
            end
        end
        _register!(name, "Normalised $axis_doc of the $doc foreground line.")
    end

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
            return _com($axis, img.img, _rare_weight(img.img, _unit(fraction, $_RARE_DEFAULT_FRACTION)))
        end
    end
    _register!(name, "Centre ($axis_doc) of the pixels carrying rare values.")

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

    for (window_suffix, fraction) in _WINDOWS
        for (stem, kernel, doc) in (
                (:refine, :_refine, "centre of mass"),
                (:peak, :_peak, "brightest pixel"),
            )
            name = Symbol(stem, suffix, window_suffix)
            pct = round(Int, 100fraction)
            @eval begin
                """
                    $($name)(img, s, args...)
                    $($name)(img, x, y, args...)

                Normalised $($axis_doc) of the $($doc) inside a window of
                $($pct)% of the image centred on `(x, y)` (or `(s, s)`). An
                empty window returns the input coordinate unchanged.
                """
                function $name(img::SImageND{S,T,2,C}, s::Number, args...) where {S,T<:LocatablePixel,C}
                    u = _unit(s)
                    return $kernel($axis, img.img, u, u, $fraction)
                end
                function $name(img::SImageND{S,T,2,C}, x::Number, y::Number, args...) where {S,T<:LocatablePixel,C}
                    return $kernel($axis, img.img, _unit(x), _unit(y), $fraction)
                end
            end
            _register!(name, "Normalised $axis_doc of the $doc in a $pct% window around a point.")
        end
    end
end

end
