~~~@meta
CurrentModule = UTCGP
~~~

# Continuous Foreground Extraction

Continuous foreground extraction returns a soft, same-size foreground-membership
image rather than a binary decision. Every output pixel is an
<code>IntensityPixel</code> in <code>[0, 1]</code>: zero means background,
one means foreground, and intermediate values preserve uncertainty for later
MAGE image arithmetic or thresholding.

~~~julia
bundle_image2DIntensity_foreground_extraction_factory
~~~

This factory bundle is opt-in through <code>get_extension_foreground_intensityimg()</code>.
Its specialization fixes the output dimensions, pixel category, and storage
type. It is separate from the discrete foreground bundle, so an intensity
chromosome cannot unexpectedly receive a binary mask.

## Random Walker foreground probabilities

<code>random_walker_foreground</code> treats every pixel as a vertex in a
four-neighbor weighted graph. Similar adjacent intensities receive strong
conductance; a walker crosses a strong intensity boundary less readily. Hard
foreground and background seeds fix the Dirichlet boundary conditions, and one
sparse Laplacian solve gives every unknown pixel the probability that a random
walker reaches foreground before background.

The original interactive method requires labeled seeds. This MAGE variant uses
the same deterministic saliency-derived seeds as the discrete foreground
operators:

- high-saliency interior pixels are fixed to probability one;
- border-connected low-saliency pixels are fixed to probability zero; and
- every remaining pixel receives a continuous probability from the solve.

Without an explicit saliency input, spectral-residual saliency is computed
internally. A same-size intensity saliency map can instead come from another
MAGE chromosome. Flat saliency supplies no foreground evidence and returns a
typed all-zero image.

### Specialized callable

~~~julia
probabilities = fn(image)
probabilities = fn(image, contrast)
probabilities = fn(image, contrast, foreground_quantile)
probabilities = fn(image, saliency)
probabilities = fn(image, saliency, contrast)
~~~

All signatures have at most three effective MAGE inputs. Ignored trailing
framework <code>args...</code> are accepted by every overload.

| Parameter | Mapping | Effect | Default |
|:--|:--|:--|:--|
| <code>contrast</code> | finite values clamped to <code>[0, 1000]</code> | Controls edge conductance <code>exp(-contrast * difference²) + 1e-6</code>. At zero, only geometry matters; larger values preserve stronger intensity boundaries. | <code>90.0</code> |
| <code>foreground_quantile</code> | finite values clamped to <code>[0.5, 0.99]</code> | In automatic-saliency calls, controls how selective the hard foreground seeds are. | <code>0.95</code> |

Non-finite values use the defaults. When saliency is supplied explicitly, its
seed quantile remains <code>0.95</code>, leaving the third MAGE input available
for <code>contrast</code>.

~~~@example
using UTCGP
using ImageCore: N0f8

values = fill(0.15, 64, 64)
values[20:45, 24:41] .= 0.85
saliency_values = zeros(64, 64)
saliency_values[20:45, 24:41] .= 1.0
image = SImageND(IntensityPixel{N0f8}.(values))
saliency = SImageND(IntensityPixel{N0f8}.(saliency_values))
fn = bundle_image2DIntensity_foreground_extraction_factory[
    :random_walker_foreground
].fn(typeof(image))
probabilities = fn(image, saliency)

(
    size(probabilities),
    eltype(probabilities),
    extrema(reinterpret(probabilities.img)),
)
~~~

## Cell, coffee, and Lena examples

The gallery uses the vendored fixtures from the saliency and discrete
foreground pages. Cell and coffee are downsampled once; Lena remains at its
native 256×256 resolution.

~~~@setup continuous_foreground_assets
using UTCGP
using FileIO
using Images
using ImageCore: N0f8, N0f16

repo_root = normpath(joinpath(dirname(pathof(UTCGP)), ".."))
assets_src = joinpath(
    repo_root,
    "docs",
    "src",
    "assets",
    "fns",
    "foreground_extraction_continuous",
)
assets_build = joinpath(
    repo_root,
    "docs",
    "build",
    "assets",
    "fns",
    "foreground_extraction_continuous",
)
mkpath(assets_src)
mkpath(assets_build)

