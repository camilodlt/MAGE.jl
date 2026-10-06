```@meta
CurrentModule = UTCGP
```

# Mask Shape Clean-up

Masks produced by thresholding, saliency or foreground extraction are rarely
clean: objects have holes, noise leaves isolated pixels, score bars and walls
touch the border. These operators repair masks before they reach the blob,
locator or zoom libraries, and turn masks into distance maps.

| Getter | Bundles |
|:--|:--|
| `get_extension_maskshape_binaryimg()` | `bundle_image2DBinary_maskshape_factory` (binary output) |
| `get_extension_maskshape_intensityimg()` | `bundle_image2DIntensity_maskshape_factory` (distance maps, intensity output) |

Signatures follow the blob-extraction convention: `(mask)` and `(mask, p)` for
a binary mask; `(saliency)`, `(saliency, threshold)` and
`(saliency, threshold, p)` for an intensity map. `p` is the operator's
parameter in `[0, 1]`. Objects are 8-connected; background regions are
4-connected, so a hole touching the outside only diagonally stays a hole.

## Example mask

```@setup shape
using UTCGP
include(joinpath(dirname(pathof(UTCGP)), "..", "docs", "gallery_helpers.jl"))
assets = g_assets("mask_shape")
const H, W = 80, 120
m = falses(H, W)
for r in 1:H, c in 1:W
    d2 = (r - 20)^2 + (c - 20)^2
    36 < d2 <= 144 && (m[r, c] = true)                                  # ring
    ((r - 22) / 10)^2 + ((c - 60) / 16)^2 <= 1 && (m[r, c] = true)      # cell
end
for (r, c) in ((18, 54), (25, 63), (20, 68))
    m[r:r+1, c:c+1] .= false                                            # small holes in the cell
end
m[45:70, 8:12] .= true; m[45:49, 8:30] .= true; m[66:70, 8:30] .= true   # "C"
m[45:70, 55:60] .= true; m[55:60, 45:70] .= true                         # thick cross
for k in 0:25
    m[45 + k, 80 + k] = true; m[45 + k, 81 + k] = true                   # thin diagonal
end
m[1:3, 85:117] .= true                                                   # HUD bar on the border
m[30:80, 118:120] .= true                                                # wall on the border
for k in 1:30
    r, c = 1 + mod(37k, 78), 1 + mod(53k, 116)
    m[r, c] = true                                                       # noise
end
mask = g_binary(m)
B = typeof(mask)
op(name) = bundle_image2DBinary_maskshape_factory[name].fn(B)
save_mask(name, img) = g_save(assets, name, g_up(g_canvas(img), 2))
save_mask("mask.png", mask)
for name in (:shape_fill_holes, :shape_holes, :shape_convex_hull, :shape_convex_hull_objects,
             :shape_bbox_fill, :shape_skeleton, :shape_boundary, :shape_remove_small,
             :shape_remove_large, :shape_clear_border, :shape_keep_border, :shape_majority)
    save_mask("$(name).png", g_call(op(name), mask))
end
for p in (1.0, 0.001)
    save_mask("fill_holes_$(g_tag(p)).png", g_call(op(:shape_fill_holes), mask, p))
end
for p in (0.0002, 0.003, 0.02)
    save_mask("remove_small_$(g_tag(p)).png", g_call(op(:shape_remove_small), mask, p))
end
for p in (0.005, 0.02)
    save_mask("remove_large_$(g_tag(p)).png", g_call(op(:shape_remove_large), mask, p))
end
```

80×120, shown at 2×: a ring, a "cell" with three 2×2 holes, a C, a thick
cross, a thin diagonal, a score bar and a wall touching the border, and 30
isolated noise pixels.

![Example mask](../assets/fns/mask_shape/mask.png)

## Every binary operator, default parameter

| Operator | Result | What it does |
|:--|:--:|:--|
| `shape_fill_holes` | ![fill holes](../assets/fns/mask_shape/shape_fill_holes.png) | fills every enclosed background region (the ring and the cell become solid) |
| `shape_holes` | ![holes](../assets/fns/mask_shape/shape_holes.png) | only the holes: what `fill_holes` adds |
| `shape_convex_hull` | ![convex hull](../assets/fns/mask_shape/shape_convex_hull.png) | one convex polygon around the whole foreground |
| `shape_convex_hull_objects` | ![convex hull objects](../assets/fns/mask_shape/shape_convex_hull_objects.png) | convex hull of each object separately (the C closes, the cross becomes a diamond) |
| `shape_bbox_fill` | ![bbox fill](../assets/fns/mask_shape/shape_bbox_fill.png) | each object replaced by its filled bounding box |
| `shape_skeleton` | ![skeleton](../assets/fns/mask_shape/shape_skeleton.png) | one-pixel-wide medial lines (Guo-Hall thinning) |
| `shape_boundary` | ![boundary](../assets/fns/mask_shape/shape_boundary.png) | object pixels touching the background or the image edge |
| `shape_remove_small` | ![remove small](../assets/fns/mask_shape/shape_remove_small.png) | drops objects under `0.1%` of the image (the noise) |
| `shape_remove_large` | ![remove large](../assets/fns/mask_shape/shape_remove_large.png) | drops objects over `10%` of the image (none here) |
| `shape_clear_border` | ![clear border](../assets/fns/mask_shape/shape_clear_border.png) | drops objects touching the border (score bar, wall, edge noise) |
| `shape_keep_border` | ![keep border](../assets/fns/mask_shape/shape_keep_border.png) | keeps only objects touching the border |
| `shape_majority` | ![majority](../assets/fns/mask_shape/shape_majority.png) | 3×3 majority vote: isolated pixels vanish, one-pixel gaps close |

