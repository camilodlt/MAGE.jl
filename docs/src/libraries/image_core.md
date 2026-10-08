# Core Image Operators


Every operator of the basic, arithmetic, transcendental, filtering, morphology,
thresholding and segmentation bundles, run on the same inputs. Captions give
the call. Images are shown at 2×.

```@setup core_gallery
using UTCGP
include(joinpath(dirname(pathof(UTCGP)), "..", "docs", "gallery_helpers.jl"))
page = "core_gallery"
cell = g_intensity(Float64.(Gray.(load(joinpath(g_repo_root(), "assets", "000_img.png"))))[1:2:end, 1:2:end])
I = typeof(cell)
B = typeof(g_binary(falses(size(cell)...)))
S = typeof(g_segment(zeros(Int, size(cell)...)))
mask = g_call(bundle_image2DBinary_binarize_factory[:binarize_otsu2D].fn(B), cell)
shifted = g_intensity(circshift(Float64.(reinterpret(cell.img)), (0, 25)))
shifted_mask = g_call(bundle_image2DBinary_binarize_factory[:binarize_otsu2D].fn(B), shifted)
fn(bundle, name, T) = getfield(UTCGP, bundle)[name].fn(T)
"""
One gallery entry per call: `(bundle, name, T, args, caption)`. Files are
named `<tag>_<operator>_<k>.png`, so galleries never overwrite each other.
"""
entries(tag, calls) = [(string(tag, "_", name, "_", k, ".png"), caption, g_call(fn(bundle, name, T), args...))
                       for (k, (bundle, name, T, args, caption)) in enumerate(calls)]
```

## Inputs

```@example core_gallery
g_gallery(page, [("input_cell.png", "`cell` (intensity)", cell), ("input_shifted.png", "`shifted` (cell moved right)", shifted),
                 ("input_mask.png", "`mask` = otsu(cell)", mask), ("input_shifted_mask.png", "`shifted_mask`", shifted_mask)])
```

## Basics and casts

```@example core_gallery
bI, bB, bS = :bundle_image2DIntensity_basic_factory, :bundle_image2DBinary_basic_factory, :bundle_image2DSegment_basic_factory
g_gallery(page, entries("basic", [
    (bI, :identity_image2D, I, (cell,), "`identity_image2D(cell)`"),
    (bI, :ones_2D, I, (cell,), "`ones_2D(cell)`"),
    (bI, :zeros_2D, I, (cell,), "`zeros_2D(cell)`"),
    (bI, :experimental_invert_2D, I, (cell,), "`experimental_invert_2D(cell)`: `1 − v`"),
    (bI, :experimental_normalize_2D, I, (cell,), "`experimental_normalize_2D(cell)`: min→0, max→1"),
    (bI, :experimental_standardize_2D, I, (cell,), "`experimental_standardize_2D(cell)`: `(v − mean)/std`, clamped to [0, 1]"),
    (bI, :experimental_tointensity_image2D, I, (mask,), "`experimental_tointensity_image2D(mask)`"),
    (bB, :experimental_tobinary_image2D, B, (cell,), "`experimental_tobinary_image2D(cell)`: every pixel > 0"),
    (bB, :experimental_tobinary_th_image2D_factory, B, (cell, 0.2), "`experimental_tobinary_th_image2D_factory(cell, 0.2)`: pixels > 0.2"),
    (bB, :experimental_invert_2D, B, (mask,), "`experimental_invert_2D(mask)`"),
    (bS, :experimental_tosegment_image2D, S, (mask,), "`experimental_tosegment_image2D(mask)`: labels 0 and 1 (no splitting into objects)"),
]))
```

## Arithmetic between two images

Intensity results are clamped to `[0, 1]`; on masks, `add` is *or*, `mult`
and `min` are *and*, `max` is *or*, `subtract` is *and not*.

