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
include(joinpath(dirname(pathof(UTCGP)), "..", "docs", "volume_gallery.jl"))
```

A 28³ phantom (the MedMNIST3D size): a textured body (soft tissue, about
`0.25`) in dark air (`0.02`), an organ (`0.55`) with a dark cavity inside, a
bright nodule (`0.92`) and a vessel (`0.78`) that wanders along `z`. The mask
is `vol ≥ 0.5`: organ, nodule and vessel.

**How to read the viewers.** Each column is one volume; each row cuts all of
them along one axis: the `z` row shows `(y, x)` slices, the `y` row `(x, z)`
slices and the `x` row `(y, z)` slices. **Drag a row's slider** to move
through the slices; it moves every volume of the row together, so a column can
be compared with the input at the same depth. The number next to the axis is
the current slice.

```@example vol
viewer(["volume" => vol, "mask = vol ≥ 0.5" => mask]) # hide
```

## Basic volumes

The basic bundles hold the operators every volume library needs (see
"Basic bundles first" above):

| Operator | Inputs | What it returns |
|:--|:--|:--|
| `vol_identity` | `(vol)` | the input, unchanged |
| `vol_ones` | `()` (anything is ignored) | a volume of ones (intensity `1.0`, or every voxel set) |
| `vol_zeros` | `()` | a volume of zeros (black, or empty mask) |
| `vol_from_mask` | `(mask)` | intensity bundle only: set voxels become `1.0`, the others `0.0` |

```@example vol
viewer(["mask" => mask, "vol_from_mask(mask)" => call(ib(:vol_from_mask), mask),
        "vol_ones()" => call(ib(:vol_ones)), "vol_zeros()" => call(ib(:vol_zeros))]) # hide
```

## 3D → 3D: intensity

All operators below take an intensity volume and return one of the same size.
A number `p` is always clamped to `[0, 1]`; the tables say what it controls.

### Filters

| Operator | What it does | `p` |
|:--|:--|:--|
| `vol_gaussian(vol, p)` | Blurs with a Gaussian of standard deviation `σ = 0.3 + 2.7p` voxels: removes noise and fine texture. | `0` → σ 0.3 (almost nothing), default `0.26` → σ 1, `1` → σ 3 |
| `vol_gaussian_s05`, `vol_gaussian_s1`, `vol_gaussian_s2` | The same with a fixed σ of 0.5, 1 and 2 voxels. | — |
| `vol_mean_3`, `vol_mean_5` | Each voxel becomes the mean of the 3³ (5³) cube around it. | — |
| `vol_gradient` | Strength of the local intensity change (central differences): bright on edges, dark on flat regions. | — |
| `vol_laplacian` | Absolute 6-neighbour Laplacian: bright on spots, thin lines and edges, `0` where the intensity is flat or a linear ramp. | — |
| `vol_dog(vol, p)` | Difference of Gaussians `G(σ) − G(1.6σ)`, `σ = 0.5 + 1.5p`, centred on `0.5`: blobs about σ voxels across become bright (> 0.5), their surroundings dark. | default `0.33` → σ 1 |
| `vol_local_std` | Twice the standard deviation in the 3³ cube: high in textured regions and on edges, `0` where flat. | — |
| `vol_unsharp(vol, p)` | Sharpens: adds back `2p` times the detail removed by a σ = 1 blur. | `0` = unchanged, default `0.5` → amount 1 |

```@example vol
viewer(["volume" => vol, "vol_gaussian" => call(iv(:vol_gaussian), vol),
        "vol_gaussian_s05" => call(iv(:vol_gaussian_s05), vol), "vol_gaussian_s2" => call(iv(:vol_gaussian_s2), vol),
        "vol_mean_3" => call(iv(:vol_mean_3), vol), "vol_mean_5" => call(iv(:vol_mean_5), vol)]) # hide
```

```@example vol
viewer(["volume" => vol, "vol_gradient" => call(iv(:vol_gradient), vol), "vol_laplacian" => call(iv(:vol_laplacian), vol),
        "vol_dog" => call(iv(:vol_dog), vol), "vol_local_std" => call(iv(:vol_local_std), vol),
        "vol_unsharp" => call(iv(:vol_unsharp), vol)]) # hide
