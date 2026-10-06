"""
Mask shape clean-up: fill holes, convex hulls, skeletons, boundaries, size and
border filters, and distance maps.

# Bundles

- bundle_image2DBinary_maskshape_factory
- bundle_image2DIntensity_maskshape_factory

The exhaustive operator list is on the Bundle Catalogue page.
"""
module image2D_mask_shape

using ImageMorphology: thinning
using ..UTCGP: FunctionBundle, append_method!
using ..UTCGP:
    BinaryPixel,
    IntensityPixel,
    SImageND,
    SizedImage,
    SizedImage2D,
    _get_image_pixel_type,
    _get_image_tuple_size,
    _get_image_type,
    _validate_factory_type
using ..image2D_object_common: ObjectTable, IsSet, AtLeast, _unit, object_table, scratch, squared_distance_map!, _fast_predicate,
    convex_hull_points, extreme_points, background_holes!
using ..image2D_zoom: _store

fallback(args...) = return nothing

const _SIGNATURES_DOC = """
Signatures follow the blob-extraction convention: `(mask)` and
`(mask, p)` for a binary mask; `(saliency)`, `(saliency, threshold)` and
`(saliency, threshold, p)` for an intensity map thresholded at `threshold`
(default `0.5`). `p` is the operator's parameter, clamped to `[0, 1]`. Objects
are 8-connected and background regions 4-connected, so a diagonal gap never
lets a hole leak out.
"""

"""
    bundle_image2DBinary_maskshape_factory

Mask clean-up operators returning a same-size binary mask.

- `shape_fill_holes[ (p)]`: fill enclosed background; with `p`, only holes of
  at most `p` of the image's pixels. `shape_holes` returns the holes alone.
- `shape_convex_hull`, `shape_convex_hull_objects`: convex hull of the whole
  foreground, or of each object separately.
- `shape_bbox_fill`: replace each object by its filled bounding box.
- `shape_skeleton`: one-pixel-wide medial lines (Guo-Hall thinning).
- `shape_boundary`: object pixels touching the background or the image border.
- `shape_remove_small(p)`, `shape_remove_large(p)`: drop objects smaller or
  larger than `p` of the image (defaults `0.001` and `0.1`).
- `shape_clear_border`, `shape_keep_border`: drop, or keep only, objects
  touching the image border (scores, HUDs, walls).
- `shape_majority`: 3×3 majority vote, removing isolated pixels and filling
  single-pixel gaps.

$_SIGNATURES_DOC
"""
const bundle_image2DBinary_maskshape_factory = FunctionBundle(fallback)

"""
    bundle_image2DIntensity_maskshape_factory

Distance maps of a mask, returned as a same-size intensity image in `[0, 1]`.

- `shape_distance_inside`: distance from each object pixel to the nearest
  background pixel, divided by the largest such distance (thick parts are
  bright, the ridge is the skeleton).
- `shape_proximity`: `1 − d / diagonal` with `d` the distance to the nearest
  object pixel: `1` on objects, fading with distance.

$_SIGNATURES_DOC
"""
const bundle_image2DIntensity_maskshape_factory = FunctionBundle(fallback)

# ---------------------------------------------------------------------------
# Kernels on Bool matrices
# ---------------------------------------------------------------------------

"Foreground as a `Bool` matrix in per-task scratch (8-bit thresholds use a lookup table)."
function _bits(pixels::AbstractMatrix, is_foreground)
    fg = scratch(:shape_fg, Bool, size(pixels)...)
    predicate = _fast_predicate(pixels, is_foreground)
    @inbounds for i in eachindex(pixels, fg)
        fg[i] = predicate(pixels[i])
    end
    return fg
end

"Background pixels not 4-connected to the image border (run labelling of the background)."
function _holes(fg::AbstractMatrix{Bool})
    holes = Matrix{Bool}(undef, size(fg))
    background_holes!(holes, fg)
    return holes
end