function continuous_foreground_image(path, ::Type{T}; downsample = false) where {T}
    values = Float64.(Gray.(load(path)))
    downsample && (values = values[1:2:end, 1:2:end])
    return SImageND(IntensityPixel{T}.(values))
end

cell = continuous_foreground_image(
    joinpath(repo_root, "assets", "000_img.png"),
    N0f8;
    downsample = true,
)
coffee = continuous_foreground_image(
    joinpath(repo_root, "assets", "coffee.png"),
    N0f8;
    downsample = true,
)
lena = continuous_foreground_image(
    joinpath(repo_root, "assets", "lena_gray_16bit.png"),
    N0f16,
)

function continuous_foreground_functions(image)
    random_walker_fn = bundle_image2DIntensity_foreground_extraction_factory[
        :random_walker_foreground
    ].fn(typeof(image))
    saliency_fn = bundle_image2DIntensity_saliency_fixation_factory[
        :spectral_residual_saliency
    ].fn(typeof(image))
    return random_walker_fn, saliency_fn
end

function save_continuous_foreground_example(name, image)
    rendered = Gray.(clamp.(Float64.(reinterpret(image.img)), 0.0, 1.0))
    save(joinpath(assets_src, name), rendered)
    save(joinpath(assets_build, name), rendered)
    return nothing
end

for (name, image) in (("cell", cell), ("coffee", coffee), ("lena", lena))
    random_walker_fn, saliency_fn = continuous_foreground_functions(image)
    saliency = saliency_fn(image)
    probabilities = random_walker_fn(image, saliency)
    save_continuous_foreground_example(name * "_input.png", image)
    save_continuous_foreground_example(name * "_saliency.png", saliency)
    save_continuous_foreground_example(
        name * "_random_walker_probability.png",
        probabilities,
    )
end

coffee_random_walker, coffee_saliency_fn =
    continuous_foreground_functions(coffee)
coffee_saliency = coffee_saliency_fn(coffee)
for contrast in (0.0, 90.0, 500.0)
    probabilities = coffee_random_walker(coffee, coffee_saliency, contrast)
    save_continuous_foreground_example(
        "coffee_random_walker_contrast_" *
        replace(string(contrast), "." => "_") * ".png",
        probabilities,
    )
end
for quantile in (0.9, 0.95, 0.98)
    probabilities = coffee_random_walker(coffee, 90.0, quantile)
    save_continuous_foreground_example(
        "coffee_random_walker_quantile_" *
        replace(string(quantile), "." => "_") * ".png",
        probabilities,
    )
end
~~~

### Default results with supplied saliency

Each row shows the intensity input, the supplied spectral-residual saliency,
and the continuous foreground-probability output. These are not binary masks:
gray pixels retain the Random Walker uncertainty.

| Fixture | Input | Spectral-residual saliency | Foreground probability |
|:--|:--:|:--:|:--:|
| Cell | ![Cell input](../assets/fns/foreground_extraction_continuous/cell_input.png) | ![Cell saliency](../assets/fns/foreground_extraction_continuous/cell_saliency.png) | ![Cell Random Walker probability](../assets/fns/foreground_extraction_continuous/cell_random_walker_probability.png) |
| Coffee | ![Coffee input](../assets/fns/foreground_extraction_continuous/coffee_input.png) | ![Coffee saliency](../assets/fns/foreground_extraction_continuous/coffee_saliency.png) | ![Coffee Random Walker probability](../assets/fns/foreground_extraction_continuous/coffee_random_walker_probability.png) |
| Lena | ![Lena input](../assets/fns/foreground_extraction_continuous/lena_input.png) | ![Lena saliency](../assets/fns/foreground_extraction_continuous/lena_saliency.png) | ![Lena Random Walker probability](../assets/fns/foreground_extraction_continuous/lena_random_walker_probability.png) |

