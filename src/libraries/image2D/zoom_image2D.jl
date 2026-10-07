"""
Attention operators: crop a region found by a mask or given by coordinates and
resize it back to the full image size, or translate the image so a point lands
in the centre.

# Bundles

- bundle_image2DIntensity_zoom_factory
- bundle_image2DBinary_zoom_factory
- bundle_image2DSegment_zoom_factory

The exhaustive operator list is on the Bundle Catalogue page.

# How the factories work

Every entry of these bundles is a *factory*: a function of an image type `I`
(the type the operator must output, e.g. `SImage2D{28,28,IntensityPixel{N0f8}}`)
that defines and returns a function specialised for it. The returned function
has several methods, one per accepted input shape; for a mask-driven operator:

| Call | Meaning |
|:--|:--|
| `op(src, mask, margin)` | `mask` is a binary image of the same size |
| `op(src, mask)` | same, default margin |
| `op(src, saliency, margin)` | `saliency` is an intensity image, thresholded at `0.5` |
| `op(src, saliency)` | same, default margin |
| `op(src)`, `op(src, margin)` | binary `src`: zoom on its own foreground |
| `op(src)`, `op(src, threshold[, margin])` | intensity `src`: threshold itself |

Every method also accepts and ignores extra trailing arguments (`args...`),
which is how MAGE passes unused inputs.

The work itself is done by plain *kernels* on the raw pixel matrices (`src.img`);
the factory methods only unpack the inputs, sanitise the scalars with
`clamp_unit`, call the kernel and wrap the result back into an `SImageND`.

# Example

```julia
using UTCGP, ImageCore
m = zeros(40, 40); m[5:12, 25:36] .= 0.9          # one bright object, top right
img = SImageND(IntensityPixel{N0f8}.(m))
I = typeof(img)

crop = bundle_image2DIntensity_zoom_factory[:zoom_crop_bbox].fn(I)
crop(img)          # the object's box (grown by 10%) stretched to 40 × 40
crop(img, 0.5, 0.0)   # threshold 0.5, no margin: the box exactly
glimpse = bundle_image2DIntensity_zoom_factory[:zoom_glimpse_25p].fn(I)
glimpse(img, 0.75, 0.2)   # a 10 × 10 window around column 30, row 9, resized to 40 × 40
```
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
    clamp_unit,
    unit_to_position,
    object_table,
    centroid_row,
    centroid_col,
    SELECTOR_FUNCTIONS,
    SELECTOR_DESCRIPTIONS,
    select_by_mean

# Returned by the bundles when no method matches the inputs (MAGE then skips the node).
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

"Margin used when the program does not provide one: 10% of the box per side."
const _DEFAULT_MARGIN = 0.1

# ---------------------------------------------------------------------------
# Pixel helpers (also used by the transform, mask-shape and volume libraries)
# ---------------------------------------------------------------------------

"""
    zero_pixel(P) -> P

The zero value of pixel type `P` (black, `false`, label 0): what fills the
pixels that come from outside an image.
"""
@inline zero_pixel(::Type{P}) where {T,P<:AbstractPixel{T}} = P(zero(T))

"""
    to_storage(T, v::Float64) -> T

Convert a computed value to the storage type `T` of an intensity pixel:
floats are kept, integers rounded, other numbers clamped to their range.
Fixed-point types (`N0f8`, `N0f16`, …) are clamped to `[0, 1]` and rounded
directly on their raw integer, which is faster than the checked conversion.

