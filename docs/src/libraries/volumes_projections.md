```@meta
CurrentModule = UTCGP
```

# 3D Volumes: Projections and Descriptors

From a volume to 2D images (projections and slices, after which every 2D
library applies) and to numbers (the features a classifier reads). The
example phantom and the slice viewers are those of [3D Volumes: CT, MRI and
Microscopy](@ref): drag a row's slider to move through the slices.

```@setup vol
using UTCGP
include(joinpath(dirname(pathof(UTCGP)), "..", "docs", "volume_gallery.jl"))
nodule_mask = call(bv(:vol_threshold), vol, 0.85)
```

```@example vol
viewer(["volume" => vol, "mask = vol ≥ 0.5" => mask, "nodule = vol ≥ 0.85" => nodule_mask]) # hide
```

## 3D → 2D: projections and slices

Each operator exists for the three axes (`_z`, `_y`, `_x`) and returns a 2D
image: a `_z` result is `(y, x)`, a `_y` result `(x, z)`, a `_x` result
`(y, z)`.

| Operator | What it returns |
|:--|:--|
| `proj_max_<a>` | For each line along the axis, its brightest voxel (maximum intensity projection, MIP): bright structures show through everything. |
| `proj_min_<a>` | The darkest voxel of each line. |
| `proj_mean_<a>` | The mean of each line: like an X-ray. |
| `proj_std_<a>` | Twice the standard deviation of each line: how much the line varies. |
| `proj_argmax_<a>` | *Where* along the line the brightest voxel is, `0` (first slice) to `1` (last): a depth map. |
| `proj_max_masked_<a>(vol, mask)`, `proj_mean_masked_<a>(vol, mask)` | Max / mean over the voxels inside the mask only (`0` where a line has none). |
| `slice_center_<a>` | The middle slice. |
| `slice_at_<a>(vol, s)` | The slice at position `s` (`0` first, `1` last). |
| `slice_brightest_<a>` | The slice through the brightest voxel. |
| `slice_centroid_<a>(vol, mask)` | The slice through the mask's centre of mass. |
| `slice_largest_<a>(vol, mask)` | The slice where the mask has the most voxels. |

The binary bundle returns 2D masks: `proj_any_<a>` (set where any voxel of
the line is set: the silhouette), `proj_all_<a>` (set where all are),
`slice_center_<a>`, `slice_at_<a>(mask, s)` and `slice_largest_<a>`.
Intensity volumes are thresholded at `0.5`, or with `proj_any_<a>(vol, t)` at
`t`.

```@setup vol
rows2d = [
    ("proj_max", (f) -> call(f, vol)), ("proj_min", (f) -> call(f, vol)), ("proj_mean", (f) -> call(f, vol)),
    ("proj_std", (f) -> call(f, vol)), ("proj_argmax", (f) -> call(f, vol)),
    ("proj_max_masked", (f) -> call(f, vol, mask)), ("proj_mean_masked", (f) -> call(f, vol, mask)),
    ("slice_center", (f) -> call(f, vol)), ("slice_brightest", (f) -> call(f, vol)),
    ("slice_centroid", (f) -> call(f, vol, nodule_mask)), ("slice_largest", (f) -> call(f, vol, mask)),
]
for (stem, apply) in rows2d, letter_ in ("z", "y", "x")
    g_save(assets, "$(stem)_$(letter_).png", g_up(g_canvas(apply(to2(Symbol(stem, "_", letter_)))), 4))
end
for s in (0.0, 0.25, 0.5, 0.75, 1.0)
    g_save(assets, "slice_at_z_$(g_tag(s)).png", g_up(g_canvas(call(to2(:slice_at_z), vol, s)), 4))
end
for stem in ("proj_any", "proj_all", "slice_center", "slice_largest"), letter_ in ("z", "y", "x")
    g_save(assets, "$(stem)_bin_$(letter_).png", g_up(g_canvas(call(to2b(Symbol(stem, "_", letter_)), mask)), 4))
end
for t in (0.2, 0.5, 0.85)
    g_save(assets, "proj_any_z_t$(g_tag(t)).png", g_up(g_canvas(call(to2b(:proj_any_z), vol, t)), 4))
end
for s in (0.25, 0.5, 0.75)
    g_save(assets, "slice_at_bin_z_$(g_tag(s)).png", g_up(g_canvas(call(to2b(:slice_at_z), mask, s)), 4))
end
```

