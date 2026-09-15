```@meta
CurrentModule = UTCGP
```

# Blob Extraction

Blob extraction turns a saliency map into 8-connected foreground components
and selects components by geometry or source-image statistics. It is useful
after saliency when MAGE needs either a hard mask or an image restricted to one
structure.

The result type is explicit:

- `bundle_image2DBinary_blob_extraction_factory` contains only `*_blob`
  operators returning same-size `BinaryPixel` masks.
- `bundle_image2DIntensity_blob_extraction_factory` contains only operators
  returning the same-size source `IntensityPixel` image masked by a component.

The specialization type fixes output dimensions and pixel storage. Input
saliency storage cannot change that contract. Both bundles are opt-in through
`get_extension_blob_binaryimg()` and `get_extension_blob_intensityimg()`.

## Inputs and parameters

Intensity saliency maps become foreground with `saliency >= threshold`.
Binary masks already define foreground and never take a threshold. Connectivity
includes diagonal neighbors. Score ties select the component whose first pixel
comes first in row-major order. Empty selections return correctly typed zeros.

| Family | Effective signatures |
|:--|:--|
| Geometric binary `*_blob` | `fn(saliency)`, `fn(saliency, threshold)`, `fn(saliency, threshold, min_pixels)`; or `fn(mask)`, `fn(mask, min_pixels)` |
| Geometric masked intensity | `fn(image, saliency)`, `fn(image, saliency, threshold)`; or `fn(image, mask)`, `fn(image, mask, min_pixels)` |
| Statistical binary `*_blob` | `fn(image, saliency)`, `fn(image, saliency, threshold)`; or `fn(image, mask)` |
| Statistical masked intensity | `fn(image, saliency)`, `fn(image, saliency, threshold)`; or `fn(image, mask)` |
| Area interval | `fn(saliency, min_pixels, max_pixels)` at threshold `0.5`, or `fn(mask, min_pixels, max_pixels)` |

`threshold` is finite-clamped to `[0, 1]` and defaults to `0.5`.
Pixel counts are rounded and clamped to `[1, length(mask)]`. Area bounds may
be given in either order and are inclusive. For custom threshold plus two area
bounds, binarize first and use the binary-mask overload; this preserves MAGE's
three-input ceiling.

```@example
using UTCGP
using ImageCore: N0f8

values = zeros(Float64, 8, 10)
values[1:2, 1:2] .= 0.8
values[4:7, 6:9] .= 0.9
saliency = SImageND(IntensityPixel{N0f8}.(values))
binary_prototype = SImageND(BinaryPixel.(falses(size(values))))
largest_blob = bundle_image2DBinary_blob_extraction_factory[
    :blob_extraction_largest_blob
].fn(typeof(binary_prototype))
mask = largest_blob(saliency, 0.5)

(size(mask), eltype(mask), sum(reinterpret(mask.img)))
```

## Operators

| Mask operator | Masked-image operator | Selection |
|:--|:--|:--|
| `blob_extraction_largest_blob` | `blob_extraction_largest` | Greatest area |
| `blob_extraction_smallest_blob` | `blob_extraction_smallest` | Least area after filtering |
| `blob_extraction_longest_horizontally_blob` | `blob_extraction_longest_horizontally` | Greatest bounding-box width |
| `blob_extraction_shortest_horizontally_blob` | `blob_extraction_shortest_horizontally` | Least bounding-box width |
| `blob_extraction_longest_vertically_blob` | `blob_extraction_longest_vertically` | Greatest bounding-box height |
| `blob_extraction_shortest_vertically_blob` | `blob_extraction_shortest_vertically` | Least bounding-box height |
| `blob_extraction_size_between_blob` | - | All components within area bounds |

Statistical operators use source pixels inside each component. Standard
deviation is the population standard deviation.

