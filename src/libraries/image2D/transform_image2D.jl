"""
Geometric transforms that keep the image size: flips, rotations, shifts, and
mask-driven canonical poses.

# Bundles

- bundle_image2DIntensity_transform_factory
- bundle_image2DBinary_transform_factory
- bundle_image2DSegment_transform_factory

The exhaustive operator list is on the Bundle Catalogue page.

# How this file is organised

Each operator is a *kernel* on pixel matrices (`Matrix{P} -> Matrix{P}`)
wrapped by a *factory*. A factory is a function of the output image type `I`;
it defines the operator's methods for `I` and returns the function. There
are four method shapes (see each `_*_factory`): image only, image and one
scalar, image and a point, image and a mask.

Arbitrary transforms go through `_warp`, which maps each *output* pixel back
to a *source* position (inverse mapping, so every output pixel gets exactly
one value), then samples there: bilinearly for intensity images, nearest
neighbour otherwise.

# Example

```julia
using UTCGP, ImageCore
img = SImageND(IntensityPixel{N0f8}.(rand(32, 32)))
I = typeof(img)
flip = bundle_image2DIntensity_transform_factory[:transform_flip_h].fn(I)
flip(img)                 # column j of the result is column 33 − j of img
shift = bundle_image2DIntensity_transform_factory[:transform_shift].fn(I)
shift(img, 0.75, 0.5)     # moved round(0.25 · 32) = 8 columns right, not vertically
rotate = bundle_image2DIntensity_transform_factory[:transform_rotate].fn(I)
rotate(img, 0.25)         # a quarter turn counter-clockwise about the centre
```
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
using ..image2D_object_common: IsSet, AtLeast, clamp_unit
using ..image2D_zoom: to_storage, zero_pixel

# Returned by the bundles when no method matches the inputs (MAGE then skips the node).
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
    _warp(src, source_of) -> Matrix

Resample `src` through `source_of(i, j) -> (row, col)`, which maps each
output pixel to a continuous source position (pixel centres at integers).
Out-of-image samples are zero.

This method (binary and segment pixels) takes the nearest source pixel.
Positions are range-checked as floats first, so the integer conversions need
no overflow checks.
"""
function _warp(src::AbstractMatrix{P}, source_of::F) where {P,F}
    h, w = size(src)
    out = similar(src)
    zero = zero_pixel(P)                     # value for samples outside the image
    @inbounds for j in 1:w, i in 1:h
        r, c = source_of(i, j)               # where output pixel (i, j) comes from
        # Rounds to a pixel inside the image exactly when r ∈ [0.5, h + 0.5) and c likewise.
        if 0.5 <= r < h + 0.5 && 0.5 <= c < w + 0.5
            ri = unsafe_trunc(Int, round(r))
            ci = unsafe_trunc(Int, round(c))
            out[i, j] = (1 <= ri <= h && 1 <= ci <= w) ? src[ri, ci] : zero
        else
            out[i, j] = zero
        end
    end
    return out
end

"Bilinear `_warp` for intensity images: pixels outside the image count as `0` in the interpolation."
function _warp(src::AbstractMatrix{IntensityPixel{T}}, source_of::F) where {T,F}
    h, w = size(src)
    out = similar(src)
    zero = IntensityPixel{T}(to_storage(T, 0.0))
    # Pixel value, or 0 outside the image (used near the border only).
    @inline value(r, c) = (1 <= r <= h && 1 <= c <= w) ? Float64(src[r, c].pixel) : 0.0
    @inbounds for j in 1:w, i in 1:h
        r, c = source_of(i, j)
        # Farther than one pixel outside: all four neighbours are outside, the result is 0.
        if !(0.0 < r < h + 1.0 && 0.0 < c < w + 1.0)
            out[i, j] = zero
            continue
        end
        r0 = unsafe_trunc(Int, r)             # r > 0, so truncation is floor
        c0 = unsafe_trunc(Int, c)
        frac_r = r - r0                       # weights of the next row / column
        frac_c = c - c0
        # The four surrounding pixels; the bounds-checked path only near the border.
        if 1 <= r0 < h && 1 <= c0 < w
            top_left = Float64(src[r0, c0].pixel)
            top_right = Float64(src[r0, c0+1].pixel)
            bottom_left = Float64(src[r0+1, c0].pixel)
            bottom_right = Float64(src[r0+1, c0+1].pixel)
        else
            top_left = value(r0, c0)
            top_right = value(r0, c0 + 1)
            bottom_left = value(r0 + 1, c0)
            bottom_right = value(r0 + 1, c0 + 1)
        end
        # Interpolate along the two rows, then between them.
        # Example: r = 2.25, c = 3.5 → 75% row 2 + 25% row 3, each the average of columns 3 and 4.
        top = top_left + frac_c * (top_right - top_left)
        bottom = bottom_left + frac_c * (bottom_right - bottom_left)
        out[i, j] = IntensityPixel{T}(to_storage(T, top + frac_r * (bottom - top)))
    end
    return out