As with the discrete operators, saliency supplies attention rather than semantic
identity. If Lena's saliency emphasizes the feather or background, Random
Walker propagates probabilities from those seeds; it does not know that the
intended semantic object is the woman.

### Effect of contrast

The same coffee image and supplied saliency map are used in every call. With
<code>contrast = 0</code>, equal conductance makes the result a geometric
harmonic interpolation. Increasing contrast makes intensity boundaries more
resistant to probability diffusion.

~~~@raw html
<div style="display:flex; gap:1rem; align-items:flex-start;">
<figure style="width:31%; margin:0;"><img src="../assets/fns/foreground_extraction_continuous/coffee_random_walker_contrast_0_0.png" alt="Coffee Random Walker probability with contrast zero" style="width:100%;" /><figcaption><code>contrast = 0.0</code></figcaption></figure>
<figure style="width:31%; margin:0;"><img src="../assets/fns/foreground_extraction_continuous/coffee_random_walker_contrast_90_0.png" alt="Coffee Random Walker probability with default contrast" style="width:100%;" /><figcaption><code>contrast = 90.0</code> (default)</figcaption></figure>
<figure style="width:31%; margin:0;"><img src="../assets/fns/foreground_extraction_continuous/coffee_random_walker_contrast_500_0.png" alt="Coffee Random Walker probability with strong contrast" style="width:100%;" /><figcaption><code>contrast = 500.0</code></figcaption></figure>
</div>
~~~

### Effect of foreground seed quantile

These calls compute spectral-residual saliency internally. A higher quantile
makes the probability-one seed set smaller and more selective; the Laplacian
still assigns every unseeded pixel.

~~~@raw html
<div style="display:flex; gap:1rem; align-items:flex-start;">
<figure style="width:31%; margin:0;"><img src="../assets/fns/foreground_extraction_continuous/coffee_random_walker_quantile_0_9.png" alt="Coffee Random Walker probability with foreground quantile 0.9" style="width:100%;" /><figcaption><code>foreground_quantile = 0.9</code></figcaption></figure>
<figure style="width:31%; margin:0;"><img src="../assets/fns/foreground_extraction_continuous/coffee_random_walker_quantile_0_95.png" alt="Coffee Random Walker probability with default foreground quantile" style="width:100%;" /><figcaption><code>foreground_quantile = 0.95</code> (default)</figcaption></figure>
<figure style="width:31%; margin:0;"><img src="../assets/fns/foreground_extraction_continuous/coffee_random_walker_quantile_0_98.png" alt="Coffee Random Walker probability with foreground quantile 0.98" style="width:100%;" /><figcaption><code>foreground_quantile = 0.98</code></figcaption></figure>
</div>
~~~

The output can remain soft for downstream multiplication
(<code>image * probabilities</code>) or be converted later to a binary decision
(<code>probabilities >= threshold</code>).

## Closed-form alpha matting

<code>closed_form_matting</code> implements the grayscale form of the
Levin–Lischinski–Weiss matting Laplacian. Inside each 3×3 neighborhood, it
models foreground and background colors as locally smooth linear mixtures.
Known foreground and background trimap pixels constrain one sparse linear
solve; unknown pixels become a continuous alpha matte.

The two-image form expects a real trimap:

- values at most <code>0.1</code> are hard background and remain exactly zero;
- values at least <code>0.9</code> are hard foreground and remain exactly one;
- intermediate values are unknown, not initial alpha estimates.

The image-only form first computes spectral-residual saliency and converts its
high-saliency core and border-connected low-saliency region into those same
trimap constraints. Flat saliency provides no foreground evidence and returns a
typed all-zero image.

### Specialized callable

~~~julia
alpha = fn(image)
alpha = fn(image, edge_sensitivity)
alpha = fn(image, edge_sensitivity, foreground_quantile)
alpha = fn(image, trimap)
alpha = fn(image, trimap, edge_sensitivity)
~~~

All signatures have at most three effective MAGE inputs, excluding ignored
framework <code>args...</code>.