| Operator | `_z` (y, x) | `_y` (x, z) | `_x` (y, z) |
|:--|:--:|:--:|:--:|
| `proj_max` | ![](../assets/fns/volumes/proj_max_z.png) | ![](../assets/fns/volumes/proj_max_y.png) | ![](../assets/fns/volumes/proj_max_x.png) |
| `proj_min` | ![](../assets/fns/volumes/proj_min_z.png) | ![](../assets/fns/volumes/proj_min_y.png) | ![](../assets/fns/volumes/proj_min_x.png) |
| `proj_mean` | ![](../assets/fns/volumes/proj_mean_z.png) | ![](../assets/fns/volumes/proj_mean_y.png) | ![](../assets/fns/volumes/proj_mean_x.png) |
| `proj_std` | ![](../assets/fns/volumes/proj_std_z.png) | ![](../assets/fns/volumes/proj_std_y.png) | ![](../assets/fns/volumes/proj_std_x.png) |
| `proj_argmax` | ![](../assets/fns/volumes/proj_argmax_z.png) | ![](../assets/fns/volumes/proj_argmax_y.png) | ![](../assets/fns/volumes/proj_argmax_x.png) |
| `proj_max_masked(vol, mask)` | ![](../assets/fns/volumes/proj_max_masked_z.png) | ![](../assets/fns/volumes/proj_max_masked_y.png) | ![](../assets/fns/volumes/proj_max_masked_x.png) |
| `proj_mean_masked(vol, mask)` | ![](../assets/fns/volumes/proj_mean_masked_z.png) | ![](../assets/fns/volumes/proj_mean_masked_y.png) | ![](../assets/fns/volumes/proj_mean_masked_x.png) |
| `slice_center` | ![](../assets/fns/volumes/slice_center_z.png) | ![](../assets/fns/volumes/slice_center_y.png) | ![](../assets/fns/volumes/slice_center_x.png) |
| `slice_brightest` | ![](../assets/fns/volumes/slice_brightest_z.png) | ![](../assets/fns/volumes/slice_brightest_y.png) | ![](../assets/fns/volumes/slice_brightest_x.png) |
| `slice_centroid(vol, nodule)` | ![](../assets/fns/volumes/slice_centroid_z.png) | ![](../assets/fns/volumes/slice_centroid_y.png) | ![](../assets/fns/volumes/slice_centroid_x.png) |
| `slice_largest(vol, mask)` | ![](../assets/fns/volumes/slice_largest_z.png) | ![](../assets/fns/volumes/slice_largest_y.png) | ![](../assets/fns/volumes/slice_largest_x.png) |
| binary `proj_any(mask)` | ![](../assets/fns/volumes/proj_any_bin_z.png) | ![](../assets/fns/volumes/proj_any_bin_y.png) | ![](../assets/fns/volumes/proj_any_bin_x.png) |
| binary `proj_all(mask)` | ![](../assets/fns/volumes/proj_all_bin_z.png) | ![](../assets/fns/volumes/proj_all_bin_y.png) | ![](../assets/fns/volumes/proj_all_bin_x.png) |
| binary `slice_center(mask)` | ![](../assets/fns/volumes/slice_center_bin_z.png) | ![](../assets/fns/volumes/slice_center_bin_y.png) | ![](../assets/fns/volumes/slice_center_bin_x.png) |
| binary `slice_largest(mask)` | ![](../assets/fns/volumes/slice_largest_bin_z.png) | ![](../assets/fns/volumes/slice_largest_bin_y.png) | ![](../assets/fns/volumes/slice_largest_bin_x.png) |

