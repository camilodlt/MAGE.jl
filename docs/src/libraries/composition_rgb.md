```@meta
CurrentModule = UTCGP
```

# RGB Composition

`bundle_image3DIntensity_rgb_composition_factory` closes the typed path from
MAGE's 2D intensity chromosome back to its RGB chromosome. It lets independently
evolved red, green, and blue planes become an RGB image and lets an evolved
intensity map control a channel, a continuous mask, a spatial blend, or output
luminance.

## Bundle contract

| Property | Contract |
|:--|:--|
| Getter | `get_extension_rgb_compositionimg()` |
| Specialization | `I <: SizedImage3D{H,W,3,IntensityPixel{T}}` |
| 2D inputs | same-size `SImage2D{H,W,IntensityPixel{U}}`; underlying numeric types may differ |
| RGB inputs | exactly the specialized type `I` |
| Output | exactly `I`, with the same size and finite values in `[0,1]` |
| MAGE arity | 1, 2, or 3; never more than 3 |
| Invalid control pixels | finite values are clamped to `[0,1]`; `NaN` and infinities become zero |

This is an extension bundle. It deliberately does not duplicate `identity_rgb`
or `return_rgb`; add it after the basic RGB bundle:

```@example rgb_composition_setup
using UTCGP
using ImageCore: N0f8

rgb = SImageND(IntensityPixel{N0f8}.(rand(32, 32, 3)))
rgb_type = typeof(rgb)

basic_rgb_bundle = only(get_extension_rgbimg())
composition_bundle = only(get_extension_rgb_compositionimg())

basic_rgb_bundle[1].name, basic_rgb_bundle[2].name, length(composition_bundle)
```

Both bundles are factory bundles and must be specialized with `rgb_type` before
being inserted into the RGB-output `Library`.

## Operators

| Function | Inputs | Result |
|:--|:--|:--|
| `compose_rgb(red, green, blue)` | three intensity planes | places them in RGB channel order |
| `gray_to_rgb(gray)` | one intensity plane | repeats it in all three channels |
| `replace_red_rgb(rgb, red)` | RGB plus intensity plane | replaces only red |
| `replace_green_rgb(rgb, green)` | RGB plus intensity plane | replaces only green |
| `replace_blue_rgb(rgb, blue)` | RGB plus intensity plane | replaces only blue |
| `multiply_rgb_intensity(rgb, mask)` | RGB plus intensity map | continuously multiplies every channel by the map |
| `alpha_blend_rgb(foreground, background, alpha)` | two RGB images plus intensity map | `alpha*foreground + (1-alpha)*background` |
| `set_luminance_rgb(rgb, luminance)` | RGB plus target intensity map | adds a common channel offset to replace Rec. 709 luminance, with clipping |

These operators have image operands rather than scalar parameters. The examples
below therefore vary the operand maps. A binary-valued intensity map is valid,
but retaining it as an intensity image also permits soft boundaries.

## Coffee input and operand examples

