```@meta
CurrentModule = UTCGP
```

# 3D Volumes: CT, MRI and Microscopy

Libraries for 3D grayscale images (`SImage3D` of `IntensityPixel` or
`BinaryPixel`), such as the MedMNIST3D datasets (28³ or 64³ CT, MRA and
electron-microscopy volumes). They cover the three directions a program needs:

| Direction | Bundles | Getter |
|:--|:--|:--|
| 3D → 3D | `bundle_image3DIntensity_volume_basic_factory`, `bundle_image3DBinary_volume_basic_factory` (identity, constants, casts), `bundle_image3DIntensity_volume_factory`, `bundle_image3DBinary_volume_factory` | `get_extension_volume_intensityimg()`, `get_extension_volume_binaryimg()` |
| 3D → 2D | `bundle_image2DIntensity_fromVolume_factory`, `bundle_image2DBinary_fromVolume_factory` | `get_extension_volume_to_intensityimg()`, `get_extension_volume_to_binaryimg()` |
| 3D → scalar | `bundle_number_volumeShapeFromImg`, `bundle_number_volumeGranulometryFromImg`, `bundle_number_volumeProfileFromImg`, and `bundle_number_intensityStatsFromImg` (2D and 3D) | `get_extension_volume_nb()` |

The 3D → 2D bundles are the bridge to every 2D library: once a program has a
projection or a slice, all 2D image and descriptor operators apply. The 3D →
3D bundles also take 2D inputs (`vol_extrude_*`, `vol_mask2d_*`), so a 2D mask
found on a projection can be pushed back into the volume.

**Basic bundles first.** As for 2D images, a library for a volume type must
start with identity (index 1) and a function that takes no input and returns
that type (index 2): node correction and mutation fall back to them. The basic
volume bundles provide exactly that (`vol_identity`, then `vol_ones`), and the
two 3D → 3D getters put them first. The intensity one also has
`vol_from_mask`, which turns a mask into a `0`/`1` intensity volume.

**Axes.** Dimension 1 is `y` (rows), 2 is `x` (columns), 3 is `z` (slices).
Collapsing an axis keeps the other two in order: a `_z` result is `(y, x)`, a
`_y` result `(x, z)`, a `_x` result `(y, z)`.

**Conventions** are those of the 2D libraries: at most three inputs; scalars
clamped to `[0, 1]` and mapped to each operator's range; masks are binary
volumes or intensity volumes thresholded at `0.5`; empty selections never
error. Objects are 26-connected and cavities 6-connected.

## Example volume

```@setup vol
using UTCGP
include(joinpath(dirname(pathof(UTCGP)), "..", "docs", "gallery_helpers.jl"))
assets = g_assets("volumes")
const N = 28
noise3(r, c, s, k) = 0.5 + 0.5 * sin(12.9898r + 78.233c + 37.719s + 4.1k)

"A CT-like phantom: body, organ with a cavity, a nodule and a wandering vessel."
function phantom(; nodule = true, organ = (8.0, 6.0, 7.0), vessel = true, cavity = true)
    v = zeros(N, N, N)
    for idx in CartesianIndices(v)
        r, c, s = Tuple(idx)
        y, x, z = r - 14.5, c - 14.5, s - 14.5
        if (y / 12)^2 + (x / 13)^2 + (z / 13)^2 > 1
            v[idx] = 0.02                                            # air
            continue
        end
        value = 0.25 + 0.06 * noise3(r, c, s, 1)                     # soft tissue
        in_organ = ((y + 2) / organ[1])^2 + ((x - 1) / organ[2])^2 + (z / organ[3])^2 <= 1
        in_organ && (value = 0.55 + 0.05 * noise3(r, c, s, 2))
        cavity && in_organ && (y + 2)^2 + (x + 2)^2 + (z - 1)^2 <= 4 && (value = 0.05)
        nodule && (y + 4)^2 + (x - 3)^2 + (z + 2)^2 <= 6.25 && (value = 0.92)
        if vessel
            cy = 7 + 2 * sin(z / 4)
            cx = -7 + 2 * cos(z / 5)
            (y - cy)^2 + (x - cx)^2 <= 2.2 && (value = 0.78)
        end
        v[idx] = value
    end
    return v
end

vol = g_intensity(phantom())
mask = g_binary(phantom() .>= 0.5)
I = typeof(vol)
B = typeof(mask)
I2 = typeof(g_intensity(zeros(N, N)))
B2 = typeof(g_binary(falses(N, N)))
iv(name) = bundle_image3DIntensity_volume_factory[name].fn(I)
bv(name) = bundle_image3DBinary_volume_factory[name].fn(B)
to2(name) = bundle_image2DIntensity_fromVolume_factory[name].fn(I2)
to2b(name) = bundle_image2DBinary_fromVolume_factory[name].fn(B2)
call(f, args...) = Base.invokelatest(f, args...)
viewer(volumes; title = "") = g_volume_viewer(volumes; scale = 4, title = title, assets = assets, page = "volumes")
```

