```@meta
CurrentModule = UTCGP
```

# RGB Images and Color Statistics

MAGE can receive red, green, blue, and RGB as four distinct inputs. The three
planes are ordinary `SImage2D` intensity images. RGB is an
`SImage3D{H,W,3,IntensityPixel{N0f8}}`, with `R`, `G`, and `B` stored in slices
1, 2, and 3 of the last axis.

Two opt-in bundles preserve the output-type boundary:

| Bundle | Specialization (output) | Callable input | Output |
|:--|:--|:--|:--|
| `bundle_image2DIntensity_color_statistics_rgb_factory` | a 2D intensity image type | same-size RGB image | same-size 2D intensity map |
| `bundle_image3DIntensity_rgb_factory` | an RGB image type | zero, one, or two same-size RGB inputs; optionally one numeric parameter or same-size 2D binary mask | same-size RGB image |

The first is available from `get_extension_color_statistics_rgb_intensityimg`;
the second from `get_extension_rgbimg`. Neither is inserted into the historical
2D image getters.

## Leading RGB functions

The RGB bundle is the basic bundle of a new output library, so its first two
entries follow the same convention as the numeric, list, and 2D image basic
bundles:

1. `identity_rgb(rgb)` is first and passes an existing RGB value through.
2. `return_rgb()` is second and constructs a same-sized RGB image filled with
   typed ones without requiring an RGB input.

`return_rgb` is parameter-free in MAGE terms. Like every bundled function, it
still accepts and ignores trailing framework `args...`. The order is asserted
by tests so later insertions cannot silently break the convention.

## Constructing the RGB input

```@example rgb_types
using UTCGP
using ImageCore: N0f8

red = [1.0 0.0; 0.5 0.0]
green = [0.0 1.0; 0.5 0.0]
blue = [0.0 0.0; 0.5 1.0]
rgb = SImageND(IntensityPixel{N0f8}.(cat(red, green, blue; dims = 3)))
output_template = SImageND(IntensityPixel{N0f8}.(zeros(2, 2)))

rgb_bundle = bundle_image3DIntensity_rgb_factory
identity_fn = rgb_bundle[:identity_rgb].fn(typeof(rgb))
return_fn = rgb_bundle[:return_rgb].fn(typeof(rgb))
constant_rgb = return_fn()

luminance = bundle_image2DIntensity_color_statistics_rgb_factory[:rgb_luminance].fn(
    typeof(output_template),
)(rgb)

(identity_fn(rgb) === rgb, size(constant_rgb), all(isone, reinterpret(constant_rgb.img)), size(luminance))
```

All seven color functions have one MAGE argument and no numeric parameters:

| Function | Map |
|:--|:--|
| `rgb_luminance(rgb)` | `0.2126R + 0.7152G + 0.0722B` |
| `red_green_opponency(rgb)` | `0.5 + 0.5(R-G)`; gray is neutral 0.5 |
| `blue_yellow_opponency(rgb)` | `0.5 + 0.5(B-(R+G)/2)`; gray is neutral 0.5 |
| `rgb_saturation(rgb)` | `max(R,G,B)-min(R,G,B)` |
| `normalized_red(rgb)` | `R/(R+G+B)`; black maps to 0 |
| `normalized_green(rgb)` | `G/(R+G+B)`; black maps to 0 |
| `normalized_blue(rgb)` | `B/(R+G+B)`; black maps to 0 |

The opponent maps use a midpoint because an unsigned intensity chromosome
cannot otherwise preserve the sign of a color difference. Every result is in
`[0,1]`, has the specialized 2D output type, and retains the RGB input's height
and width.

## RGB arithmetic

The RGB-output bundle provides five two-argument, parameter-free arithmetic
operators. All work independently at every pixel and color channel and return
the exact specialized `H×W×3` RGB type.

| Function | Result |
|:--|:--|
| `add_img3D(a, b)` | `clamp(a + b, 0, 1)` |
| `subtract_img3D(a, b)` | `clamp(a - b, 0, 1)` |
| `mult_img3D(a, b)` | `a * b` |
| `max_img3D(a, b)` | channelwise maximum |
| `min_img3D(a, b)` | channelwise minimum |

For example, this combines the RGB input above with a uniform RGB image and
shows the first output triplet from each operation:

