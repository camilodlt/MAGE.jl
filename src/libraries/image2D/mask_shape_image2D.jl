"""
Mask shape clean-up: fill holes, convex hulls, skeletons, boundaries, size and
border filters, and distance maps.

# Bundles

- bundle_image2DBinary_maskshape_factory
- bundle_image2DIntensity_maskshape_factory

The exhaustive operator list is on the Bundle Catalogue page.

# How this file is organised

Every operator is a destination-first kernel `kernel!(destination, fg, p)`.
Binary kernels write into the output storage; distance kernels use reusable
Float64 working storage before the final pixel conversion. `_shape_factory` specialises it on an output image type: it turns
the input (a mask, or a saliency map and a threshold) into `fg`, sanitises
`p`, calls the kernel and returns the output image. Kernels without a
parameter ignore `p`.

# Example

```julia
using UTCGP, ImageCore
m = falses(9, 9); m[2:8, 2:8] .= true; m[5, 5] = false   # a square with a one-pixel hole
mask = SImageND(BinaryPixel.(m))
B = typeof(mask)

fill = bundle_image2DBinary_maskshape_factory[:shape_fill_holes].fn(B)
fill(mask)          # the square without its hole
holes = bundle_image2DBinary_maskshape_factory[:shape_holes].fn(B)
holes(mask)         # only pixel (5, 5) is set
```
"""
module image2D_mask_shape

using ..UTCGP: _factory_type_symbol, @serialized_factory

using ..UTCGP: image_result

using ImageMorphology: guo_iteration!
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
using ..image2D_object_common: ObjectTable, IsSet, AtLeast, clamp_unit, object_table, scratch, squared_distance_map!, fast_foreground_test,
    background_holes!
using ..image2D_zoom: to_storage

# Returned by the bundles when no method matches the inputs (MAGE then skips the node).
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
  bright; ridges indicate thick regions but are not the thinning skeleton).
  Empty masks return zeros; full masks return ones (no background sample).
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
    fg = scratch(:shape_fg, Bool, size(pixels)...)   # reused buffer, overwritten by the next call
    predicate = fast_foreground_test(pixels, is_foreground)
    @inbounds for i in eachindex(pixels, fg)
        fg[i] = predicate(pixels[i])
    end
    return fg
end

"""
Background pixels not 4-connected to the image border (run labelling of the background).

Example: in a ring, the inside of the ring is a hole; the background around
it reaches the border, so it is not.
"""
function _holes!(out, fg::AbstractMatrix{Bool})
    background_holes!(out, fg)
    return out
end

"Holes whose area is at most `fraction` of the image."
function _holes_upto!(out, fg::AbstractMatrix{Bool}, fraction::Float64)
    holes = _holes!(out, fg)
    fraction >= 1.0 && return holes                  # every hole qualifies
    t = object_table(holes, identity)                # label the holes to know each one's area
    limit = fraction * length(fg)                    # largest hole kept, in pixels
    @inbounds for i in eachindex(holes)
        l = t.labels[i]                              # hole of pixel i (0 = not a hole)
        holes[i] = l != 0 && t.area[l] <= limit
    end
    return holes
end

"The mask with its holes of at most `fraction` of the image filled."
function _fill_holes!(out, fg::AbstractMatrix{Bool}, fraction::Float64)
    _holes_upto!(out, fg, fraction)
    @inbounds @simd for i in eachindex(out)
        out[i] |= fg[i]                              # mask OR small holes
    end
    return out
end

"""
Set every pixel of `out` inside the convex polygon `hull` (boundary included):
for each row, intersect the polygon with the row and fill that span.

`hull` lists the polygon's vertices as `(row, column)` in order around it.
Example: the triangle `(1, 1), (1, 5), (5, 1)` fills row 1 columns 1–5,
row 3 columns 1–3, row 5 column 1.
"""
function _fill_hull!(out::AbstractMatrix{Bool}, hull::Vector{Tuple{Int,Int}})
    isempty(hull) && return out
    n = length(hull)
    r0, r1 = extrema(first, hull)
    @inbounds for r in r0:r1
        lo = Inf                                  # leftmost and rightmost polygon column on row r
        hi = -Inf
        for k in 1:n                              # every edge a → b of the polygon
            a = hull[k]
            b = hull[k == n ? 1 : k + 1]          # the last vertex connects back to the first
            if a[1] == r                          # a hull vertex on row r
                lo = min(lo, a[2])
                hi = max(hi, a[2])
            end
            if (a[1] - r) * (b[1] - r) < 0       # the edge strictly crosses row r
                x = a[2] + (r - a[1]) * (b[2] - a[2]) / (b[1] - a[1])   # column where it crosses
                lo = min(lo, x)
                hi = max(hi, x)
            end
        end
        lo > hi && continue                       # the polygon does not reach this row
        for c in ceil(Int, lo - 1e-9):floor(Int, hi + 1e-9)          # tolerance keeps pixels on the edges
            out[r, c] = true
        end
    end
    return out
