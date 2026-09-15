```@meta
CurrentModule = UTCGP
```

# Discrete Foreground Extraction

Discrete foreground extraction converts an intensity image into a hard,
same-size `BinaryPixel{Bool}` mask. The bundle is kept separate from intensity
operators so a specialized MAGE binary chromosome can never receive an
intensity result.

```julia
bundle_image2DBinary_foreground_extraction_factory
```

This factory bundle is opt-in through `get_extension_foreground_binaryimg()`. Its
specialization type fixes the output dimensions and binary storage type; the
input intensity storage does not change that output contract.

## Boykov–Jolly graph cuts

`boykov_jolly_foreground` minimizes a two-label graph-cut energy. Thirty-two-bin
intensity histograms provide foreground/background appearance costs, a
scale-space saliency map supplies a soft spatial prior, and contrast-sensitive
four-neighbor edges penalize boundaries between similar pixels. The minimum cut
is deterministic.

The original interactive method expects user-provided seeds. This MAGE variant
derives them from saliency:

- high-saliency interior pixels are hard foreground seeds;
- every border pixel and low-saliency pixels connected to the border are hard
  background seeds; and
- all remaining pixels are assigned by the graph cut.

With no saliency input, the operator computes spectral-residual saliency
internally. A same-size intensity saliency image can instead come from another
MAGE chromosome. A flat saliency map has no foreground evidence and returns an
all-zero mask.

The saliency map is smoothed at an image-relative scale before seeds and the
soft prior are constructed. This turns fixation peaks into usable spatial
evidence, but it does not add semantic understanding: the output follows the
structure emphasized by the chosen saliency method. For example, a fixation
map that prefers Lena's feather can produce a feather-centered foreground mask
rather than a person mask.

### Specialized callable

```julia
mask = fn(image)
mask = fn(image, smoothness)
mask = fn(image, smoothness, foreground_quantile)
mask = fn(image, saliency)
mask = fn(image, saliency, smoothness)
```

The signatures have at most three effective MAGE inputs. Trailing framework
`args...` are accepted and ignored.

| Parameter | Mapping | Effect | Default |
|:--|:--|:--|:--|
| `smoothness` | finite values clamped to `[0, 20]` | Larger values favor shorter boundaries through similar neighboring intensities; `0` disables the pairwise term | `5.0` |
| `foreground_quantile` | finite values clamped to `[0.5, 0.99]` | With automatic saliency, controls how selective the high-saliency foreground seeds are | `0.9` |

Non-finite values use the defaults. A supplied saliency map uses a fixed
foreground quantile of `0.9`, leaving the third input available for
`smoothness` under MAGE's arity ceiling.

```@example
using UTCGP
using ImageCore: N0f8

values = fill(0.15, 64, 64)
values[20:45, 24:41] .= 0.85
saliency_values = zeros(64, 64)
saliency_values[20:45, 24:41] .= 1.0
image = SImageND(IntensityPixel{N0f8}.(values))
saliency = SImageND(IntensityPixel{N0f8}.(saliency_values))
binary_prototype = SImageND(BinaryPixel.(falses(size(values))))
fn = bundle_image2DBinary_foreground_extraction_factory[
    :boykov_jolly_foreground
].fn(typeof(binary_prototype))
mask = fn(image, saliency)

(size(mask), eltype(mask), sum(reinterpret(mask.img)))
```

## Cell, coffee, and Lena examples

The gallery uses the same vendored fixtures as the fixation-saliency manual.
Cell and coffee are downsampled once to keep this exact graph-cut example below
the library's runtime target; Lena remains at its native 256×256 resolution.

