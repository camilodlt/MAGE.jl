"""
Granulometry: the size distribution of structures, from morphological openings
at increasing radii.

# Bundles

- [`bundle_number_granulometryFromImg`](@ref)

The exhaustive, always-current list of operators in each bundle is on the
[Bundle Catalogue](@ref) page.
"""
module number_granulometryFromImg

using ..UTCGP: FunctionBundle, append_method!
using ..UTCGP: SImageND, IntensityPixel, BinaryPixel
using ..image2D_object_common:
    IsSet, AtLeast, _unit, _value, _fast_predicate, scratch, squared_distance_map!,
    squared_distance_map_upto!

fallback(args...) = return 0.0

"""
    bundle_number_granulometryFromImg

How big are the structures? An *opening* of radius `r` removes everything
narrower than a disk (or square) of that radius and keeps the rest; the
fraction that survives, as `r` grows, is the size distribution.

Binary masks (Euclidean disks, exact):

- `gran_open_r<k>(mask)`, `k ∈ {1, 2, 3, 4, 6, 8}`: fraction of the foreground
  surviving an opening of radius `k`. `gran_open(mask, r)` takes the radius as
  a scalar (`1 + round(15 r)` pixels).
- `gran_open_bg_r<k>(mask)`: the same for the background, so small gaps and
  holes show as a drop.
- `gran_thickness_mean`, `gran_thickness_max`: mean and maximum distance from
  foreground pixels to the background, over half the shorter image side.

Intensity images (square windows of side `2k + 1`):

- `gran_grey_open_r<k>(img)`: share of the total intensity that survives a
  grey opening, i.e. bright structures at least that wide.
- `gran_grey_close_r<k>(img)`: share of the total darkness (`1 − v`) that
  survives a grey closing, i.e. dark structures at least that wide.
- `(img, roi)` measures the shares only inside a region of interest.

Mask inputs: `(mask)`, `(img)` thresholded at `0.5`, `(img, threshold)`. The
image border is not treated as background. Empty inputs → `0.0`.
"""
bundle_number_granulometryFromImg = FunctionBundle(fallback)

const _Img = SImageND{S,T,2,C} where {S,T<:IntensityPixel,C}
const _Mask = SImageND{S,T,2,C} where {S,T<:BinaryPixel,C}
const _RADII = (1, 2, 3, 4, 6, 8)

# ---------------------------------------------------------------------------
# Binary openings by Euclidean disks
# ---------------------------------------------------------------------------

function _foreground(pixels::AbstractMatrix, is_foreground)
    fg = scratch(:gran_fg, Bool, size(pixels)...)
    predicate = _fast_predicate(pixels, is_foreground)
    @inbounds for i in eachindex(pixels, fg)
        fg[i] = predicate(pixels[i])
    end
    return fg
end

"""
Fraction of the `true` pixels of `fg` (or of its complement when `invert`)
surviving an opening by a disk of radius `radius`: erode (distance to the
other phase `> r`), then dilate (distance to the eroded set `≤ r`).
"""
function _open_fraction(fg::AbstractMatrix{Bool}, radius::Int, invert::Bool)
    h, w = size(fg)
    phase = scratch(:gran_phase, Bool, h, w)
    other = scratch(:gran_other, Bool, h, w)
    @inbounds for i in eachindex(fg)
        phase[i] = fg[i] != invert
        other[i] = !phase[i]
    end
    n = count(phase)
    n == 0 && return 0.0
    any(other) || return 1.0
    r2 = Float64(radius^2)
    # Only comparisons with r² are needed, so distances exact up to r suffice.
    d = scratch(:gran_distance, Float64, h, w)
    squared_distance_map_upto!(d, other, radius)
    eroded = other                              # reuse: eroded set
    @inbounds for i in eachindex(d)
        eroded[i] = phase[i] && d[i] > r2
    end
    any(eroded) || return 0.0
    squared_distance_map_upto!(d, eroded, radius)
    survived = 0
    @inbounds for i in eachindex(d)
        survived += phase[i] && d[i] <= r2
    end
    return survived / n
end

function _thickness(fg::AbstractMatrix{Bool}, statistic::Symbol)
    h, w = size(fg)
    n = count(fg)
    n == 0 && return 0.0
    background = scratch(:gran_other, Bool, h, w)
    @inbounds for i in eachindex(fg)
        background[i] = !fg[i]
    end
    scale = 2.0 / min(h, w)
    any(background) || return 1.0
    d = scratch(:gran_distance, Float64, h, w)
    squared_distance_map!(d, background)
    total = 0.0
    largest = 0.0
    @inbounds for i in eachindex(d)
        fg[i] || continue
        v = sqrt(d[i])
        total += v
        largest = max(largest, v)
    end
    value = statistic === :mean ? total / n : largest
    return clamp(value * scale, 0.0, 1.0)