end

"""
Convex hull of the whole foreground. The hull is computed from the
`extreme_points` (leftmost and rightmost pixel of each row), the only pixels
that can be hull vertices.
"""
# These vectors are private to shape operators and consumed before reuse.
function _shape_extremes!(labels, id, row_first, row_last, col_first, col_last)
    points = empty!(scratch(:shape_hull_points, Tuple{Int,Int}, 0))
    @inbounds for row in row_first:row_last
        first_col = 0
        last_col = 0
        for col in col_first:col_last
            value = labels[row, col]
            (id == 0 ? value != 0 : value == id) || continue
            first_col == 0 && (first_col = col)
            last_col = col
        end
        first_col == 0 && continue
        push!(points, (row, first_col))
        last_col != first_col && push!(points, (row, last_col))
    end
    return points
end

@inline _shape_cross(origin, a, b) =
    (a[1] - origin[1]) * (b[2] - origin[2]) - (a[2] - origin[2]) * (b[1] - origin[1])

function _shape_hull!(points)
    # extreme points are unique; sort in place without allocating a merge buffer.
    sort!(points; alg = QuickSort)
    length(points) <= 2 && return points
    lower = empty!(scratch(:shape_hull_lower, Tuple{Int,Int}, 0))
    upper = empty!(scratch(:shape_hull_upper, Tuple{Int,Int}, 0))
    for point in points
        while length(lower) >= 2 && _shape_cross(lower[end-1], lower[end], point) <= 0
            pop!(lower)
        end
        push!(lower, point)
    end
    for point in Iterators.reverse(points)
        while length(upper) >= 2 && _shape_cross(upper[end-1], upper[end], point) <= 0
            pop!(upper)
        end
        push!(upper, point)
    end
    pop!(lower)
    for index in 1:length(upper)-1
        push!(lower, upper[index])
    end
    return lower
end

function _convex_hull!(out, fg::AbstractMatrix{Bool})
    copyto!(out, fg)                               # start from the mask, add the hull
    any(fg) || return out
    h, w = size(fg)
    r0, r1, c0, c1 = h + 1, 0, w + 1, 0                  # bounding box of the foreground
    @inbounds for c in 1:w, r in 1:h
        fg[r, c] || continue
        r0 = min(r0, r); r1 = max(r1, r); c0 = min(c0, c); c1 = max(c1, c)
    end
    # On a Bool matrix, label 0 selects every `true` pixel (see `extreme_points`).
    return _fill_hull!(out, _shape_hull!(_shape_extremes!(fg, 0, r0, r1, c0, c1)))
end

"Convex hull of each 8-connected object, drawn over the mask (hulls may overlap)."
function _convex_hull_objects!(out, fg::AbstractMatrix{Bool})
    t = object_table(fg, identity)
    copyto!(out, fg)
    for i in 1:t.n
        # Extreme pixels of object i only, searched within its bounding box.
        points = _shape_extremes!(t.labels, i, t.min_r[i], t.max_r[i], t.min_c[i], t.max_c[i])
        _fill_hull!(out, _shape_hull!(points))
    end
    return out
end

"Each object replaced by its filled bounding box."
function _bbox_fill!(out, fg::AbstractMatrix{Bool})
    t = object_table(fg, identity)
    fill!(out, false)
    for i in 1:t.n
        out[t.min_r[i]:t.max_r[i], t.min_c[i]:t.max_c[i]] .= true   # rows × columns of object i's box
    end
    return out
end

"One-pixel-wide skeleton (Guo–Hall thinning from ImageMorphology)."
function _skeleton!(out, fg::AbstractMatrix{Bool})
    height, width = size(fg)
    current = scratch(:shape_thinning_current, Bool, height + 2, width + 2)
    previous = scratch(:shape_thinning_previous, Bool, height + 2, width + 2)
    mask = scratch(:shape_thinning_mask, Bool, height + 2, width + 2)
    fill!(current, false)
    @inbounds for col in 1:width, row in 1:height
        current[row + 1, col + 1] = fg[row, col]
    end
    iteration = 1
    while true
        copyto!(previous, current)
        guo_iteration!(mask, current, isodd(iteration))
        @inbounds for index in eachindex(current, mask)
            if mask[index]
                current[index] = false
            end
        end
        previous == current && break
        iteration += 1
    end
    @inbounds for col in 1:width, row in 1:height
        out[row, col] = current[row + 1, col + 1]
    end
    return out