```@example rgb_types
other_rgb = SImageND(IntensityPixel{N0f8}.(fill(0.25, 2, 2, 3)))
rgb_bundle = bundle_image3DIntensity_rgb_factory

function first_triplet(name)
    fn = rgb_bundle[name].fn(typeof(rgb))
    # The factory defines a specialized method during this example block.
    result = Base.invokelatest(fn, rgb, other_rgb)
    values = Float64.(reinterpret(result.img))
    return values[1, 1, :]
end

[(name, first_triplet(name)) for name in
    (:add_img3D, :subtract_img3D, :mult_img3D, :max_img3D, :min_img3D)]
```

## Unary RGB transforms

These one-argument, parameter-free functions also preserve the specialized RGB
type:

| Function | Result |
|:--|:--|
| `invert_rgb(rgb)` | replaces each channel `x` with `1-x` |
| `grayscale_rgb(rgb)` | replicates Rec. 709 luminance into R, G, and B |
| `keep_red_rgb(rgb)` | retains red; sets green and blue to zero |
| `keep_green_rgb(rgb)` | retains green; sets red and blue to zero |
| `keep_blue_rgb(rgb)` | retains blue; sets red and green to zero |
| `rotate_channels_left_rgb(rgb)` | maps `(R,G,B)` to `(G,B,R)` |
| `rotate_channels_right_rgb(rgb)` | maps `(R,G,B)` to `(B,R,G)` |

## Parameterized RGB adjustments

Each adjustment has two MAGE arguments—the RGB image and one `Real` value—and
returns RGB. Inputs outside the documented range are clamped. `NaN` and
infinite parameters select the identity behavior, except brightness where they
select an offset of zero, which is also identity.

| Function | Parameter | Meaning |
|:--|:--|:--|
| `adjust_brightness_rgb(rgb, amount)` | `amount ∈ [-1,1]` | adds `amount` to every channel; `0` is identity |
| `adjust_contrast_rgb(rgb, factor)` | `factor ∈ [0,4]` | scales distance from `0.5`; `1` is identity |
| `adjust_saturation_rgb(rgb, factor)` | `factor ∈ [0,4]` | scales distance from luminance; `0` is grayscale and `1` is identity |
| `adjust_gamma_rgb(rgb, gamma)` | `gamma ∈ [0.1,5]` | computes `channel^gamma`; `1` is identity |

## Coffee example: inputs and outputs