end

# ---------------------------------------------------------------------------
# Grey openings and closings by squares (van Herk / Gil-Werman)
# ---------------------------------------------------------------------------

"""
Running minimum (`take = min`) or maximum over windows of half-width `k`, down
every column of `src` into `dst` (van Herk / Gil-Werman: blocks of `2k + 1`
with forward and backward partial extrema, three comparisons per value
whatever `k`). Windows are clipped at the ends.
"""
function _filter_columns!(dst::Matrix{Float64}, src::Matrix{Float64}, k::Int, take::T) where {T}
    n, w = size(src)
    block = 2k + 1
    forward = scratch(:gran_forward, Float64, n)
    backward = scratch(:gran_backward, Float64, n)
    @inbounds for c in 1:w
        for start in 1:block:n
            stop = min(start + block - 1, n)
            forward[start] = src[start, c]
            for i in start+1:stop
                forward[i] = take(forward[i-1], src[i, c])
            end
            backward[stop] = src[stop, c]
            for i in stop-1:-1:start
                backward[i] = take(backward[i+1], src[i, c])
            end
        end
        # Full windows [i-k, i+k] either span two adjacent blocks or are one
        # whole block: combining the partial extrema is always exact.
        for i in k+1:n-k
            dst[i, c] = take(backward[i-k], forward[i+k])
        end
        # Windows clipped by the ends (at most k on each side): direct.
        for i in Iterators.flatten((1:min(k, n), max(n - k + 1, k + 1):n))
            lo = max(i - k, 1)
            hi = min(i + k, n)
            v = src[lo, c]
            for j in lo+1:hi
                v = take(v, src[j, c])
            end
            dst[i, c] = v
        end
    end
    return dst
end

@inline _fmin(a::Float64, b::Float64) = ifelse(a < b, a, b)
@inline _fmax(a::Float64, b::Float64) = ifelse(a > b, a, b)

"""
Separable square filter (`_fmin` = erosion, `_fmax` = dilation) with windows
clipped at the border. Small windows compare shifted copies of whole
contiguous columns (vectorised); from `k = 5` on, the vertical direction uses
the van Herk / Gil-Werman running extrema.
"""
function _square_filter!(dst::Matrix{Float64}, src::Matrix{Float64}, k::Int, take::T) where {T}
    h, w = size(src)
    tmp = scratch(:gran_tmp, Float64, h, w)
    if k >= 5
        _filter_columns!(tmp, src, k, take)
    else
        @inbounds for c in 1:w
            @simd for r in 1:h
                tmp[r, c] = src[r, c]
            end
            for d in 1:k
                @simd for r in 1+d:h
                    tmp[r, c] = take(tmp[r, c], src[r-d, c])
                end
                @simd for r in 1:h-d
                    tmp[r, c] = take(tmp[r, c], src[r+d, c])
                end
            end
        end
    end
    # Horizontal direction: extremum over neighbouring whole columns.
    @inbounds for c in 1:w
        @simd for r in 1:h
            dst[r, c] = tmp[r, c]
        end
        for d in 1:k
            if c - d >= 1
                @simd for r in 1:h
                    dst[r, c] = take(dst[r, c], tmp[r, c-d])
                end
            end
            if c + d <= w
                @simd for r in 1:h
                    dst[r, c] = take(dst[r, c], tmp[r, c+d])
                end
            end
        end
    end
    return dst
end

@inline _roi_in(p::BinaryPixel) = p.pixel == true
@inline _roi_in(p) = Float64(p) >= 0.5

"Share of the intensity (`closing = false`) or darkness surviving a grey opening (closing)."
function _grey_fraction(pixels::AbstractMatrix, k::Int, closing::Bool, roi)
    h, w = size(pixels)
    values = scratch(:gran_values, Float64, h, w)
    @inbounds for i in eachindex(pixels)
        values[i] = clamp(_value(pixels[i]), 0.0, 1.0)
    end
    first_pass = scratch(:gran_first, Float64, h, w)
    result = scratch(:gran_result, Float64, h, w)
    if closing
        _square_filter!(first_pass, values, k, _fmax)
        _square_filter!(result, first_pass, k, _fmin)
    else
        _square_filter!(first_pass, values, k, _fmin)
        _square_filter!(result, first_pass, k, _fmax)
    end
    before = 0.0
    after = 0.0
    @inbounds for i in eachindex(values)
        roi === nothing || _roi_in(roi[i]) || continue
        if closing
            before += 1.0 - values[i]
            after += 1.0 - result[i]
        else
            before += values[i]
            after += result[i]
        end
    end
    return before <= 0.0 ? 0.0 : clamp(after / before, 0.0, 1.0)