```@example core_gallery
aI, aB = :bundle_image2DIntensity_arithmetic_factory, :bundle_image2DBinary_arithmetic_factory
g_gallery(page, entries("arith", vcat(
    [(aI, n, I, (cell, shifted), "`$(n)(cell, shifted)`") for n in (:add_img2D, :subtract_img2D, :mult_img2D, :max_img2D, :min_img2D)],
    [(aB, n, B, (mask, shifted_mask), "`$(n)(mask, shifted_mask)`") for n in (:add_img2D, :subtract_img2D, :mult_img2D, :max_img2D, :min_img2D)],
)); cols = 5)
```

## Arithmetic with a number, and transcendental maps

```@example core_gallery
sI, tI = :bundle_image2DIntensity_barithmetic_factory, :bundle_image2DIntensity_transcendental_factory
g_gallery(page, entries("scalar", [
    (sI, :badd_image2D, I, (cell, 0.3), "`badd_image2D(cell, 0.3)`"),
    (sI, :bsubtract_image2D, I, (cell, 0.1), "`bsubtract_image2D(cell, 0.1)`"),
    (sI, :bmult_image2D, I, (cell, 3.0), "`bmult_image2D(cell, 3)`"),
    (tI, :exp_image2D, I, (cell,), "`exp_image2D(cell)`"),
    (tI, :log_image2D, I, (cell,), "`log_image2D(cell)`"),
    (tI, :loginv_image2D, I, (cell,), "`loginv_image2D(cell)`"),
    (tI, :powerof_image2D, I, (cell, 0.5), "`powerof_image2D(cell, 0.5)`: brightens"),
    (tI, :powerof_image2D, I, (cell, 2.0), "`powerof_image2D(cell, 2)`: darkens"),
]))
```

## Filtering

All results are rescaled min to max. The `x` / `y` derivatives are signed:
edges getting brighter to the right (`x`) or downwards (`y`) are dark, the
opposite edges bright, flat areas mid-grey. The optional second input of the
gradients, Gaussians and Laplacian is the border mode (`< 0` wrap, `0` repeat
the edge, `> 0` mirror), which only changes the outermost pixels.

```@example core_gallery
fI = :bundle_image2DIntensity_filtering_factory
plain = [w.name for w in bundle_image2DIntensity_filtering_factory if !(w.name in (:dog_image2D, :moffat5_image2D, :moffat13_image2D, :moffat25_image2D))]
g_gallery(page, entries("filter", vcat(
    [(fI, n, I, (cell,), "`$(n)(cell)`") for n in plain],
    [(fI, :dog_image2D, I, (cell, 1.0, 1.0), "`dog_image2D(cell, 1, 1)`"),
     (fI, :dog_image2D, I, (cell, 3.0, 3.0), "`dog_image2D(cell, 3, 3)`"),
     (fI, :moffat5_image2D, I, (cell, 2.0, 1.5), "`moffat5_image2D(cell, 2, 1.5)`"),
     (fI, :moffat25_image2D, I, (cell, 4.0, 1.5), "`moffat25_image2D(cell, 4, 1.5)`")],
)); cols = 6)
```

The binary filtering bundle applies the same filters and rounds the result to
a mask (set above `0.5`), and adds the local extrema:

```@example core_gallery
fB = :bundle_image2DBinary_filtering_factory
g_gallery(page, entries("bfilter", [
    (fB, :sobelm_image2D, B, (cell,), "`sobelm_image2D(cell)` → mask"),
    (fB, :gaussian9_image2D, B, (cell,), "`gaussian9_image2D(cell)` → mask"),
    (fB, :findlocalmaxima_image2D, B, (cell, 5.0, 5.0), "`findlocalmaxima_image2D(cell, 5, 5)`"),
    (fB, :findlocalminima_image2D, B, (cell, 5.0, 5.0), "`findlocalminima_image2D(cell, 5, 5)`"),
]))
```

## Morphology

The parameter `k` is the size of the diamond-shaped structuring element:
rounded, made odd and clamped to `3 … 13` (default `3`). `morphogradient_2D`
takes a third input, the mode: `< 0` Beucher (dilation − erosion), `0`
internal (image − erosion), `> 0` external (dilation − image).

