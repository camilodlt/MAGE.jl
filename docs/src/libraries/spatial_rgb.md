```@meta
CurrentModule = UTCGP
```

# Spatial RGB Features

`bundle_image3DIntensity_spatial_rgb_factory` provides fixed, training-free
spatial features for small RGB images such as CIFAR-10. Every function processes
R, G, and B independently, uses reflected boundaries, and returns an RGB image
with the exact specialized size and pixel type.

## Bundle contract

| Property | Contract |
|:--|:--|
| Getter | `get_extension_spatial_rgbimg()` |
| Specialization | `I <: SizedImage3D{H,W,3,IntensityPixel{T}}` |
| Input | one RGB image of type `I`, followed by at most two `Real` parameters |
| Output | exactly `I`, finite and bounded to `[0,1]` |
| MAGE arity | between 1 and 3 |
| Boundary handling | reflection |

This is an extension bundle, so it does not repeat `identity_rgb` or
`return_rgb`. Place it after the basic RGB bundle:

```@example spatial_rgb_setup
using UTCGP
using ImageCore: N0f8

rgb = SImageND(IntensityPixel{N0f8}.(rand(32, 32, 3)))
rgb_type = typeof(rgb)

basic_rgb_bundle = only(get_extension_rgbimg())
spatial_rgb_bundle = only(get_extension_spatial_rgbimg())

basic_rgb_bundle[1].name, basic_rgb_bundle[2].name, length(spatial_rgb_bundle)
```

Both factory bundles must be specialized with `rgb_type` before being placed in
the RGB output library.

## Operators and parameters

| Function | Parameters | Result |
|:--|:--|:--|
| `sobel_magnitude_rgb(rgb)` | none | normalized channelwise gradient magnitude |
| `laplacian_magnitude_rgb(rgb)` | none | normalized absolute second derivative |
| `gaussian_blur_rgb(rgb, sigma)` | `sigma ∈ [0.3,4]` | Gaussian smoothing |
| `difference_of_gaussians_rgb(rgb, sigma1, sigma2)` | both in `[0.3,4]` | normalized absolute band-pass response; order-independent |
| `unsharp_mask_rgb(rgb, sigma, amount)` | `sigma ∈ [0.3,4]`, `amount ∈ [0,3]` | `rgb + amount*(rgb-blur)` |
| `local_contrast_normalize_rgb(rgb, radius)` | integer radius in `[1,5]` | local signed contrast mapped around `0.5` |
| `local_std_rgb(rgb, radius)` | integer radius in `[1,5]` | normalized local texture energy |
| `gabor_energy_rgb(rgb, orientation, wavelength)` | orientation modulo `π`, wavelength in `[2,8]` | phase-independent oriented texture energy |

Finite parameters are clamped to the ranges above. Non-finite parameters use
documented neutral defaults: Gaussian `1`, DoG `(0.8,1.6)`, unsharp `(1,1)`,
local radius `3`, and Gabor `(0,4)`.

## Coffee input and parameter examples

The examples use a half-resolution copy of `coffee.png` so the page exercises
the same implementation while remaining quick to build.