| Mask operator | Masked-image operator | Selection |
|:--|:--|:--|
| `blob_extraction_max_mean_blob` | `blob_extraction_max_mean` | Greatest mean |
| `blob_extraction_max_median_blob` | `blob_extraction_max_median` | Greatest median |
| `blob_extraction_max_std_blob` | `blob_extraction_max_std` | Greatest standard deviation |
| `blob_extraction_max_max_blob` | `blob_extraction_max_max` | Greatest maximum |
| `blob_extraction_max_min_blob` | `blob_extraction_max_min` | Greatest minimum |
| `blob_extraction_min_mean_blob` | `blob_extraction_min_mean` | Least mean |
| `blob_extraction_min_median_blob` | `blob_extraction_min_median` | Least median |
| `blob_extraction_min_std_blob` | `blob_extraction_min_std` | Least standard deviation |
| `blob_extraction_min_max_blob` | `blob_extraction_min_max` | Least maximum |
| `blob_extraction_min_min_blob` | `blob_extraction_min_min` | Least minimum |

Source-statistic interval selectors are deferred because
`image + saliency + lower + upper` would require four MAGE inputs. They can be
added after MAGE gains a range-valued parameter chromosome.

## Lena examples

The examples use the vendored 16-bit `lena_gray_16bit.png` from
[JuliaImages/TestImages.jl](https://github.com/JuliaImages/TestImages.jl).
Source, saliency, and masked outputs retain `N0f16` inside MAGE.

```@setup blob_extraction_assets
using UTCGP
using FileIO
using Images
using ImageCore: N0f16

repo_root = normpath(joinpath(dirname(pathof(UTCGP)), ".."))
assets_src = joinpath(repo_root, "docs", "src", "assets", "fns", "blob_extraction")
assets_build = joinpath(repo_root, "docs", "build", "assets", "fns", "blob_extraction")
mkpath(assets_src)
mkpath(assets_build)

lena_values = Float64.(Gray.(load(joinpath(repo_root, "assets", "lena_gray_16bit.png"))))
lena_image = SImageND(IntensityPixel{N0f16}.(lena_values))
saliency_fn = bundle_image2DIntensity_saliency_fixation_factory[
    :itti_koch_saliency
].fn(typeof(lena_image))
lena_saliency = saliency_fn(lena_image)
binary_prototype = SImageND(BinaryPixel.(falses(size(lena_values))))
binary_functions = Dict(
    wrapper.name => wrapper.fn(typeof(binary_prototype))
    for wrapper in bundle_image2DBinary_blob_extraction_factory
)
intensity_functions = Dict(
    wrapper.name => wrapper.fn(typeof(lena_image))
    for wrapper in bundle_image2DIntensity_blob_extraction_factory
)

function save_blob_example(name, image)
    rendered = Gray.(clamp.(Float64.(reinterpret(image.img)), 0.0, 1.0))
    save(joinpath(assets_src, name), rendered)
    save(joinpath(assets_build, name), rendered)
    return nothing
end

save_blob_example("source.png", lena_image)
save_blob_example("saliency.png", lena_saliency)
area_between = binary_functions[:blob_extraction_size_between_blob]
clean_mask = area_between(lena_saliency, 20, length(lena_saliency))
save_blob_example("components_min20.png", clean_mask)

for (suffix, threshold) in (("035", 0.35), ("05", 0.5), ("07", 0.7))
    output = binary_functions[:blob_extraction_largest_blob](
        lena_saliency, threshold, 20,
    )
    save_blob_example("threshold_" * suffix * ".png", output)
end
for minimum_area in (1, 50, 300)
    output = binary_functions[:blob_extraction_smallest_blob](
        lena_saliency, 0.5, minimum_area,
    )
    save_blob_example("minimum_area_" * string(minimum_area) * ".png", output)
end
for (name, lower, upper) in (
        ("area_1_250.png", 1, 250),
        ("area_200_500.png", 200, 500),
        ("area_500_2000.png", 500, 2000),
    )
    save_blob_example(name, area_between(lena_saliency, lower, upper))
end

geometry_selectors = (
    :largest, :smallest, :longest_horizontally, :shortest_horizontally,
    :longest_vertically, :shortest_vertically,
)
for selector in geometry_selectors
    blob_name = Symbol(:blob_extraction_, selector, :_blob)
    image_name = Symbol(:blob_extraction_, selector)
    save_blob_example(
        "geometry_" * string(selector) * "_blob.png",
        binary_functions[blob_name](clean_mask),
    )
    save_blob_example(
        "geometry_" * string(selector) * ".png",
        intensity_functions[image_name](lena_image, clean_mask),
    )
end

statistic_selectors = (
    :max_mean, :max_median, :max_std, :max_max, :max_min,
    :min_mean, :min_median, :min_std, :min_max, :min_min,
)
for selector in statistic_selectors
    blob_name = Symbol(:blob_extraction_, selector, :_blob)
    image_name = Symbol(:blob_extraction_, selector)
    save_blob_example(
        "statistic_" * string(selector) * "_blob.png",
        binary_functions[blob_name](lena_image, clean_mask),
    )
    save_blob_example(
        "statistic_" * string(selector) * ".png",
        intensity_functions[image_name](lena_image, clean_mask),
    )
end
```

```@raw html
<div style="display:flex; gap:1rem; align-items:flex-start;">
<figure style="width:31%; margin:0;"><img src="../assets/fns/blob_extraction/source.png" alt="Lena 16-bit grayscale source" style="width:100%;" /><figcaption>Source (<code>N0f16</code>)</figcaption></figure>
<figure style="width:31%; margin:0;"><img src="../assets/fns/blob_extraction/saliency.png" alt="Lena Itti-Koch saliency map" style="width:100%;" /><figcaption>Itti-Koch saliency</figcaption></figure>
<figure style="width:31%; margin:0;"><img src="../assets/fns/blob_extraction/components_min20.png" alt="Components of at least twenty pixels" style="width:100%;" /><figcaption><code>threshold = 0.5</code>, area at least 20</figcaption></figure>
</div>
```

### Effect of `threshold`

This preprocessing parameter is shared by every intensity-saliency overload.

```@raw html
<div style="display:flex; gap:1rem; align-items:flex-start;">
<figure style="width:31%; margin:0;"><img src="../assets/fns/blob_extraction/threshold_035.png" alt="Largest blob at threshold 0.35" style="width:100%;" /><figcaption><code>threshold = 0.35</code></figcaption></figure>
<figure style="width:31%; margin:0;"><img src="../assets/fns/blob_extraction/threshold_05.png" alt="Largest blob at threshold 0.5" style="width:100%;" /><figcaption><code>threshold = 0.5</code> (default)</figcaption></figure>
<figure style="width:31%; margin:0;"><img src="../assets/fns/blob_extraction/threshold_07.png" alt="Largest blob at threshold 0.7" style="width:100%;" /><figcaption><code>threshold = 0.7</code></figcaption></figure>
</div>
```

### Effect of `min_pixels`

```@raw html
<div style="display:flex; gap:1rem; align-items:flex-start;">
<figure style="width:31%; margin:0;"><img src="../assets/fns/blob_extraction/minimum_area_1.png" alt="Smallest blob with minimum one pixel" style="width:100%;" /><figcaption><code>min_pixels = 1</code></figcaption></figure>
<figure style="width:31%; margin:0;"><img src="../assets/fns/blob_extraction/minimum_area_50.png" alt="Smallest blob with minimum fifty pixels" style="width:100%;" /><figcaption><code>min_pixels = 50</code></figcaption></figure>
<figure style="width:31%; margin:0;"><img src="../assets/fns/blob_extraction/minimum_area_300.png" alt="Smallest blob with minimum three hundred pixels" style="width:100%;" /><figcaption><code>min_pixels = 300</code></figcaption></figure>
</div>
```

### Effect of area bounds

```@raw html
<div style="display:flex; gap:1rem; align-items:flex-start;">
<figure style="width:31%; margin:0;"><img src="../assets/fns/blob_extraction/area_1_250.png" alt="Blobs from one to 250 pixels" style="width:100%;" /><figcaption>1-250 pixels</figcaption></figure>
<figure style="width:31%; margin:0;"><img src="../assets/fns/blob_extraction/area_200_500.png" alt="Blobs from 200 to 500 pixels" style="width:100%;" /><figcaption>200-500 pixels</figcaption></figure>
<figure style="width:31%; margin:0;"><img src="../assets/fns/blob_extraction/area_500_2000.png" alt="Blobs from 500 to 2000 pixels" style="width:100%;" /><figcaption>500-2000 pixels</figcaption></figure>
</div>
```

## Geometry output gallery

Each row shows the binary `*_blob` result and the separately bundled
masked-intensity result.

| Criterion | Binary blob | Masked `N0f16` source |
|:--|:--:|:--:|
| Largest | ![Largest blob](../assets/fns/blob_extraction/geometry_largest_blob.png) | ![Largest masked source](../assets/fns/blob_extraction/geometry_largest.png) |
| Smallest | ![Smallest blob](../assets/fns/blob_extraction/geometry_smallest_blob.png) | ![Smallest masked source](../assets/fns/blob_extraction/geometry_smallest.png) |
| Longest horizontally | ![Widest blob](../assets/fns/blob_extraction/geometry_longest_horizontally_blob.png) | ![Widest masked source](../assets/fns/blob_extraction/geometry_longest_horizontally.png) |
| Shortest horizontally | ![Narrowest blob](../assets/fns/blob_extraction/geometry_shortest_horizontally_blob.png) | ![Narrowest masked source](../assets/fns/blob_extraction/geometry_shortest_horizontally.png) |
| Longest vertically | ![Tallest blob](../assets/fns/blob_extraction/geometry_longest_vertically_blob.png) | ![Tallest masked source](../assets/fns/blob_extraction/geometry_longest_vertically.png) |
| Shortest vertically | ![Shortest blob](../assets/fns/blob_extraction/geometry_shortest_vertically_blob.png) | ![Shortest masked source](../assets/fns/blob_extraction/geometry_shortest_vertically.png) |

## Source-statistic output gallery

| Criterion | Binary blob | Masked `N0f16` source |
|:--|:--:|:--:|
| Maximum mean | ![Maximum mean blob](../assets/fns/blob_extraction/statistic_max_mean_blob.png) | ![Maximum mean image](../assets/fns/blob_extraction/statistic_max_mean.png) |
| Maximum median | ![Maximum median blob](../assets/fns/blob_extraction/statistic_max_median_blob.png) | ![Maximum median image](../assets/fns/blob_extraction/statistic_max_median.png) |
| Maximum standard deviation | ![Maximum std blob](../assets/fns/blob_extraction/statistic_max_std_blob.png) | ![Maximum std image](../assets/fns/blob_extraction/statistic_max_std.png) |
| Maximum maximum | ![Maximum max blob](../assets/fns/blob_extraction/statistic_max_max_blob.png) | ![Maximum max image](../assets/fns/blob_extraction/statistic_max_max.png) |
| Maximum minimum | ![Maximum min blob](../assets/fns/blob_extraction/statistic_max_min_blob.png) | ![Maximum min image](../assets/fns/blob_extraction/statistic_max_min.png) |
| Minimum mean | ![Minimum mean blob](../assets/fns/blob_extraction/statistic_min_mean_blob.png) | ![Minimum mean image](../assets/fns/blob_extraction/statistic_min_mean.png) |
| Minimum median | ![Minimum median blob](../assets/fns/blob_extraction/statistic_min_median_blob.png) | ![Minimum median image](../assets/fns/blob_extraction/statistic_min_median.png) |
| Minimum standard deviation | ![Minimum std blob](../assets/fns/blob_extraction/statistic_min_std_blob.png) | ![Minimum std image](../assets/fns/blob_extraction/statistic_min_std.png) |
| Minimum maximum | ![Minimum max blob](../assets/fns/blob_extraction/statistic_min_max_blob.png) | ![Minimum max image](../assets/fns/blob_extraction/statistic_min_max.png) |
| Minimum minimum | ![Minimum min blob](../assets/fns/blob_extraction/statistic_min_min_blob.png) | ![Minimum min image](../assets/fns/blob_extraction/statistic_min_min.png) |

```@docs
UTCGP.image2D_blob_extraction
UTCGP.image2D_blob_extraction.bundle_image2DBinary_blob_extraction_factory
UTCGP.image2D_blob_extraction.bundle_image2DIntensity_blob_extraction_factory
```
