"""
Attention operators: crop a region found by a mask or given by coordinates and
resize it back to the full image size, or translate the image so a point lands
in the centre.

# Bundles

- bundle_image2DIntensity_zoom_factory
- bundle_image2DBinary_zoom_factory
- bundle_image2DSegment_zoom_factory

The exhaustive operator list is on the Bundle Catalogue page.
"""
module image2D_zoom

using ImageCore: Normed
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
using ..image2D_object_common:
    scratch,
    ObjectTable,
    IsSet,
    AtLeast,
    _unit,
    _to_position,
    object_table,
    centroid_row,
    centroid_col,
    SELECTOR_FUNCTIONS,
    SELECTOR_DESCRIPTIONS,
    select_by_mean

fallback(args...) = return nothing

const _COMMON_DOC = """
Window conventions shared by all zoom operators:

- The crop is resized back to the specialised image size: bilinear for
  intensity images, nearest neighbour for binary masks and segment maps, so
  labels and mask values are never blended.
- Windows reaching past the border are clipped to the image; nothing is
  padded.
- `margin ∈ [0, 1]` (default `0.1`) grows a bounding box by that fraction of
  its own height and width on each side.
- An empty mask leaves the image unchanged.
- Coordinates are normalised to `[0, 1]` (`x` = column, `y` = row) like the
  locator libraries, and `(img, s)` means `x = y = s`.
"""

"""
    bundle_image2DIntensity_zoom_factory

Attention operators returning a same-size intensity image: crop around a mask,
a selected object or a point, then resize back (bilinear).

- `zoom_crop_bbox[_<sel>]`: bounding box of the foreground, or of the object
  chosen by a selector (`largest`, `most_circular`, `brightest`, …).
- `zoom_crop_aspect[_<sel>]`: same box widened to the image aspect ratio, so
  shapes are not stretched.
- `zoom_crop_isolate[_<sel>]`: same box with everything outside the
  object(s) set to zero.
- `zoom_recenter[_<sel>]`: translate the object centroid to the image centre
  without rescaling (borders filled with zero).
- `zoom_glimpse_<p>`, `zoom_center`, `zoom_rows`, `zoom_cols`,
  `zoom_recenter_point`: coordinate-driven windows.

Mask-driven signatures: `(img)`, `(img, threshold)` and
`(img, threshold, margin)` use the image itself as the mask;
`(img, mask)` and `(img, mask, margin)` take a binary mask or an intensity map
thresholded at `0.5`.

$_COMMON_DOC
"""
const bundle_image2DIntensity_zoom_factory = FunctionBundle(fallback)

"""
    bundle_image2DBinary_zoom_factory

Attention operators returning a same-size binary mask, resized with nearest
neighbour. Same operators as `bundle_image2DIntensity_zoom_factory` except the
source-statistic selectors. Mask-driven signatures: `(mask)` and
`(mask, margin)` zoom on the mask's own foreground; `(mask, other)` and
`(mask, other, margin)` use another binary mask or intensity map.

$_COMMON_DOC
"""
const bundle_image2DBinary_zoom_factory = FunctionBundle(fallback)

"""
    bundle_image2DSegment_zoom_factory

Attention operators returning a same-size segment (label) map, resized with
nearest neighbour so labels are preserved. Mask-driven signatures:
`(labels, mask)` and `(labels, mask, margin)` with a binary mask or an
intensity map thresholded at `0.5`.

$_COMMON_DOC
"""
const bundle_image2DSegment_zoom_factory = FunctionBundle(fallback)

const _DEFAULT_MARGIN = 0.1

# ---------------------------------------------------------------------------
# Pixel helpers
# ---------------------------------------------------------------------------

@inline _zero(::Type{P}) where {T,P<:AbstractPixel{T}} = P(zero(T))