Example for `N0f8`: `0.5 → 128/255` (raw `0.5 · 255 + 0.5 = 128`),
`1.7 → 1.0`, `-0.3 → 0.0`.
"""
@inline to_storage(::Type{T}, v::Float64) where {T<:AbstractFloat} = T(v)
@inline to_storage(::Type{T}, v::Float64) where {T<:Integer} = round(T, v)
@inline to_storage(::Type{T}, v::Float64) where {T<:Real} =
    T(clamp(v, Float64(typemin(T)), Float64(typemax(T))))
@inline function to_storage(::Type{Normed{U,f}}, v::Float64) where {U,f}
    scale = Float64((one(UInt64) << f) - one(UInt64))         # raw value of 1.0, e.g. 255
    raw = clamp(muladd(v, scale, 0.5), 0.0, Float64(typemax(U)))   # v · scale + 0.5, then truncation = rounding
    return reinterpret(Normed{U,f}, unsafe_trunc(U, raw))            # use the integer as the raw storage
end

# ---------------------------------------------------------------------------
# Which source pixels survive the crop
#
# A "keep" functor answers keep(r, c) -> Bool for a source pixel; rejected
# pixels are read as zero. The resamplers call it for every pixel they read.
# ---------------------------------------------------------------------------

"Keep every source pixel (plain crop)."
struct KeepEveryPixel end
@inline (::KeepEveryPixel)(r::Int, c::Int) = true

"Keep only the pixels of object `id` in `labels` (isolating crop of one object)."
struct KeepObject
    labels::Matrix{Int32}    # object number of each pixel (from the object table)
    id::Int32                # the object to keep
end
@inline (keep::KeepObject)(r::Int, c::Int) = @inbounds keep.labels[r, c] == keep.id

"Keep only the mask's foreground pixels (isolating crop of the whole foreground)."
struct KeepForeground{M<:AbstractMatrix,P}
    mask::M                  # the mask's pixel matrix
    is_foreground::P         # pixel -> Bool (IsSet() or AtLeast(t))
end
@inline (keep::KeepForeground)(r::Int, c::Int) = @inbounds keep.is_foreground(keep.mask[r, c])

# ---------------------------------------------------------------------------
# Resampling a window back to full size
# ---------------------------------------------------------------------------

"""
Nearest-neighbour resize of the window `src[r0:r1, c0:c1]` to `size(src)`.
Output pixel `i` reads the source pixel whose cell contains its centre.
Pixels rejected by `keep(r, c)` become zero.

Example: rows `5:6` stretched to 4 output rows → rows `5, 5, 6, 6`.
"""
function _resample_nearest(src::AbstractMatrix{P}, r0::Int, r1::Int, c0::Int, c1::Int, keep::K) where {P,K}
    h, w = size(src)
    crop_h = r1 - r0 + 1
    crop_w = c1 - c0 + 1
    rows = scratch(:zoom_nearest_rows, Int, h)       # source row of each output row
    @inbounds for i in 1:h
        # Output centre i − 0.5 scaled by crop_h / h, in integer arithmetic.
        rows[i] = r0 + ((2i - 1) * crop_h) ÷ (2h)
    end
    out = similar(src)
    zero = zero_pixel(P)
    @inbounds for j in 1:w
        c = c0 + ((2j - 1) * crop_w) ÷ (2w)          # source column of output column j
        for i in 1:h
            r = rows[i]
            out[i, j] = keep(r, c) ? src[r, c] : zero
        end
    end
    return out
end

"""
    _source_coordinate(i, n, lo, hi) -> (a, b, weight)

When the window `lo:hi` is stretched over `n` output pixels, output pixel `i`
falls between source pixels `a` and `b = a + 1`; its value is
`(1 − weight) · src[a] + weight · src[b]`.

Example: window `5:6` stretched to 4 pixels: output 2 sits at source position
`4.5 + 1.5 · 0.5 = 5.25` → `(5, 6, 0.25)`.
"""
@inline function _source_coordinate(i::Int, n::Int, lo::Int, hi::Int)
    # Centre of output pixel i (i − 0.5 in [0, n]) mapped onto the window [lo − 0.5, hi + 0.5].
    position = lo - 0.5 + (i - 0.5) * (hi - lo + 1) / n
    position = clamp(position, Float64(lo), Float64(hi))    # the outermost half pixels repeat the edge
    a = unsafe_trunc(Int, position)                  # position ≥ lo ≥ 1, so truncation is floor
    b = min(a + 1, hi)
    return a, b, position - a
end

"""
Bilinear resize of the window `src[r0:r1, c0:c1]` to `size(src)` (intensity
pixels), in two separable passes:

1. horizontal interpolation of every window row into a scratch buffer
   (contiguous, vectorised);
2. vertical interpolation of that buffer into the output.

This is the same arithmetic as interpolating each output pixel from its four
neighbours, horizontally first. Pixels rejected by `keep(r, c)` count as zero.
"""
function _resample_bilinear(
        src::AbstractMatrix{IntensityPixel{T}},
        r0::Int, r1::Int, c0::Int, c1::Int,
        keep::K,
    ) where {T,K}
    h, w = size(src)
    window_rows = r1 - r0 + 1

    # 1. Horizontal: every window row, interpolated at the w output columns.
    horizontal = scratch(:zoom_horizontal, Float64, window_rows, w)
    @inbounds for j in 1:w
        col_left, col_right, weight_x = _source_coordinate(j, w, c0, c1)
        @simd for k in 1:window_rows
            r = r0 + k - 1                           # source row of window row k
            left = keep(r, col_left) ? Float64(src[r, col_left].pixel) : 0.0
            right = keep(r, col_right) ? Float64(src[r, col_right].pixel) : 0.0
            horizontal[k, j] = left + weight_x * (right - left)
        end
    end

    # 2. Vertical: the two window rows around each output row, and their weight.
    row_top = scratch(:zoom_row_a, Int, h)
    row_bottom = scratch(:zoom_row_b, Int, h)
    row_weight = scratch(:zoom_row_f, Float64, h)
    @inbounds for i in 1:h
        top, bottom, weight_y = _source_coordinate(i, h, r0, r1)
        row_top[i], row_bottom[i], row_weight[i] = top - r0 + 1, bottom - r0 + 1, weight_y
    end
    out = similar(src)
    @inbounds for j in 1:w
        for i in 1:h
            top = horizontal[row_top[i], j]
            bottom = horizontal[row_bottom[i], j]
            out[i, j] = IntensityPixel{T}(to_storage(T, top + row_weight[i] * (bottom - top)))
        end
    end
    return out
end

"Resize a window back to full size: bilinear for intensity images, nearest neighbour otherwise."
@inline _resample(src::AbstractMatrix{<:IntensityPixel}, r0, r1, c0, c1, keep) =
    _resample_bilinear(src, r0, r1, c0, c1, keep)
@inline _resample(src::AbstractMatrix, r0, r1, c0, c1, keep) =
    _resample_nearest(src, r0, r1, c0, c1, keep)

"""
Translate `src` without rescaling so the pixel position `(row, col)` lands on the image centre; the uncovered border is zero.

Example: a 40-row image with the object at row 10.5 (centre 20.5): shift by
`−10` rows, so output row `i` shows input row `i − 10`.
"""
function _translate(src::AbstractMatrix{P}, row::Float64, col::Float64) where {P}
    h, w = size(src)
    # Offset from the image centre to the point (ties rounded up, so results do not flip with parity).
    shift_r = round(Int, row - (h + 1) / 2, RoundNearestTiesUp)
    shift_c = round(Int, col - (w + 1) / 2, RoundNearestTiesUp)
    out = similar(src)
    zero = zero_pixel(P)
    @inbounds for j in 1:w
        c = j + shift_c
        for i in 1:h
            r = i + shift_r                          # source row
            out[i, j] = (1 <= r <= h && 1 <= c <= w) ? src[r, c] : zero
        end
    end
    return out
end

# ---------------------------------------------------------------------------
# Windows
# ---------------------------------------------------------------------------

"What a mask-driven zoom does with the window it found."
abstract type ZoomMode end
"Crop the bounding box and resize it back."
struct CropBox <: ZoomMode end
"Crop the bounding box widened to the image's aspect ratio, so shapes keep their proportions."
struct CropAspect <: ZoomMode end
"Crop the bounding box and zero every pixel outside the object(s)."
struct CropIsolate <: ZoomMode end
"Translate the centroid to the image centre, without cropping or rescaling."
struct RecenterMode <: ZoomMode end

"""
    _expand_box(r0, r1, c0, c1, h, w, margin, aspect) -> (r0, r1, c0, c1)

