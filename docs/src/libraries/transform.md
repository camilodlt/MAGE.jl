```@meta
CurrentModule = UTCGP
```

# Geometric Transforms

Same-size flips, rotations and shifts, and mask-driven *canonical poses*:
transforms that put an image into a standard orientation so that situations
that are mirror images or rotations of each other look the same to the rest
of the program.

| Getter | Bundles |
|:--|:--|
| `get_extension_transform_intensityimg()` | `bundle_image2DIntensity_transform_factory` |
| `get_extension_transform_binaryimg()` | `bundle_image2DBinary_transform_factory` |
| `get_extension_transform_segmentimg()` | `bundle_image2DSegment_transform_factory` |

All three bundles hold the same twelve operators. Outputs keep the specialised
size and pixel type; pixels coming from outside the image are zero. Intensity
images are resampled bilinearly, masks and segment maps with nearest
neighbour so their values are never blended.

## Example frame

```@setup tr
using UTCGP
include(joinpath(dirname(pathof(UTCGP)), "..", "docs", "gallery_helpers.jl"))
assets = g_assets("transform")
const H, W = 80, 120
function frame_values(; ball = (30, 30))
    v = fill(0.1, H, W)
    v[5:20, 5:8] .= 0.9; v[17:20, 5:16] .= 0.9          # "L" marker, top-left
    v[30:40, 110:112] .= 0.7                             # right paddle
    v[60:70, 8:10] .= 0.7                                # left paddle
    v[ball[1]:ball[1]+2, ball[2]:ball[2]+2] .= 1.0       # ball
    return v
end
frame = g_intensity(frame_values())
I = typeof(frame)
op(name) = bundle_image2DIntensity_transform_factory[name].fn(I)
save_img(name, img; scale = 2) = g_save(assets, name, g_up(g_canvas(img), scale))
save_img("frame.png", frame)
for name in (:transform_flip_h, :transform_flip_v, :transform_rotate_180,
             :transform_rotate_90, :transform_rotate_270)
    save_img("$(name).png", g_call(op(name), frame))
end
for a in (0.03, 0.125, 0.25, 0.5)
    save_img("rotate_$(g_tag(a)).png", g_call(op(:transform_rotate), frame, a))
end
for (tag, args) in (("x06", (0.6, 0.5)), ("y07", (0.5, 0.7)), ("diag03", (0.3,)), ("x09_y03", (0.9, 0.3)))
    save_img("shift_$(tag).png", g_call(op(:transform_shift), frame, args...))
    save_img("shift_wrap_$(tag).png", g_call(op(:transform_shift_wrap), frame, args...))
end
```

80×120, shown at 2×: an "L" marker in the top-left corner (so orientation is
easy to read), two paddles and a ball.

![frame](../assets/fns/transform/frame.png)

## Flips and quarter turns

| `transform_flip_h` | `transform_flip_v` | `transform_rotate_180` |
|:--:|:--:|:--:|
| ![flip h](../assets/fns/transform/transform_flip_h.png) | ![flip v](../assets/fns/transform/transform_flip_v.png) | ![rotate 180](../assets/fns/transform/transform_rotate_180.png) |

| `transform_rotate_90` (counter-clockwise) | `transform_rotate_270` (clockwise) |
|:--:|:--:|
| ![rotate 90](../assets/fns/transform/transform_rotate_90.png) | ![rotate 270](../assets/fns/transform/transform_rotate_270.png) |

Quarter turns are exact on square images. This frame is 80×120, so the
rotated 120×80 picture is stretched back to 80×120: the type, and therefore
the size, of a MAGE image cannot change.

## Rotation by any angle

`transform_rotate(img, a)` rotates by `a` turns counter-clockwise about the
centre (`0.25` = 90°). Corners that come from outside the image are zero.