```@setup foreground_extraction_assets
using UTCGP
using FileIO
using Images
using ImageCore: N0f8, N0f16

repo_root = normpath(joinpath(dirname(pathof(UTCGP)), ".."))
assets_src = joinpath(repo_root, "docs", "src", "assets", "fns", "foreground_extraction")
assets_build = joinpath(repo_root, "docs", "build", "assets", "fns", "foreground_extraction")
mkpath(assets_src)
mkpath(assets_build)

function foreground_image(path, ::Type{T}; downsample = false) where {T}
    values = Float64.(Gray.(load(path)))
    downsample && (values = values[1:2:end, 1:2:end])
    return SImageND(IntensityPixel{T}.(values))
end

cell = foreground_image(joinpath(repo_root, "assets", "000_img.png"), N0f8; downsample = true)
coffee = foreground_image(joinpath(repo_root, "assets", "coffee.png"), N0f8; downsample = true)
lena = foreground_image(joinpath(repo_root, "assets", "lena_gray_16bit.png"), N0f16)

function foreground_functions(image)
    prototype = SImageND(BinaryPixel.(falses(size(image))))
    foreground_fn = bundle_image2DBinary_foreground_extraction_factory[
        :boykov_jolly_foreground
    ].fn(typeof(prototype))
    saliency_fn = bundle_image2DIntensity_saliency_fixation_factory[
        :spectral_residual_saliency
    ].fn(typeof(image))
    return foreground_fn, saliency_fn
end

function save_foreground_example(name, image)
    rendered = Gray.(clamp.(Float64.(reinterpret(image.img)), 0.0, 1.0))
    save(joinpath(assets_src, name), rendered)
    save(joinpath(assets_build, name), rendered)
    return nothing
end

for (name, image) in (("cell", cell), ("coffee", coffee), ("lena", lena))
    foreground_fn, saliency_fn = foreground_functions(image)
    saliency = saliency_fn(image)
    mask = foreground_fn(image, saliency)
    save_foreground_example(name * "_input.png", image)
    save_foreground_example(name * "_saliency.png", saliency)
    save_foreground_example(name * "_mask.png", mask)
end

coffee_foreground, coffee_saliency_fn = foreground_functions(coffee)
coffee_saliency = coffee_saliency_fn(coffee)
for smoothness in (0.0, 5.0, 15.0)
    mask = coffee_foreground(coffee, coffee_saliency, smoothness)
    save_foreground_example(
        "coffee_smoothness_" * replace(string(smoothness), "." => "_") * ".png",
        mask,
    )
end
for quantile in (0.75, 0.9, 0.97)
    mask = coffee_foreground(coffee, 5.0, quantile)
    save_foreground_example(
        "coffee_quantile_" * replace(string(quantile), "." => "_") * ".png",
        mask,
    )
end
```

### Default results with supplied saliency

These calls pass the displayed spectral-residual map explicitly. Each row is
input intensity, saliency seed evidence, then binary graph-cut output.

| Fixture | Input | Spectral-residual saliency | Foreground mask |
|:--|:--:|:--:|:--:|
| Cell | ![Cell input](../assets/fns/foreground_extraction/cell_input.png) | ![Cell saliency](../assets/fns/foreground_extraction/cell_saliency.png) | ![Cell foreground](../assets/fns/foreground_extraction/cell_mask.png) |
| Coffee | ![Coffee input](../assets/fns/foreground_extraction/coffee_input.png) | ![Coffee saliency](../assets/fns/foreground_extraction/coffee_saliency.png) | ![Coffee foreground](../assets/fns/foreground_extraction/coffee_mask.png) |
| Lena | ![Lena input](../assets/fns/foreground_extraction/lena_input.png) | ![Lena saliency](../assets/fns/foreground_extraction/lena_saliency.png) | ![Lena foreground](../assets/fns/foreground_extraction/lena_mask.png) |

### Effect of `smoothness`

The same coffee saliency map is supplied in all three calls. Stronger
regularization suppresses isolated assignments and favors coherent boundaries,
while contrast still permits cuts at strong intensity changes.

```@raw html
<div style="display:flex; gap:1rem; align-items:flex-start;">
<figure style="width:31%; margin:0;"><img src="../assets/fns/foreground_extraction/coffee_smoothness_0_0.png" alt="Coffee foreground with smoothness zero" style="width:100%;" /><figcaption><code>smoothness = 0.0</code></figcaption></figure>
<figure style="width:31%; margin:0;"><img src="../assets/fns/foreground_extraction/coffee_smoothness_5_0.png" alt="Coffee foreground with default smoothness" style="width:100%;" /><figcaption><code>smoothness = 5.0</code> (default)</figcaption></figure>
<figure style="width:31%; margin:0;"><img src="../assets/fns/foreground_extraction/coffee_smoothness_15_0.png" alt="Coffee foreground with strong smoothness" style="width:100%;" /><figcaption><code>smoothness = 15.0</code></figcaption></figure>
</div>
```