Grow the box `r0:r1 × c0:c1` by `margin` of its own height and width on each
side; with `aspect`, widen it further along the shorter direction until its
proportions match the `h × w` image. The result is clipped to the image.

Example in a `40 × 40` image: box rows `5:12`, columns `25:36` (8 × 12) with
`margin = 0.1` grows by `round(0.8) = 1` row and `round(1.2) = 1` column:
rows `4:13`, columns `24:37`. With `aspect`, the 10 × 14 box gets 4 more rows
(2 above, 2 below) to become square like the image: rows `2:15`.
"""
function _expand_box(r0::Int, r1::Int, c0::Int, c1::Int, h::Int, w::Int, margin::Float64, aspect::Bool)
    box_h = r1 - r0 + 1
    box_w = c1 - c0 + 1
    grow_r = round(Int, margin * box_h)              # rows added above and below
    grow_c = round(Int, margin * box_w)              # columns added left and right
    r0 -= grow_r
    r1 += grow_r
    c0 -= grow_c
    c1 += grow_c
    if aspect
        box_h = r1 - r0 + 1
        box_w = c1 - c0 + 1
        # The box aspect box_h / box_w must equal the image aspect h / w.
        if box_h * w > box_w * h
            extra = cld(box_h * w, h) - box_w          # columns to add
            c0 -= extra ÷ 2                          # half on each side (odd: one more on the right)
            c1 += extra - extra ÷ 2
        else
            extra = cld(box_w * h, w) - box_h          # rows to add
            r0 -= extra ÷ 2
            r1 += extra - extra ÷ 2
        end
    end
    return max(r0, 1), min(r1, h), max(c0, 1), min(c1, w)
end

"Bounding box `(r0, r1, c0, c1)` of every foreground pixel of `mask`, or `nothing` when it is empty."
function _foreground_box(mask::AbstractMatrix, is_foreground::P) where {P}
    h, w = size(mask)
    r0, r1, c0, c1 = h + 1, 0, w + 1, 0              # start "inside out": any pixel will shrink/grow them
    @inbounds for c in 1:w, r in 1:h
        is_foreground(mask[r, c]) || continue
        r0 = min(r0, r)
        r1 = max(r1, r)
        c0 = min(c0, c)
        c1 = max(c1, c)
    end
    r1 == 0 && return nothing                        # no foreground pixel was seen
    return r0, r1, c0, c1
end

"`(count, mean row, mean column)` of the foreground pixels of `mask`."
function _foreground_centroid(mask::AbstractMatrix, is_foreground::P) where {P}
    n = 0
    sum_r = 0.0
    sum_c = 0.0
    @inbounds for c in axes(mask, 2), r in axes(mask, 1)
        is_foreground(mask[r, c]) || continue
        n += 1
        sum_r += r
        sum_c += c
    end
    return n, sum_r / max(n, 1), sum_c / max(n, 1)  # max(n, 1): no division by 0 when empty
end

"Kernel of the whole-foreground zooms: apply `mode` to the foreground of `mask`; returns a pixel matrix."
function _zoom_foreground(src::AbstractMatrix, mask::AbstractMatrix, is_foreground, mode::ZoomMode, margin::Float64)
    if mode isa RecenterMode
        n, row, col = _foreground_centroid(mask, is_foreground)
        return n == 0 ? src : _translate(src, row, col)
    end
    box = _foreground_box(mask, is_foreground)
    box === nothing && return src                     # empty mask: image unchanged
    h, w = size(src)
    r0, r1, c0, c1 = _expand_box(box..., h, w, margin, mode isa CropAspect)   # box... = r0, r1, c0, c1
    # Isolating crops blank everything that is not foreground.
    keep = mode isa CropIsolate ? KeepForeground(mask, is_foreground) : KeepEveryPixel()
    return _resample(src, r0, r1, c0, c1, keep)
end

"""
Kernel of the selector zooms: label the objects of `mask`, pick one with
`select(table, src) -> id`, apply `mode` to it; returns a pixel matrix.
"""
function _zoom_object(src::AbstractMatrix, mask::AbstractMatrix, is_foreground, select::F, mode::ZoomMode, margin::Float64) where {F}
    t = object_table(mask, is_foreground)            # label the objects of the mask
    id = select(t, src)                              # e.g. the largest one; 0 when there is none
    id == 0 && return src                             # no object: image unchanged
    mode isa RecenterMode && return _translate(src, centroid_row(t, id), centroid_col(t, id))
    h, w = size(src)
    # The chosen object's bounding box, grown by the margin.
    r0, r1, c0, c1 = _expand_box(t.min_r[id], t.max_r[id], t.min_c[id], t.max_c[id],
        h, w, margin, mode isa CropAspect)
    keep = mode isa CropIsolate ? KeepObject(t.labels, Int32(id)) : KeepEveryPixel()
    return _resample(src, r0, r1, c0, c1, keep)
end

"""
Window covering `fraction` of each side of an `h × w` image, centred on the normalised point `(x, y)` and clipped.