@inline _store(::Type{T}, v::Float64) where {T<:AbstractFloat} = T(v)
@inline _store(::Type{T}, v::Float64) where {T<:Integer} = round(T, v)
@inline _store(::Type{T}, v::Float64) where {T<:Real} =
    T(clamp(v, Float64(typemin(T)), Float64(typemax(T))))
# Fixed-point storage (N0f8, N0f16, …): round the raw integer directly instead
# of going through the checked conversion.
@inline function _store(::Type{Normed{U,f}}, v::Float64) where {U,f}
    scale = Float64((one(UInt64) << f) - one(UInt64))
    raw = clamp(muladd(v, scale, 0.5), 0.0, Float64(typemax(U)))
    return reinterpret(Normed{U,f}, unsafe_trunc(U, raw))
end

# ---------------------------------------------------------------------------
# Which pixels survive the crop
# ---------------------------------------------------------------------------

struct _KeepAll end
@inline (::_KeepAll)(r::Int, c::Int) = true

struct _KeepLabel
    labels::Matrix{Int32}
    id::Int32
end
@inline (k::_KeepLabel)(r::Int, c::Int) = @inbounds k.labels[r, c] == k.id

struct _KeepForeground{M<:AbstractMatrix,P}
    mask::M
    is_foreground::P
end
@inline (k::_KeepForeground)(r::Int, c::Int) = @inbounds k.is_foreground(k.mask[r, c])

# ---------------------------------------------------------------------------
# Resampling a window back to full size
# ---------------------------------------------------------------------------

"Nearest-neighbour resize of `src[r0:r1, c0:c1]` to `size(src)`."
function _resample_nearest(src::AbstractMatrix{P}, r0::Int, r1::Int, c0::Int, c1::Int, keep::K) where {P,K}
    h, w = size(src)
    hc = r1 - r0 + 1
    wc = c1 - c0 + 1
    rows = scratch(:zoom_nearest_rows, Int, h)
    @inbounds for i in 1:h
        rows[i] = r0 + ((2i - 1) * hc) ÷ (2h)
    end
    out = similar(src)
    z = _zero(P)
    @inbounds for j in 1:w
        c = c0 + ((2j - 1) * wc) ÷ (2w)
        for i in 1:h
            r = rows[i]
            out[i, j] = keep(r, c) ? src[r, c] : z
        end
    end
    return out
end

"Lower/upper source index and weight of output index `i` in `lo:hi`."
@inline function _source_coordinate(i::Int, n::Int, lo::Int, hi::Int)
    position = lo - 0.5 + (i - 0.5) * (hi - lo + 1) / n
    position = clamp(position, Float64(lo), Float64(hi))
    a = unsafe_trunc(Int, position)
    b = min(a + 1, hi)
    return a, b, position - a
end

"""
Bilinear resize of `src[r0:r1, c0:c1]` to `size(src)` (intensity pixels), in two
separable passes: horizontal interpolation of every crop row into a scratch
buffer (contiguous, vectorisable), then vertical interpolation. The arithmetic
is the same as interpolating each output pixel from its four neighbours,
horizontal first.
"""
function _resample_bilinear(
        src::AbstractMatrix{IntensityPixel{T}},
        r0::Int, r1::Int, c0::Int, c1::Int,
        keep::K,
    ) where {T,K}
    h, w = size(src)
    rows = r1 - r0 + 1
    horizontal = scratch(:zoom_horizontal, Float64, rows, w)
    @inbounds for j in 1:w
        ca, cb, fx = _source_coordinate(j, w, c0, c1)
        @simd for k in 1:rows
            r = r0 + k - 1
            v_a = keep(r, ca) ? Float64(src[r, ca].pixel) : 0.0
            v_b = keep(r, cb) ? Float64(src[r, cb].pixel) : 0.0
            horizontal[k, j] = v_a + fx * (v_b - v_a)
        end
    end
    row_a = scratch(:zoom_row_a, Int, h)
    row_b = scratch(:zoom_row_b, Int, h)
    row_f = scratch(:zoom_row_f, Float64, h)
    @inbounds for i in 1:h
        ra, rb, fy = _source_coordinate(i, h, r0, r1)
        row_a[i], row_b[i], row_f[i] = ra - r0 + 1, rb - r0 + 1, fy
    end
    out = similar(src)
    @inbounds for j in 1:w
        for i in 1:h
            top = horizontal[row_a[i], j]
            bottom = horizontal[row_b[i], j]
            out[i, j] = IntensityPixel{T}(_store(T, top + row_f[i] * (bottom - top)))
        end
    end
    return out