"Holes whose area is at most `fraction` of the image."
function _holes_upto(fg::AbstractMatrix{Bool}, fraction::Float64)
    holes = _holes(fg)
    fraction >= 1.0 && return holes
    t = object_table(holes, identity)
    limit = fraction * length(fg)
    @inbounds for i in eachindex(holes)
        l = t.labels[i]
        holes[i] = l != 0 && t.area[l] <= limit
    end
    return holes
end

function _fill_holes(fg::AbstractMatrix{Bool}, fraction::Float64)
    out = _holes_upto(fg, fraction)
    @inbounds @simd for i in eachindex(out)
        out[i] |= fg[i]
    end
    return out
end

"""
Set every pixel of `out` inside the convex polygon `hull` (boundary included):
for each row, intersect the polygon with the row and fill that span.
"""
function _fill_hull!(out::AbstractMatrix{Bool}, hull::Vector{Tuple{Int,Int}})
    isempty(hull) && return out
    n = length(hull)
    r0, r1 = extrema(first.(hull))
    @inbounds for r in r0:r1
        lo = Inf
        hi = -Inf
        for k in 1:n
            a = hull[k]
            b = hull[k == n ? 1 : k + 1]
            if a[1] == r
                lo = min(lo, a[2])
                hi = max(hi, a[2])
            end
            if (a[1] - r) * (b[1] - r) < 0       # the edge strictly crosses row r
                x = a[2] + (r - a[1]) * (b[2] - a[2]) / (b[1] - a[1])
                lo = min(lo, x)
                hi = max(hi, x)
            end
        end
        lo > hi && continue
        for c in ceil(Int, lo - 1e-9):floor(Int, hi + 1e-9)
            out[r, c] = true
        end
    end
    return out
end

function _convex_hull(fg::AbstractMatrix{Bool})
    out = Matrix{Bool}(fg)
    any(fg) || return out
    h, w = size(fg)
    r0, r1, c0, c1 = h + 1, 0, w + 1, 0
    @inbounds for c in 1:w, r in 1:h
        fg[r, c] || continue
        r0 = min(r0, r); r1 = max(r1, r); c0 = min(c0, c); c1 = max(c1, c)
    end
    return _fill_hull!(out, convex_hull_points(extreme_points(fg, 0, r0, r1, c0, c1)))
end

function _convex_hull_objects(fg::AbstractMatrix{Bool})
    t = object_table(fg, identity)
    out = Matrix{Bool}(fg)
    for i in 1:t.n
        points = extreme_points(t.labels, i, t.min_r[i], t.max_r[i], t.min_c[i], t.max_c[i])
        _fill_hull!(out, convex_hull_points(points))
    end
    return out
end

function _bbox_fill(fg::AbstractMatrix{Bool})
    t = object_table(fg, identity)
    out = zeros(Bool, size(fg))
    for i in 1:t.n
        out[t.min_r[i]:t.max_r[i], t.min_c[i]:t.max_c[i]] .= true
    end
    return out
end

_skeleton(fg::AbstractMatrix{Bool}) = any(fg) ? Matrix{Bool}(thinning(fg)) : zeros(Bool, size(fg))

function _boundary(fg::AbstractMatrix{Bool})
    h, w = size(fg)
    out = zeros(Bool, h, w)
    @inbounds for c in 1:w, r in 1:h
        fg[r, c] || continue
        out[r, c] = r == 1 || r == h || c == 1 || c == w ||
                    !fg[r-1, c] || !fg[r+1, c] || !fg[r, c-1] || !fg[r, c+1]
    end
    return out
end

"Keep objects for which `keep(table, id)` holds."
function _filter_objects(fg::AbstractMatrix{Bool}, keep::F) where {F}
    t = object_table(fg, identity)
    kept = [keep(t, i) for i in 1:t.n]
    out = Matrix{Bool}(undef, size(fg))
    @inbounds for i in eachindex(out)
        l = t.labels[i]
        out[i] = l != 0 && kept[l]
    end
    return out