```@setup rgb_composition_gallery
using UTCGP
using FileIO
using Images
using ImageCore: N0f8

repo_root = normpath(joinpath(dirname(pathof(UTCGP)), ".."))
full_input = RGB.(load(joinpath(repo_root, "assets", "coffee.png")))
color_input = full_input[1:2:end, 1:2:end]
channel_last = permutedims(Float64.(channelview(color_input)), (2, 3, 1))
rgb_input = SImageND(IntensityPixel{N0f8}.(channel_last))
h, w, _ = size(rgb_input)

plane(values) = SImageND(IntensityPixel{N0f8}.(clamp.(values, 0.0, 1.0)))
red = plane(channel_last[:, :, 1])
green = plane(channel_last[:, :, 2])
blue = plane(channel_last[:, :, 3])
luminance_values = 0.2126 .* channel_last[:, :, 1] .+
    0.7152 .* channel_last[:, :, 2] .+ 0.0722 .* channel_last[:, :, 3]
luminance = plane(luminance_values)

row_center = (h + 1) / 2
col_center = (w + 1) / 2
max_radius = hypot(max(row_center - 1, h - row_center),
    max(col_center - 1, w - col_center))
radial_values = [
    clamp(1.0 - hypot(row - row_center, col - col_center) / max_radius, 0.0, 1.0)
    for row in 1:h, col in 1:w
]
radial_mask = plane(radial_values)
horizontal_alpha = plane(repeat(reshape(range(0.0, 1.0; length = w), 1, w), h, 1))
zero_map = plane(zeros(h, w))
dark_luminance = plane(fill(0.25, h, w))
bright_luminance = plane(fill(0.75, h, w))

bundle = bundle_image3DIntensity_rgb_composition_factory
names = (
    :compose_rgb,
    :gray_to_rgb,
    :replace_red_rgb,
    :replace_green_rgb,
    :replace_blue_rgb,
    :multiply_rgb_intensity,
    :alpha_blend_rgb,
    :set_luminance_rgb,
)
functions = Dict(name => bundle[name].fn(typeof(rgb_input)) for name in names)

assets_src = joinpath(repo_root, "docs", "src", "assets", "fns", "composition_rgb")
assets_build = joinpath(repo_root, "docs", "build", "assets", "fns", "composition_rgb")
mkpath(assets_src)
mkpath(assets_build)

function save_composition_image(filename, image)
    for directory in (assets_src, assets_build)
        save(joinpath(directory, filename), image)
    end
end

function render_rgb(filename, result)
    values = reinterpret(result.img)
    rendered = RGB.(values[:, :, 1], values[:, :, 2], values[:, :, 3])
    save_composition_image(filename, rendered)
end

function render_map(filename, map)
    save_composition_image(filename, Gray.(reinterpret(map.img)))
end

save_composition_image("input.png", color_input)
render_map("luminance_map.png", luminance)
render_map("radial_mask.png", radial_mask)
render_map("horizontal_alpha.png", horizontal_alpha)

compose = functions[:compose_rgb]
render_rgb("compose_original.png", Base.invokelatest(compose, red, green, blue))
render_rgb("compose_permuted.png", Base.invokelatest(compose, blue, red, green))
render_rgb("compose_blue_only.png", Base.invokelatest(compose, zero_map, zero_map, blue))

render_rgb("gray_luminance.png", Base.invokelatest(functions[:gray_to_rgb], luminance))
render_rgb("replace_red.png", Base.invokelatest(functions[:replace_red_rgb], rgb_input, luminance))
render_rgb("replace_green.png", Base.invokelatest(functions[:replace_green_rgb], rgb_input, luminance))
render_rgb("replace_blue.png", Base.invokelatest(functions[:replace_blue_rgb], rgb_input, luminance))

render_rgb("masked_luminance.png",
    Base.invokelatest(functions[:multiply_rgb_intensity], rgb_input, luminance))
render_rgb("masked_radial.png",
    Base.invokelatest(functions[:multiply_rgb_intensity], rgb_input, radial_mask))
render_rgb("masked_zero.png",
    Base.invokelatest(functions[:multiply_rgb_intensity], rgb_input, zero_map))

rotated_channels = Base.invokelatest(compose, blue, red, green)
render_rgb("blend_horizontal.png",
    Base.invokelatest(functions[:alpha_blend_rgb], rgb_input, rotated_channels,
        horizontal_alpha))

render_rgb("luminance_dark.png",
    Base.invokelatest(functions[:set_luminance_rgb], rgb_input, dark_luminance))
render_rgb("luminance_original.png",
    Base.invokelatest(functions[:set_luminance_rgb], rgb_input, luminance))
render_rgb("luminance_bright.png",
    Base.invokelatest(functions[:set_luminance_rgb], rgb_input, bright_luminance))
```

### Constructing RGB from three planes

The first result reconstructs the source. The other two demonstrate that each
input is an ordinary evolved intensity image: channels can be permuted,
filtered, masked, or replaced before composition.

```@raw html
<div style="display:flex; gap:1rem; flex-wrap:wrap;">
<figure style="width:22%; margin:0;"><img src="../assets/fns/composition_rgb/input.png" alt="Coffee RGB input" style="width:100%;" /><figcaption>RGB input</figcaption></figure>
<figure style="width:22%; margin:0;"><img src="../assets/fns/composition_rgb/compose_original.png" alt="RGB recomposed from source channels" style="width:100%;" /><figcaption><code>compose_rgb(R,G,B)</code></figcaption></figure>
<figure style="width:22%; margin:0;"><img src="../assets/fns/composition_rgb/compose_permuted.png" alt="RGB composed from permuted channels" style="width:100%;" /><figcaption><code>compose_rgb(B,R,G)</code></figcaption></figure>
<figure style="width:22%; margin:0;"><img src="../assets/fns/composition_rgb/compose_blue_only.png" alt="RGB composed with only blue" style="width:100%;" /><figcaption><code>compose_rgb(0,0,B)</code></figcaption></figure>
</div>
```

### Replicating and replacing planes