end

@inline _resample(src::AbstractMatrix{<:IntensityPixel}, r0, r1, c0, c1, keep) =
    _resample_bilinear(src, r0, r1, c0, c1, keep)
@inline _resample(src::AbstractMatrix, r0, r1, c0, c1, keep) =
    _resample_nearest(src, r0, r1, c0, c1, keep)

"Translate so pixel position `(row, col)` lands on the image centre."
function _translate(src::AbstractMatrix{P}, row::Float64, col::Float64) where {P}
    h, w = size(src)
    dr = round(Int, row - (h + 1) / 2, RoundNearestTiesUp)
    dc = round(Int, col - (w + 1) / 2, RoundNearestTiesUp)
    out = similar(src)
    z = _zero(P)
    @inbounds for j in 1:w
        c = j + dc
        for i in 1:h
            r = i + dr
            out[i, j] = (1 <= r <= h && 1 <= c <= w) ? src[r, c] : z
        end
    end
    return out
end

# ---------------------------------------------------------------------------
# Windows
# ---------------------------------------------------------------------------

abstract type _Mode end
struct _Box <: _Mode end
struct _Aspect <: _Mode end
struct _Isolate <: _Mode end
struct _Recenter <: _Mode end

"Grow a box by `margin` of its size per side, optionally to the image aspect, then clip."
function _expand_box(r0::Int, r1::Int, c0::Int, c1::Int, h::Int, w::Int, margin::Float64, aspect::Bool)
    bh = r1 - r0 + 1
    bw = c1 - c0 + 1
    mr = round(Int, margin * bh)
    mc = round(Int, margin * bw)
    r0 -= mr
    r1 += mr
    c0 -= mc
    c1 += mc
    if aspect
        bh = r1 - r0 + 1
        bw = c1 - c0 + 1
        # Box aspect bh / bw must equal the image aspect h / w.
        if bh * w > bw * h
            extra = cld(bh * w, h) - bw
            c0 -= extra ÷ 2
            c1 += extra - extra ÷ 2
        else
            extra = cld(bw * h, w) - bh
            r0 -= extra ÷ 2
            r1 += extra - extra ÷ 2
        end
    end
    return max(r0, 1), min(r1, h), max(c0, 1), min(c1, w)
end

"Bounding box of every foreground pixel, or `nothing`."
function _foreground_box(mask::AbstractMatrix, is_foreground::P) where {P}
    h, w = size(mask)
    r0, r1, c0, c1 = h + 1, 0, w + 1, 0
    @inbounds for c in 1:w, r in 1:h
        is_foreground(mask[r, c]) || continue
        r0 = min(r0, r)
        r1 = max(r1, r)
        c0 = min(c0, c)
        c1 = max(c1, c)
    end
    r1 == 0 && return nothing
    return r0, r1, c0, c1
end

function _foreground_centroid(mask::AbstractMatrix, is_foreground::P) where {P}
    n = 0
    sr = 0.0
    sc = 0.0
    @inbounds for c in axes(mask, 2), r in axes(mask, 1)
        is_foreground(mask[r, c]) || continue
        n += 1
        sr += r
        sc += c
    end
    return n, sr / max(n, 1), sc / max(n, 1)
end