The input below is the `coffee.png` image distributed by
[JuliaImages/TestImages.jl](https://github.com/JuliaImages/TestImages.jl).

```@setup rgb_gallery
using UTCGP
using FileIO
using Images
using ImageCore: N0f8

repo_root = normpath(joinpath(dirname(pathof(UTCGP)), ".."))
color_input = RGB.(load(joinpath(repo_root, "assets", "coffee.png")))
channel_first = Float64.(channelview(color_input))
channel_last = permutedims(channel_first, (2, 3, 1))
rgb_input = SImageND(IntensityPixel{N0f8}.(channel_last))
h, w, _ = size(rgb_input)
intensity_type = typeof(SImageND(IntensityPixel{N0f8}.(zeros(h, w))))

assets_src = joinpath(repo_root, "docs", "src", "assets", "fns", "color_statistics_rgb")
assets_build = joinpath(repo_root, "docs", "build", "assets", "fns", "color_statistics_rgb")
mkpath(assets_src)
mkpath(assets_build)

function save_rgb_gallery(name, image)
    for directory in (assets_src, assets_build)
        save(joinpath(directory, name), image)
    end
    return nothing
end

save_rgb_gallery("coffee_rgb.png", color_input)
for name in (
        :rgb_luminance,
        :red_green_opponency,
        :blue_yellow_opponency,
        :rgb_saturation,
        :normalized_red,
        :normalized_green,
        :normalized_blue,
    )
    fn = bundle_image2DIntensity_color_statistics_rgb_factory[name].fn(intensity_type)
    result = fn(rgb_input)
    save_rgb_gallery("$(name).png", Gray.(reinterpret(result.img)))
end

rgb_bundle = bundle_image3DIntensity_rgb_factory
unary_names = (
    :invert_rgb,
    :grayscale_rgb,
    :keep_red_rgb,
    :keep_green_rgb,
    :keep_blue_rgb,
    :rotate_channels_left_rgb,
    :rotate_channels_right_rgb,
)
adjustment_names = (
    :adjust_brightness_rgb,
    :adjust_contrast_rgb,
    :adjust_saturation_rgb,
    :adjust_gamma_rgb,
)
rgb_fns = Dict(
    name => rgb_bundle[name].fn(typeof(rgb_input))
    for name in (unary_names..., adjustment_names...)
)

function save_rgb_result(filename, result)
    values = reinterpret(result.img)
    rendered = RGB.(values[:, :, 1], values[:, :, 2], values[:, :, 3])
    save_rgb_gallery(filename, rendered)
end

for name in unary_names
    result = Base.invokelatest(rgb_fns[name], rgb_input)
    save_rgb_result("$(name).png", result)
end

adjustment_variants = (
    (:adjust_brightness_rgb, -0.3, "brightness_minus_0_3.png"),
    (:adjust_brightness_rgb, 0.0, "brightness_0.png"),
    (:adjust_brightness_rgb, 0.3, "brightness_plus_0_3.png"),
    (:adjust_contrast_rgb, 0.5, "contrast_0_5.png"),
    (:adjust_contrast_rgb, 1.0, "contrast_1.png"),
    (:adjust_contrast_rgb, 2.0, "contrast_2.png"),
    (:adjust_saturation_rgb, 0.0, "saturation_0.png"),
    (:adjust_saturation_rgb, 1.0, "saturation_1.png"),
    (:adjust_saturation_rgb, 2.0, "saturation_2.png"),
    (:adjust_gamma_rgb, 0.5, "gamma_0_5.png"),
    (:adjust_gamma_rgb, 1.0, "gamma_1.png"),
    (:adjust_gamma_rgb, 2.0, "gamma_2.png"),
)
for (name, parameter, filename) in adjustment_variants
    result = Base.invokelatest(rgb_fns[name], rgb_input, parameter)
    save_rgb_result(filename, result)
end

luminance_fn = bundle_image2DIntensity_color_statistics_rgb_factory[:rgb_luminance].fn(intensity_type)
luminance_values = reinterpret(luminance_fn(rgb_input).img)
bright_mask = SImageND(BinaryPixel{Bool}.(luminance_values .>= 0.5))
mult_rgb = bundle_image3DIntensity_rgb_factory[:mult_image3D].fn(typeof(rgb_input))
masked_rgb = reinterpret(mult_rgb(rgb_input, bright_mask).img)
save_rgb_gallery(
    "coffee_masked_rgb.png",
    RGB.(masked_rgb[:, :, 1], masked_rgb[:, :, 2], masked_rgb[:, :, 3]),
)
```

```@raw html
<div style="display:flex; gap:1rem; flex-wrap:wrap; align-items:flex-start;">
<figure style="width:30%; margin:0;"><img src="../assets/fns/color_statistics_rgb/coffee_rgb.png" alt="Coffee RGB input" style="width:100%;" /><figcaption>RGB input</figcaption></figure>
<figure style="width:30%; margin:0;"><img src="../assets/fns/color_statistics_rgb/rgb_luminance.png" alt="Coffee luminance" style="width:100%;" /><figcaption><code>rgb_luminance</code></figcaption></figure>
<figure style="width:30%; margin:0;"><img src="../assets/fns/color_statistics_rgb/rgb_saturation.png" alt="Coffee saturation" style="width:100%;" /><figcaption><code>rgb_saturation</code></figcaption></figure>
<figure style="width:30%; margin:0;"><img src="../assets/fns/color_statistics_rgb/red_green_opponency.png" alt="Coffee red green opponency" style="width:100%;" /><figcaption><code>red_green_opponency</code></figcaption></figure>
<figure style="width:30%; margin:0;"><img src="../assets/fns/color_statistics_rgb/blue_yellow_opponency.png" alt="Coffee blue yellow opponency" style="width:100%;" /><figcaption><code>blue_yellow_opponency</code></figcaption></figure>
<figure style="width:30%; margin:0;"><img src="../assets/fns/color_statistics_rgb/normalized_red.png" alt="Coffee normalized red" style="width:100%;" /><figcaption><code>normalized_red</code></figcaption></figure>
<figure style="width:30%; margin:0;"><img src="../assets/fns/color_statistics_rgb/normalized_green.png" alt="Coffee normalized green" style="width:100%;" /><figcaption><code>normalized_green</code></figcaption></figure>
<figure style="width:30%; margin:0;"><img src="../assets/fns/color_statistics_rgb/normalized_blue.png" alt="Coffee normalized blue" style="width:100%;" /><figcaption><code>normalized_blue</code></figcaption></figure>
</div>
```

### Unary RGB input/output examples

```@raw html
<div style="display:flex; gap:1rem; flex-wrap:wrap; align-items:flex-start;">
<figure style="width:22%; margin:0;"><img src="../assets/fns/color_statistics_rgb/coffee_rgb.png" alt="Coffee RGB input" style="width:100%;" /><figcaption>RGB input</figcaption></figure>
<figure style="width:22%; margin:0;"><img src="../assets/fns/color_statistics_rgb/invert_rgb.png" alt="Inverted coffee RGB" style="width:100%;" /><figcaption><code>invert_rgb</code></figcaption></figure>
<figure style="width:22%; margin:0;"><img src="../assets/fns/color_statistics_rgb/grayscale_rgb.png" alt="Grayscale coffee stored as RGB" style="width:100%;" /><figcaption><code>grayscale_rgb</code></figcaption></figure>
<figure style="width:22%; margin:0;"><img src="../assets/fns/color_statistics_rgb/keep_red_rgb.png" alt="Coffee red channel retained in RGB" style="width:100%;" /><figcaption><code>keep_red_rgb</code></figcaption></figure>
<figure style="width:22%; margin:0;"><img src="../assets/fns/color_statistics_rgb/keep_green_rgb.png" alt="Coffee green channel retained in RGB" style="width:100%;" /><figcaption><code>keep_green_rgb</code></figcaption></figure>
<figure style="width:22%; margin:0;"><img src="../assets/fns/color_statistics_rgb/keep_blue_rgb.png" alt="Coffee blue channel retained in RGB" style="width:100%;" /><figcaption><code>keep_blue_rgb</code></figcaption></figure>
<figure style="width:22%; margin:0;"><img src="../assets/fns/color_statistics_rgb/rotate_channels_left_rgb.png" alt="Coffee RGB channels rotated left" style="width:100%;" /><figcaption><code>rotate_channels_left_rgb</code></figcaption></figure>
<figure style="width:22%; margin:0;"><img src="../assets/fns/color_statistics_rgb/rotate_channels_right_rgb.png" alt="Coffee RGB channels rotated right" style="width:100%;" /><figcaption><code>rotate_channels_right_rgb</code></figcaption></figure>
</div>
```

### Brightness parameters

```@raw html
<div style="display:flex; gap:1rem; flex-wrap:wrap; align-items:flex-start;">
<figure style="width:30%; margin:0;"><img src="../assets/fns/color_statistics_rgb/brightness_minus_0_3.png" alt="Coffee brightness minus 0.3" style="width:100%;" /><figcaption><code>amount = -0.3</code></figcaption></figure>
<figure style="width:30%; margin:0;"><img src="../assets/fns/color_statistics_rgb/brightness_0.png" alt="Coffee brightness unchanged" style="width:100%;" /><figcaption><code>amount = 0</code></figcaption></figure>
<figure style="width:30%; margin:0;"><img src="../assets/fns/color_statistics_rgb/brightness_plus_0_3.png" alt="Coffee brightness plus 0.3" style="width:100%;" /><figcaption><code>amount = 0.3</code></figcaption></figure>
</div>
```

### Contrast parameters

```@raw html
<div style="display:flex; gap:1rem; flex-wrap:wrap; align-items:flex-start;">
<figure style="width:30%; margin:0;"><img src="../assets/fns/color_statistics_rgb/contrast_0_5.png" alt="Coffee contrast factor 0.5" style="width:100%;" /><figcaption><code>factor = 0.5</code></figcaption></figure>
<figure style="width:30%; margin:0;"><img src="../assets/fns/color_statistics_rgb/contrast_1.png" alt="Coffee contrast factor 1" style="width:100%;" /><figcaption><code>factor = 1</code></figcaption></figure>
<figure style="width:30%; margin:0;"><img src="../assets/fns/color_statistics_rgb/contrast_2.png" alt="Coffee contrast factor 2" style="width:100%;" /><figcaption><code>factor = 2</code></figcaption></figure>
</div>
```

### Saturation parameters

```@raw html
<div style="display:flex; gap:1rem; flex-wrap:wrap; align-items:flex-start;">
<figure style="width:30%; margin:0;"><img src="../assets/fns/color_statistics_rgb/saturation_0.png" alt="Coffee saturation factor 0" style="width:100%;" /><figcaption><code>factor = 0</code></figcaption></figure>
<figure style="width:30%; margin:0;"><img src="../assets/fns/color_statistics_rgb/saturation_1.png" alt="Coffee saturation factor 1" style="width:100%;" /><figcaption><code>factor = 1</code></figcaption></figure>
<figure style="width:30%; margin:0;"><img src="../assets/fns/color_statistics_rgb/saturation_2.png" alt="Coffee saturation factor 2" style="width:100%;" /><figcaption><code>factor = 2</code></figcaption></figure>
</div>
```

### Gamma parameters

```@raw html
<div style="display:flex; gap:1rem; flex-wrap:wrap; align-items:flex-start;">
<figure style="width:30%; margin:0;"><img src="../assets/fns/color_statistics_rgb/gamma_0_5.png" alt="Coffee gamma 0.5" style="width:100%;" /><figcaption><code>gamma = 0.5</code></figcaption></figure>
<figure style="width:30%; margin:0;"><img src="../assets/fns/color_statistics_rgb/gamma_1.png" alt="Coffee gamma 1" style="width:100%;" /><figcaption><code>gamma = 1</code></figcaption></figure>
<figure style="width:30%; margin:0;"><img src="../assets/fns/color_statistics_rgb/gamma_2.png" alt="Coffee gamma 2" style="width:100%;" /><figcaption><code>gamma = 2</code></figcaption></figure>
</div>
```

## Masking RGB with a binary image

`mult_image3D(rgb, binary_mask)` is the RGB counterpart of the existing 2D
`mult_image2D` operation. It has two MAGE arguments. A white mask pixel retains
the complete RGB triplet; a black pixel produces black in all three channels.
An all-black mask returns a valid, all-black RGB image of the specialized type,
never `nothing`.

```@raw html
<div style="display:flex; gap:1rem; align-items:flex-start;">
<figure style="width:40%; margin:0;"><img src="../assets/fns/color_statistics_rgb/coffee_rgb.png" alt="Coffee RGB input before masking" style="width:100%;" /><figcaption>RGB input</figcaption></figure>
<figure style="width:40%; margin:0;"><img src="../assets/fns/color_statistics_rgb/coffee_masked_rgb.png" alt="Coffee RGB masked by luminance" style="width:100%;" /><figcaption><code>mult_image3D(rgb, luminance ≥ 0.5)</code></figcaption></figure>
</div>
```

```@docs
UTCGP.image3D_color_statistics_rgb
UTCGP.image3D_color_statistics_rgb.bundle_image2DIntensity_color_statistics_rgb_factory
UTCGP.image3D_color_statistics_rgb.rgb_luminance_image2D_factory
UTCGP.image3D_color_statistics_rgb.red_green_opponency_image2D_factory
UTCGP.image3D_color_statistics_rgb.blue_yellow_opponency_image2D_factory
UTCGP.image3D_color_statistics_rgb.rgb_saturation_image2D_factory
UTCGP.image3D_color_statistics_rgb.normalized_red_image2D_factory
UTCGP.image3D_color_statistics_rgb.normalized_green_image2D_factory
UTCGP.image3D_color_statistics_rgb.normalized_blue_image2D_factory
UTCGP.image3D_rgb
UTCGP.image3D_rgb.bundle_image3DIntensity_rgb_factory
UTCGP.image3D_rgb.identity_rgb_image3D_factory
UTCGP.image3D_rgb.return_rgb_image3D_factory
UTCGP.image3D_rgb.add_image3D_factory
UTCGP.image3D_rgb.subtract_image3D_factory
UTCGP.image3D_rgb.mult_rgb_image3D_factory
UTCGP.image3D_rgb.max_image3D_factory
UTCGP.image3D_rgb.min_image3D_factory
UTCGP.image3D_rgb.invert_rgb_image3D_factory
UTCGP.image3D_rgb.grayscale_rgb_image3D_factory
UTCGP.image3D_rgb.keep_red_rgb_image3D_factory
UTCGP.image3D_rgb.keep_green_rgb_image3D_factory
UTCGP.image3D_rgb.keep_blue_rgb_image3D_factory
UTCGP.image3D_rgb.rotate_channels_left_rgb_image3D_factory
UTCGP.image3D_rgb.rotate_channels_right_rgb_image3D_factory
UTCGP.image3D_rgb.adjust_brightness_rgb_image3D_factory
UTCGP.image3D_rgb.adjust_contrast_rgb_image3D_factory
UTCGP.image3D_rgb.adjust_saturation_rgb_image3D_factory
UTCGP.image3D_rgb.adjust_gamma_rgb_image3D_factory
UTCGP.image3D_rgb.mult_image3D_factory
```