The MIP shows the nodule and the vessel through everything else;
`proj_min` is uniformly dark, because every line starts and ends in air; `slice_brightest` cuts
through the nodule; `proj_argmax` is a depth map (dark = near the first
slice). `proj_all` is empty: no line crosses the mask from end to end.

Effect of the position `s` on `slice_at_z(vol, s)`:

| `s = 0` | `0.25` | `0.5` | `0.75` | `1` |
|:--:|:--:|:--:|:--:|:--:|
| ![](../assets/fns/volumes/slice_at_z_00.png) | ![](../assets/fns/volumes/slice_at_z_025.png) | ![](../assets/fns/volumes/slice_at_z_05.png) | ![](../assets/fns/volumes/slice_at_z_075.png) | ![](../assets/fns/volumes/slice_at_z_10.png) |

Effect of the threshold on `proj_any_z(vol, t)`, and binary
`slice_at_z(mask, s)`:

| `proj_any_z(vol, 0.2)`: the body | `t = 0.5`: organ, nodule, vessel | `t = 0.85`: the nodule | `slice_at_z(mask, 0.25)` | `(mask, 0.5)` | `(mask, 0.75)` |
|:--:|:--:|:--:|:--:|:--:|:--:|
| ![](../assets/fns/volumes/proj_any_z_t02.png) | ![](../assets/fns/volumes/proj_any_z_t05.png) | ![](../assets/fns/volumes/proj_any_z_t085.png) | ![](../assets/fns/volumes/slice_at_bin_z_025.png) | ![](../assets/fns/volumes/slice_at_bin_z_05.png) | ![](../assets/fns/volumes/slice_at_bin_z_075.png) |

## 3D → scalar

These return one number per volume, the features a classifier reads.
`bundle_number_intensityStatsFromImg` (quantiles, moments, entropy, Otsu…,
see the descriptors page) takes volumes as well as 2D images, with the same
ROI, outside and inside − outside forms. The volume bundles add the
following. Mask operators take `(mask)`, `(vol)` (thresholded at `0.5`),
`(vol, t)` or `(mask, roi)`.

**Shape of the whole mask** (`bundle_number_volumeShapeFromImg`):

| Operator | What it measures |
|:--|:--|
| `vshape_fill` | Fraction of the volume's voxels that are set. |
| `vshape_sphericity` | How ball-like the mask is: surface of a ball of the same volume over the actual surface (counted as exposed voxel faces). A voxelised ball scores about `0.65`, anything less compact lower: compare values with each other. |
| `vshape_elongation` | `1 − sqrt(λ2/λ1)` of the principal axes: `0` when the two longest axes are equal, towards `1` for a needle. |
| `vshape_flatness` | `1 − sqrt(λ3/λ2)`: towards `1` for a plate. |
| `vshape_extent` | Set voxels over the voxels of the bounding box: `1` for a box, about `0.52` for a ball. |
| `vshape_components` | Number of separate objects. |
| `vshape_largest_fraction` | Share of the set voxels in the largest object. |
| `vshape_cavities`, `vshape_cavity_fraction` | Number of enclosed cavities, and cavity voxels over (set + cavity) voxels. |
| `vshape_centroid_y`, `vshape_centroid_x`, `vshape_centroid_z` | Position of the centre of mass, `0` to `1` along each axis. |
| `vobjs_<d>_<a>` | A descriptor `d` ∈ {`volume` (share of the voxels), `sphericity`, `elongation`, `extent`} of every object, aggregated with `a` ∈ {`mean`, `std`, `min`, `max`, `median`, `cv` (std / mean)}. E.g. `vobjs_volume_max` = the largest object's share. |