```@example core_gallery
mI, mB = :bundle_image2DIntensity_morph_factory, :bundle_image2DBinary_morph_factory
ops = (:erosion_2D, :dilation_2D, :opening_2D, :closing_2D, :tophat_2D, :bothat_2D, :morphogradient_2D, :morpholaplace_2D)
g_gallery(page, entries("morph", vcat(
    [(mI, n, I, (cell, 5.0), "`$(n)(cell, 5)`") for n in ops],
    [(mB, n, B, (mask, 5.0), "`$(n)(mask, 5)`") for n in ops],
)))
```

Effect of `k` on `erosion_2D(mask, k)`:

```@example core_gallery
g_gallery(page, entries("morphk", [(mB, :erosion_2D, B, (mask, k), "`k = $(Int(k))`") for k in (3.0, 7.0, 13.0)]); cols = 3)
```

## Thresholding

Every method on `cell` with its defaults. Histogram methods (`otsu`, `yen`,
…) take an optional number of histogram bins (`30 … 500`, default `256`);
local methods take a window size and a bias (`adaptive`, `niblack`,
`sauvola`); `binarize_manual2D(img, t)` thresholds at `t` (a float in
`[0, 1]`, or an integer on the `0 … 255` scale), and
`binarize_manual2D(img, other)` at the mean of another image. A constant image
gives an empty mask.

The methods disagree a lot on a dim image like this one (median `0.016`):
`unimodalrosin` keeps 93% of the pixels, `otsu` 11%, `balanced` none. Balanced
histogram thresholding assumes two comparable peaks and fails on such a skewed
histogram, and `binarize_manual2D(cell)` thresholds at `0.5`, above almost
every pixel.

```@example core_gallery
g_gallery(page, entries("thresh", [(:bundle_image2DBinary_binarize_factory, w.name, B, (cell,), "`$(w.name)(cell)`")
                         for w in bundle_image2DBinary_binarize_factory]); cols = 5)
```

## Segmentation

`fastscanning_image2D(img, t)` groups neighbouring pixels whose intensities
differ by less than `t` (default `0.1`): a smaller `t` gives more regions.

`watershed_image2D(mask, [restrict], [h])` gives each object of a mask its own
label and cuts touching objects at their narrowest part. The depth of an
object pixel is its distance to the background; each object is seeded where
its depth is at least `h` times its own maximum (default `h = 0.7`) and
flooded from there. `h = 0` keeps every connected object whole; a higher `h`
splits more. Background stays `0`.

```@example core_gallery
seg = :bundle_image2DSegment_segmentation_factory
disks = g_binary([((r - 20)^2 + (c - 14)^2 <= 81) || ((r - 20)^2 + (c - 28)^2 <= 81) for r in 1:40, c in 1:44])
SD = typeof(g_segment(zeros(Int, 40, 44)))
g_gallery(page, vcat(entries("seg", [
    (seg, :fastscanning_image2D, S, (cell, 0.05), "`fastscanning_image2D(cell, 0.05)`"),
    (seg, :fastscanning_image2D, S, (cell, 0.1), "`fastscanning_image2D(cell, 0.1)`"),
    (seg, :fastscanning_image2D, S, (cell, 0.2), "`fastscanning_image2D(cell, 0.2)`"),
    (seg, :watershed_image2D, S, (mask,), "`watershed_image2D(mask)`"),
]), [("seg_disks.png", "`disks`: two touching disks", disks)], entries("segd", [
    (seg, :watershed_image2D, SD, (disks, 0.0), "`watershed_image2D(disks, 0)`: one object"),
    (seg, :watershed_image2D, SD, (disks, 0.5), "`watershed_image2D(disks, 0.5)`: neck (≈ 0.62) not cut"),
    (seg, :watershed_image2D, SD, (disks, 0.7), "`watershed_image2D(disks, 0.7)`: cut in two"),
])))
```