```

Effect of `p` on `vol_gaussian`, `vol_dog` and `vol_unsharp`:

```@example vol
viewer(["gaussian p = 0" => call(iv(:vol_gaussian), vol, 0.0), "gaussian p = 0.26" => call(iv(:vol_gaussian), vol, 0.26),
        "gaussian p = 0.6" => call(iv(:vol_gaussian), vol, 0.6), "gaussian p = 1" => call(iv(:vol_gaussian), vol, 1.0)]) # hide
```

```@example vol
viewer(["dog p = 0" => call(iv(:vol_dog), vol, 0.0), "dog p = 0.33" => call(iv(:vol_dog), vol, 0.33),
        "dog p = 1" => call(iv(:vol_dog), vol, 1.0), "unsharp p = 0.25" => call(iv(:vol_unsharp), vol, 0.25),
        "unsharp p = 1" => call(iv(:vol_unsharp), vol, 1.0)]) # hide
```

### Intensity transforms

| Operator | What it does | Parameters |
|:--|:--|:--|
| `vol_window(vol, level, width)` | CT windowing: maps the intensity range `[level − width/2, level + width/2]` to `[0, 1]`; everything below is black, everything above white. Highlights one tissue. | defaults `0.5`, `0.5` |
| `vol_normalize` | Stretches the volume's own `[min, max]` to `[0, 1]`. | — |
| `vol_robust_normalize` | Stretches the 2nd–98th percentile range to `[0, 1]`: a few extreme voxels do not squash the contrast. | — |
| `vol_equalize` | Histogram equalisation: each voxel becomes the share of voxels darker than or as dark as it, spreading contrast evenly. | — |
| `vol_gamma(vol, p)` | Gamma correction with exponent `2^(4p − 2)`: `p < 0.5` brightens the dark range, `p > 0.5` darkens it. | default `0.5` = unchanged |
| `vol_invert` | `1 − v`. | — |
| `vol_threshold_zero(vol, t)` | Keeps voxels `≥ t` with their value and sets the others to `0`. | default `0.5` |

```@example vol
viewer(["volume" => vol, "vol_normalize" => call(iv(:vol_normalize), vol),
        "vol_robust_normalize" => call(iv(:vol_robust_normalize), vol), "vol_equalize" => call(iv(:vol_equalize), vol),
        "vol_invert" => call(iv(:vol_invert), vol), "vol_threshold_zero" => call(iv(:vol_threshold_zero), vol)]) # hide
```

Effect of the window: the level selects which intensities become mid-grey,
the width how many of them are stretched over the full range.

```@example vol
viewer(["level 0.6, width 0.15" => call(iv(:vol_window), vol, 0.6, 0.15),
        "level 0.25, width 0.2" => call(iv(:vol_window), vol, 0.25, 0.2),
        "level 0.25, width 0.6" => call(iv(:vol_window), vol, 0.25, 0.6),
        "level 0.85, width 0.1" => call(iv(:vol_window), vol, 0.85, 0.1)]) # hide
```

The first window shows the organ, nodule and vessel; the second the soft
tissue; the third the same with less contrast; the fourth only the nodule.

```@example vol
viewer(["gamma p = 0" => call(iv(:vol_gamma), vol, 0.0), "gamma p = 0.25" => call(iv(:vol_gamma), vol, 0.25),
        "gamma p = 0.75" => call(iv(:vol_gamma), vol, 0.75), "threshold_zero t = 0.3" => call(iv(:vol_threshold_zero), vol, 0.3),
        "threshold_zero t = 0.8" => call(iv(:vol_threshold_zero), vol, 0.8)]) # hide
```

### Two volumes, voxel by voxel

`vol_add`, `vol_sub`, `vol_absdiff`, `vol_mult`, `vol_min`, `vol_max` and
`vol_average` combine two volumes voxel by voxel (results are clamped to
`[0, 1]`). The second volume `b` is a phantom without the nodule and with a
smaller organ, so `vol_absdiff(a, b)` shows exactly what differs.

```@setup vol
vol_b = g_intensity(phantom(nodule = false, organ = (6.0, 5.0, 6.0)))
```

```@example vol
viewer(["a" => vol, "b" => vol_b, "vol_add" => call(iv(:vol_add), vol, vol_b), "vol_sub" => call(iv(:vol_sub), vol, vol_b),
        "vol_absdiff" => call(iv(:vol_absdiff), vol, vol_b), "vol_mult" => call(iv(:vol_mult), vol, vol_b)]) # hide
```

```@example vol
viewer(["a" => vol, "b" => vol_b, "vol_min" => call(iv(:vol_min), vol, vol_b), "vol_max" => call(iv(:vol_max), vol, vol_b),
        "vol_average" => call(iv(:vol_average), vol, vol_b)]) # hide