Example: `40 × 40`, `fraction = 0.25` (10 pixels), `(x, y) = (0.5, 0.5)`:
centre `20.5`, window rows and columns `16:25`.
"""
function _point_window(h::Int, w::Int, x::Float64, y::Float64, fraction::Float64)
    half_r = (fraction * h) / 2                      # half the window height, in pixels
    half_c = (fraction * w) / 2
    centre_r = unit_to_position(y, h)                # y ∈ [0, 1] → row in [1, h]
    centre_c = unit_to_position(x, w)
    # ±0.5 converts between pixel edges and pixel centres; r1 ≥ r0 keeps at least one pixel.
    r0 = clamp(round(Int, centre_r - half_r + 0.5), 1, h)
    r1 = clamp(round(Int, centre_r + half_r - 0.5), r0, h)
    c0 = clamp(round(Int, centre_c - half_c + 0.5), 1, w)
    c1 = clamp(round(Int, centre_c + half_c - 0.5), c0, w)
    return r0, r1, c0, c1
end

"Kernel of the glimpses: crop the window of `fraction` around `(x, y)` and resize it back."
function _zoom_point(src::AbstractMatrix, x::Float64, y::Float64, fraction::Float64)
    h, w = size(src)
    return _resample(src, _point_window(h, w, x, y, fraction)..., KeepEveryPixel())
end

"Kernel of `zoom_rows` / `zoom_cols`: keep the band between normalised positions `a` and `b` along `axis` (1 = rows, 2 = columns) and stretch it."
function _zoom_band(src::AbstractMatrix, axis::Int, a::Float64, b::Float64)
    h, w = size(src)
    lo, hi = minmax(a, b)                            # the two positions in any order
    n = axis == 1 ? h : w                            # length of the axis
    i0 = clamp(round(Int, unit_to_position(lo, n)), 1, n)     # first row/column of the band
    i1 = clamp(round(Int, unit_to_position(hi, n)), i0, n)    # last (at least i0)
    # Rows: crop rows i0:i1, all columns. Columns: all rows, columns i0:i1.
    return axis == 1 ? _resample(src, i0, i1, 1, w, KeepEveryPixel()) :
           _resample(src, 1, h, i0, i1, KeepEveryPixel())
end

# ---------------------------------------------------------------------------
# Factory builders
# ---------------------------------------------------------------------------

"The bundle an operator goes into, by the pixel kind it outputs."
_bundle_for(::Type{<:IntensityPixel}) = bundle_image2DIntensity_zoom_factory
_bundle_for(::Type{<:BinaryPixel}) = bundle_image2DBinary_zoom_factory
_bundle_for(::Type{<:SegmentPixel}) = bundle_image2DSegment_zoom_factory

"""
    _mask_driven_factory(I, operator, kernel) -> Function