"Zoom on the whole foreground of `mask`. Returns a pixel matrix."
function _zoom_foreground(src::AbstractMatrix, mask::AbstractMatrix, is_foreground, mode::_Mode, margin::Float64)
    if mode isa _Recenter
        n, row, col = _foreground_centroid(mask, is_foreground)
        return n == 0 ? src : _translate(src, row, col)
    end
    box = _foreground_box(mask, is_foreground)
    box === nothing && return src
    h, w = size(src)
    r0, r1, c0, c1 = _expand_box(box..., h, w, margin, mode isa _Aspect)
    keep = mode isa _Isolate ? _KeepForeground(mask, is_foreground) : _KeepAll()
    return _resample(src, r0, r1, c0, c1, keep)
end

"Zoom on the object `select(table, src)` of `mask`. Returns a pixel matrix."
function _zoom_object(src::AbstractMatrix, mask::AbstractMatrix, is_foreground, select::F, mode::_Mode, margin::Float64) where {F}
    t = object_table(mask, is_foreground)
    id = select(t, src)
    id == 0 && return src
    mode isa _Recenter && return _translate(src, centroid_row(t, id), centroid_col(t, id))
    h, w = size(src)
    r0, r1, c0, c1 = _expand_box(t.min_r[id], t.max_r[id], t.min_c[id], t.max_c[id],
        h, w, margin, mode isa _Aspect)
    keep = mode isa _Isolate ? _KeepLabel(t.labels, Int32(id)) : _KeepAll()
    return _resample(src, r0, r1, c0, c1, keep)
end

"Window of `fraction` of the image centred on normalised `(x, y)`, clipped."
function _point_window(h::Int, w::Int, x::Float64, y::Float64, fraction::Float64)
    half_r = (fraction * h) / 2
    half_c = (fraction * w) / 2
    cr = _to_position(y, h)
    cc = _to_position(x, w)
    r0 = clamp(round(Int, cr - half_r + 0.5), 1, h)
    r1 = clamp(round(Int, cr + half_r - 0.5), r0, h)
    c0 = clamp(round(Int, cc - half_c + 0.5), 1, w)
    c1 = clamp(round(Int, cc + half_c - 0.5), c0, w)
    return r0, r1, c0, c1
end

function _zoom_point(src::AbstractMatrix, x::Float64, y::Float64, fraction::Float64)
    h, w = size(src)
    return _resample(src, _point_window(h, w, x, y, fraction)..., _KeepAll())
end

"Band between two normalised positions along `axis` (1 = rows, 2 = columns)."
function _zoom_band(src::AbstractMatrix, axis::Int, a::Float64, b::Float64)
    h, w = size(src)
    lo, hi = minmax(a, b)
    n = axis == 1 ? h : w
    i0 = clamp(round(Int, _to_position(lo, n)), 1, n)
    i1 = clamp(round(Int, _to_position(hi, n)), i0, n)
    return axis == 1 ? _resample(src, i0, i1, 1, w, _KeepAll()) :
           _resample(src, 1, h, i0, i1, _KeepAll())
end

# ---------------------------------------------------------------------------
# Factory builders
# ---------------------------------------------------------------------------

_bundle_for(::Type{<:IntensityPixel}) = bundle_image2DIntensity_zoom_factory
_bundle_for(::Type{<:BinaryPixel}) = bundle_image2DBinary_zoom_factory
_bundle_for(::Type{<:SegmentPixel}) = bundle_image2DSegment_zoom_factory