| Parameter | Mapping | Effect | Default |
|:--|:--|:--|:--|
| <code>edge_sensitivity</code> | finite values clamped to <code>[2, 12]</code> | Sets the matting-Laplacian regularizer to <code>epsilon = 10^-edge_sensitivity</code>. Higher values preserve subtler local intensity relationships; lower values regularize nearly flat neighborhoods more strongly. | <code>7.0</code> |
| <code>foreground_quantile</code> | finite values clamped to <code>[0.5, 0.99]</code> | Controls how selective the automatically generated hard-foreground trimap region is. | <code>0.95</code> |

Non-finite values use the defaults. Explicit-trimap calls reserve the third
MAGE input for <code>edge_sensitivity</code>. To keep evaluation below MAGE's
runtime budget, inputs above 9,216 pixels solve the same closed-form objective
on a deterministic aspect-preserving working grid. The result is lifted
bilinearly to the specialized output dimensions and original hard constraints
are restored exactly.

~~~@example
using UTCGP
using ImageCore: N0f8

values = repeat(reshape(range(0, 1; length = 64), 1, :), 64, 1)
trimap_values = fill(0.5, 64, 64)
trimap_values[:, 1:5] .= 0.0
trimap_values[:, 60:64] .= 1.0
image = SImageND(IntensityPixel{N0f8}.(values))
trimap = SImageND(IntensityPixel{N0f8}.(trimap_values))
fn = bundle_image2DIntensity_foreground_extraction_factory[
    :closed_form_matting
].fn(typeof(image))
alpha = fn(image, trimap)

(
    size(alpha),
    eltype(alpha),
    extrema(reinterpret(alpha.img)),
    count(value -> 0 < value < 1, reinterpret(alpha.img)),
)
~~~

### Cell, coffee, and Lena alpha mattes

The trimap column visualizes the exact automatic constraints: black is known
background, white is known foreground, and gray is unknown. The output column
contains the resulting continuous alpha matte.

~~~@example continuous_foreground_assets
function closed_form_function(image)
    return bundle_image2DIntensity_foreground_extraction_factory[
        :closed_form_matting
    ].fn(typeof(image))
end

function automatic_closed_form_trimap(image)
    saliency_fn = bundle_image2DIntensity_saliency_fixation_factory[
        :spectral_residual_saliency
    ].fn(typeof(image))
    saliency = saliency_fn(image)
    trimap_values, _ =
        UTCGP.image2D_foreground_extraction_continuous.
        _automatic_closed_form_trimap(reinterpret(saliency.img), 0.95)
    return SImageND(eltype(image).(trimap_values))
end

for (name, image) in (("cell", cell), ("coffee", coffee), ("lena", lena))
    matting_fn = closed_form_function(image)
    trimap = automatic_closed_form_trimap(image)
    alpha = matting_fn(image, trimap)
    save_continuous_foreground_example(
        name * "_closed_form_trimap.png",
        trimap,
    )
    save_continuous_foreground_example(
        name * "_closed_form_alpha.png",
        alpha,
    )
end

coffee_matting = closed_form_function(coffee)
coffee_trimap = automatic_closed_form_trimap(coffee)
for sensitivity in (2.0, 7.0, 12.0)
    alpha = coffee_matting(coffee, coffee_trimap, sensitivity)
    save_continuous_foreground_example(
        "coffee_closed_form_sensitivity_" *
        replace(string(sensitivity), "." => "_") * ".png",
        alpha,
    )
end
for quantile in (0.9, 0.95, 0.98)
    alpha = coffee_matting(coffee, 7.0, quantile)
    save_continuous_foreground_example(
        "coffee_closed_form_quantile_" *
        replace(string(quantile), "." => "_") * ".png",
        alpha,
    )
end
nothing
~~~