Define the function `operator` specialised for output type `I` and return it.
`kernel(src_pixels, mask_pixels, is_foreground, margin)` does the work and
returns the output pixel matrix. The methods (see the module docstring) differ
only in where the mask comes from and whether a margin is given.
"""
function _mask_driven_factory(::Type{I}, operator::Symbol, kernel::K) where {I,K}
    storage_type = _get_image_type(I)                 # e.g. N0f8
    pixel_type = _get_image_pixel_type(I)             # e.g. IntensityPixel{N0f8}
    size_type = _get_image_tuple_size(I)              # e.g. Tuple{28,28}
    _validate_factory_type(storage_type)
    function_name = Symbol(operator, :_, Symbol(I))

    # (src, binary mask, margin) and (src, binary mask)
    fn = @eval function $function_name(
            src::Source,
            mask::Mask,
            margin::Real,
            args::Vararg{Any},
        ) where {Source<:$I,MaskBool,Mask<:SizedImage{$size_type,BinaryPixel{MaskBool}}}
        return SImageND($kernel(src.img, mask.img, IsSet(), clamp_unit(margin, $_DEFAULT_MARGIN)), $size_type)
    end
    @eval function $function_name(
            src::Source,
            mask::Mask,
            args::Vararg{Any},
        ) where {Source<:$I,MaskBool,Mask<:SizedImage{$size_type,BinaryPixel{MaskBool}}}
        return SImageND($kernel(src.img, mask.img, IsSet(), $_DEFAULT_MARGIN), $size_type)
    end
    # (src, intensity saliency map, margin) and (src, saliency): threshold 0.5
    @eval function $function_name(
            src::Source,
            saliency::Saliency,
            margin::Real,
            args::Vararg{Any},
        ) where {Source<:$I,SaliencyStorage,Saliency<:SizedImage{$size_type,IntensityPixel{SaliencyStorage}}}
        return SImageND($kernel(src.img, saliency.img, AtLeast(0.5), clamp_unit(margin, $_DEFAULT_MARGIN)), $size_type)
    end
    @eval function $function_name(
            src::Source,
            saliency::Saliency,
            args::Vararg{Any},
        ) where {Source<:$I,SaliencyStorage,Saliency<:SizedImage{$size_type,IntensityPixel{SaliencyStorage}}}
        return SImageND($kernel(src.img, saliency.img, AtLeast(0.5), $_DEFAULT_MARGIN), $size_type)
    end

    if pixel_type <: BinaryPixel
        # (mask) and (mask, margin): a mask zooms on its own foreground.
        @eval function $function_name(src::Source, args::Vararg{Any}) where {Source<:$I}
            return SImageND($kernel(src.img, src.img, IsSet(), $_DEFAULT_MARGIN), $size_type)
        end
        @eval function $function_name(src::Source, margin::Real, args::Vararg{Any}) where {Source<:$I}
            return SImageND($kernel(src.img, src.img, IsSet(), clamp_unit(margin, $_DEFAULT_MARGIN)), $size_type)
        end
    elseif pixel_type <: IntensityPixel
        # (img), (img, threshold) and (img, threshold, margin): an intensity
        # image is thresholded to find its own foreground.
        @eval function $function_name(src::Source, args::Vararg{Any}) where {Source<:$I}
            return SImageND($kernel(src.img, src.img, AtLeast(0.5), $_DEFAULT_MARGIN), $size_type)
        end
        @eval function $function_name(src::Source, threshold::Real, args::Vararg{Any}) where {Source<:$I}
            return SImageND($kernel(src.img, src.img, AtLeast(clamp_unit(threshold)), $_DEFAULT_MARGIN), $size_type)
        end
        @eval function $function_name(
                src::Source,
                threshold::Real,
                margin::Real,
                args::Vararg{Any},
            ) where {Source<:$I}
            return SImageND(
                $kernel(src.img, src.img, AtLeast(clamp_unit(threshold)), clamp_unit(margin, $_DEFAULT_MARGIN)),
                $size_type,
            )
        end
    end
    return fn
end

"""
    _point_driven_factory(I, operator, kernel) -> Function