"""
Specialise a mask-driven operator. `kernel(src, mask, is_foreground, margin)`
returns the output pixel matrix.
"""
function _mask_driven_factory(::Type{I}, operator::Symbol, kernel::K) where {I,K}
    IT = _get_image_type(I)
    PT = _get_image_pixel_type(I)
    S = _get_image_tuple_size(I)
    _validate_factory_type(IT)
    function_name = Symbol(operator, :_, Symbol(I))

    fn = @eval function $function_name(
            src::CONCT,
            mask::MASK,
            margin::Real,
            args::Vararg{Any},
        ) where {CONCT<:$I,BT,MASK<:SizedImage{$S,BinaryPixel{BT}}}
        return SImageND($kernel(src.img, mask.img, IsSet(), _unit(margin, $_DEFAULT_MARGIN)), $S)
    end
    @eval function $function_name(
            src::CONCT,
            mask::MASK,
            args::Vararg{Any},
        ) where {CONCT<:$I,BT,MASK<:SizedImage{$S,BinaryPixel{BT}}}
        return SImageND($kernel(src.img, mask.img, IsSet(), $_DEFAULT_MARGIN), $S)
    end
    @eval function $function_name(
            src::CONCT,
            saliency::SAL,
            margin::Real,
            args::Vararg{Any},
        ) where {CONCT<:$I,ST,SAL<:SizedImage{$S,IntensityPixel{ST}}}
        return SImageND($kernel(src.img, saliency.img, AtLeast(0.5), _unit(margin, $_DEFAULT_MARGIN)), $S)
    end
    @eval function $function_name(
            src::CONCT,
            saliency::SAL,
            args::Vararg{Any},
        ) where {CONCT<:$I,ST,SAL<:SizedImage{$S,IntensityPixel{ST}}}
        return SImageND($kernel(src.img, saliency.img, AtLeast(0.5), $_DEFAULT_MARGIN), $S)
    end

    if PT <: BinaryPixel
        # The mask zooms on its own foreground.
        @eval function $function_name(src::CONCT, args::Vararg{Any}) where {CONCT<:$I}
            return SImageND($kernel(src.img, src.img, IsSet(), $_DEFAULT_MARGIN), $S)
        end
        @eval function $function_name(src::CONCT, margin::Real, args::Vararg{Any}) where {CONCT<:$I}
            return SImageND($kernel(src.img, src.img, IsSet(), _unit(margin, $_DEFAULT_MARGIN)), $S)
        end
    elseif PT <: IntensityPixel
        # The image is thresholded to find its own foreground.
        @eval function $function_name(src::CONCT, args::Vararg{Any}) where {CONCT<:$I}
            return SImageND($kernel(src.img, src.img, AtLeast(0.5), $_DEFAULT_MARGIN), $S)
        end
        @eval function $function_name(src::CONCT, threshold::Real, args::Vararg{Any}) where {CONCT<:$I}
            return SImageND($kernel(src.img, src.img, AtLeast(_unit(threshold)), $_DEFAULT_MARGIN), $S)
        end
        @eval function $function_name(
                src::CONCT,
                threshold::Real,
                margin::Real,
                args::Vararg{Any},
            ) where {CONCT<:$I}
            return SImageND(
                $kernel(src.img, src.img, AtLeast(_unit(threshold)), _unit(margin, $_DEFAULT_MARGIN)),
                $S,
            )
        end
    end
    return fn
end

"Specialise a point-driven operator: `kernel(src, x, y)`; `(src)` uses the centre."
function _point_driven_factory(::Type{I}, operator::Symbol, kernel::K) where {I,K}
    IT = _get_image_type(I)
    S = _get_image_tuple_size(I)
    _validate_factory_type(IT)
    function_name = Symbol(operator, :_, Symbol(I))
    fn = @eval function $function_name(src::CONCT, x::Real, y::Real, args::Vararg{Any}) where {CONCT<:$I}
        return SImageND($kernel(src.img, _unit(x), _unit(y)), $S)
    end
    @eval function $function_name(src::CONCT, s::Real, args::Vararg{Any}) where {CONCT<:$I}
        u = _unit(s)
        return SImageND($kernel(src.img, u, u), $S)
    end
    @eval function $function_name(src::CONCT, args::Vararg{Any}) where {CONCT<:$I}
        return SImageND($kernel(src.img, 0.5, 0.5), $S)
    end
    return fn
end

# ---------------------------------------------------------------------------
# Operators
# ---------------------------------------------------------------------------

