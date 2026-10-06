"""
Geometric transforms that keep the image size: flips, rotations, shifts, and
mask-driven canonical poses.

# Bundles

- bundle_image2DIntensity_transform_factory
- bundle_image2DBinary_transform_factory
- bundle_image2DSegment_transform_factory

The exhaustive operator list is on the Bundle Catalogue page.
"""
module image2D_transform

using ..UTCGP: FunctionBundle, append_method!
using ..UTCGP:
    AbstractPixel,
    BinaryPixel,
    IntensityPixel,
    SegmentPixel,
    SImageND,
    SizedImage,
    SizedImage2D,
    _get_image_pixel_type,
    _get_image_tuple_size,
    _get_image_type,
    _validate_factory_type
using ..image2D_object_common: IsSet, AtLeast, _unit
using ..image2D_zoom: _store, _zero

fallback(args...) = return nothing

const _COMMON_DOC = """
All operators keep the specialised size and pixel type. Pixels that come from
outside the image are zero. Intensity images are resampled bilinearly; binary
masks and segment maps use nearest neighbour, so their values are never
blended.

- `transform_flip_h`, `transform_flip_v`, `transform_rotate_180`: exact.
- `transform_rotate_90`, `transform_rotate_270`: exact on square images; on
  rectangular ones the rotated image is stretched back to the original size.
- `transform_rotate(img, a)`: rotation by `a` turns (`0.25` = 90°
  counter-clockwise on screen) about the centre.
- `transform_shift(img, dx, dy)` / `(img, s)`: translation by `(u − 0.5)` of
  the image size per axis, so `0.5` is no shift, `0` moves half the image
  left/up and `1` half right/down. `transform_shift_wrap` wraps around
  instead of filling with zero.
- `transform_flip_h_if_right`, `transform_flip_v_if_bottom`: flip so the mask's
  foreground lies in the left (top) half. Mirrored situations then look the
  same, e.g. the ball on either side of a Pong court.
- `transform_align_axis`: rotate about the centre so the foreground's main
  axis is horizontal. `transform_canonical_pose` also moves the foreground's
  centroid to the centre.

Mask-driven operators accept `(img, mask)` with a binary mask or an intensity
map thresholded at `0.5`; `(img)` uses the image itself (binary, or intensity
at `0.5`).
"""

"""
    bundle_image2DIntensity_transform_factory

Same-size geometric transforms of intensity images (bilinear resampling).

$_COMMON_DOC
"""
const bundle_image2DIntensity_transform_factory = FunctionBundle(fallback)

"""
    bundle_image2DBinary_transform_factory

Same-size geometric transforms of binary masks (nearest neighbour).

$_COMMON_DOC
"""
const bundle_image2DBinary_transform_factory = FunctionBundle(fallback)

"""
    bundle_image2DSegment_transform_factory

Same-size geometric transforms of segment maps (nearest neighbour).

$_COMMON_DOC
"""
const bundle_image2DSegment_transform_factory = FunctionBundle(fallback)

# ---------------------------------------------------------------------------
# Sampling
# ---------------------------------------------------------------------------

"""
Resample `src` through `source_of(i, j) -> (row, col)`, a map from each output
pixel to a continuous source position. Out-of-image samples are zero.
Positions are range-checked as floats first, so the integer conversions need
no overflow checks.
"""
function _warp(src::AbstractMatrix{P}, source_of::F) where {P,F}
    h, w = size(src)
    out = similar(src)
    z = _zero(P)
    @inbounds for j in 1:w, i in 1:h
        r, c = source_of(i, j)
        if 0.5 <= r < h + 0.5 && 0.5 <= c < w + 0.5
            ri = unsafe_trunc(Int, round(r))
            ci = unsafe_trunc(Int, round(c))
            out[i, j] = (1 <= ri <= h && 1 <= ci <= w) ? src[ri, ci] : z
        else
            out[i, j] = z
        end
    end
    return out
end