Define `operator` for output type `I` with methods `(src, x, y)`, `(src, s)`
(meaning `x = y = s`) and `(src)` (the image centre).
`kernel(src_pixels, x, y)` returns the output pixel matrix.
"""
function _point_driven_factory(::Type{I}, operator::Symbol, kernel::K) where {I,K}
    storage_type = _get_image_type(I)
    size_type = _get_image_tuple_size(I)
    _validate_factory_type(storage_type)
    function_name = Symbol(operator, :_, Symbol(I))
    # (src, x, y): the point given by two coordinates.
    fn = @eval function $function_name(src::Source, x::Real, y::Real, args::Vararg{Any}) where {Source<:$I}
        return SImageND($kernel(src.img, clamp_unit(x), clamp_unit(y)), $size_type)
    end
    # (src, s): a point on the diagonal, x = y = s.
    @eval function $function_name(src::Source, s::Real, args::Vararg{Any}) where {Source<:$I}
        u = clamp_unit(s)
        return SImageND($kernel(src.img, u, u), $size_type)
    end
    # (src): the image centre.
    @eval function $function_name(src::Source, args::Vararg{Any}) where {Source<:$I}
        return SImageND($kernel(src.img, 0.5, 0.5), $size_type)
    end
    return fn
end

# ---------------------------------------------------------------------------
# Operators
# ---------------------------------------------------------------------------

"""
Mask-driven operator families: `(prefix, mode, verb, tail)` for the generated descriptions.

- `prefix`: the operator name (and the start of its selector variants, e.g.
  `zoom_crop_bbox_largest`);
- `mode`: what to do with the window (`CropBox()`, …);
- `verb`, `tail`: wording around the target in the descriptions, e.g.
  "Zoom that *crops the bounding box of* the whole mask foreground *and
  resizes it back*."