const _MODES = (
    (:zoom_crop_bbox, _Box(), "crops the bounding box of", "and resizes it back"),
    (:zoom_crop_aspect, _Aspect(), "crops the bounding box, widened to the image aspect ratio, of", "and resizes it back"),
    (:zoom_crop_isolate, _Isolate(), "crops the bounding box of", "with other pixels zeroed, and resizes it back"),
    (:zoom_recenter, _Recenter(), "translates the centroid of", "to the image centre (margin ignored)"),
)

const _ALL_KINDS = (IntensityPixel, BinaryPixel, SegmentPixel)

"Define a factory function and register it in the bundles of `kinds`."
function _define_factory!(factory_name::Symbol, operator::Symbol, builder, kinds, description::String, doc::String)
    @eval function $factory_name(output_type::Type{I}) where {S1,S2,P,I<:SizedImage2D{S1,S2,P}}
        return $builder(output_type)
    end
    @eval @doc $doc $factory_name
    factory = getfield(@__MODULE__, factory_name)
    for kind in kinds
        append_method!(_bundle_for(kind), factory, operator; description = description)
    end
end

# Closures are built inside functions so each captures its own arguments
# (loop variables reassigned in an enclosing loop body would be shared).
_mask_builder(operator::Symbol, kernel) = I -> _mask_driven_factory(I, operator, kernel)
_point_builder(operator::Symbol, kernel) = I -> _point_driven_factory(I, operator, kernel)
_foreground_kernel(mode::_Mode) =
    (src, mask, fg, margin) -> _zoom_foreground(src, mask, fg, mode, margin)
_object_kernel(select, mode::_Mode) =
    (src, mask, fg, margin) -> _zoom_object(src, mask, fg, select, mode, margin)
_fixed_select(select_fn) = (t, src) -> select_fn(t)
_mean_select(direction::Float64) = (t, src) -> select_by_mean(t, src, direction)
_glimpse_kernel(fraction::Float64) = (src, x, y) -> _zoom_point(src, x, y, fraction)

for (prefix, mode, verb, tail) in _MODES
    # Whole foreground.
    operator = prefix
    _define_factory!(Symbol(operator, :_image2D_factory), operator,
        _mask_builder(operator, _foreground_kernel(mode)), _ALL_KINDS,
        "Zoom that $verb the whole mask foreground $tail.",
        """
            $(operator)_image2D_factory(::Type{I})

        Specialises `$operator`, which $verb the whole foreground of a mask
        $tail.
        """)

    # Selected object.
    for (selector, select_fn) in SELECTOR_FUNCTIONS
        operator = Symbol(prefix, :_, selector)
        criterion = SELECTOR_DESCRIPTIONS[selector]
        _define_factory!(Symbol(operator, :_image2D_factory), operator,
            _mask_builder(operator, _object_kernel(_fixed_select(select_fn), mode)), _ALL_KINDS,
            "Zoom that $verb the object with the $criterion $tail.",
            """
                $(operator)_image2D_factory(::Type{I})

            Specialises `$operator`, which $verb the 8-connected object with
            the $criterion $tail.
            """)
    end

    # Selected by the source image (intensity only).
    for (selector, direction, criterion) in ((:brightest, 1.0, "greatest"), (:darkest, -1.0, "least"))
        operator = Symbol(prefix, :_, selector)
        _define_factory!(Symbol(operator, :_image2D_factory), operator,
            _mask_builder(operator, _object_kernel(_mean_select(direction), mode)), (IntensityPixel,),
            "Zoom that $verb the object with the $criterion mean source value $tail.",
            """
                $(operator)_image2D_factory(::Type{I})

            Specialises `$operator`, which $verb the object whose mean source
            intensity is the $criterion $tail.
            """)
    end
end