A 28³ phantom (the MedMNIST3D size): a textured body in dark air, an organ
with a dark cavity, a bright nodule and a vessel that wanders along `z`. The
mask is `vol ≥ 0.5` (organ, nodule, vessel). `vol_otsu` picks its threshold
automatically and finds the dominant split of this volume instead: body
against air.

**Use the sliders** to move through the slices: each row is one axis, and its
slider moves every volume of the row together.

```@example vol
viewer(["volume" => vol, "mask ≥ 0.5" => mask, "vol_otsu" => call(bv(:vol_otsu), vol)]) # hide
```

## 3D → 3D: intensity

### Filters

`vol_gaussian` (`σ = 0.3 + 2.7p`; fixed `_s05`, `_s1`, `_s2`), `vol_mean_3`,
`vol_mean_5`, `vol_gradient` (central differences), `vol_laplacian`
(absolute, 6-neighbour), `vol_dog` (difference of Gaussians, centred on `0.5`),
`vol_local_std`, `vol_unsharp`.

```@example vol
viewer(["volume" => vol, "vol_gaussian_s1" => call(iv(:vol_gaussian_s1), vol),
        "vol_gradient" => call(iv(:vol_gradient), vol), "vol_dog" => call(iv(:vol_dog), vol),
        "vol_local_std" => call(iv(:vol_local_std), vol), "vol_unsharp" => call(iv(:vol_unsharp), vol)]) # hide
```

### Intensity transforms

CT values are usually *windowed*: `vol_window(vol, level, width)` maps
`[level − width/2, level + width/2]` to `[0, 1]`, highlighting one tissue.
Also `vol_normalize`, `vol_robust_normalize` (2nd–98th percentile),
`vol_equalize`, `vol_gamma` (exponent `2^(4p−2)`), `vol_invert`,
`vol_threshold_zero`.

```@example vol
viewer(["volume" => vol, "vol_window(·, 0.6, 0.15)" => call(iv(:vol_window), vol, 0.6, 0.15),
        "vol_window(·, 0.25, 0.2)" => call(iv(:vol_window), vol, 0.25, 0.2),
        "vol_robust_normalize" => call(iv(:vol_robust_normalize), vol),
        "vol_equalize" => call(iv(:vol_equalize), vol), "vol_gamma(·, 0.8)" => call(iv(:vol_gamma), vol, 0.8)]) # hide
```

The first window isolates the organ, nodule and vessel; the second shows the
soft tissue.

### Grey morphology

With a `(2r+1)³` cube, `r = 1 + round(2p)`: `vol_erode`, `vol_dilate`,
`vol_open`, `vol_close`, `vol_morph_gradient`, `vol_tophat` (small bright
structures: the vessel and the nodule stand out), `vol_bothat` (small dark
structures: the cavity); `vol_erode_cross` and `vol_dilate_cross` use the
6-neighbour cross.

```@example vol
viewer(["volume" => vol, "vol_erode" => call(iv(:vol_erode), vol), "vol_dilate" => call(iv(:vol_dilate), vol),
        "vol_open" => call(iv(:vol_open), vol), "vol_tophat" => call(iv(:vol_tophat), vol),
        "vol_bothat" => call(iv(:vol_bothat), vol)]) # hide
```

### Two volumes and masks