```

### Grey morphology

Each voxel is replaced by the minimum (erosion) or maximum (dilation) over a
cube of side `2r + 1` around it, `r = 1 + round(2p)`: `p ≤ 0.25` → 3³,
`0.25 < p < 0.75` → 5³, `p ≥ 0.75` → 7³ (default `p = 0`: 3³).

| Operator | What it does |
|:--|:--|
| `vol_erode(vol, p)` | Minimum over the cube: bright structures shrink, thin bright ones (the vessel) vanish. |
| `vol_dilate(vol, p)` | Maximum: bright structures grow, small dark ones (the cavity) vanish. |
| `vol_open(vol, p)` | Erosion then dilation: removes bright structures smaller than the cube, keeps the rest. |
| `vol_close(vol, p)` | Dilation then erosion: removes dark structures smaller than the cube. |
| `vol_morph_gradient(vol, p)` | Dilation minus erosion: bright on boundaries. |
| `vol_tophat(vol, p)` | Volume minus its opening: only the small bright structures (vessel, nodule). |
| `vol_bothat(vol, p)` | Closing minus volume: only the small dark structures (the cavity). |
| `vol_erode_cross`, `vol_dilate_cross` | Minimum / maximum over the voxel and its 6 face neighbours only (a gentler 3D cross). |

```@example vol
viewer(["volume" => vol, "vol_erode" => call(iv(:vol_erode), vol), "vol_dilate" => call(iv(:vol_dilate), vol),
        "vol_open" => call(iv(:vol_open), vol), "vol_close" => call(iv(:vol_close), vol),
        "vol_morph_gradient" => call(iv(:vol_morph_gradient), vol)]) # hide
```

```@example vol
viewer(["volume" => vol, "vol_tophat" => call(iv(:vol_tophat), vol), "vol_bothat" => call(iv(:vol_bothat), vol),
        "vol_erode_cross" => call(iv(:vol_erode_cross), vol), "vol_dilate_cross" => call(iv(:vol_dilate_cross), vol)]) # hide
```

Effect of `p` (cube size) on `vol_dilate` and `vol_tophat`:

```@example vol
viewer(["dilate p = 0 (3³)" => call(iv(:vol_dilate), vol, 0.0), "dilate p = 0.5 (5³)" => call(iv(:vol_dilate), vol, 0.5),
        "dilate p = 1 (7³)" => call(iv(:vol_dilate), vol, 1.0), "tophat p = 0 (3³)" => call(iv(:vol_tophat), vol, 0.0),
        "tophat p = 1 (7³)" => call(iv(:vol_tophat), vol, 1.0)]) # hide
```

### Masks and distance maps

| Operator | What it does |
|:--|:--|
| `vol_mask_keep(vol, mask)` | Keeps the voxels inside the mask, sets the others to `0`. |
| `vol_mask_zero(vol, mask)` | The opposite: sets the voxels inside the mask to `0`. |
| `vol_distance_inside(mask)` | For each voxel of the mask, its distance to the nearest voxel outside, divided by the largest such distance: `1` deep inside thick parts, small near the surface, `0` outside. |
| `vol_proximity(mask)` | `1` on the mask, decreasing with the distance to it (`1 − distance / volume diagonal`): "how close am I to the mask". |

The mask can be binary or an intensity volume (voxels `≥ 0.5` are inside);
`vol_distance_inside(vol, t)` and `vol_proximity(vol, t)` threshold an
intensity volume at `t` first.

```@example vol
viewer(["mask" => mask, "vol_mask_keep(vol, mask)" => call(iv(:vol_mask_keep), vol, mask),
        "vol_mask_zero(vol, mask)" => call(iv(:vol_mask_zero), vol, mask),
        "vol_distance_inside" => call(iv(:vol_distance_inside), mask),
        "vol_proximity" => call(iv(:vol_proximity), mask)]) # hide