end

"Mirror left-right: output column `j` is input column `w + 1 − j`."
function _flip_h(src::AbstractMatrix)
    h, w = size(src)
    out = similar(src)
    @inbounds for j in 1:w, i in 1:h
        out[i, j] = src[i, w + 1 - j]
    end
    return out
end

"Mirror top-bottom: output row `i` is input row `h + 1 − i`."
function _flip_v(src::AbstractMatrix)
    h, w = size(src)
    out = similar(src)
    @inbounds for j in 1:w, i in 1:h
        out[i, j] = src[h + 1 - i, j]
    end
    return out
end

"Rotate by 180° (both mirrors)."
function _rotate_180(src::AbstractMatrix)
    h, w = size(src)
    out = similar(src)
    @inbounds for j in 1:w, i in 1:h
        out[i, j] = src[h + 1 - i, w + 1 - j]
    end
    return out
end

"""
Rotate 90° (`k = 1`) or 270° (`k = 3`) counter-clockwise on screen, stretched back to size.

Example (`k = 1`): `[1 2; 3 4]` → `[2 4; 1 3]` (the top-right pixel moves to
the top-left corner).
"""
function _rotate_quarter(src::AbstractMatrix, k::Int)
    h, w = size(src)
    if h == w
        # Square: an exact permutation (what the sampler below computes too).
        out = similar(src)
        @inbounds for j in 1:w, i in 1:h
            # k = 1: output row i is input column w + 1 − i read top to bottom; k = 3 the reverse.
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

"""
    _rotate(src, turns, centre_r, centre_c, target_r, target_c)

Rotate by `turns` (fraction of a full turn, counter-clockwise on screen)
about the source point `(centre_r, centre_c)`, which ends up at
`(target_r, target_c)` in the output.

With the centre equal to the target this is a plain rotation; with different
points it also translates (used by `transform_canonical_pose` to rotate about
an object's centroid and move it to the image centre).
"""
function _rotate(src::AbstractMatrix, turns::Float64, centre_r::Float64, centre_c::Float64, target_r::Float64, target_c::Float64)
    sin_a, cos_a = sincospi(2turns)          # sin and cos of the angle 2π · turns
    return _warp(src, (i, j) -> begin
        dy = i - target_r
        dx = j - target_c
        # Inverse of a counter-clockwise screen rotation (rows point down):
        # rotate the output offset clockwise to find its source.
        (centre_r + cos_a * dy + sin_a * dx, centre_c + cos_a * dx - sin_a * dy)
    end)
end

"Rotate by `turns` about the image centre `((h + 1)/2, (w + 1)/2)`."
_rotate(src::AbstractMatrix, turns::Float64) =
    (h = size(src, 1); w = size(src, 2); _rotate(src, turns, (h + 1) / 2, (w + 1) / 2, (h + 1) / 2, (w + 1) / 2))

"""
Shift in pixels for parameter `u` along an axis of length `n`: `round((u − 0.5) · n)`.

Example with `n = 32`: `u = 0.5 → 0`, `u = 0.75 → 8`, `u = 0 → −16`.
"""
@inline _shift_amount(u::Float64, n::Int) = round(Int, (u - 0.5) * n)

"""
Translate by `_shift_amount(dx, w)` columns and `_shift_amount(dy, h)` rows; zero fill, or wrap around when `wrap`.

Example on one row `[1 2 3 4]` shifted one column right: `[0 1 2 3]` (zero
fill) or `[4 1 2 3]` (wrap).
"""
function _shift(src::AbstractMatrix{P}, dx::Float64, dy::Float64, wrap::Bool) where {P}
    h, w = size(src)
    col_shift = _shift_amount(dx, w)
    row_shift = _shift_amount(dy, h)
    out = similar(src)
    zero = zero_pixel(P)
    @inbounds for j in 1:w
        c = j - col_shift                       # source column
        if wrap
            c = mod1(c, w)                      # wrap the column into 1:w
            shift = mod(row_shift, h)           # 0 ≤ shift < h, so r ≥ 1 - h
            for i in 1:h
                r = i - shift
                out[i, j] = src[r < 1 ? r + h : r, c]   # rows above the top come from the bottom
            end
        elseif 1 <= c <= w
            for i in 1:h
                r = i - row_shift
                out[i, j] = (1 <= r <= h) ? src[r, c] : zero
            end
        else                                    # source column outside the image
            for i in 1:h
                out[i, j] = zero
            end
        end
    end
    return out