end

"""
Object pixels with a 4-neighbour in the background or on the image border.

Example: a filled 5 × 5 square becomes its 16-pixel outline.
"""
function _boundary!(out, fg::AbstractMatrix{Bool})
    h, w = size(fg)
    fill!(out, false)
    @inbounds for c in 1:w, r in 1:h
        fg[r, c] || continue
        # On the image border, or one of the 4 neighbours (above, below, left, right) is background.
        # `||` stops at the first true term, so neighbours are only read inside the image.
        out[r, c] = r == 1 || r == h || c == 1 || c == w ||
                    !fg[r-1, c] || !fg[r+1, c] || !fg[r, c-1] || !fg[r, c+1]
    end
    return out
end

"""
Keep objects for which `keep(table, id)` holds.

Example: `_filter_objects(fg, (t, i) -> t.area[i] >= 10)` drops the objects
under 10 pixels.
"""
function _filter_objects!(out, fg::AbstractMatrix{Bool}, keep::F) where {F}
    t = object_table(fg, identity)
    kept = scratch(:shape_kept, Bool, t.n)
    for i in 1:t.n
        kept[i] = keep(t, i)
    end #           # verdict per object number
    @inbounds for i in eachindex(out)
        l = t.labels[i]
        out[i] = l != 0 && kept[l]
    end
    return out
end

"Whether the bounding box of object `i` touches the image border."
_touches_border(t::ObjectTable, i::Int) =
    t.min_r[i] == 1 || t.min_c[i] == 1 || t.max_r[i] == t.h || t.max_c[i] == t.w

"""
3×3 majority vote with separable sums: vertical 3-sums, then horizontal.

A pixel is set when more than half of its 3 × 3 window is (the window is
cropped at the border: 2 × 2 in a corner, 2 × 3 on an edge). Example: an
isolated pixel (1 vote of 9) disappears; a one-pixel gap inside a solid area
(8 votes of 9) is filled.
"""
function _majority!(out, fg::AbstractMatrix{Bool})
    h, w = size(fg)
    # vertical[r, c] = number of set pixels among rows r−1, r, r+1 of column c.
    vertical = scratch(:majority_vertical, Int8, h, w)
    @inbounds for c in 1:w
        vertical[1, c] = fg[1, c] + (h > 1 ? fg[2, c] : false)      # top row: no row above
        @simd for r in 2:h-1
            vertical[r, c] = fg[r-1, c] + fg[r, c] + fg[r+1, c]
        end
        h > 1 && (vertical[h, c] = fg[h-1, c] + fg[h, c])           # bottom row: no row below
    end
    @inbounds for c in 1:w
        col_left = max(c - 1, 1)
        col_right = min(c + 1, w)
        n_cols = col_right - col_left + 1
        for r in 1:h
            # Votes = sum of the vertical 3-sums of the window's columns (left, centre, right when they exist).
            votes = Int(vertical[r, col_left]) + (col_left < c ? Int(vertical[r, c]) : 0) + (col_right > c ? Int(vertical[r, col_right]) : 0)
            n_rows = (r > 1) + 1 + (r < h)           # rows in the window (2 on the top/bottom row)
            # Strict majority of the window, which is smaller at the border.
            out[r, c] = 2votes > n_rows * n_cols
        end
    end
    return out
end

"""
Distance from each object pixel to the background, divided by the largest such distance (`0` outside).

Empty masks return zeros; full masks return ones because there is no
background sample inside the frame. Distances do not treat the image exterior
as background. Example: a disk of radius 10 surrounded by background gets `1`
at its centre and about `0.1` on its rim.
"""
function _distance_inside!(out, fg::AbstractMatrix{Bool})
    any(fg) || return fill!(out, 0.0)            # no object
    all(fg) && return fill!(out, 1.0)             # no background to measure from
    background = scratch(:shape_background, Bool, size(fg)...)
    @inbounds @simd for i in eachindex(fg, background)
        background[i] = !fg[i]
    end
    # Squared Euclidean distance from every pixel to the nearest background pixel.
    d = squared_distance_map!(out, background)
    largest = 0.0
    @inbounds for i in eachindex(d)
        d[i] = fg[i] ? sqrt(d[i]) : 0.0
        largest = max(largest, d[i])
    end
    largest > 0 && (d ./= largest)
    return d
end