```

## 3D → 3D: masks

### Binarisation

| Operator | What it does | Parameter |
|:--|:--|:--|
| `vol_threshold(vol, t)` | Voxels `≥ t`. (A binary input is returned as is.) | default `0.5` |
| `vol_otsu(vol)` | Picks the threshold automatically (Otsu: the level that best splits the voxels into two groups). Here it finds the strongest split, body against air, not the organ. | — |
| `vol_top_fraction(vol, p)` | The brightest fraction `p` of the voxels. | default `0.1` |

```@example vol
viewer(["volume" => vol, "vol_threshold t = 0.2" => call(bv(:vol_threshold), vol, 0.2),
        "vol_threshold t = 0.5" => call(bv(:vol_threshold), vol, 0.5), "vol_threshold t = 0.85" => call(bv(:vol_threshold), vol, 0.85),
        "vol_otsu" => call(bv(:vol_otsu), vol)]) # hide
```

```@example vol
viewer(["top_fraction p = 0.005" => call(bv(:vol_top_fraction), vol, 0.005),
        "top_fraction p = 0.02" => call(bv(:vol_top_fraction), vol, 0.02),
        "top_fraction p = 0.1" => call(bv(:vol_top_fraction), vol, 0.1),
        "top_fraction p = 0.4" => call(bv(:vol_top_fraction), vol, 0.4)]) # hide
```

### Clean-up

The test mask below is the phantom's mask plus problems a real segmentation
has: scattered single voxels (noise) and a slab glued to the volume's border.

```@setup vol
messy = copy(phantom() .>= 0.5)
for k in 1:40
    messy[1 + mod(37k, N), 1 + mod(53k, N), 1 + mod(71k, N)] = true          # isolated voxels
end
messy[20:26, 1:3, 6:20] .= true                                              # slab touching the border
messy_mask = g_binary(messy)
```

| Operator | What it does | Parameter |
|:--|:--|:--|
| `vol_fill_holes` | Fills every enclosed cavity (background not connected to the volume's border): the organ becomes solid. | — |
| `vol_holes` | Only the cavities: what `vol_fill_holes` adds. | — |
| `vol_largest_component` | Keeps the largest connected object (26-connectivity). | — |
| `vol_central_component` | Keeps the object whose centre is closest to the volume's centre. | — |
| `vol_remove_small(mask, p)` | Removes objects smaller than the fraction `p` of all voxels. | default `0.001` (≈ 22 voxels in 28³) |
| `vol_clear_border` | Removes objects touching the volume's border. | — |
| `vol_majority` | 3³ majority vote: a voxel is set when most of its cube is; removes isolated voxels and fills one-voxel pits. | — |
| `vol_bbox_fill` | Replaces each object by its filled bounding box. | — |

```@example vol
viewer(["messy mask" => messy_mask, "vol_fill_holes" => call(bv(:vol_fill_holes), messy_mask),
        "vol_holes" => call(bv(:vol_holes), messy_mask), "vol_largest_component" => call(bv(:vol_largest_component), messy_mask),
        "vol_central_component" => call(bv(:vol_central_component), messy_mask)]) # hide
```

```@example vol
viewer(["messy mask" => messy_mask, "vol_remove_small" => call(bv(:vol_remove_small), messy_mask),
        "vol_clear_border" => call(bv(:vol_clear_border), messy_mask), "vol_majority" => call(bv(:vol_majority), messy_mask),
        "vol_bbox_fill" => call(bv(:vol_bbox_fill), messy_mask)]) # hide
```

Effect of `p` on `vol_remove_small`. The messy mask holds 23 single noise
voxels and three larger objects; their sizes are printed below the viewer.
Each `p` removes the objects under `p · 28³` voxels:

```@example vol
viewer(["p = 0.00004 (< 1 voxel)" => call(bv(:vol_remove_small), messy_mask, 0.00004),
        "p = 0.001 (< 22)" => call(bv(:vol_remove_small), messy_mask, 0.001),
        "p = 0.01 (< 220)" => call(bv(:vol_remove_small), messy_mask, 0.01),
        "p = 0.05 (< 1100)" => call(bv(:vol_remove_small), messy_mask, 0.05)]) # hide
```

```@example vol
t = UTCGP.image3D_volume_common.volume_table(Bool.(reinterpret(messy_mask.img)), identity) # hide
println("object sizes in the messy mask (voxels): ", sort(t.area; rev = true)) # hide
```

### Binary morphology and logic

The binary versions of the morphology operators, with the same cube sizes
(`p` → `3³`, `5³`, `7³`): `vol_erode` (a voxel stays only if its whole cube
is set: objects shrink, thin ones vanish), `vol_dilate` (a voxel becomes set
if any voxel of its cube is: objects grow), `vol_open` (removes specks and
thin bridges), `vol_close` (fills small gaps and dents), `vol_morph_gradient`
(a shell around each object's surface), `vol_erode_cross` and
`vol_dilate_cross` (6-neighbour cross). Logic: `vol_and`, `vol_or`, `vol_xor`
(two masks) and `vol_not`.

```@example vol
viewer(["mask" => mask, "vol_erode" => call(bv(:vol_erode), mask), "vol_dilate" => call(bv(:vol_dilate), mask),
        "vol_open" => call(bv(:vol_open), mask), "vol_close" => call(bv(:vol_close), mask),
        "vol_morph_gradient" => call(bv(:vol_morph_gradient), mask)]) # hide