**Size distribution** (`bundle_number_volumeGranulometryFromImg`):

| Operator | What it measures |
|:--|:--|
| `vgran_open_r1` … `vgran_open_r4` | Fraction of the mask that survives an *opening* by a ball of radius 1–4: the parts a ball of that size can reach while staying inside. High = thick structures, low = thin ones. |
| `vgran_open_bg_r1` … `vgran_open_bg_r4` | The same for the background: low when the background is made of narrow gaps. |
| `vgran_thickness_mean`, `vgran_thickness_max` | Mean and largest distance from a set voxel to the background, over half the shortest side. |
| `vgran_grey_open_r1`, `vgran_grey_open_r2` | Intensity version: share of the total brightness surviving a grey opening by a 3³ (5³) cube. Low when the brightness is in fine structures. |
| `vgran_grey_close_r1`, `vgran_grey_close_r2` | Share of the total darkness surviving a grey closing: low when the dark parts are fine. |

**Where the intensity is** (`bundle_number_volumeProfileFromImg`, intensity
volumes):

| Operator | What it measures |
|:--|:--|
| `vprof_shell_inner`, `vprof_shell_middle`, `vprof_shell_outer` | Mean intensity in the inner, middle and outer third of the distance from the centre (or from a mask's centroid with `(vol, mask)`). |
| `vprof_center_contrast` | Inner minus outer shell: positive when the centre is brighter than the periphery. |
| `vprof_slab_<a>_low`, `_mid`, `_high` | Mean intensity in the first, middle and last third along axis `a` (e.g. top, middle, bottom for `a = y`). |
| `vprof_symmetry_<a>` | `1 − mean abs(v − mirror(v))` with the mirror across the middle of `a`: `1` = perfectly symmetric. |
| `vprof_com_<a>`, `vprof_spread_<a>` | Intensity-weighted centre (`0` to `1`) and spread along `a`. |

Three phantom classes — with a nodule, without one, and with an elongated
organ and no vessel:

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

Every scalar operator of the three volume bundles on the three classes (mask
operators get the volume, thresholded at `0.5`), plus a few intensity
statistics. Rows that differ between the classes are the useful features.
Note that "nodule" and "no nodule" have the same mask descriptors: the
nodule lies inside the organ, so thresholding at `0.5` merges it with the
organ. Only the intensity features see it (`stat_frac_above(·, 0.85)`,
`vprof_shell_inner`, `vgran_grey_open_*`); a mask at `0.85` would separate
it.

```@example vol
ST = UTCGP.number_intensityStatsFromImg
println(rpad("", 30), join(rpad.(first.(classes), 18)))
for (name, f) in (("stat_q95", ST.stat_q95), ("stat_frac_above(·, 0.85)", v -> ST.stat_frac_above(v, 0.85)),
                  ("stat_entropy", ST.stat_entropy))
    println(rpad(name, 30), join(rpad.(string.(round.([f(v) for (_, v) in classes], digits = 3)), 18)))
end
for bundle in (bundle_number_volumeShapeFromImg, bundle_number_volumeGranulometryFromImg, bundle_number_volumeProfileFromImg)
    for w in bundle
        values = [w.fn(v) for (_, v) in classes]
        println(rpad(w.name, 30), join(rpad.(string.(round.(values, digits = 3)), 18)))
    end
end
```

## Bundles

```@docs
UTCGP.image3D_to_image2D
UTCGP.image3D_to_image2D.bundle_image2DIntensity_fromVolume_factory
UTCGP.image3D_to_image2D.bundle_image2DBinary_fromVolume_factory
UTCGP.number_volumeFromImg
UTCGP.number_volumeFromImg.bundle_number_volumeShapeFromImg
UTCGP.number_volumeFromImg.bundle_number_volumeGranulometryFromImg
UTCGP.number_volumeFromImg.bundle_number_volumeProfileFromImg
```