| Fixture | Input | Automatic trimap | Alpha matte |
|:--|:--:|:--:|:--:|
| Cell | ![Cell input](../assets/fns/foreground_extraction_continuous/cell_input.png) | ![Cell closed-form trimap](../assets/fns/foreground_extraction_continuous/cell_closed_form_trimap.png) | ![Cell closed-form alpha matte](../assets/fns/foreground_extraction_continuous/cell_closed_form_alpha.png) |
| Coffee | ![Coffee input](../assets/fns/foreground_extraction_continuous/coffee_input.png) | ![Coffee closed-form trimap](../assets/fns/foreground_extraction_continuous/coffee_closed_form_trimap.png) | ![Coffee closed-form alpha matte](../assets/fns/foreground_extraction_continuous/coffee_closed_form_alpha.png) |
| Lena | ![Lena input](../assets/fns/foreground_extraction_continuous/lena_input.png) | ![Lena closed-form trimap](../assets/fns/foreground_extraction_continuous/lena_closed_form_trimap.png) | ![Lena closed-form alpha matte](../assets/fns/foreground_extraction_continuous/lena_closed_form_alpha.png) |

As with the other automatic foreground operators, these results follow visual
saliency rather than semantic identity. A supplied trimap is preferable when
the desired foreground object is known externally.

### Effect of edge sensitivity

All three outputs use the same coffee image and explicit automatic trimap, so
only the local matting regularization changes.

~~~@raw html
<div style="display:flex; gap:1rem; align-items:flex-start;">
<figure style="width:31%; margin:0;"><img src="../assets/fns/foreground_extraction_continuous/coffee_closed_form_sensitivity_2_0.png" alt="Coffee alpha with edge sensitivity two" style="width:100%;" /><figcaption><code>edge_sensitivity = 2.0</code></figcaption></figure>
<figure style="width:31%; margin:0;"><img src="../assets/fns/foreground_extraction_continuous/coffee_closed_form_sensitivity_7_0.png" alt="Coffee alpha with default edge sensitivity" style="width:100%;" /><figcaption><code>edge_sensitivity = 7.0</code> (default)</figcaption></figure>
<figure style="width:31%; margin:0;"><img src="../assets/fns/foreground_extraction_continuous/coffee_closed_form_sensitivity_12_0.png" alt="Coffee alpha with edge sensitivity twelve" style="width:100%;" /><figcaption><code>edge_sensitivity = 12.0</code></figcaption></figure>
</div>
~~~

### Effect of automatic foreground quantile

These image-plus-number calls regenerate the saliency trimap each time. Higher
quantiles make the known-foreground portion smaller and more selective.

~~~@raw html
<div style="display:flex; gap:1rem; align-items:flex-start;">
<figure style="width:31%; margin:0;"><img src="../assets/fns/foreground_extraction_continuous/coffee_closed_form_quantile_0_9.png" alt="Coffee alpha with foreground quantile 0.9" style="width:100%;" /><figcaption><code>foreground_quantile = 0.9</code></figcaption></figure>
<figure style="width:31%; margin:0;"><img src="../assets/fns/foreground_extraction_continuous/coffee_closed_form_quantile_0_95.png" alt="Coffee alpha with default foreground quantile" style="width:100%;" /><figcaption><code>foreground_quantile = 0.95</code> (default)</figcaption></figure>
<figure style="width:31%; margin:0;"><img src="../assets/fns/foreground_extraction_continuous/coffee_closed_form_quantile_0_98.png" alt="Coffee alpha with foreground quantile 0.98" style="width:100%;" /><figcaption><code>foreground_quantile = 0.98</code></figcaption></figure>
</div>
~~~

~~~@docs
UTCGP.image2D_foreground_extraction_continuous
UTCGP.image2D_foreground_extraction_continuous.bundle_image2DIntensity_foreground_extraction_factory
UTCGP.image2D_foreground_extraction_continuous.random_walker_foreground_image2D_factory
UTCGP.image2D_foreground_extraction_continuous.closed_form_matting_image2D_factory
~~~

References:

- Grady, *Random Walks for Image Segmentation* (IEEE Transactions on Pattern
  Analysis and Machine Intelligence, 2006).
- Levin, Lischinski, and Weiss, *A Closed-Form Solution to Natural Image
  Matting* (IEEE Transactions on Pattern Analysis and Machine Intelligence,
  2008).