"""
`1 − distance to the nearest object pixel / image diagonal`, clamped to `[0, 1]`.

Example: in a `60 × 80` image (diagonal ≈ 98.8), a pixel 20 pixels from the
nearest object gets `1 − 20/98.8 ≈ 0.80`.
"""
function _proximity!(out, fg::AbstractMatrix{Bool})
    any(fg) || return fill!(out, 0.0)
    h, w = size(fg)
    scale = 1.0 / max(hypot(h - 1, w - 1), 1.0)  # 1 / diagonal length
    d = squared_distance_map!(out, fg)
    @inbounds @simd for i in eachindex(d)
        d[i] = clamp(1.0 - sqrt(d[i]) * scale, 0.0, 1.0)
    end
    return d
end

# ---------------------------------------------------------------------------
# Factories
# ---------------------------------------------------------------------------

"""
    _shape_factory(I, operator, kernel, default) -> Function

Specialise a mask operator on the output type `I`. Methods, with
`p = clamp_unit(p, default)` (or `default` when absent):

| Method | `fg` passed to `kernel(fg, p)` |
|:--|:--|
| `op(mask, p)`, `op(mask)` | the binary mask |
| `op(saliency, threshold, p)`, `op(saliency, threshold)` | `saliency ≥ threshold` |
| `op(saliency)` | `saliency ≥ 0.5` |

The kernel result becomes `BinaryPixel`s, or intensity pixels (values stored
with rounding and clamping), depending on `I`.
"""
@serialized_factory function _shape_factory(::Type{I}, operator::Symbol, kernel::K, default::Float64) where {I,K}
    storage_type = _get_image_type(I)
    pixel_type = _get_image_pixel_type(I)
    size_type = _get_image_tuple_size(I)
    _validate_factory_type(storage_type)
    function_name = Symbol(operator, :_, _factory_type_symbol(I))
    isdefined(@__MODULE__, function_name) && return getfield(@__MODULE__, function_name)
    # Kernels work in a plain array from task scratch (writing through a
    # `reinterpret` view is several times slower), then one pass stores the pixels.
    working = pixel_type <: BinaryPixel ? :(scratch(:shape_mask_result, Bool, size(pixels)...)) :
        :(scratch(:shape_distance_result, Float64, size(pixels)...))
    to_output = pixel_type <: BinaryPixel ? quote
        _store_mask!(pixels, result)
        image_result(out, pixels, $size_type)
    end : quote
        _store_intensity!(pixels, result, $storage_type)
        image_result(out, pixels, $size_type)
    end
    # Binary mask, with the parameter p.
    fn = @eval function $function_name(mask::Mask, p::Real, args::Vararg{Any}; out = nothing) where {MaskBool,Mask<:SizedImage{$size_type,BinaryPixel{MaskBool}}}
        pixels = out === nothing ? Matrix{$pixel_type}(undef, $(size_type.parameters[1]), $(size_type.parameters[2])) : out.img
        result = $kernel($working, _bits(mask.img, IsSet()), clamp_unit(p, $default))
        return $to_output
    end
    # Binary mask, default p.
    @eval function $function_name(mask::Mask, args::Vararg{Any}; out = nothing) where {MaskBool,Mask<:SizedImage{$size_type,BinaryPixel{MaskBool}}}
        pixels = out === nothing ? Matrix{$pixel_type}(undef, $(size_type.parameters[1]), $(size_type.parameters[2])) : out.img
        result = $kernel($working, _bits(mask.img, IsSet()), $default)
        return $to_output
    end
    # Intensity map thresholded at `threshold`, with p.
    @eval function $function_name(saliency::Saliency, threshold::Real, p::Real, args::Vararg{Any}; out = nothing) where {SaliencyStorage,Saliency<:SizedImage{$size_type,IntensityPixel{SaliencyStorage}}}
        pixels = out === nothing ? Matrix{$pixel_type}(undef, $(size_type.parameters[1]), $(size_type.parameters[2])) : out.img
        result = $kernel($working, _bits(saliency.img, AtLeast(clamp_unit(threshold))), clamp_unit(p, $default))
        return $to_output
    end
    # Intensity map thresholded at `threshold`, default p.
    @eval function $function_name(saliency::Saliency, threshold::Real, args::Vararg{Any}; out = nothing) where {SaliencyStorage,Saliency<:SizedImage{$size_type,IntensityPixel{SaliencyStorage}}}
        pixels = out === nothing ? Matrix{$pixel_type}(undef, $(size_type.parameters[1]), $(size_type.parameters[2])) : out.img
        result = $kernel($working, _bits(saliency.img, AtLeast(clamp_unit(threshold))), $default)
        return $to_output
    end
    # Intensity map thresholded at 0.5, default p.
    @eval function $function_name(saliency::Saliency, args::Vararg{Any}; out = nothing) where {SaliencyStorage,Saliency<:SizedImage{$size_type,IntensityPixel{SaliencyStorage}}}
        pixels = out === nothing ? Matrix{$pixel_type}(undef, $(size_type.parameters[1]), $(size_type.parameters[2])) : out.img
        result = $kernel($working, _bits(saliency.img, AtLeast(0.5)), $default)
        return $to_output
    end
    return fn