### Effect of `foreground_quantile`

These calls use internal spectral-residual saliency. Higher quantiles make the
hard foreground seed set more selective; the graph cut still labels the full
image from appearance and boundary evidence.

```@raw html
<div style="display:flex; gap:1rem; align-items:flex-start;">
<figure style="width:31%; margin:0;"><img src="../assets/fns/foreground_extraction/coffee_quantile_0_75.png" alt="Coffee foreground at quantile 0.75" style="width:100%;" /><figcaption><code>foreground_quantile = 0.75</code></figcaption></figure>
<figure style="width:31%; margin:0;"><img src="../assets/fns/foreground_extraction/coffee_quantile_0_9.png" alt="Coffee foreground at default quantile" style="width:100%;" /><figcaption><code>foreground_quantile = 0.9</code> (default)</figcaption></figure>
<figure style="width:31%; margin:0;"><img src="../assets/fns/foreground_extraction/coffee_quantile_0_97.png" alt="Coffee foreground at quantile 0.97" style="width:100%;" /><figcaption><code>foreground_quantile = 0.97</code></figcaption></figure>
</div>
```

## GrabCut

`grabcut_foreground` uses the same saliency-derived permanent seeds as the
Boykov--Jolly operator, then alternates between two operations:

1. fit foreground and background Gaussian mixture models from the current mask;
2. find the exact minimum cut using those per-image appearance models.

The mixtures are fitted afresh from the input image. They are not pretrained
weights and nothing external is downloaded. The current intensity-image
specialization fits five one-dimensional Gaussian components per class. The
model-fitting boundary is isolated internally so a future RGB specialization
can use three-dimensional color vectors without changing the callable API or
binary output contract.

### Specialized callable

```julia
mask = grabcut_fn(image)
mask = grabcut_fn(image, iterations)
mask = grabcut_fn(image, iterations, smoothness)
mask = grabcut_fn(image, saliency)
mask = grabcut_fn(image, saliency, iterations)
```

All signatures have at most three effective MAGE inputs and accept ignored
trailing framework `args...`.

| Parameter | Mapping | Effect | Default |
|:--|:--|:--|:--|
| `iterations` | rounded and clamped to `[1, 2]` | Refits both mixtures and recomputes the cut; the second round can refine ambiguous pixels and exits early if the mask is unchanged | `2` |
| `smoothness` | finite values clamped to `[0, 20]` | Controls contrast-sensitive boundary regularization in automatic-saliency calls | `5.0` |

Non-finite values use the defaults. When saliency is supplied explicitly, the
third MAGE input is `iterations` and smoothness remains at `5.0`. A flat
saliency map returns an all-zero mask.

```@example foreground_extraction_assets
function grabcut_function(image)
    prototype = SImageND(BinaryPixel.(falses(size(image))))
    return bundle_image2DBinary_foreground_extraction_factory[
        :grabcut_foreground
    ].fn(typeof(prototype))
end

for (name, image) in (("cell", cell), ("coffee", coffee), ("lena", lena))
    _, saliency_fn = foreground_functions(image)
    saliency = saliency_fn(image)
    mask = grabcut_function(image)(image, saliency)
    save_foreground_example(name * "_grabcut_mask.png", mask)
end

coffee_grabcut = grabcut_function(coffee)
for iterations in (1.0, 2.0)
    mask = coffee_grabcut(coffee, coffee_saliency, iterations)
    save_foreground_example(
        "coffee_grabcut_iterations_" *
        replace(string(iterations), "." => "_") * ".png",
        mask,
    )
end
for smoothness in (0.0, 5.0, 15.0)
    mask = coffee_grabcut(coffee, 2.0, smoothness)
    save_foreground_example(
        "coffee_grabcut_smoothness_" *
        replace(string(smoothness), "." => "_") * ".png",
        mask,
    )
end
```

### Cell, coffee, and Lena results

