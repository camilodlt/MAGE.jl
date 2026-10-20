```@meta
CurrentModule = UTCGP
```

# Image-to-scalar inputs and inference

Choose operators by their spatial meaning as well as their return type. A
volume is not a stack of unrelated 2D images, and a colour channel is not a
spatial coordinate.

## Which bundles belong in a library

| Family | Inputs | Meaning |
|:--|:--|:--|
| `bundle_number_reduceFromImg` | Any dimension; accepted pixel kinds vary by operator | Stored sample count, axis sizes, histogram and whole-array statistics |
| `bundle_number_intensityStatsFromImg` | Intensity arrays: 2D, RGB or volumes | All 51 intensity statistics, including inside/outside/difference forms |
| `bundle_number_similarityNDFromImg` | Intensity or binary arrays of equal size | MSE, MAE, correlation, histograms and foreground overlap |
| `bundle_number_similarity2DFromImg` | 2D intensity or binary | Block SSIM, chamfer distance and x/y profile shifts |
| Coordinate bundles | 2D or 3D intensity/binary | Row/column of the maximal sample (maximum channel for RGB) |
| Region and Haar bundles | 2D; pixel kinds vary | Planar windows and their locations |
| Orientation and GLCM | 2D intensity; GLCM also accepts labels | Planar gradients and directional co-occurrences |
| Image graph | 2D binary | Graph from planar component centroids and Delaunay triangles |
| Locate, object, shape and granulometry bundles | 2D intensity or binary | Planar components, Hu moments, morphology and geometry |
| Template matching | 2D intensity or binary | A planar window searched in another image |
| Volume shape, granulometry and profile bundles | 3D intensity or binary; profiles require intensity | Voxel geometry, volumetric morphology and spatial depth |

The original `bundle_number_similarityFromImg` remains a compatibility
collection containing all 13 operators. Use the separate ND and 2D bundles
when assembling a new library. No operator has been deleted or renamed.

```@docs
bundle_number_similarityNDFromImg
bundle_number_similarity2DFromImg
```

[`get_image_scalar_bundles`](@ref) filters individual operators using their methods,
the available concrete input types and the maximum node arity. For example:

```julia
I = typeof(image)
B = typeof(mask)
bundles = get_image_scalar_bundles([I, B, Float64]; domain=:rgb, max_arity=3)
```

Append these extension bundles to a scalar library whose basic bundle already
provides identity and constant operators. This supplies shared statistics and
comparisons, without planar or volumetric geometry. Pass `domain=:volume` for volumetric descriptors, or `:image2D` for
planar features. Existing `get_extension_*_nb()` collections retain their
membership and order for compatibility with saved configurations.

RGB is stored as `H×W×3` intensity samples. A volume of depth three has exactly
the same Julia type. Dispatch cannot distinguish their intended meaning;
the domain argument prevents the selector from treating colour as depth.
Directly adding a volume bundle to an RGB configuration still gives volume
semantics, so choose the appropriate bundle collection.

## ROI selection

Intensity statistics accept:

- A binary or intensity ROI with exactly the source's size parameter `S`.
  Intensity membership is `value ≥ 0.5`.
- For a 3D source, a 2D ROI with the same height and width. It is repeated
  logically over every channel/depth slice without allocating a replicated
  mask. Each selected channel sample or voxel contributes independently.

A full `H×W×3` ROI selects individual channel samples; it is not converted to
a 2D colour mask. A 3D ROI cannot select a 2D source. Masked MSE, MAE and
correlation similarly accept full-size binary masks and spatial 2D masks.

MAGE's framework requires a trailing `args...` on operators. Thus `hasmethod`
can find a unary whole-image method when an invalid second image is supplied.
Such an image is rejected rather than silently ignored as a whole-image call.
Required ROI methods (`stat_x_out`, `stat_x_diff`) share their size parameters
in dispatch. Other unused trailing framework arguments remain supported.

## Channel pooling is not luminance

A mean of an RGB array averages all red, green and blue samples. Histogram,
entropy, quantile and overlap operators use the same sample-wise convention.
Use an RGB-to-intensity operator first when the intended statistic concerns
luminance or another colour feature.

```@setup scalar_contract
using UTCGP, Markdown
include(joinpath(dirname(pathof(UTCGP)), "..", "docs", "gallery_helpers.jl"))
S = UTCGP.number_intensityStatsFromImg
# Left column red, right column blue. Each pixel has channel mean 1/3.
channels = zeros(2, 2, 3)
channels[:, 1, 1] .= 1
channels[:, 2, 3] .= 1
rgb = g_name!(g_intensity(channels), "red/blue RGB")
roi = g_name!(g_binary([true false; true false]), "left-column spatial ROI")
mean_all = g_call(S.stat_mean, rgb)
mean_inside = g_call(S.stat_mean, rgb, roi)
mean_outside = g_call(S.stat_mean_out, rgb, roi)
mean_difference = g_call(S.stat_mean_diff, rgb, roi)
@assert mean_all ≈ 1/3 && mean_inside ≈ 1/3 && mean_outside ≈ 1/3
@assert mean_difference == 0.0
assets = g_assets("scalar_contract")
canvas = [RGB(Float64(rgb.img[r,c,1]), Float64(rgb.img[r,c,2]), Float64(rgb.img[r,c,3])) for r in 1:2,c in 1:2]
g_save(assets, "rgb.png", g_up(canvas, 48))
g_save(assets, "roi.png", g_up(g_canvas(roi), 48))
```

```@example scalar_contract
prefix = g_asset_prefix(library_page=false) # hide
Markdown.parse("| RGB input | 2D ROI (white selects) |\n|:--:|:--:|\n| ![RGB input]($prefix/scalar_contract/rgb.png) | ![spatial ROI]($prefix/scalar_contract/roi.png) |") # hide
```

```@example scalar_contract
(mean=mean_all, inside=mean_inside, outside=mean_outside, difference=mean_difference)
```

The differently coloured regions have equal pooled intensity. This is an
actual call to the registered statistics, not an approximation of a colour
conversion.

## Inference checks

Tests use `@inferred` on the registered functions themselves, before any
library caster runs. They exercise each scalar family and all intensity
statistics with `N0f8`, `N0f16`, `Float32` and `Float64` storage, full-size and
spatial ROIs, and RGB/volume inputs. Factory regressions also check that image
constructors preserve the specialised size and pixel type.

GLCM quantisation bounds every bin explicitly: fixed-point rounding must not
produce `bins + 1`. All-zero inputs occupy the first level. The raw symmetric
co-occurrence counts are retained; this does not introduce probability
normalisation. Non-finite distance/size parameters use their defaults.

The volume principal-axis calculation uses an explicit covariance loop to
avoid capturing a changing count in a boxed comprehension. This preserves
its voxel-width correction and eigenvalue calculation while allowing the
elongation, flatness and centroid operators to infer their scalar results.

## Measured calls

```@example scalar_contract
# Rendering and fixture construction are excluded; see Timing methodology.
g_timings()
```