end

# ---------------------------------------------------------------------------
# Registration
# ---------------------------------------------------------------------------

macro _mask_methods(name, compute)
    name, compute = esc(name), esc(compute)
    return quote
        $name(mask::_Mask, args...) = $compute(_foreground(mask.img, IsSet()))
        $name(img::_Img, args...) = $compute(_foreground(img.img, AtLeast(0.5)))
        $name(img::_Img, threshold::Number, args...) =
            $compute(_foreground(img.img, AtLeast(_unit(threshold))))
    end
end

function _register!(name::Symbol, description::String, doc::String)
    @eval @doc $doc $name
    append_method!(bundle_number_granulometryFromImg, getfield(@__MODULE__, name), name;
        description = description)
end

_mask_doc(name, what) = """
    $name(mask, args...)
    $name(img, [threshold], args...)

$what Intensity inputs are thresholded at `threshold` (default `0.5`).
"""

for radius in _RADII
    name = Symbol(:gran_open_r, radius)
    compute = fg -> _open_fraction(fg, radius, false)
    @eval @_mask_methods $name $compute
    _register!(name, "Fraction of the foreground surviving an opening by a disk of radius $radius.",
        _mask_doc(name, "Fraction of the foreground surviving an opening by a Euclidean disk of radius $radius pixels."))

    name = Symbol(:gran_open_bg_r, radius)
    compute = fg -> _open_fraction(fg, radius, true)
    @eval @_mask_methods $name $compute
    _register!(name, "Fraction of the background surviving an opening by a disk of radius $radius.",
        _mask_doc(name, "Fraction of the background surviving an opening by a Euclidean disk of radius $radius pixels: low when the background is made of small gaps."))

    for (stem, closing, what) in ((:gran_grey_open_r, false, "intensity surviving a grey opening"),
                                  (:gran_grey_close_r, true, "darkness surviving a grey closing"))
        name = Symbol(stem, radius)
        side = 2radius + 1
        @eval begin
            $name(img::_Img, args...) = _grey_fraction(img.img, $radius, $closing, nothing)
            function $name(img::_Img, roi::Union{_Mask,_Img}, args...)
                size(img) == size(roi) || throw(DimensionMismatch("image and region must have the same size"))
                return _grey_fraction(img.img, $radius, $closing, roi.img)
            end
        end
        _register!(name, "Share of the $what with a $(side)x$(side) square.", """
            $name(img, [roi], args...)

        Share of the total $what with a $(side)×$(side) square (only inside
        `roi` when given). Structures narrower than the square are removed.
        """)
    end
end

let compute = fg -> _thickness(fg, :mean)
    @eval @_mask_methods gran_thickness_mean $compute
end
let compute = fg -> _thickness(fg, :max)
    @eval @_mask_methods gran_thickness_max $compute
end
_register!(:gran_thickness_mean, "Mean distance from foreground pixels to the background.",
    _mask_doc(:gran_thickness_mean, "Mean distance from foreground pixels to the nearest background pixel, over half the shorter image side."))
_register!(:gran_thickness_max, "Largest distance from a foreground pixel to the background.",
    _mask_doc(:gran_thickness_max, "Largest distance from a foreground pixel to the nearest background pixel (the radius of the largest inscribed disk), over half the shorter image side."))

gran_open(mask::_Mask, r::Number, args...) = _open_fraction(_foreground(mask.img, IsSet()), 1 + round(Int, 15 * _unit(r)), false)
gran_open(img::_Img, r::Number, args...) = _open_fraction(_foreground(img.img, AtLeast(0.5)), 1 + round(Int, 15 * _unit(r)), false)
gran_open(img::_Img, r::Number, threshold::Number, args...) =
    _open_fraction(_foreground(img.img, AtLeast(_unit(threshold))), 1 + round(Int, 15 * _unit(r)), false)
_register!(:gran_open, "Fraction of the foreground surviving an opening of radius 1 + round(15 r).", """
    gran_open(mask, r, args...)
    gran_open(img, r, [threshold], args...)

Fraction of the foreground surviving an opening by a Euclidean disk of radius
`1 + round(15 r)` pixels, `r ∈ [0, 1]`.
""")

end