end

_touches_border(t::ObjectTable, i::Int) =
    t.min_r[i] == 1 || t.min_c[i] == 1 || t.max_r[i] == t.h || t.max_c[i] == t.w

"3×3 majority vote with separable sums: vertical 3-sums, then horizontal."
function _majority(fg::AbstractMatrix{Bool})
    h, w = size(fg)
    vertical = scratch(:majority_vertical, Int8, h, w)
    @inbounds for c in 1:w
        vertical[1, c] = fg[1, c] + (h > 1 ? fg[2, c] : false)
        @simd for r in 2:h-1
            vertical[r, c] = fg[r-1, c] + fg[r, c] + fg[r+1, c]
        end
        h > 1 && (vertical[h, c] = fg[h-1, c] + fg[h, c])
    end
    out = Matrix{Bool}(undef, h, w)
    @inbounds for c in 1:w
        cl = max(c - 1, 1)
        cr = min(c + 1, w)
        ncols = cr - cl + 1
        for r in 1:h
            votes = Int(vertical[r, cl]) + (cl < c ? Int(vertical[r, c]) : 0) + (cr > c ? Int(vertical[r, cr]) : 0)
            nrows = (r > 1) + 1 + (r < h)
            out[r, c] = 2votes > nrows * ncols
        end
    end
    return out
end

function _distance_inside(fg::AbstractMatrix{Bool})
    any(fg) || return zeros(size(fg))
    all(fg) && return ones(size(fg))
    background = scratch(:shape_background, Bool, size(fg)...)
    @inbounds @simd for i in eachindex(fg, background)
        background[i] = !fg[i]
    end
    d = squared_distance_map!(Matrix{Float64}(undef, size(fg)), background)
    m = 0.0
    @inbounds for i in eachindex(d)
        d[i] = fg[i] ? sqrt(d[i]) : 0.0
        m = max(m, d[i])
    end
    m > 0 && (d ./= m)
    return d
end

function _proximity(fg::AbstractMatrix{Bool})
    any(fg) || return zeros(size(fg))
    h, w = size(fg)
    scale = 1.0 / max(hypot(h - 1, w - 1), 1.0)
    d = squared_distance_map!(Matrix{Float64}(undef, size(fg)), fg)
    @inbounds @simd for i in eachindex(d)
        d[i] = clamp(1.0 - sqrt(d[i]) * scale, 0.0, 1.0)
    end
    return d
end

# ---------------------------------------------------------------------------
# Factories
# ---------------------------------------------------------------------------

"""
Specialise a mask operator. `kernel(fg::Matrix{Bool}, p::Float64)` returns a
`Bool` matrix (binary bundle) or a `Matrix{Float64}` (intensity bundle).
"""
function _shape_factory(::Type{I}, operator::Symbol, kernel::K, default::Float64) where {I,K}
    IT = _get_image_type(I)
    PT = _get_image_pixel_type(I)
    S = _get_image_tuple_size(I)
    _validate_factory_type(IT)
    function_name = Symbol(operator, :_, Symbol(I))
    wrap = PT <: BinaryPixel ? :(SImageND($PT.(result), $S)) :
           :(SImageND($PT.(_store.($IT, result)), $S))
    fn = @eval function $function_name(mask::M, p::Real, args::Vararg{Any}) where {BT,M<:SizedImage{$S,BinaryPixel{BT}}}
        result = $kernel(_bits(mask.img, IsSet()), _unit(p, $default))
        return $wrap
    end
    @eval function $function_name(mask::M, args::Vararg{Any}) where {BT,M<:SizedImage{$S,BinaryPixel{BT}}}
        result = $kernel(_bits(mask.img, IsSet()), $default)
        return $wrap
    end
    @eval function $function_name(saliency::M, threshold::Real, p::Real, args::Vararg{Any}) where {ST,M<:SizedImage{$S,IntensityPixel{ST}}}
        result = $kernel(_bits(saliency.img, AtLeast(_unit(threshold))), _unit(p, $default))
        return $wrap
    end
    @eval function $function_name(saliency::M, threshold::Real, args::Vararg{Any}) where {ST,M<:SizedImage{$S,IntensityPixel{ST}}}
        result = $kernel(_bits(saliency.img, AtLeast(_unit(threshold))), $default)
        return $wrap
    end
    @eval function $function_name(saliency::M, args::Vararg{Any}) where {ST,M<:SizedImage{$S,IntensityPixel{ST}}}
        result = $kernel(_bits(saliency.img, AtLeast(0.5)), $default)
        return $wrap
    end
    return fn