end

"""
    _foreground_moments(mask, is_foreground) -> (n, mean_r, mean_c, var_rr, var_cc, cov_rc)

Foreground pixel count, centroid and central second moments of `mask`
(all zeros when empty).

The second moments describe the shape's spread: `var_rr` along rows,
`var_cc` along columns, `cov_rc` how they vary together (non-zero for a
tilted shape).
"""
function _foreground_moments(mask::AbstractMatrix, is_foreground::P) where {P}
    n = 0
    sum_r = sum_c = sum_rr = sum_cc = sum_rc = 0.0      # Σr, Σc, Σr², Σc², Σr·c
    @inbounds for c in axes(mask, 2), r in axes(mask, 1)
        is_foreground(mask[r, c]) || continue
        n += 1
        sum_r += r
        sum_c += c
        sum_rr += r * r
        sum_cc += c * c
        sum_rc += r * c
    end
    n == 0 && return 0, 0.0, 0.0, 0.0, 0.0, 0.0
    mean_r, mean_c = sum_r / n, sum_c / n
    # var = E[x²] − E[x]², cov = E[xy] − E[x]E[y]
    return n, mean_r, mean_c, sum_rr / n - mean_r^2, sum_cc / n - mean_c^2, sum_rc / n - mean_r * mean_c
end

"""
Main-axis angle in turns, counter-clockwise on screen from the +x axis (`0` for an isotropic shape).

Example: a horizontal bar gives `0`, a vertical bar `±0.25`, a bar rising to
the right at 45° `0.125`.
"""
function _axis_turns(var_rr, var_cc, cov_rc)
    # A disk or square has no main axis: equal variances and no covariance.
    abs(var_cc - var_rr) + 2abs(cov_rc) <= 1e-9 * (var_rr + var_cc + 1e-12) && return 0.0
    θ = 0.5 * atan(2cov_rc, var_cc - var_rr)    # towards +rows, i.e. clockwise on screen
    return -θ / 2π
end

"Rotate so the mask's main axis is horizontal, about the image centre, or (when `recenter`) about the mask's centroid, moved to the centre."
function _align(src::AbstractMatrix, mask::AbstractMatrix, is_foreground, recenter::Bool)
    n, mean_r, mean_c, var_rr, var_cc, cov_rc = _foreground_moments(mask, is_foreground)
    n == 0 && return src                     # empty mask: unchanged
    h, w = size(src)
    turns = -_axis_turns(var_rr, var_cc, cov_rc)   # rotate back by the axis angle
    if recenter
        return _rotate(src, turns, mean_r, mean_c, (h + 1) / 2, (w + 1) / 2)
    end
    return _rotate(src, turns)
end

"Mirror across `axis` (2: left-right, 1: top-bottom) when the mask's centroid is past the middle."
function _flip_if(src::AbstractMatrix, mask::AbstractMatrix, is_foreground, axis::Int)
    n, mean_r, mean_c, _, _, _ = _foreground_moments(mask, is_foreground)
    n == 0 && return src
    h, w = size(src)
    # (w + 1) / 2 is the middle column (e.g. 16.5 for 32 columns).
    if axis == 2
        return mean_c > (w + 1) / 2 ? _flip_h(src) : src
    end
    return mean_r > (h + 1) / 2 ? _flip_v(src) : src
end

# ---------------------------------------------------------------------------
# Factories
# ---------------------------------------------------------------------------

"The bundle of a pixel kind."
_bundle_for(::Type{<:IntensityPixel}) = bundle_image2DIntensity_transform_factory
_bundle_for(::Type{<:BinaryPixel}) = bundle_image2DBinary_transform_factory
_bundle_for(::Type{<:SegmentPixel}) = bundle_image2DSegment_transform_factory