```

```@example vol
viewer(["vol_erode_cross" => call(bv(:vol_erode_cross), mask), "vol_dilate_cross" => call(bv(:vol_dilate_cross), mask),
        "dilate p = 0.5 (5³)" => call(bv(:vol_dilate), mask, 0.5), "dilate p = 1 (7³)" => call(bv(:vol_dilate), mask, 1.0)]) # hide
```

```@setup vol
mask_b = g_binary(phantom(nodule = false, organ = (6.0, 5.0, 6.0)) .>= 0.5)
```

```@example vol
viewer(["a = mask" => mask, "b" => mask_b, "vol_and(a, b)" => call(bv(:vol_and), mask, mask_b),
        "vol_or(a, b)" => call(bv(:vol_or), mask, mask_b), "vol_xor(a, b)" => call(bv(:vol_xor), mask, mask_b),
        "vol_not(a)" => call(bv(:vol_not), mask)]) # hide
```

## 3D → 3D: geometry (both bundles)

These move voxels around without changing their values, so they exist for
intensity volumes and masks alike.

| Operator | What it does | Parameter |
|:--|:--|:--|
| `vol_flip_y`, `vol_flip_x`, `vol_flip_z` | Mirror along one axis (top ↔ bottom, left ↔ right, first ↔ last slice). | — |
| `vol_rot90_xy`, `vol_rot90_xz`, `vol_rot90_yz` | Quarter turn in one plane (unchanged when that plane is not square). | — |
| `vol_shift_y(vol, u)`, `vol_shift_x`, `vol_shift_z` | Shifts by `(u − 0.5)` of the size along one axis; uncovered voxels are `0`. | `0.5` = no shift, `0.75` = a quarter of the size forward, `0.25` backward |
| `vol_crop_bbox(vol, mask, margin)` | Cuts out the bounding box of the mask (grown by `margin` of its size) and stretches it back to 28³: a 3D zoom on the mask. | default `0.1` |
| `vol_crop_bbox_largest(vol, mask, margin)` | Same, on the mask's largest object only. | default `0.1` |
| `vol_recenter(vol, mask)` | Shifts so the mask's centre of mass lands on the volume's centre. | — |
| `vol_recenter_largest(vol, mask)` | Same, for the mask's largest object. | — |

```@example vol
viewer(["volume" => vol, "vol_flip_y" => call(iv(:vol_flip_y), vol), "vol_flip_x" => call(iv(:vol_flip_x), vol),
        "vol_flip_z" => call(iv(:vol_flip_z), vol), "vol_rot90_xy" => call(iv(:vol_rot90_xy), vol),
        "vol_rot90_xz" => call(iv(:vol_rot90_xz), vol), "vol_rot90_yz" => call(iv(:vol_rot90_yz), vol)]) # hide
```

```@example vol
viewer(["volume" => vol, "vol_shift_y(·, 0.7)" => call(iv(:vol_shift_y), vol, 0.7),
        "vol_shift_x(·, 0.3)" => call(iv(:vol_shift_x), vol, 0.3), "vol_shift_z(·, 0.7)" => call(iv(:vol_shift_z), vol, 0.7),
        "vol_shift_z(·, 0.9)" => call(iv(:vol_shift_z), vol, 0.9)]) # hide
```

The crops and recentring below are driven by the nodule
(`vol_threshold(vol, 0.85)`); the `_largest` versions by the phantom mask,
whose largest object is the organ.

```@setup vol
nodule_mask = call(bv(:vol_threshold), vol, 0.85)
```

```@example vol
viewer(["volume" => vol, "nodule mask" => nodule_mask,
        "crop_bbox(vol, nodule, 0)" => call(iv(:vol_crop_bbox), vol, nodule_mask, 0.0),
        "crop_bbox(vol, nodule, 0.5)" => call(iv(:vol_crop_bbox), vol, nodule_mask, 0.5),
        "crop_bbox(vol, nodule, 1)" => call(iv(:vol_crop_bbox), vol, nodule_mask, 1.0),
        "crop_bbox_largest(vol, mask)" => call(iv(:vol_crop_bbox_largest), vol, mask)]) # hide