## Effect of `p`

`shape_fill_holes(mask, p)` fills only holes of at most `p` of the image's
pixels (`p = 1`, the default, fills all of them):

| `p = 1` (all holes) | `p = 0.001` (≤ 9 px: the cell's holes, not the ring's) |
|:--:|:--:|
| ![fill all](../assets/fns/mask_shape/fill_holes_10.png) | ![fill small](../assets/fns/mask_shape/fill_holes_0001.png) |

`shape_remove_small(mask, p)` drops objects smaller than `p` of the image:

| `p = 0.0002` (< 2 px) | `p = 0.003` (< 29 px) | `p = 0.02` (< 192 px) |
|:--:|:--:|:--:|
| ![small 0.0002](../assets/fns/mask_shape/remove_small_00002.png) | ![small 0.003](../assets/fns/mask_shape/remove_small_0003.png) | ![small 0.02](../assets/fns/mask_shape/remove_small_002.png) |

`shape_remove_large(mask, p)` drops objects larger than `p`:

| `p = 0.005` (> 48 px) | `p = 0.02` (> 192 px) |
|:--:|:--:|
| ![large 0.005](../assets/fns/mask_shape/remove_large_0005.png) | ![large 0.02](../assets/fns/mask_shape/remove_large_002.png) |

## Distance maps

`bundle_image2DIntensity_maskshape_factory` returns intensity images:

```@setup shape
I = typeof(g_intensity(zeros(H, W)))
iop(name) = bundle_image2DIntensity_maskshape_factory[name].fn(I)
filled = g_call(op(:shape_fill_holes), g_call(op(:shape_remove_small), mask))
save_mask("filled_clean.png", filled)
save_mask("distance_inside.png", g_call(iop(:shape_distance_inside), filled))
save_mask("proximity.png", g_call(iop(:shape_proximity), filled))
```

| Input (`fill_holes ∘ remove_small`) | `shape_distance_inside` | `shape_proximity` |
|:--:|:--:|:--:|
| ![input](../assets/fns/mask_shape/filled_clean.png) | ![distance inside](../assets/fns/mask_shape/distance_inside.png) | ![proximity](../assets/fns/mask_shape/proximity.png) |

`shape_distance_inside` is the distance from each object pixel to the
background, divided by its maximum: thick parts are bright and the brightest
ridge is the skeleton. `shape_proximity` is `1` on objects and fades with the
distance to the nearest object (`1 − d / diagonal`): a smooth "how close am I
to something" map that `region_*` or the locators can read.

## On a real mask

Lena's Itti-Koch saliency thresholded at `0.5` gives a ragged mask; a short
chain of clean-up operators turns it into a few solid regions.

```@setup shape
lena_values = Float64.(Gray.(load(joinpath(g_repo_root(), "assets", "lena_gray_16bit.png"))))[1:2:end, 1:2:end]
lena = g_intensity(lena_values, N0f16)
saliency = g_call(bundle_image2DIntensity_saliency_fixation_factory[:itti_koch_saliency].fn(typeof(lena)), lena)
LB = typeof(g_binary(falses(size(lena_values))))
lop(name) = bundle_image2DBinary_maskshape_factory[name].fn(LB)
step1 = g_call(lop(:shape_majority), saliency, 0.45)
step2 = g_call(lop(:shape_remove_small), step1, 0.002)
step3 = g_call(lop(:shape_fill_holes), step2)
step4 = g_call(lop(:shape_convex_hull_objects), step3)
g_save(assets, "lena_saliency.png", g_canvas(saliency))
for (k, img) in enumerate((step1, step2, step3, step4))
    g_save(assets, "lena_step$(k).png", g_canvas(img))
end
```

| Saliency | `shape_majority(saliency, 0.45)` | `shape_remove_small(·, 0.002)` | `shape_fill_holes(·)` | `shape_convex_hull_objects(·)` |
|:--:|:--:|:--:|:--:|:--:|
| ![saliency](../assets/fns/mask_shape/lena_saliency.png) | ![step 1](../assets/fns/mask_shape/lena_step1.png) | ![step 2](../assets/fns/mask_shape/lena_step2.png) | ![step 3](../assets/fns/mask_shape/lena_step3.png) | ![step 4](../assets/fns/mask_shape/lena_step4.png) |

## Performance

On an 84×84 mask: boundary ~7 µs, majority ~8 µs, bounding boxes ~13 µs, fill
holes ~14 µs, size and border filters ~16 µs, convex hulls 17–22 µs, skeleton
~60 µs (ImageMorphology's Guo-Hall thinning), distance maps 60–75 µs (an exact
Euclidean distance transform, Felzenszwalb–Huttenlocher).

## Bundles

```@docs
UTCGP.image2D_mask_shape
UTCGP.image2D_mask_shape.bundle_image2DBinary_maskshape_factory
UTCGP.image2D_mask_shape.bundle_image2DIntensity_maskshape_factory
```