| `a = 0.03` (≈ 11°) | `a = 0.125` (45°) | `a = 0.25` (90°) | `a = 0.5` (180°) |
|:--:|:--:|:--:|:--:|
| ![rotate 0.03](../assets/fns/transform/rotate_003.png) | ![rotate 0.125](../assets/fns/transform/rotate_0125.png) | ![rotate 0.25](../assets/fns/transform/rotate_025.png) | ![rotate 0.5](../assets/fns/transform/rotate_05.png) |

## Shifts

`transform_shift(img, dx, dy)` moves the image by `(u − 0.5)` of its size per
axis: `0.5` is no shift, `0` half the image left (up), `1` half right (down).
`(img, s)` uses `dx = dy = s`. `transform_shift_wrap` wraps around instead of
filling with zero, like playfields where leaving one side re-enters the other.

| Call | `transform_shift` | `transform_shift_wrap` |
|:--|:--:|:--:|
| `(img, 0.6, 0.5)`: 12 px right | ![shift x](../assets/fns/transform/shift_x06.png) | ![wrap x](../assets/fns/transform/shift_wrap_x06.png) |
| `(img, 0.5, 0.7)`: 16 px down | ![shift y](../assets/fns/transform/shift_y07.png) | ![wrap y](../assets/fns/transform/shift_wrap_y07.png) |
| `(img, 0.3)`: up-left | ![shift diag](../assets/fns/transform/shift_diag03.png) | ![wrap diag](../assets/fns/transform/shift_wrap_diag03.png) |
| `(img, 0.9, 0.3)` | ![shift xy](../assets/fns/transform/shift_x09_y03.png) | ![wrap xy](../assets/fns/transform/shift_wrap_x09_y03.png) |

## Canonical poses from a mask

These operators look at a mask (a binary mask, an intensity map thresholded at
`0.5`, or with `(img)` the image itself) and transform the image accordingly.

### Mirror so the object is always on the same side

`transform_flip_h_if_right(img, mask)` mirrors the image left-right when the
mask's centroid is in the right half; `transform_flip_v_if_bottom` does the
same vertically. Here the mask is the ball (`frame > 0.95`): the two rallies
are mirror images, and after the operator they are the same picture, so one
evolved rule covers both sides of the court.

```@setup tr
left_rally = g_intensity(frame_values(ball = (45, 40)))
right_rally = g_call(op(:transform_flip_h), left_rally)
ball_mask(img) = g_binary(Float64.(reinterpret(img.img)) .> 0.95)
save_img("rally_left.png", left_rally)
save_img("rally_right.png", right_rally)
save_img("rally_left_canonical.png", g_call(op(:transform_flip_h_if_right), left_rally, ball_mask(left_rally)))
save_img("rally_right_canonical.png", g_call(op(:transform_flip_h_if_right), right_rally, ball_mask(right_rally)))
```

| | Ball on the left | Ball on the right |
|:--|:--:|:--:|
| input | ![left rally](../assets/fns/transform/rally_left.png) | ![right rally](../assets/fns/transform/rally_right.png) |
| `transform_flip_h_if_right(img, ball)` | ![left canonical](../assets/fns/transform/rally_left_canonical.png) | ![right canonical](../assets/fns/transform/rally_right_canonical.png) |

`transform_flip_v_if_bottom(img, mask)` does the same vertically: the image
is mirrored top-bottom when the mask's centroid is in the bottom half, so the
ball always ends up in the top half.

```@setup tr
top_rally = g_intensity(frame_values(ball = (15, 60)))
bottom_rally = g_call(op(:transform_flip_v), top_rally)
save_img("rally_top.png", top_rally)
save_img("rally_bottom.png", bottom_rally)
save_img("rally_top_canonical.png", g_call(op(:transform_flip_v_if_bottom), top_rally, ball_mask(top_rally)))
save_img("rally_bottom_canonical.png", g_call(op(:transform_flip_v_if_bottom), bottom_rally, ball_mask(bottom_rally)))
```