```@setup spatial_rgb_gallery
using UTCGP
using FileIO
using Images
using ImageCore: N0f8

repo_root = normpath(joinpath(dirname(pathof(UTCGP)), ".."))
full_color_input = RGB.(load(joinpath(repo_root, "assets", "coffee.png")))
color_input = full_color_input[1:2:end, 1:2:end]
channel_last = permutedims(Float64.(channelview(color_input)), (2, 3, 1))
rgb_input = SImageND(IntensityPixel{N0f8}.(channel_last))
bundle = bundle_image3DIntensity_spatial_rgb_factory
names = (
    :sobel_magnitude_rgb,
    :laplacian_magnitude_rgb,
    :gaussian_blur_rgb,
    :difference_of_gaussians_rgb,
    :unsharp_mask_rgb,
    :local_contrast_normalize_rgb,
    :local_std_rgb,
    :gabor_energy_rgb,
)
functions = Dict(name => bundle[name].fn(typeof(rgb_input)) for name in names)

assets_src = joinpath(repo_root, "docs", "src", "assets", "fns", "spatial_rgb")
assets_build = joinpath(repo_root, "docs", "build", "assets", "fns", "spatial_rgb")
mkpath(assets_src)
mkpath(assets_build)

function save_spatial_rgb(filename, image)
    for directory in (assets_src, assets_build)
        save(joinpath(directory, filename), image)
    end
end

function render_spatial_rgb(filename, name, arguments...)
    result = Base.invokelatest(functions[name], rgb_input, arguments...)
    values = reinterpret(result.img)
    rendered = RGB.(values[:, :, 1], values[:, :, 2], values[:, :, 3])
    save_spatial_rgb(filename, rendered)
end

save_spatial_rgb("input.png", color_input)
render_spatial_rgb("sobel.png", :sobel_magnitude_rgb)
render_spatial_rgb("laplacian.png", :laplacian_magnitude_rgb)

for (sigma, filename) in (
        (0.5, "gaussian_0_5.png"),
        (1.5, "gaussian_1_5.png"),
        (3.0, "gaussian_3.png"),
    )
    render_spatial_rgb(filename, :gaussian_blur_rgb, sigma)
end

for (sigma1, sigma2, filename) in (
        (0.5, 1.0, "dog_0_5_1.png"),
        (1.0, 2.0, "dog_1_2.png"),
        (2.0, 4.0, "dog_2_4.png"),
    )
    render_spatial_rgb(filename, :difference_of_gaussians_rgb, sigma1, sigma2)
end

for (sigma, amount, filename) in (
        (1.0, 0.0, "unsharp_1_0.png"),
        (0.5, 1.0, "unsharp_0_5_1.png"),
        (1.5, 1.0, "unsharp_1_5_1.png"),
        (1.0, 2.5, "unsharp_1_2_5.png"),
    )
    render_spatial_rgb(filename, :unsharp_mask_rgb, sigma, amount)
end

for radius in (1, 3, 5)
    render_spatial_rgb("local_contrast_$(radius).png", :local_contrast_normalize_rgb, radius)
    render_spatial_rgb("local_std_$(radius).png", :local_std_rgb, radius)
end

for (orientation, filename) in (
        (0.0, "gabor_o_0.png"),
        (π / 4, "gabor_o_pi4.png"),
        (π / 2, "gabor_o_pi2.png"),
    )
    render_spatial_rgb(filename, :gabor_energy_rgb, orientation, 4.0)
end
for (wavelength, filename) in (
        (2.0, "gabor_w_2.png"),
        (4.0, "gabor_w_4.png"),
        (8.0, "gabor_w_8.png"),
    )
    render_spatial_rgb(filename, :gabor_energy_rgb, π / 4, wavelength)
end
```

### Parameter-free edges

```@raw html
<div style="display:flex; gap:1rem; flex-wrap:wrap;">
<figure style="width:30%; margin:0;"><img src="../assets/fns/spatial_rgb/input.png" alt="Coffee RGB input" style="width:100%;" /><figcaption>RGB input</figcaption></figure>
<figure style="width:30%; margin:0;"><img src="../assets/fns/spatial_rgb/sobel.png" alt="Channelwise Sobel magnitude" style="width:100%;" /><figcaption><code>sobel_magnitude_rgb</code></figcaption></figure>
<figure style="width:30%; margin:0;"><img src="../assets/fns/spatial_rgb/laplacian.png" alt="Channelwise Laplacian magnitude" style="width:100%;" /><figcaption><code>laplacian_magnitude_rgb</code></figcaption></figure>
</div>
```

### Gaussian scale

```@raw html
<div style="display:flex; gap:1rem; flex-wrap:wrap;">
<figure style="width:30%; margin:0;"><img src="../assets/fns/spatial_rgb/gaussian_0_5.png" alt="Gaussian sigma 0.5" style="width:100%;" /><figcaption><code>sigma = 0.5</code></figcaption></figure>
<figure style="width:30%; margin:0;"><img src="../assets/fns/spatial_rgb/gaussian_1_5.png" alt="Gaussian sigma 1.5" style="width:100%;" /><figcaption><code>sigma = 1.5</code></figcaption></figure>
<figure style="width:30%; margin:0;"><img src="../assets/fns/spatial_rgb/gaussian_3.png" alt="Gaussian sigma 3" style="width:100%;" /><figcaption><code>sigma = 3</code></figcaption></figure>
</div>
```

### Difference-of-Gaussians scales

```@raw html
<div style="display:flex; gap:1rem; flex-wrap:wrap;">
<figure style="width:30%; margin:0;"><img src="../assets/fns/spatial_rgb/dog_0_5_1.png" alt="DoG sigmas 0.5 and 1" style="width:100%;" /><figcaption><code>sigma = (0.5,1)</code></figcaption></figure>
<figure style="width:30%; margin:0;"><img src="../assets/fns/spatial_rgb/dog_1_2.png" alt="DoG sigmas 1 and 2" style="width:100%;" /><figcaption><code>sigma = (1,2)</code></figcaption></figure>
<figure style="width:30%; margin:0;"><img src="../assets/fns/spatial_rgb/dog_2_4.png" alt="DoG sigmas 2 and 4" style="width:100%;" /><figcaption><code>sigma = (2,4)</code></figcaption></figure>
</div>
```

### Unsharp scale and amount