```

```@example vol
viewer(["volume" => vol, "vol_recenter(vol, nodule)" => call(iv(:vol_recenter), vol, nodule_mask),
        "vol_recenter_largest(vol, mask)" => call(iv(:vol_recenter_largest), vol, mask),
        "binary: crop_bbox(mask, nodule)" => call(bv(:vol_crop_bbox), mask, nodule_mask, 0.5)]) # hide
```

## 2D → 3D

These operators take a **2D image** and use it on the volume.

- `vol_extrude_z(img2d)` builds a volume whose every `z` slice is the 2D
  image (a `28 × 28` image `(y, x)`): the image is pushed through the volume
  like a cookie cutter, making a prism. `vol_extrude_y` repeats a `(x, z)`
  image along `y`, `vol_extrude_x` a `(y, z)` image along `x`.
- `vol_mask2d_z(vol, mask2d)` keeps, in every `z` slice of the volume, only
  the voxels where the 2D mask is set (binary, or intensity `≥ 0.5`), and
  zeroes the rest. `vol_mask2d_y` and `vol_mask2d_x` do the same along the
  other axes.

The 2D input used here is an "F" shape, so the orientation is easy to follow
(shown below at 6×):

```@setup vol
letter = zeros(N, N)
letter[5:24, 7:10] .= 1.0          # vertical stroke
letter[5:8, 7:22] .= 1.0           # top bar
letter[13:16, 7:18] .= 1.0         # middle bar
letter_img = g_intensity(letter)
letter_mask = g_binary(letter .> 0.5)
save2d("letter_2d.png", letter_img)
disk2d = g_binary([(r - 15)^2 + (c - 17)^2 <= 36 for r in 1:N, c in 1:N])
save2d("disk_2d.png", disk2d)
```

| 2D input `letter` (28 × 28) | 2D mask `disk` (28 × 28) |
|:--:|:--:|
| ![letter](../assets/fns/volumes/letter_2d.png) | ![disk](../assets/fns/volumes/disk_2d.png) |

`vol_extrude_<axis>(letter)`: in the `z` row, every slice of
`vol_extrude_z` is the letter, whatever the slider; the `y` and `x` rows cut
across the extrusion, so they show stripes (the letter seen from the side).
The other two extrusions are the same idea along `y` and `x`: each one shows
the letter in the row of its own axis and stripes in the other two.

```@example vol
viewer(["vol_extrude_z(letter)" => call(iv(:vol_extrude_z), letter_img),
        "vol_extrude_y(letter)" => call(iv(:vol_extrude_y), letter_img),
        "vol_extrude_x(letter)" => call(iv(:vol_extrude_x), letter_img),
        "binary: vol_extrude_z" => call(bv(:vol_extrude_z), letter_mask)]) # hide
```

`vol_mask2d_<axis>(vol, disk)`: along `z`, every slice of the volume is cut
to the disk, so the result is the phantom cut by a cylinder along `z`:

```@example vol
viewer(["volume" => vol, "vol_mask2d_z(vol, disk)" => call(iv(:vol_mask2d_z), vol, disk2d),
        "vol_mask2d_y(vol, disk)" => call(iv(:vol_mask2d_y), vol, disk2d),
        "vol_mask2d_x(vol, disk)" => call(iv(:vol_mask2d_x), vol, disk2d)]) # hide
```

A typical chain: find something on a 2D projection, then push it back into
the volume. Here the nodule's silhouette along `z` (`proj_any_z`, a 2D mask)
removes everything outside the nodule's column:

```@setup vol
silhouette = call(to2b(:proj_any_z), nodule_mask)
save2d("silhouette_2d.png", silhouette)
```

| `proj_any_z(nodule_mask)` (2D) |
|:--:|
| ![silhouette](../assets/fns/volumes/silhouette_2d.png) |

```@example vol
viewer(["volume" => vol, "vol_mask2d_z(vol, silhouette)" => call(iv(:vol_mask2d_z), vol, silhouette)]) # hide
```

## Projections, slices and descriptors

Turning a volume into 2D images (projections, slices) or into numbers
(shape, size distribution, intensity profiles) is on the next page,
[3D Volumes: Projections and Descriptors](@ref).

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
```