| | Ball in the top half | Ball in the bottom half |
|:--|:--:|:--:|
| input | ![top rally](../assets/fns/transform/rally_top.png) | ![bottom rally](../assets/fns/transform/rally_bottom.png) |
| `transform_flip_v_if_bottom(img, ball)` | ![top canonical](../assets/fns/transform/rally_top_canonical.png) | ![bottom canonical](../assets/fns/transform/rally_bottom_canonical.png) |

With `(img)` alone, the image is its own mask (intensity `≥ 0.5`): the
decision then depends on where all the bright pixels are, not only the ball.

### Align the main axis

`transform_align_axis(img, mask)` rotates about the image centre so the
mask's principal axis is horizontal. `transform_canonical_pose(img, mask)`
also moves the mask's centroid to the centre: position and orientation are
removed, only shape remains.

```@setup tr
tilted = zeros(H, W)
for r in 1:H, c in 1:W
    # Ellipse with a notch, centred at (25, 85), tilted by 35 degrees.
    y, x = r - 25, c - 85
    u = x * cosd(35) - y * sind(35)
    v = x * sind(35) + y * cosd(35)
    (u / 16)^2 + (v / 6)^2 <= 1 && (tilted[r, c] = 0.85)
    (u - 9)^2 + v^2 <= 9 && (tilted[r, c] = 0.3)
end
tilted_img = g_intensity(0.1 .+ tilted)
tilted_mask = g_binary(tilted .> 0.5)
save_img("tilted.png", tilted_img)
save_img("tilted_aligned.png", g_call(op(:transform_align_axis), tilted_img, tilted_mask))
save_img("tilted_pose.png", g_call(op(:transform_canonical_pose), tilted_img, tilted_mask))
```

| Input | `transform_align_axis(img, mask)` | `transform_canonical_pose(img, mask)` |
|:--:|:--:|:--:|
| ![tilted](../assets/fns/transform/tilted.png) | ![aligned](../assets/fns/transform/tilted_aligned.png) | ![pose](../assets/fns/transform/tilted_pose.png) |

The principal axis has no head or tail, so an object can end up pointing left
or right; follow with `transform_flip_h_if_right` on a mask of a
distinguishing part to fix that too.

## Binary and segment images

The binary and segment bundles hold the same operators with nearest-neighbour
sampling:

```@setup tr
mask = g_binary(frame_values() .> 0.5)
segment = g_segment(round.(Int, 3 .* frame_values()))
bop(name) = bundle_image2DBinary_transform_factory[name].fn(typeof(mask))
sop(name) = bundle_image2DSegment_transform_factory[name].fn(typeof(segment))
save_img("mask.png", mask)
save_img("mask_rotate.png", g_call(bop(:transform_rotate), mask, 0.06))
save_img("segment.png", segment)
save_img("segment_rotate.png", g_call(sop(:transform_rotate), segment, 0.06))
```

| Mask | `transform_rotate(mask, 0.06)` | Segment map | `transform_rotate(labels, 0.06)` |
|:--:|:--:|:--:|:--:|
| ![mask](../assets/fns/transform/mask.png) | ![mask rotate](../assets/fns/transform/mask_rotate.png) | ![segment](../assets/fns/transform/segment.png) | ![segment rotate](../assets/fns/transform/segment_rotate.png) |

## Performance

On an 84×84 image: flips and quarter turns ~3 µs, shifts ~4 µs (wrapping
~6 µs), `flip_*_if_*` 3–6 µs, arbitrary rotation and axis alignment ~48 µs
(bilinear; ~20 µs for masks and segment maps).

## Bundles

```@docs
UTCGP.image2D_transform
UTCGP.image2D_transform.bundle_image2DIntensity_transform_factory
UTCGP.image2D_transform.bundle_image2DBinary_transform_factory
UTCGP.image2D_transform.bundle_image2DSegment_transform_factory
```