```@raw html
<div style="display:flex; gap:1rem; flex-wrap:wrap;">
<figure style="width:22%; margin:0;"><img src="../assets/fns/spatial_rgb/unsharp_1_0.png" alt="Unsharp amount zero" style="width:100%;" /><figcaption><code>(sigma,amount) = (1,0)</code></figcaption></figure>
<figure style="width:22%; margin:0;"><img src="../assets/fns/spatial_rgb/unsharp_0_5_1.png" alt="Unsharp sigma 0.5 amount 1" style="width:100%;" /><figcaption><code>(0.5,1)</code></figcaption></figure>
<figure style="width:22%; margin:0;"><img src="../assets/fns/spatial_rgb/unsharp_1_5_1.png" alt="Unsharp sigma 1.5 amount 1" style="width:100%;" /><figcaption><code>(1.5,1)</code></figcaption></figure>
<figure style="width:22%; margin:0;"><img src="../assets/fns/spatial_rgb/unsharp_1_2_5.png" alt="Unsharp sigma 1 amount 2.5" style="width:100%;" /><figcaption><code>(1,2.5)</code></figcaption></figure>
</div>
```

### Local window radius

```@raw html
<div style="display:flex; gap:1rem; flex-wrap:wrap;">
<figure style="width:30%; margin:0;"><img src="../assets/fns/spatial_rgb/local_contrast_1.png" alt="Local contrast radius 1" style="width:100%;" /><figcaption><code>local_contrast</code>, radius 1</figcaption></figure>
<figure style="width:30%; margin:0;"><img src="../assets/fns/spatial_rgb/local_contrast_3.png" alt="Local contrast radius 3" style="width:100%;" /><figcaption><code>local_contrast</code>, radius 3</figcaption></figure>
<figure style="width:30%; margin:0;"><img src="../assets/fns/spatial_rgb/local_contrast_5.png" alt="Local contrast radius 5" style="width:100%;" /><figcaption><code>local_contrast</code>, radius 5</figcaption></figure>
<figure style="width:30%; margin:0;"><img src="../assets/fns/spatial_rgb/local_std_1.png" alt="Local standard deviation radius 1" style="width:100%;" /><figcaption><code>local_std</code>, radius 1</figcaption></figure>
<figure style="width:30%; margin:0;"><img src="../assets/fns/spatial_rgb/local_std_3.png" alt="Local standard deviation radius 3" style="width:100%;" /><figcaption><code>local_std</code>, radius 3</figcaption></figure>
<figure style="width:30%; margin:0;"><img src="../assets/fns/spatial_rgb/local_std_5.png" alt="Local standard deviation radius 5" style="width:100%;" /><figcaption><code>local_std</code>, radius 5</figcaption></figure>
</div>
```

### Gabor orientation and wavelength

```@raw html
<div style="display:flex; gap:1rem; flex-wrap:wrap;">
<figure style="width:30%; margin:0;"><img src="../assets/fns/spatial_rgb/gabor_o_0.png" alt="Gabor orientation zero" style="width:100%;" /><figcaption><code>orientation = 0</code>, wavelength 4</figcaption></figure>
<figure style="width:30%; margin:0;"><img src="../assets/fns/spatial_rgb/gabor_o_pi4.png" alt="Gabor orientation pi over four" style="width:100%;" /><figcaption><code>orientation = π/4</code>, wavelength 4</figcaption></figure>
<figure style="width:30%; margin:0;"><img src="../assets/fns/spatial_rgb/gabor_o_pi2.png" alt="Gabor orientation pi over two" style="width:100%;" /><figcaption><code>orientation = π/2</code>, wavelength 4</figcaption></figure>
<figure style="width:30%; margin:0;"><img src="../assets/fns/spatial_rgb/gabor_w_2.png" alt="Gabor wavelength 2" style="width:100%;" /><figcaption><code>wavelength = 2</code>, orientation π/4</figcaption></figure>
<figure style="width:30%; margin:0;"><img src="../assets/fns/spatial_rgb/gabor_w_4.png" alt="Gabor wavelength 4" style="width:100%;" /><figcaption><code>wavelength = 4</code>, orientation π/4</figcaption></figure>
<figure style="width:30%; margin:0;"><img src="../assets/fns/spatial_rgb/gabor_w_8.png" alt="Gabor wavelength 8" style="width:100%;" /><figcaption><code>wavelength = 8</code>, orientation π/4</figcaption></figure>
</div>
```

```@docs
UTCGP.image3D_spatial_rgb
UTCGP.image3D_spatial_rgb.bundle_image3DIntensity_spatial_rgb_factory
UTCGP.image3D_spatial_rgb.sobel_magnitude_rgb_image3D_factory
UTCGP.image3D_spatial_rgb.laplacian_magnitude_rgb_image3D_factory
UTCGP.image3D_spatial_rgb.gaussian_blur_rgb_image3D_factory
UTCGP.image3D_spatial_rgb.difference_of_gaussians_rgb_image3D_factory
UTCGP.image3D_spatial_rgb.unsharp_mask_rgb_image3D_factory
UTCGP.image3D_spatial_rgb.local_contrast_normalize_rgb_image3D_factory
UTCGP.image3D_spatial_rgb.local_std_rgb_image3D_factory
UTCGP.image3D_spatial_rgb.gabor_energy_rgb_image3D_factory
```