end

_shape_builder(operator::Symbol, kernel, default::Float64) =
    I -> _shape_factory(I, operator, kernel, default)

const _BINARY_OPERATORS = (
    (:shape_fill_holes, (fg, p) -> _fill_holes(fg, p), 1.0,
        "Fills enclosed background regions of at most p of the image (default: all)."),
    (:shape_holes, (fg, p) -> _holes_upto(fg, p), 1.0,
        "Returns the enclosed background regions of at most p of the image."),
    (:shape_convex_hull, (fg, p) -> _convex_hull(fg), 0.0,
        "Convex hull of the whole foreground."),
    (:shape_convex_hull_objects, (fg, p) -> _convex_hull_objects(fg), 0.0,
        "Convex hull of each 8-connected object."),
    (:shape_bbox_fill, (fg, p) -> _bbox_fill(fg), 0.0,
        "Replaces each object by its filled bounding box."),
    (:shape_skeleton, (fg, p) -> _skeleton(fg), 0.0,
        "One-pixel-wide skeleton (Guo-Hall thinning)."),
    (:shape_boundary, (fg, p) -> _boundary(fg), 0.0,
        "Object pixels touching the background or the image border."),
    (:shape_remove_small, (fg, p) -> _filter_objects(fg, (t, i) -> t.area[i] >= p * t.h * t.w), 0.001,
        "Removes objects smaller than p of the image (default 0.001)."),
    (:shape_remove_large, (fg, p) -> _filter_objects(fg, (t, i) -> t.area[i] <= p * t.h * t.w), 0.1,
        "Removes objects larger than p of the image (default 0.1)."),
    (:shape_clear_border, (fg, p) -> _filter_objects(fg, (t, i) -> !_touches_border(t, i)), 0.0,
        "Removes objects touching the image border."),
    (:shape_keep_border, (fg, p) -> _filter_objects(fg, _touches_border), 0.0,
        "Keeps only objects touching the image border."),
    (:shape_majority, (fg, p) -> _majority(fg), 0.0,
        "3x3 majority vote: removes isolated pixels, fills one-pixel gaps."),
)

const _INTENSITY_OPERATORS = (
    (:shape_distance_inside, (fg, p) -> _distance_inside(fg), 0.0,
        "Distance to the background inside objects, normalised to [0, 1]."),
    (:shape_proximity, (fg, p) -> _proximity(fg), 0.0,
        "1 on objects, decreasing with distance to the nearest object."),
)

for (bundle, operators) in (
        (bundle_image2DBinary_maskshape_factory, _BINARY_OPERATORS),
        (bundle_image2DIntensity_maskshape_factory, _INTENSITY_OPERATORS),
    )
    for (operator, kernel, default, description) in operators
        factory_name = Symbol(operator, :_image2D_factory)
        builder = _shape_builder(operator, kernel, default)
        @eval function $factory_name(output_type::Type{I}) where {S1,S2,P,I<:SizedImage2D{S1,S2,P}}
            return $builder(output_type)
        end
        doc = """
            $(factory_name)(::Type{I})

        Specialises `$operator`. $description
        """
        @eval @doc $doc $factory_name
        append_method!(bundle, getfield(@__MODULE__, factory_name), operator; description = description)
    end
end

end