for (suffix, fraction) in ((:_10p, 0.10), (:_25p, 0.25), (:_50p, 0.50))
    operator = Symbol(:zoom_glimpse, suffix)
    pct = round(Int, 100fraction)
    _define_factory!(Symbol(operator, :_image2D_factory), operator,
        _point_builder(operator, _glimpse_kernel(fraction)), _ALL_KINDS,
        "Crops a $pct% window around a point and resizes it back.",
        """
            $(operator)_image2D_factory(::Type{I})

        Specialises `$operator(img, x, y)` / `(img, s)` / `(img)`: crops a
        window of $pct% of each side centred on the point (clipped at the
        borders) and resizes it back.
        """)
end

_define_factory!(:zoom_recenter_point_image2D_factory, :zoom_recenter_point,
    I -> _point_driven_factory(I, :zoom_recenter_point,
        (src, x, y) -> _translate(src, _to_position(y, size(src, 1)), _to_position(x, size(src, 2)))),
    _ALL_KINDS,
    "Translates the image so a point lands on the centre.",
    """
        zoom_recenter_point_image2D_factory(::Type{I})

    Specialises `zoom_recenter_point(img, x, y)` / `(img, s)`: translates the
    image without rescaling so `(x, y)` lands on the centre; borders are filled
    with zero.
    """)

"Specialise `zoom_center(img, [z])`: centred window of fraction `z` (default 0.5)."
function _center_factory(::Type{I}) where {I}
    IT = _get_image_type(I)
    S = _get_image_tuple_size(I)
    _validate_factory_type(IT)
    function_name = Symbol(:zoom_center_, Symbol(I))
    fn = @eval function $function_name(src::CONCT, z::Real, args::Vararg{Any}) where {CONCT<:$I}
        return SImageND(_zoom_point(src.img, 0.5, 0.5, max(_unit(z), 0.05)), $S)
    end
    @eval function $function_name(src::CONCT, args::Vararg{Any}) where {CONCT<:$I}
        return SImageND(_zoom_point(src.img, 0.5, 0.5, 0.5), $S)
    end
    return fn
end
_define_factory!(:zoom_center_image2D_factory, :zoom_center, _center_factory, _ALL_KINDS,
    "Centred digital zoom keeping a fraction z of each side.",
    """
        zoom_center_image2D_factory(::Type{I})

    Specialises `zoom_center(img, [z])`: keeps the central fraction
    `z ∈ [0.05, 1]` (default `0.5`) of each side and resizes it back.
    """)

"Specialise a band crop along `axis`: `(img, a, b)` or `(img, a)` (25% band)."
function _band_factory(::Type{I}, operator::Symbol, axis::Int) where {I}
    IT = _get_image_type(I)
    S = _get_image_tuple_size(I)
    _validate_factory_type(IT)
    function_name = Symbol(operator, :_, Symbol(I))
    fn = @eval function $function_name(src::CONCT, a::Real, b::Real, args::Vararg{Any}) where {CONCT<:$I}
        return SImageND(_zoom_band(src.img, $axis, _unit(a), _unit(b)), $S)
    end
    @eval function $function_name(src::CONCT, a::Real, args::Vararg{Any}) where {CONCT<:$I}
        u = _unit(a)
        return SImageND(_zoom_band(src.img, $axis, max(u - 0.125, 0.0), min(u + 0.125, 1.0)), $S)
    end
    return fn
end
_band_builder(operator::Symbol, axis::Int) = I -> _band_factory(I, operator, axis)
for (operator, axis, what) in ((:zoom_rows, 1, "rows"), (:zoom_cols, 2, "columns"))
    _define_factory!(Symbol(operator, :_image2D_factory), operator,
        _band_builder(operator, axis), _ALL_KINDS,
        "Crops the band of $what between two positions and stretches it back.",
        """
            $(operator)_image2D_factory(::Type{I})

        Specialises `$operator(img, a, b)`: keeps the $what between normalised
        positions `a` and `b` (any order) and stretches them to the full size.
        `(img, a)` keeps a band of 25% centred on `a`.
        """)
end

end