"""
    _factory_setup(I, operator) -> (pixel_type, size_type, function_name)

Validate the output type `I` and return its pixel type, its size as a tuple
type, and the name of the specialised function.
"""
function _factory_setup(::Type{I}, operator::Symbol) where {I}
    _validate_factory_type(_get_image_type(I))
    return _get_image_pixel_type(I), _get_image_tuple_size(I), Symbol(operator, :_, Symbol(I))
end

"Method `op(img)` → `kernel(pixels)`."
function _plain_factory(::Type{I}, operator::Symbol, kernel::K) where {I,K}
    _, size_type, name = _factory_setup(I, operator)
    return @eval function $name(src::Source, args::Vararg{Any}) where {Source<:$I}
        return SImageND($kernel(src.img), $size_type)
    end
end

"Method `op(img, u)` → `kernel(pixels, clamp_unit(u))`."
function _scalar_factory(::Type{I}, operator::Symbol, kernel::K) where {I,K}
    _, size_type, name = _factory_setup(I, operator)
    return @eval function $name(src::Source, u::Real, args::Vararg{Any}) where {Source<:$I}
        return SImageND($kernel(src.img, clamp_unit(u)), $size_type)
    end
end

"Methods `op(img, x, y)` → `kernel(pixels, x, y)` and `op(img, s)` → `kernel(pixels, s, s)` (clamped to `[0, 1]`)."
function _point_factory(::Type{I}, operator::Symbol, kernel::K) where {I,K}
    _, size_type, name = _factory_setup(I, operator)
    fn = @eval function $name(src::Source, x::Real, y::Real, args::Vararg{Any}) where {Source<:$I}
        return SImageND($kernel(src.img, clamp_unit(x), clamp_unit(y)), $size_type)
    end
    @eval function $name(src::Source, s::Real, args::Vararg{Any}) where {Source<:$I}
        u = clamp_unit(s)
        return SImageND($kernel(src.img, u, u), $size_type)
    end
    return fn
end

"""
Mask-driven methods, each calling `kernel(pixels, mask_pixels, is_foreground)`:

- `op(img, binary_mask)` with `is_foreground = IsSet()`;
- `op(img, saliency)` (intensity map) with `AtLeast(0.5)`;
- `op(img)` using the image as its own mask — binary and intensity images
  only (a segment map has no foreground of its own).
"""
function _mask_factory(::Type{I}, operator::Symbol, kernel::K) where {I,K}
    pixel_type, size_type, name = _factory_setup(I, operator)
    fn = @eval function $name(src::Source, mask::Mask, args::Vararg{Any}) where {Source<:$I,MaskBool,Mask<:SizedImage{$size_type,BinaryPixel{MaskBool}}}
        return SImageND($kernel(src.img, mask.img, IsSet()), $size_type)
    end
    @eval function $name(src::Source, saliency::Saliency, args::Vararg{Any}) where {Source<:$I,SaliencyStorage,Saliency<:SizedImage{$size_type,IntensityPixel{SaliencyStorage}}}
        return SImageND($kernel(src.img, saliency.img, AtLeast(0.5)), $size_type)
    end
    if pixel_type <: BinaryPixel
        @eval function $name(src::Source, args::Vararg{Any}) where {Source<:$I}
            return SImageND($kernel(src.img, src.img, IsSet()), $size_type)
        end
    elseif pixel_type <: IntensityPixel
        @eval function $name(src::Source, args::Vararg{Any}) where {Source<:$I}
            return SImageND($kernel(src.img, src.img, AtLeast(0.5)), $size_type)
        end
    end
    return fn
end

# ---------------------------------------------------------------------------
# Registration
# ---------------------------------------------------------------------------

"`output_type -> factory(output_type, operator, kernel)`; a function so each closure captures its own arguments."
_builder(factory, operator::Symbol, kernel) = I -> factory(I, operator, kernel)

# Each entry is (operator name, factory, kernel, description):
#   - the factory sets the method shapes: plain (img), scalar (img, u),
#     point (img, x, y) / (img, s), mask (img, mask) / (img);
#   - the kernel's arguments follow the factory: plain (pixels), scalar
#     (pixels, u), point (pixels, x, y), mask (pixels, mask_pixels, is_foreground);
#   - the description is shown in the Bundle Catalogue.
# Example: (:transform_flip_h, _plain_factory, src -> _flip_h(src), …) defines
# transform_flip_h(img).
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

# One factory per operator, shared by the three bundles: the pixel kind comes
# from the output type the factory is specialised with.
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