function _warp(src::AbstractMatrix{IntensityPixel{T}}, source_of::F) where {T,F}
    h, w = size(src)
    out = similar(src)
    zero_pixel = IntensityPixel{T}(_store(T, 0.0))
    @inline value(r, c) = (1 <= r <= h && 1 <= c <= w) ? Float64(src[r, c].pixel) : 0.0
    @inbounds for j in 1:w, i in 1:h
        r, c = source_of(i, j)
        if !(0.0 < r < h + 1.0 && 0.0 < c < w + 1.0)
            out[i, j] = zero_pixel
            continue
        end
        r0 = unsafe_trunc(Int, r)             # r > 0, so truncation is floor
        c0 = unsafe_trunc(Int, c)
        fr = r - r0
        fc = c - c0
        if 1 <= r0 < h && 1 <= c0 < w
            v_aa = Float64(src[r0, c0].pixel)
            v_ab = Float64(src[r0, c0+1].pixel)
            v_ba = Float64(src[r0+1, c0].pixel)
            v_bb = Float64(src[r0+1, c0+1].pixel)
        else
            v_aa = value(r0, c0)
            v_ab = value(r0, c0 + 1)
            v_ba = value(r0 + 1, c0)
            v_bb = value(r0 + 1, c0 + 1)
        end
        top = v_aa + fc * (v_ab - v_aa)
        bottom = v_ba + fc * (v_bb - v_ba)
        out[i, j] = IntensityPixel{T}(_store(T, top + fr * (bottom - top)))
    end
    return out
end

function _flip_h(src::AbstractMatrix)
    h, w = size(src)
    out = similar(src)
    @inbounds for j in 1:w, i in 1:h
        out[i, j] = src[i, w + 1 - j]
    end
    return out
end

function _flip_v(src::AbstractMatrix)
    h, w = size(src)
    out = similar(src)
    @inbounds for j in 1:w, i in 1:h
        out[i, j] = src[h + 1 - i, j]
    end
    return out
end

function _rotate_180(src::AbstractMatrix)
    h, w = size(src)
    out = similar(src)
    @inbounds for j in 1:w, i in 1:h
        out[i, j] = src[h + 1 - i, w + 1 - j]
    end
    return out
end

"Rotate 90° (k = 1) or 270° (k = 3) counter-clockwise on screen, stretched back to size."
function _rotate_quarter(src::AbstractMatrix, k::Int)
    h, w = size(src)
    if h == w
        # Square: an exact permutation (what the sampler below computes too).
        out = similar(src)
        @inbounds for j in 1:w, i in 1:h
            out[i, j] = k == 1 ? src[j, w + 1 - i] : src[h + 1 - j, i]
        end
        return out
    end
    # Output (i, j) on an h×w grid maps to the rotated w×h grid, then to src.
    return _warp(src, (i, j) -> begin
        u = 1 + (i - 1) * (w - 1) / max(h - 1, 1)   # row in the rotated (w×h) image
        v = 1 + (j - 1) * (h - 1) / max(w - 1, 1)   # column in the rotated image
        k == 1 ? (v, w + 1 - u) : (h + 1 - v, u)
    end)
end

"Rotate by `turns` (fraction of a full turn, counter-clockwise on screen) about `(cr, cc)`, then put that point at `(tr, tc)`."
function _rotate(src::AbstractMatrix, turns::Float64, cr::Float64, cc::Float64, tr::Float64, tc::Float64)
    s, c = sincospi(2turns)
    return _warp(src, (i, j) -> begin
        dy = i - tr
        dx = j - tc
        # Inverse of a counter-clockwise screen rotation (rows point down):
        # rotate the output offset clockwise to find its source.
        (cr + c * dy + s * dx, cc + c * dx - s * dy)
    end)
end

_rotate(src::AbstractMatrix, turns::Float64) =
    (h = size(src, 1); w = size(src, 2); _rotate(src, turns, (h + 1) / 2, (w + 1) / 2, (h + 1) / 2, (w + 1) / 2))

@inline _offset(u::Float64, n::Int) = round(Int, (u - 0.5) * n)

function _shift(src::AbstractMatrix{P}, dx::Float64, dy::Float64, wrap::Bool) where {P}
    h, w = size(src)
    oc = _offset(dx, w)
    or = _offset(dy, h)
    out = similar(src)
    z = _zero(P)
    @inbounds for j in 1:w
        c = j - oc
        if wrap
            c = mod1(c, w)
            shift = mod(or, h)                  # 0 ≤ shift < h
            for i in 1:h
                r = i - shift
                out[i, j] = src[r < 1 ? r + h : r, c]
            end
        elseif 1 <= c <= w
            for i in 1:h
                r = i - or
                out[i, j] = (1 <= r <= h) ? src[r, c] : z
            end
        else
            for i in 1:h
                out[i, j] = z
            end
        end
    end
    return out