end

"Store a Bool result as binary pixels."
function _store_mask!(pixels::AbstractArray{P}, result::AbstractArray{Bool}) where {P}
    pixels .= P.(result)
    return pixels
end

"Store a Float64 result as intensity pixels of storage `T` (rounded, clamped)."
function _store_intensity!(pixels::AbstractArray{P}, result, ::Type{T}) where {P,T}
    @inbounds for index in eachindex(pixels, result)
        pixels[index] = P(to_storage(T, result[index]))
    end
    return pixels
end

"`output_type -> _shape_factory(output_type, …)`; a function so each closure captures its own arguments."
_shape_builder(operator::Symbol, kernel, default::Float64) =
    I -> _shape_factory(I, operator, kernel, default)

# Each entry is (operator name, kernel, default p, description):
#   - kernel(fg, p) -> Bool matrix; most ignore p (e.g. (fg, p) -> _convex_hull(fg));
#   - default p is used when the program passes no number;
#   - the description is shown in the Bundle Catalogue.
# Example: (:shape_remove_small, …, 0.001, …) defines shape_remove_small(mask),
# which drops objects under 0.1% of the image, and shape_remove_small(mask, p).
const _BINARY_OPERATORS = (
    (:shape_fill_holes, (out, fg, p) -> _fill_holes!(out, fg, p), 1.0,
        "Fills enclosed background regions of at most p of the image (default: all)."),
    (:shape_holes, (out, fg, p) -> _holes_upto!(out, fg, p), 1.0,
        "Returns the enclosed background regions of at most p of the image."),
    (:shape_convex_hull, (out, fg, p) -> _convex_hull!(out, fg), 0.0,
        "Convex hull of the whole foreground."),
    (:shape_convex_hull_objects, (out, fg, p) -> _convex_hull_objects!(out, fg), 0.0,
        "Convex hull of each 8-connected object."),
    (:shape_bbox_fill, (out, fg, p) -> _bbox_fill!(out, fg), 0.0,
        "Replaces each object by its filled bounding box."),
    (:shape_skeleton, (out, fg, p) -> _skeleton!(out, fg), 0.0,
        "One-pixel-wide skeleton (Guo-Hall thinning)."),
    (:shape_boundary, (out, fg, p) -> _boundary!(out, fg), 0.0,
        "Object pixels touching the background or the image border."),
    (:shape_remove_small, (out, fg, p) -> _filter_objects!(out, fg, (t, i) -> t.area[i] >= p * t.h * t.w), 0.001,
        "Removes objects smaller than p of the image (default 0.001)."),
    (:shape_remove_large, (out, fg, p) -> _filter_objects!(out, fg, (t, i) -> t.area[i] <= p * t.h * t.w), 0.1,
        "Removes objects larger than p of the image (default 0.1)."),
    (:shape_clear_border, (out, fg, p) -> _filter_objects!(out, fg, (t, i) -> !_touches_border(t, i)), 0.0,
        "Removes objects touching the image border."),
    (:shape_keep_border, (out, fg, p) -> _filter_objects!(out, fg, _touches_border), 0.0,
        "Keeps only objects touching the image border."),
    (:shape_majority, (out, fg, p) -> _majority!(out, fg), 0.0,
        "3x3 majority vote: removes isolated pixels, fills one-pixel gaps."),
)

# Same layout; the kernels return a Float64 matrix in [0, 1].
const _INTENSITY_OPERATORS = (
    (:shape_distance_inside, (out, fg, p) -> _distance_inside!(out, fg), 0.0,
        "Distance to the background inside objects, normalised to [0, 1]."),
    (:shape_proximity, (out, fg, p) -> _proximity!(out, fg), 0.0,
        "1 on objects, decreasing with distance to the nearest object."),
)

for (bundle, operators) in (
        (bundle_image2DBinary_maskshape_factory, _BINARY_OPERATORS),
        (bundle_image2DIntensity_maskshape_factory, _INTENSITY_OPERATORS),
    )
    # Define <operator>_image2D_factory(I) for every operator and register it.
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