```@raw html
<div style="display:flex; gap:1rem; flex-wrap:wrap;">
<figure style="width:22%; margin:0;"><img src="../assets/fns/composition_rgb/luminance_map.png" alt="Luminance control map" style="width:100%;" /><figcaption>luminance operand</figcaption></figure>
<figure style="width:22%; margin:0;"><img src="../assets/fns/composition_rgb/gray_luminance.png" alt="Luminance repeated as RGB" style="width:100%;" /><figcaption><code>gray_to_rgb(Y)</code></figcaption></figure>
<figure style="width:22%; margin:0;"><img src="../assets/fns/composition_rgb/replace_red.png" alt="Red replaced by luminance" style="width:100%;" /><figcaption><code>replace_red_rgb(rgb,Y)</code></figcaption></figure>
<figure style="width:22%; margin:0;"><img src="../assets/fns/composition_rgb/replace_green.png" alt="Green replaced by luminance" style="width:100%;" /><figcaption><code>replace_green_rgb(rgb,Y)</code></figcaption></figure>
<figure style="width:22%; margin:0;"><img src="../assets/fns/composition_rgb/replace_blue.png" alt="Blue replaced by luminance" style="width:100%;" /><figcaption><code>replace_blue_rgb(rgb,Y)</code></figcaption></figure>
</div>
```

### Continuous masks and alpha blending

An all-zero intensity mask returns an all-black image of the specialized RGB
type. It never returns `nothing` or a 2D image.

```@raw html
<div style="display:flex; gap:1rem; flex-wrap:wrap;">
<figure style="width:22%; margin:0;"><img src="../assets/fns/composition_rgb/radial_mask.png" alt="Soft radial mask" style="width:100%;" /><figcaption>radial mask</figcaption></figure>
<figure style="width:22%; margin:0;"><img src="../assets/fns/composition_rgb/masked_luminance.png" alt="RGB continuously masked by luminance" style="width:100%;" /><figcaption><code>multiply_rgb_intensity(rgb,Y)</code></figcaption></figure>
<figure style="width:22%; margin:0;"><img src="../assets/fns/composition_rgb/masked_radial.png" alt="RGB continuously masked radially" style="width:100%;" /><figcaption><code>multiply_rgb_intensity(rgb,radial)</code></figcaption></figure>
<figure style="width:22%; margin:0;"><img src="../assets/fns/composition_rgb/masked_zero.png" alt="RGB masked by all-zero intensity" style="width:100%;" /><figcaption>all-zero mask → RGB black</figcaption></figure>
<figure style="width:22%; margin:0;"><img src="../assets/fns/composition_rgb/horizontal_alpha.png" alt="Horizontal alpha map" style="width:100%;" /><figcaption>alpha operand</figcaption></figure>
<figure style="width:22%; margin:0;"><img src="../assets/fns/composition_rgb/blend_horizontal.png" alt="Spatial blend of two RGB images" style="width:100%;" /><figcaption><code>alpha_blend_rgb</code></figcaption></figure>
</div>
```

### Replacing luminance

The common channel offset preserves colour differences until clipping at zero
or one becomes necessary. The middle example uses the source's own luminance
and therefore reconstructs it up to pixel quantization.

```@raw html
<div style="display:flex; gap:1rem; flex-wrap:wrap;">
<figure style="width:30%; margin:0;"><img src="../assets/fns/composition_rgb/luminance_dark.png" alt="RGB with target luminance 0.25" style="width:100%;" /><figcaption>target luminance 0.25</figcaption></figure>
<figure style="width:30%; margin:0;"><img src="../assets/fns/composition_rgb/luminance_original.png" alt="RGB with original luminance map" style="width:100%;" /><figcaption>source luminance map</figcaption></figure>
<figure style="width:30%; margin:0;"><img src="../assets/fns/composition_rgb/luminance_bright.png" alt="RGB with target luminance 0.75" style="width:100%;" /><figcaption>target luminance 0.75</figcaption></figure>
</div>
```

## API

```@docs
UTCGP.image3D_rgb_composition
UTCGP.image3D_rgb_composition.bundle_image3DIntensity_rgb_composition_factory
UTCGP.image3D_rgb_composition.compose_rgb_image3D_factory
UTCGP.image3D_rgb_composition.gray_to_rgb_image3D_factory
UTCGP.image3D_rgb_composition.replace_red_rgb_image3D_factory
UTCGP.image3D_rgb_composition.replace_green_rgb_image3D_factory
UTCGP.image3D_rgb_composition.replace_blue_rgb_image3D_factory
UTCGP.image3D_rgb_composition.multiply_rgb_intensity_image3D_factory
UTCGP.image3D_rgb_composition.alpha_blend_rgb_image3D_factory
UTCGP.image3D_rgb_composition.set_luminance_rgb_image3D_factory
```