Each call receives the displayed spectral-residual map explicitly. GrabCut
uses it for initialization, then learns foreground and background intensity
mixtures from that individual image.

| Fixture | Input | Spectral-residual saliency | GrabCut mask |
|:--|:--:|:--:|:--:|
| Cell | ![Cell input](../assets/fns/foreground_extraction/cell_input.png) | ![Cell saliency](../assets/fns/foreground_extraction/cell_saliency.png) | ![Cell GrabCut foreground](../assets/fns/foreground_extraction/cell_grabcut_mask.png) |
| Coffee | ![Coffee input](../assets/fns/foreground_extraction/coffee_input.png) | ![Coffee saliency](../assets/fns/foreground_extraction/coffee_saliency.png) | ![Coffee GrabCut foreground](../assets/fns/foreground_extraction/coffee_grabcut_mask.png) |
| Lena | ![Lena input](../assets/fns/foreground_extraction/lena_input.png) | ![Lena saliency](../assets/fns/foreground_extraction/lena_saliency.png) | ![Lena GrabCut foreground](../assets/fns/foreground_extraction/lena_grabcut_mask.png) |

As with Boykov--Jolly, automatic seeds provide attention rather than semantic
object identity. GrabCut can improve an intensity-consistent region around
those seeds, but it cannot infer that the intended subject is the person when
the supplied Lena saliency map emphasizes the feather or background.

### Effect of `iterations`

The same coffee image and supplied saliency are used below. The second round
refits both mixtures from the first cut. If the first mask is already stable,
both outputs are intentionally identical.

```@raw html
<div style="display:flex; gap:1rem; align-items:flex-start;">
<figure style="width:48%; margin:0;"><img src="../assets/fns/foreground_extraction/coffee_grabcut_iterations_1_0.png" alt="Coffee GrabCut after one iteration" style="width:100%;" /><figcaption><code>iterations = 1</code></figcaption></figure>
<figure style="width:48%; margin:0;"><img src="../assets/fns/foreground_extraction/coffee_grabcut_iterations_2_0.png" alt="Coffee GrabCut after two iterations" style="width:100%;" /><figcaption><code>iterations = 2</code> (default)</figcaption></figure>
</div>
```

### Effect of GrabCut `smoothness`

These calls use automatic spectral-residual saliency. Increasing smoothness
makes cuts through similar neighboring intensities more expensive.

```@raw html
<div style="display:flex; gap:1rem; align-items:flex-start;">
<figure style="width:31%; margin:0;"><img src="../assets/fns/foreground_extraction/coffee_grabcut_smoothness_0_0.png" alt="Coffee GrabCut with smoothness zero" style="width:100%;" /><figcaption><code>smoothness = 0.0</code></figcaption></figure>
<figure style="width:31%; margin:0;"><img src="../assets/fns/foreground_extraction/coffee_grabcut_smoothness_5_0.png" alt="Coffee GrabCut with default smoothness" style="width:100%;" /><figcaption><code>smoothness = 5.0</code> (default)</figcaption></figure>
<figure style="width:31%; margin:0;"><img src="../assets/fns/foreground_extraction/coffee_grabcut_smoothness_15_0.png" alt="Coffee GrabCut with strong smoothness" style="width:100%;" /><figcaption><code>smoothness = 15.0</code></figcaption></figure>
</div>
```

The output is a mask, not a masked intensity image. MAGE can combine it with
the source using image arithmetic, for example `image * mask`.

```@docs
UTCGP.image2D_foreground_extraction_discrete
UTCGP.image2D_foreground_extraction_discrete.bundle_image2DBinary_foreground_extraction_factory
UTCGP.image2D_foreground_extraction_discrete.boykov_jolly_foreground_image2D_factory
UTCGP.image2D_foreground_extraction_discrete.grabcut_foreground_image2D_factory
```

References:

- Boykov and Jolly, *Interactive Graph Cuts for Optimal Boundary & Region
  Segmentation of Objects in N-D Images* (ICCV 2001).
- Rother, Kolmogorov, and Blake, *GrabCut: Interactive Foreground Extraction
  Using Iterated Graph Cuts* (ACM SIGGRAPH 2004).