end

"Foreground count, centroid and central second moments of `mask`."
function _foreground_moments(mask::AbstractMatrix, is_foreground::P) where {P}
    n = 0
    sr = sc = srr = scc = src_ = 0.0
    @inbounds for c in axes(mask, 2), r in axes(mask, 1)
        is_foreground(mask[r, c]) || continue
        n += 1
        sr += r
        sc += c
        srr += r * r
        scc += c * c
        src_ += r * c
    end
    n == 0 && return 0, 0.0, 0.0, 0.0, 0.0, 0.0
    mr, mc = sr / n, sc / n
    return n, mr, mc, srr / n - mr^2, scc / n - mc^2, src_ / n - mr * mc
end

"Main-axis angle in turns, counter-clockwise on screen from the +x axis."
function _axis_turns(v_rr, v_cc, v_rc)
    abs(v_cc - v_rr) + 2abs(v_rc) <= 1e-9 * (v_rr + v_cc + 1e-12) && return 0.0
    θ = 0.5 * atan(2v_rc, v_cc - v_rr)        # towards +rows, i.e. clockwise on screen
    return -θ / 2π
end

function _align(src::AbstractMatrix, mask::AbstractMatrix, is_foreground, recenter::Bool)
    n, mr, mc, v_rr, v_cc, v_rc = _foreground_moments(mask, is_foreground)
    n == 0 && return src
    h, w = size(src)
    turns = -_axis_turns(v_rr, v_cc, v_rc)
    if recenter
        return _rotate(src, turns, mr, mc, (h + 1) / 2, (w + 1) / 2)
    end
    return _rotate(src, turns)
end

function _flip_if(src::AbstractMatrix, mask::AbstractMatrix, is_foreground, axis::Int)
    n, mr, mc, _, _, _ = _foreground_moments(mask, is_foreground)
    n == 0 && return src
    h, w = size(src)
    if axis == 2
        return mc > (w + 1) / 2 ? _flip_h(src) : src
    end
    return mr > (h + 1) / 2 ? _flip_v(src) : src
end

# ---------------------------------------------------------------------------
# Factories
# ---------------------------------------------------------------------------

_bundle_for(::Type{<:IntensityPixel}) = bundle_image2DIntensity_transform_factory
_bundle_for(::Type{<:BinaryPixel}) = bundle_image2DBinary_transform_factory
_bundle_for(::Type{<:SegmentPixel}) = bundle_image2DSegment_transform_factory

function _prelude(::Type{I}, operator::Symbol) where {I}
    IT = _get_image_type(I)
    _validate_factory_type(IT)
    return _get_image_pixel_type(I), _get_image_tuple_size(I), Symbol(operator, :_, Symbol(I))
end

"`kernel(src)`; signature `(img)`."
function _plain_factory(::Type{I}, operator::Symbol, kernel::K) where {I,K}
    _, S, name = _prelude(I, operator)
    return @eval function $name(src::CONCT, args::Vararg{Any}) where {CONCT<:$I}
        return SImageND($kernel(src.img), $S)
    end
end

"`kernel(src, u)`; signature `(img, u)`."
function _scalar_factory(::Type{I}, operator::Symbol, kernel::K) where {I,K}
    _, S, name = _prelude(I, operator)
    return @eval function $name(src::CONCT, u::Real, args::Vararg{Any}) where {CONCT<:$I}
        return SImageND($kernel(src.img, _unit(u)), $S)
    end
end

"`kernel(src, x, y)`; signatures `(img, s)` (x = y = s) and `(img, x, y)`."
function _point_factory(::Type{I}, operator::Symbol, kernel::K) where {I,K}
    _, S, name = _prelude(I, operator)
    fn = @eval function $name(src::CONCT, x::Real, y::Real, args::Vararg{Any}) where {CONCT<:$I}
        return SImageND($kernel(src.img, _unit(x), _unit(y)), $S)
    end
    @eval function $name(src::CONCT, s::Real, args::Vararg{Any}) where {CONCT<:$I}
        u = _unit(s)
        return SImageND($kernel(src.img, u, u), $S)
    end
    return fn