"""
const _MODES = (
    (:zoom_crop_bbox, CropBox(), "crops the bounding box of", "and resizes it back"),
    (:zoom_crop_aspect, CropAspect(), "crops the bounding box, widened to the image aspect ratio, of", "and resizes it back"),
    (:zoom_crop_isolate, CropIsolate(), "crops the bounding box of", "with other pixels zeroed, and resizes it back"),
    (:zoom_recenter, RecenterMode(), "translates the centroid of", "to the image centre (margin ignored)"),
)

"Pixel kinds an operator is registered for by default."
const _ALL_KINDS = (IntensityPixel, BinaryPixel, SegmentPixel)

"""
Define the factory function `factory_name(output_type)` (which calls
`builder(output_type)`), attach `doc`, and register it under `operator` in the
bundle of each pixel kind in `kinds`.
"""
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

# The closures below are built by functions rather than inline in the loops, so
# each one captures its own arguments: a variable reassigned later in the same
# loop body would otherwise be shared by every closure created in it.
_mask_builder(operator::Symbol, kernel) = I -> _mask_driven_factory(I, operator, kernel)
_point_builder(operator::Symbol, kernel) = I -> _point_driven_factory(I, operator, kernel)
_foreground_kernel(mode::ZoomMode) =
    (src, mask, fg, margin) -> _zoom_foreground(src, mask, fg, mode, margin)
_object_kernel(select, mode::ZoomMode) =
    (src, mask, fg, margin) -> _zoom_object(src, mask, fg, select, mode, margin)
_fixed_select(select_fn) = (t, src) -> select_fn(t)
_mean_select(direction::Float64) = (t, src) -> select_by_mean(t, src, direction)
_glimpse_kernel(fraction::Float64) = (src, x, y) -> _zoom_point(src, x, y, fraction)
# Kernel signatures: mask-driven (src_pixels, mask_pixels, is_foreground, margin) -> pixels;
# selectors (table, src_pixels) -> object id; point-driven (src_pixels, x, y) -> pixels.

for (prefix, mode, verb, tail) in _MODES
    # Whole foreground: zoom_crop_bbox, zoom_crop_aspect, …
    operator = prefix
    _define_factory!(Symbol(operator, :_image2D_factory), operator,
        _mask_builder(operator, _foreground_kernel(mode)), _ALL_KINDS,
        "Zoom that $verb the whole mask foreground $tail.",
        """
            $(operator)_image2D_factory(::Type{I})

        Specialises `$operator`, which $verb the whole foreground of a mask
        $tail.
        """)

    # One object chosen by a fixed selector: zoom_crop_bbox_largest, …
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

    # One object chosen by its mean source intensity (intensity bundle only).
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

# Glimpses: (name suffix, window size as a fraction of each side), e.g. zoom_glimpse_25p.
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
        (src, x, y) -> _translate(src, unit_to_position(y, size(src, 1)), unit_to_position(x, size(src, 2)))),
    _ALL_KINDS,
    "Translates the image so a point lands on the centre.",
    """
        zoom_recenter_point_image2D_factory(::Type{I})

    Specialises `zoom_recenter_point(img, x, y)` / `(img, s)`: translates the
    image without rescaling so `(x, y)` lands on the centre; borders are filled
    with zero.
    """)

"Define `zoom_center` for output type `I`: `(img, z)` keeps the central fraction `z` of each side (at least 5%), `(img)` keeps half."
function _center_factory(::Type{I}) where {I}
    storage_type = _get_image_type(I)
    size_type = _get_image_tuple_size(I)
    _validate_factory_type(storage_type)
    function_name = Symbol(:zoom_center_, Symbol(I))
    # (img, z): never smaller than 5% of each side.
    fn = @eval function $function_name(src::Source, z::Real, args::Vararg{Any}) where {Source<:$I}
        return SImageND(_zoom_point(src.img, 0.5, 0.5, max(clamp_unit(z), 0.05)), $size_type)
    end
    @eval function $function_name(src::Source, args::Vararg{Any}) where {Source<:$I}
        return SImageND(_zoom_point(src.img, 0.5, 0.5, 0.5), $size_type)
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

"Define a band crop along `axis` for output type `I`: `(img, a, b)` keeps the band between `a` and `b`; `(img, a)` a 25% band centred on `a`."
function _band_factory(::Type{I}, operator::Symbol, axis::Int) where {I}
    storage_type = _get_image_type(I)
    size_type = _get_image_tuple_size(I)
    _validate_factory_type(storage_type)
    function_name = Symbol(operator, :_, Symbol(I))
    # (img, a, b): the band between a and b.
    fn = @eval function $function_name(src::Source, a::Real, b::Real, args::Vararg{Any}) where {Source<:$I}
        return SImageND(_zoom_band(src.img, $axis, clamp_unit(a), clamp_unit(b)), $size_type)
    end
    # (img, a): a band from a − 0.125 to a + 0.125 (25% of the image), clipped.
    @eval function $function_name(src::Source, a::Real, args::Vararg{Any}) where {Source<:$I}
        u = clamp_unit(a)
        return SImageND(_zoom_band(src.img, $axis, max(u - 0.125, 0.0), min(u + 0.125, 1.0)), $size_type)
    end
    return fn
end
_band_builder(operator::Symbol, axis::Int) = I -> _band_factory(I, operator, axis)
# Bands: (operator name, axis (1 rows, 2 columns), wording).
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