`vol_add`, `vol_sub`, `vol_absdiff`, `vol_mult`, `vol_min`, `vol_max`,
`vol_average` combine two volumes; `vol_mask_keep(vol, mask)` and
`vol_mask_zero(vol, mask)` apply a mask; `vol_distance_inside(mask)` and
`vol_proximity(mask)` turn a mask into a distance map.

```@example vol
viewer(["mask" => mask, "vol_mask_keep(vol, mask)" => call(iv(:vol_mask_keep), vol, mask),
        "vol_distance_inside" => call(iv(:vol_distance_inside), mask),
        "vol_proximity" => call(iv(:vol_proximity), mask)]) # hide
```

## 3D → 3D: masks

Binarisation of an intensity volume: `vol_threshold(vol, t)`, `vol_otsu`,
`vol_top_fraction(vol, p)`. Clean-up: `vol_fill_holes`, `vol_holes` (the
enclosed cavities), `vol_largest_component`, `vol_central_component`,
`vol_remove_small(p)`, `vol_clear_border`, `vol_majority` (3³ vote),
`vol_bbox_fill`; binary morphology (`vol_erode`, `vol_dilate`, `vol_open`,
`vol_close`, `vol_morph_gradient` = a shell around the boundary); logic
(`vol_and`, `vol_or`, `vol_xor`, `vol_not`).

```@example vol
viewer(["mask" => mask, "vol_fill_holes" => call(bv(:vol_fill_holes), mask), "vol_holes" => call(bv(:vol_holes), mask),
        "vol_largest_component" => call(bv(:vol_largest_component), mask),
        "vol_top_fraction(vol, 0.02)" => call(bv(:vol_top_fraction), vol, 0.02),
        "vol_morph_gradient" => call(bv(:vol_morph_gradient), mask)]) # hide
```

## 3D → 3D: geometry and 2D → 3D

Shared by both bundles: `vol_flip_x/y/z`, `vol_rot90_xy/xz/yz` (identity when
the plane is not square), `vol_shift_x/y/z(vol, s)`,
`vol_crop_bbox[_largest](vol, mask[, margin])` (crop to the mask's box and
resize back: a 3D zoom), `vol_recenter[_largest](vol, mask)`.

```@example vol
nodule_mask = call(bv(:vol_threshold), vol, 0.85) # hide
viewer(["volume" => vol, "vol_rot90_xy" => call(iv(:vol_rot90_xy), vol),
        "vol_shift_z(·, 0.7)" => call(iv(:vol_shift_z), vol, 0.7),
        "vol_crop_bbox(vol, nodule)" => call(iv(:vol_crop_bbox), vol, nodule_mask, 0.5),
        "vol_recenter(vol, nodule)" => call(iv(:vol_recenter), vol, nodule_mask)]) # hide
```

`vol_extrude_x/y/z(img2d)` repeats a 2D image through the volume, and
`vol_mask2d_x/y/z(vol, mask2d)` applies a 2D mask to every slice. Below, the
nodule's silhouette along `z` (`proj_any_z`, a 2D mask) is pushed back into
the volume: everything outside the nodule's column is removed.

```@example vol
silhouette = call(to2b(:proj_any_z), nodule_mask) # hide
viewer(["volume" => vol, "vol_extrude_z(silhouette)" => call(bv(:vol_extrude_z), silhouette),
        "vol_mask2d_z(vol, silhouette)" => call(iv(:vol_mask2d_z), vol, silhouette)]) # hide
```

## 3D → 2D: projections and slices

For each axis `a ∈ {x, y, z}`: `proj_max_a` (maximum intensity projection,
MIP), `proj_min_a`, `proj_mean_a`, `proj_std_a`, `proj_argmax_a` (depth of the
maximum, `0` to `1`); masked `proj_max_masked_a(vol, mask)` and
`proj_mean_masked_a`; slices `slice_center_a`, `slice_at_a(vol, s)`,
`slice_brightest_a`, `slice_centroid_a(vol, mask)`, `slice_largest_a(vol,
mask)`. The binary bundle gives `proj_any_a` (silhouette), `proj_all_a`,
`slice_center_a`, `slice_at_a`, `slice_largest_a`.