end

"`kernel(src, mask, is_foreground)`; signatures `(img, mask)` and `(img)`."
function _mask_factory(::Type{I}, operator::Symbol, kernel::K) where {I,K}
    PT, S, name = _prelude(I, operator)
    fn = @eval function $name(src::CONCT, mask::MASK, args::Vararg{Any}) where {CONCT<:$I,BT,MASK<:SizedImage{$S,BinaryPixel{BT}}}
        return SImageND($kernel(src.img, mask.img, IsSet()), $S)
    end
    @eval function $name(src::CONCT, saliency::SAL, args::Vararg{Any}) where {CONCT<:$I,ST,SAL<:SizedImage{$S,IntensityPixel{ST}}}
        return SImageND($kernel(src.img, saliency.img, AtLeast(0.5)), $S)
    end
    if PT <: BinaryPixel
        @eval function $name(src::CONCT, args::Vararg{Any}) where {CONCT<:$I}
            return SImageND($kernel(src.img, src.img, IsSet()), $S)
        end
    elseif PT <: IntensityPixel
        @eval function $name(src::CONCT, args::Vararg{Any}) where {CONCT<:$I}
            return SImageND($kernel(src.img, src.img, AtLeast(0.5)), $S)
        end
    end
    return fn
end

_builder(factory, operator::Symbol, kernel) = I -> factory(I, operator, kernel)

const _OPERATORS = (
    (:transform_flip_h, _plain_factory, src -> _flip_h(src), "Mirrors left-right."),
    (:transform_flip_v, _plain_factory, src -> _flip_v(src), "Mirrors top-bottom."),
    (:transform_rotate_180, _plain_factory, src -> _rotate_180(src), "Rotates by 180 degrees."),
    (:transform_rotate_90, _plain_factory, src -> _rotate_quarter(src, 1),
        "Rotates 90 degrees counter-clockwise (stretched back to size if not square)."),
    (:transform_rotate_270, _plain_factory, src -> _rotate_quarter(src, 3),
        "Rotates 90 degrees clockwise (stretched back to size if not square)."),
    (:transform_rotate, _scalar_factory, (src, a) -> _rotate(src, a),
        "Rotates by a fraction of a turn about the centre."),
    (:transform_shift, _point_factory, (src, x, y) -> _shift(src, x, y, false),
        "Translates by (u - 0.5) of the size per axis, zero fill."),
    (:transform_shift_wrap, _point_factory, (src, x, y) -> _shift(src, x, y, true),
        "Translates by (u - 0.5) of the size per axis, wrapping around."),
    (:transform_flip_h_if_right, _mask_factory, (src, m, fg) -> _flip_if(src, m, fg, 2),
        "Mirrors left-right when the mask's centroid is in the right half."),
    (:transform_flip_v_if_bottom, _mask_factory, (src, m, fg) -> _flip_if(src, m, fg, 1),
        "Mirrors top-bottom when the mask's centroid is in the bottom half."),
    (:transform_align_axis, _mask_factory, (src, m, fg) -> _align(src, m, fg, false),
        "Rotates about the centre so the mask's main axis is horizontal."),
    (:transform_canonical_pose, _mask_factory, (src, m, fg) -> _align(src, m, fg, true),
        "Moves the mask's centroid to the centre and its main axis to horizontal."),
)

for (operator, factory, kernel, description) in _OPERATORS
    factory_name = Symbol(operator, :_image2D_factory)
    builder = _builder(factory, operator, kernel)
    @eval function $factory_name(output_type::Type{I}) where {S1,S2,P,I<:SizedImage2D{S1,S2,P}}
        return $builder(output_type)
    end
    doc = """
        $(factory_name)(::Type{I})

    Specialises `$operator`. $description
    """
    @eval @doc $doc $factory_name
    for kind in (IntensityPixel, BinaryPixel, SegmentPixel)
        append_method!(_bundle_for(kind), getfield(@__MODULE__, factory_name), operator;
            description = description)
    end
end

end