```@setup vol
rows2d = [
    ("proj_max", (f) -> call(f, vol)), ("proj_mean", (f) -> call(f, vol)), ("proj_std", (f) -> call(f, vol)),
    ("proj_argmax", (f) -> call(f, vol)), ("slice_center", (f) -> call(f, vol)),
    ("slice_brightest", (f) -> call(f, vol)), ("slice_largest", (f) -> call(f, vol, mask)),
    ("proj_max_masked", (f) -> call(f, vol, mask)),
]
for (stem, apply) in rows2d, letter in ("z", "y", "x")
    g_save(assets, "$(stem)_$(letter).png", g_up(g_canvas(apply(to2(Symbol(stem, "_", letter)))), 4))
end
for stem in ("proj_any", "proj_all", "slice_largest"), letter in ("z", "y", "x")
    g_save(assets, "$(stem)_bin_$(letter).png", g_up(g_canvas(call(to2b(Symbol(stem, "_", letter)), mask)), 4))
end
```

| Operator | `_z` (y, x) | `_y` (x, z) | `_x` (y, z) |
|:--|:--:|:--:|:--:|
| `proj_max` | ![](../assets/fns/volumes/proj_max_z.png) | ![](../assets/fns/volumes/proj_max_y.png) | ![](../assets/fns/volumes/proj_max_x.png) |
| `proj_mean` | ![](../assets/fns/volumes/proj_mean_z.png) | ![](../assets/fns/volumes/proj_mean_y.png) | ![](../assets/fns/volumes/proj_mean_x.png) |
| `proj_std` | ![](../assets/fns/volumes/proj_std_z.png) | ![](../assets/fns/volumes/proj_std_y.png) | ![](../assets/fns/volumes/proj_std_x.png) |
| `proj_argmax` | ![](../assets/fns/volumes/proj_argmax_z.png) | ![](../assets/fns/volumes/proj_argmax_y.png) | ![](../assets/fns/volumes/proj_argmax_x.png) |
| `slice_center` | ![](../assets/fns/volumes/slice_center_z.png) | ![](../assets/fns/volumes/slice_center_y.png) | ![](../assets/fns/volumes/slice_center_x.png) |
| `slice_brightest` | ![](../assets/fns/volumes/slice_brightest_z.png) | ![](../assets/fns/volumes/slice_brightest_y.png) | ![](../assets/fns/volumes/slice_brightest_x.png) |
| `slice_largest(vol, mask)` | ![](../assets/fns/volumes/slice_largest_z.png) | ![](../assets/fns/volumes/slice_largest_y.png) | ![](../assets/fns/volumes/slice_largest_x.png) |
| `proj_max_masked(vol, mask)` | ![](../assets/fns/volumes/proj_max_masked_z.png) | ![](../assets/fns/volumes/proj_max_masked_y.png) | ![](../assets/fns/volumes/proj_max_masked_x.png) |
| `proj_any(mask)` | ![](../assets/fns/volumes/proj_any_bin_z.png) | ![](../assets/fns/volumes/proj_any_bin_y.png) | ![](../assets/fns/volumes/proj_any_bin_x.png) |
| `proj_all(mask)` | ![](../assets/fns/volumes/proj_all_bin_z.png) | ![](../assets/fns/volumes/proj_all_bin_y.png) | ![](../assets/fns/volumes/proj_all_bin_x.png) |
| `slice_largest(mask)` | ![](../assets/fns/volumes/slice_largest_bin_z.png) | ![](../assets/fns/volumes/slice_largest_bin_y.png) | ![](../assets/fns/volumes/slice_largest_bin_x.png) |

The MIP shows the nodule and the vessel through everything else;
`slice_brightest` cuts through the nodule; `proj_argmax` encodes depth (dark
= near the start of the axis).

## 3D → scalar

`bundle_number_intensityStatsFromImg` (quantiles, moments, entropy, Otsu…,
with ROI, outside and inside − outside forms) takes volumes as well as 2D
images. The volume bundles add:

| Bundle | Operators |
|:--|:--|
| `bundle_number_volumeShapeFromImg` | `vshape_fill`, `vshape_sphericity` (`π^(1/3)(6V)^(2/3)/A`, voxel-face surface: a voxelised ball scores about 0.65), `vshape_elongation`, `vshape_flatness` (principal axes), `vshape_extent`, `vshape_components`, `vshape_largest_fraction`, `vshape_cavities`, `vshape_cavity_fraction`, `vshape_centroid_x/y/z`; per component `vobjs_<volume\|sphericity\|elongation\|extent>_<mean\|std\|min\|max\|median\|cv>` |
| `bundle_number_volumeGranulometryFromImg` | `vgran_open_r1…r4` and `vgran_open_bg_r1…r4` (exact ball openings), `vgran_thickness_mean/max`, `vgran_grey_open_r1/r2`, `vgran_grey_close_r1/r2` |
| `bundle_number_volumeProfileFromImg` | radial shells `vprof_shell_inner/middle/outer`, `vprof_center_contrast` (around the centre or a mask's centroid), slabs `vprof_slab_<a>_low/mid/high`, mirror symmetry `vprof_symmetry_<a>`, `vprof_com_<a>`, `vprof_spread_<a>` |

Three phantom classes — with a nodule, without one, and with an elongated
organ and no vessel — and how a few descriptors separate them:

```@setup vol
classes = [
    "nodule" => g_intensity(phantom()),
    "no nodule" => g_intensity(phantom(nodule = false)),
    "elongated organ" => g_intensity(phantom(nodule = false, organ = (4.0, 4.0, 11.0), vessel = false, cavity = false)),
]
```

```@example vol
viewer(classes) # hide
```

```@example vol
ST = UTCGP.number_intensityStatsFromImg
V = UTCGP.number_volumeFromImg
features = [
    ("stat_q95(vol)", v -> ST.stat_q95(v)),
    ("stat_frac_above(vol, 0.85)", v -> ST.stat_frac_above(v, 0.85)),
    ("vshape_components(vol, 0.5)", v -> V.vshape_components(v, 0.5)),
    ("vshape_cavities(vol, 0.5)", v -> V.vshape_cavities(v, 0.5)),
    ("vshape_elongation(vol, 0.5)", v -> V.vshape_elongation(v, 0.5)),
    ("vobjs_volume_max(vol, 0.5)", v -> V.vobjs_volume_max(v, 0.5)),
    ("vgran_open_r2(vol, 0.5)", v -> V.vgran_open_r2(v, 0.5)),
    ("vprof_center_contrast(vol)", v -> V.vprof_center_contrast(v)),
    ("vprof_symmetry_x(vol)", v -> V.vprof_symmetry_x(v)),
]
println(rpad("", 30), join(rpad.(first.(classes), 18)))
for (name, f) in features
    println(rpad(name, 30), join(rpad.(string.(round.([f(v) for (_, v) in classes], digits = 3)), 18)))
end
```

## Performance

On a 28³ volume, while the machine was also running other heavy jobs (so
these are upper bounds): projections, slices, flips, shifts, masking and
most scalar descriptors run in tens of microseconds (median over all 3D
operators ≈ 75 µs); filters and grey morphology 0.1–0.45 ms; distance maps
and the larger openings 0.3–0.75 ms. Shifts along `x` and `z` are processed
as long contiguous loops, labelling works on runs, and temporaries are
reused per task.

## Bundles

```@docs
UTCGP.image3D_volume_common
UTCGP.image3D_volume_basic
UTCGP.image3D_volume_basic.bundle_image3DIntensity_volume_basic_factory
UTCGP.image3D_volume_basic.bundle_image3DBinary_volume_basic_factory
UTCGP.image3D_volume
UTCGP.image3D_volume.bundle_image3DIntensity_volume_factory
UTCGP.image3D_volume.bundle_image3DBinary_volume_factory
UTCGP.image3D_to_image2D
UTCGP.image3D_to_image2D.bundle_image2DIntensity_fromVolume_factory
UTCGP.image3D_to_image2D.bundle_image2DBinary_fromVolume_factory
UTCGP.number_volumeFromImg
UTCGP.number_volumeFromImg.bundle_number_volumeShapeFromImg
UTCGP.number_volumeFromImg.bundle_number_volumeGranulometryFromImg
UTCGP.number_volumeFromImg.bundle_number_volumeProfileFromImg
```
