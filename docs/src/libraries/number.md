
```@meta
CurrentModule = UTCGP
DocTestSetup = quote

  # NUMBER ARITHMETIC
  using UTCGP.number_arithmetic:number_sum
  using UTCGP.number_arithmetic:number_minus
  using UTCGP.number_arithmetic:number_mult
  using UTCGP.number_arithmetic:number_div
  using UTCGP.number_arithmetic:safe_div

  # INTEGER REDUCE

  using UTCGP.number_reduce:reduce_sum
  using UTCGP.number_reduce:reduce_min
  using UTCGP.number_reduce:reduce_max
  using UTCGP.number_reduce:reduce_argmin
  using UTCGP.number_reduce:reduce_argmax
  using UTCGP.number_reduce:reduce_length
end
```

```@contents
Pages = ["number.md"]
```

# Integer Operations

## Orientation Summary From Image

These scalar summaries are exposed through:

- `bundle_float_orientation`

They operate on intensity images and use raw Sobel derivatives internally.
Each example below shows the original image, Sobel x, Sobel y, and the scalar
result.

### Orientation Function Index

- [`orientation_coherence`](#orientation_coherence)
- [`dominant_orientation`](#dominant_orientation)
- [`orientation_energy_0`](#orientation_energy_0)
- [`orientation_energy_45`](#orientation_energy_45)
- [`orientation_energy_90`](#orientation_energy_90)
- [`orientation_energy_135`](#orientation_energy_135)
- [`orientation_spread`](#orientation_spread)

```@setup orientation_summary_assets
using UTCGP
using FileIO
using Images
using ImageCore: N0f8

function orientation_vertical_step_array(n::Int = 30)
    img = zeros(Float64, n, n)
    img[:, fld(n, 2)+1:end] .= 1.0
    return img
end

function orientation_horizontal_step_array(n::Int = 30)
    img = zeros(Float64, n, n)
    img[fld(n, 2)+1:end, :] .= 1.0
    return img
end

function orientation_vertical_bars_array(n::Int = 30)
    img = zeros(Float64, n, n)
    for c in 4:8:(n - 3)
        img[:, c:min(c + 2, n)] .= 1.0
    end
    return img
end

function orientation_diag45_step_array(n::Int = 30)
    img = zeros(Float64, n, n)
    for i in 1:n, j in 1:n
        img[i, j] = j >= i ? 1.0 : 0.0
    end
    return img
end

function orientation_diag135_step_array(n::Int = 30)
    img = zeros(Float64, n, n)
    for i in 1:n, j in 1:n
        img[i, j] = j >= (n - i + 1) ? 1.0 : 0.0
    end
    return img
end

function orientation_diag135_array(n::Int = 30)
    img = zeros(Float64, n, n)
    for i in 1:n
        for d in -1:1
            j = n - i + 1 + d
            if 1 <= j <= n
                img[i, j] = 1.0
            end
        end
    end
    return img
end

function orientation_cross_array(n::Int = 30)
    img = zeros(Float64, n, n)
    for r in 4:8:(n - 3)
        img[r:min(r + 2, n), :] .= 1.0
    end
    for c in 4:8:(n - 3)
        img[:, c:min(c + 2, n)] .= 1.0
    end
    return clamp.(img, 0.0, 1.0)
end

orientation_intensity_image(arr::AbstractMatrix{<:Real}) =
    UTCGP.SImageND(UTCGP.IntensityPixel{N0f8}.(Float64.(arr)))

repo_root = normpath(joinpath(dirname(pathof(UTCGP)), ".."))
docs_assets_src = joinpath(repo_root, "docs", "src", "assets", "fns", "orientation_summary")
docs_assets_build = joinpath(repo_root, "docs", "build", "assets", "fns", "orientation_summary")
mkpath(docs_assets_src)
mkpath(docs_assets_build)

function _save_orientation_summary_gray(name, img)
    vals = Float64.(img)
    minv = minimum(vals)
    maxv = maximum(vals)
    scaled = maxv == minv ? zeros(size(vals)) : (vals .- minv) ./ (maxv - minv)
    g = Gray.(scaled)
    save(joinpath(docs_assets_src, name), g)
    save(joinpath(docs_assets_build, name), g)
    return nothing
end

function _save_orientation_summary_rgb(name, img)
    save(joinpath(docs_assets_src, name), img)
    save(joinpath(docs_assets_build, name), img)
    return nothing
end

function _save_orientation_summary_set(prefix, img)
    gx, gy = UTCGP.image2D_orientation_common._sobel_xy(img)
    gm, _, _ = UTCGP.image2D_orientation_common._grad_magnitude_matrix(img)
    grad_theta, _, _ = UTCGP.image2D_orientation_common._gradient_orientation_matrix(img)
    struct_theta, _, _ = UTCGP.image2D_orientation_common._structure_orientation_matrix(img)
    _save_orientation_summary_gray(prefix * "_original.png", reinterpret(img.img))
    _save_orientation_summary_gray(prefix * "_gx.png", gx)
    _save_orientation_summary_gray(prefix * "_gy.png", gy)
    _save_orientation_summary_gray(prefix * "_grad_theta.png", grad_theta ./ π)
    glyphs = UTCGP.image2D_orientation_common._orientation_glyph_canvas(struct_theta, gm; stride = 1)
    _save_orientation_summary_rgb(prefix * "_structure_theta.png", glyphs)
    return gx, gy
end

orientation_coherence_img = orientation_intensity_image(orientation_vertical_bars_array())
dominant_orientation_img = orientation_intensity_image(orientation_diag135_step_array())
orientation_energy_0_img = orientation_intensity_image(orientation_horizontal_step_array())
orientation_energy_45_img = orientation_intensity_image(orientation_diag45_step_array())
orientation_energy_90_img = orientation_intensity_image(orientation_vertical_step_array())
orientation_energy_135_img = orientation_intensity_image(orientation_diag135_array())
orientation_spread_img = orientation_intensity_image(orientation_cross_array())

_save_orientation_summary_set("orientation_coherence", orientation_coherence_img)
_save_orientation_summary_set("dominant_orientation", dominant_orientation_img)
_save_orientation_summary_set("orientation_energy_0", orientation_energy_0_img)
_save_orientation_summary_set("orientation_energy_45", orientation_energy_45_img)
_save_orientation_summary_set("orientation_energy_90", orientation_energy_90_img)
_save_orientation_summary_set("orientation_energy_135", orientation_energy_135_img)
_save_orientation_summary_set("orientation_spread", orientation_spread_img)
```

### `orientation_coherence`

Measure how aligned the image orientations are.

```@example orientation_summary_assets
img = orientation_coherence_img
fn = UTCGP.bundle_float_orientation[:orientation_coherence].fn
fn(img)
```

```@raw html
<div style="display:flex; gap:1rem; align-items:flex-start; flex-wrap:wrap;">
<div style="width:18%;"><div style="text-align:center; font-size:0.9em;">orig</div><img src="../assets/fns/orientation_summary/orientation_coherence_original.png" alt="orientation_coherence original" style="width:100%; image-rendering:pixelated; image-rendering:crisp-edges;" /></div>
<div style="width:18%;"><div style="text-align:center; font-size:0.9em;">gx</div><img src="../assets/fns/orientation_summary/orientation_coherence_gx.png" alt="orientation_coherence sobel x" style="width:100%; image-rendering:pixelated; image-rendering:crisp-edges;" /></div>
<div style="width:18%;"><div style="text-align:center; font-size:0.9em;">gy</div><img src="../assets/fns/orientation_summary/orientation_coherence_gy.png" alt="orientation_coherence sobel y" style="width:100%; image-rendering:pixelated; image-rendering:crisp-edges;" /></div>
<div style="width:18%;"><div style="text-align:center; font-size:0.9em;">grad θ</div><img src="../assets/fns/orientation_summary/orientation_coherence_grad_theta.png" alt="orientation_coherence gradient angle" style="width:100%; image-rendering:pixelated; image-rendering:crisp-edges;" /></div>
<div style="width:18%;"><div style="text-align:center; font-size:0.9em;">glyph θ</div><img src="../assets/fns/orientation_summary/orientation_coherence_structure_theta.png" alt="orientation_coherence orientation glyphs" style="width:100%; image-rendering:pixelated; image-rendering:crisp-edges;" /></div>
</div>
```

### `dominant_orientation`

Dominant structure orientation over the whole image.

```@example orientation_summary_assets
img = dominant_orientation_img
fn = UTCGP.bundle_float_orientation[:dominant_orientation].fn
fn(img)
```

```@raw html
<div style="display:flex; gap:1rem; align-items:flex-start; flex-wrap:wrap;">
<div style="width:18%;"><div style="text-align:center; font-size:0.9em;">orig</div><img src="../assets/fns/orientation_summary/dominant_orientation_original.png" alt="dominant_orientation original" style="width:100%; image-rendering:pixelated; image-rendering:crisp-edges;" /></div>
<div style="width:18%;"><div style="text-align:center; font-size:0.9em;">gx</div><img src="../assets/fns/orientation_summary/dominant_orientation_gx.png" alt="dominant_orientation sobel x" style="width:100%; image-rendering:pixelated; image-rendering:crisp-edges;" /></div>
<div style="width:18%;"><div style="text-align:center; font-size:0.9em;">gy</div><img src="../assets/fns/orientation_summary/dominant_orientation_gy.png" alt="dominant_orientation sobel y" style="width:100%; image-rendering:pixelated; image-rendering:crisp-edges;" /></div>
<div style="width:18%;"><div style="text-align:center; font-size:0.9em;">grad θ</div><img src="../assets/fns/orientation_summary/dominant_orientation_grad_theta.png" alt="dominant_orientation gradient angle" style="width:100%; image-rendering:pixelated; image-rendering:crisp-edges;" /></div>
<div style="width:18%;"><div style="text-align:center; font-size:0.9em;">glyph θ</div><img src="../assets/fns/orientation_summary/dominant_orientation_structure_theta.png" alt="dominant_orientation orientation glyphs" style="width:100%; image-rendering:pixelated; image-rendering:crisp-edges;" /></div>
</div>
```

### `orientation_energy_0`

Directional energy near horizontal structure.

```@example orientation_summary_assets
img = orientation_energy_0_img
fn = UTCGP.bundle_float_orientation[:orientation_energy_0].fn
fn(img)
```

```@raw html
<div style="display:flex; gap:1rem; align-items:flex-start; flex-wrap:wrap;">
<div style="width:18%;"><div style="text-align:center; font-size:0.9em;">orig</div><img src="../assets/fns/orientation_summary/orientation_energy_0_original.png" alt="orientation_energy_0 original" style="width:100%; image-rendering:pixelated; image-rendering:crisp-edges;" /></div>
<div style="width:18%;"><div style="text-align:center; font-size:0.9em;">gx</div><img src="../assets/fns/orientation_summary/orientation_energy_0_gx.png" alt="orientation_energy_0 sobel x" style="width:100%; image-rendering:pixelated; image-rendering:crisp-edges;" /></div>
<div style="width:18%;"><div style="text-align:center; font-size:0.9em;">gy</div><img src="../assets/fns/orientation_summary/orientation_energy_0_gy.png" alt="orientation_energy_0 sobel y" style="width:100%; image-rendering:pixelated; image-rendering:crisp-edges;" /></div>
<div style="width:18%;"><div style="text-align:center; font-size:0.9em;">grad θ</div><img src="../assets/fns/orientation_summary/orientation_energy_0_grad_theta.png" alt="orientation_energy_0 gradient angle" style="width:100%; image-rendering:pixelated; image-rendering:crisp-edges;" /></div>
<div style="width:18%;"><div style="text-align:center; font-size:0.9em;">glyph θ</div><img src="../assets/fns/orientation_summary/orientation_energy_0_structure_theta.png" alt="orientation_energy_0 orientation glyphs" style="width:100%; image-rendering:pixelated; image-rendering:crisp-edges;" /></div>
</div>
```

### `orientation_energy_45`

Directional energy near 45-degree structure.

```@example orientation_summary_assets
img = orientation_energy_45_img
fn = UTCGP.bundle_float_orientation[:orientation_energy_45].fn
fn(img)
```

```@raw html
<div style="display:flex; gap:1rem; align-items:flex-start; flex-wrap:wrap;">
<div style="width:18%;"><div style="text-align:center; font-size:0.9em;">orig</div><img src="../assets/fns/orientation_summary/orientation_energy_45_original.png" alt="orientation_energy_45 original" style="width:100%; image-rendering:pixelated; image-rendering:crisp-edges;" /></div>
<div style="width:18%;"><div style="text-align:center; font-size:0.9em;">gx</div><img src="../assets/fns/orientation_summary/orientation_energy_45_gx.png" alt="orientation_energy_45 sobel x" style="width:100%; image-rendering:pixelated; image-rendering:crisp-edges;" /></div>
<div style="width:18%;"><div style="text-align:center; font-size:0.9em;">gy</div><img src="../assets/fns/orientation_summary/orientation_energy_45_gy.png" alt="orientation_energy_45 sobel y" style="width:100%; image-rendering:pixelated; image-rendering:crisp-edges;" /></div>
<div style="width:18%;"><div style="text-align:center; font-size:0.9em;">grad θ</div><img src="../assets/fns/orientation_summary/orientation_energy_45_grad_theta.png" alt="orientation_energy_45 gradient angle" style="width:100%; image-rendering:pixelated; image-rendering:crisp-edges;" /></div>
<div style="width:18%;"><div style="text-align:center; font-size:0.9em;">glyph θ</div><img src="../assets/fns/orientation_summary/orientation_energy_45_structure_theta.png" alt="orientation_energy_45 orientation glyphs" style="width:100%; image-rendering:pixelated; image-rendering:crisp-edges;" /></div>
</div>
```

### `orientation_energy_90`

Directional energy near vertical structure.

```@example orientation_summary_assets
img = orientation_energy_90_img
fn = UTCGP.bundle_float_orientation[:orientation_energy_90].fn
fn(img)
```

```@raw html
<div style="display:flex; gap:1rem; align-items:flex-start; flex-wrap:wrap;">
<div style="width:18%;"><div style="text-align:center; font-size:0.9em;">orig</div><img src="../assets/fns/orientation_summary/orientation_energy_90_original.png" alt="orientation_energy_90 original" style="width:100%; image-rendering:pixelated; image-rendering:crisp-edges;" /></div>
<div style="width:18%;"><div style="text-align:center; font-size:0.9em;">gx</div><img src="../assets/fns/orientation_summary/orientation_energy_90_gx.png" alt="orientation_energy_90 sobel x" style="width:100%; image-rendering:pixelated; image-rendering:crisp-edges;" /></div>
<div style="width:18%;"><div style="text-align:center; font-size:0.9em;">gy</div><img src="../assets/fns/orientation_summary/orientation_energy_90_gy.png" alt="orientation_energy_90 sobel y" style="width:100%; image-rendering:pixelated; image-rendering:crisp-edges;" /></div>
<div style="width:18%;"><div style="text-align:center; font-size:0.9em;">grad θ</div><img src="../assets/fns/orientation_summary/orientation_energy_90_grad_theta.png" alt="orientation_energy_90 gradient angle" style="width:100%; image-rendering:pixelated; image-rendering:crisp-edges;" /></div>
<div style="width:18%;"><div style="text-align:center; font-size:0.9em;">glyph θ</div><img src="../assets/fns/orientation_summary/orientation_energy_90_structure_theta.png" alt="orientation_energy_90 orientation glyphs" style="width:100%; image-rendering:pixelated; image-rendering:crisp-edges;" /></div>
</div>
```

### `orientation_energy_135`

Directional energy near 135-degree structure.

```@example orientation_summary_assets
img = orientation_energy_135_img
fn = UTCGP.bundle_float_orientation[:orientation_energy_135].fn
fn(img)
```

```@raw html
<div style="display:flex; gap:1rem; align-items:flex-start; flex-wrap:wrap;">
<div style="width:18%;"><div style="text-align:center; font-size:0.9em;">orig</div><img src="../assets/fns/orientation_summary/orientation_energy_135_original.png" alt="orientation_energy_135 original" style="width:100%; image-rendering:pixelated; image-rendering:crisp-edges;" /></div>
<div style="width:18%;"><div style="text-align:center; font-size:0.9em;">gx</div><img src="../assets/fns/orientation_summary/orientation_energy_135_gx.png" alt="orientation_energy_135 sobel x" style="width:100%; image-rendering:pixelated; image-rendering:crisp-edges;" /></div>
<div style="width:18%;"><div style="text-align:center; font-size:0.9em;">gy</div><img src="../assets/fns/orientation_summary/orientation_energy_135_gy.png" alt="orientation_energy_135 sobel y" style="width:100%; image-rendering:pixelated; image-rendering:crisp-edges;" /></div>
<div style="width:18%;"><div style="text-align:center; font-size:0.9em;">grad θ</div><img src="../assets/fns/orientation_summary/orientation_energy_135_grad_theta.png" alt="orientation_energy_135 gradient angle" style="width:100%; image-rendering:pixelated; image-rendering:crisp-edges;" /></div>
<div style="width:18%;"><div style="text-align:center; font-size:0.9em;">glyph θ</div><img src="../assets/fns/orientation_summary/orientation_energy_135_structure_theta.png" alt="orientation_energy_135 orientation glyphs" style="width:100%; image-rendering:pixelated; image-rendering:crisp-edges;" /></div>
</div>
```

### `orientation_spread`

Dispersion of the image orientations.

```@example orientation_summary_assets
img = orientation_spread_img
fn = UTCGP.bundle_float_orientation[:orientation_spread].fn
fn(img)
```

```@raw html
<div style="display:flex; gap:1rem; align-items:flex-start; flex-wrap:wrap;">
<div style="width:18%;"><div style="text-align:center; font-size:0.9em;">orig</div><img src="../assets/fns/orientation_summary/orientation_spread_original.png" alt="orientation_spread original" style="width:100%; image-rendering:pixelated; image-rendering:crisp-edges;" /></div>
<div style="width:18%;"><div style="text-align:center; font-size:0.9em;">gx</div><img src="../assets/fns/orientation_summary/orientation_spread_gx.png" alt="orientation_spread sobel x" style="width:100%; image-rendering:pixelated; image-rendering:crisp-edges;" /></div>
<div style="width:18%;"><div style="text-align:center; font-size:0.9em;">gy</div><img src="../assets/fns/orientation_summary/orientation_spread_gy.png" alt="orientation_spread sobel y" style="width:100%; image-rendering:pixelated; image-rendering:crisp-edges;" /></div>
<div style="width:18%;"><div style="text-align:center; font-size:0.9em;">grad θ</div><img src="../assets/fns/orientation_summary/orientation_spread_grad_theta.png" alt="orientation_spread gradient angle" style="width:100%; image-rendering:pixelated; image-rendering:crisp-edges;" /></div>
<div style="width:18%;"><div style="text-align:center; font-size:0.9em;">glyph θ</div><img src="../assets/fns/orientation_summary/orientation_spread_structure_theta.png" alt="orientation_spread orientation glyphs" style="width:100%; image-rendering:pixelated; image-rendering:crisp-edges;" /></div>
</div>
```

## Image To Float Region Statistics

These functions reduce a fixed local patch around a normalized image location to
one `Float64`. They are exposed through:

- `bundle_number_regionFromImg`

Coordinates are normalized in `[0, 1]`. For the first version:

- `region_mean`, `region_std`, `region_min`, `region_max`, `region_sum`,
  `region_median`, `region_range`, `region_energy`, and `region_entropy`
  operate on a fixed `3 × 3` patch centered at `(cx, cy)`.
- `region_contrast` compares that `3 × 3` center patch to its surrounding `5 × 5`
  ring.
- the same family is also available at fixed relative scales:
  `*_5p`, `*_10p`, and `*_20p`, where the patch side is derived from `5%`, `10%`,
  or `20%` of `min(height, width)`, clamped to an odd valid size.
- windows are clipped at image borders, so corner evaluations use smaller valid
  patches rather than padding.

### Region Function Index

- [`region_mean`](#region_mean)
- [`region_std`](#region_std)
- [`region_min`](#region_min)
- [`region_max`](#region_max)
- [`region_sum`](#region_sum)
- [`region_median`](#region_median)
- [`region_range`](#region_range)
- [`region_contrast`](#region_contrast)
- [`region_energy`](#region_energy)
- [`region_entropy`](#region_entropy)
- [`region_mean_5p`](#region_mean_5p)
- [`region_mean_10p`](#region_mean_10p)
- [`region_mean_20p`](#region_mean_20p)
- [`region_std_5p`](#region_std_5p)
- [`region_std_10p`](#region_std_10p)
- [`region_std_20p`](#region_std_20p)
- [`region_min_5p`](#region_min_5p)
- [`region_min_10p`](#region_min_10p)
- [`region_min_20p`](#region_min_20p)
- [`region_max_5p`](#region_max_5p)
- [`region_max_10p`](#region_max_10p)
- [`region_max_20p`](#region_max_20p)
- [`region_sum_5p`](#region_sum_5p)
- [`region_sum_10p`](#region_sum_10p)
- [`region_sum_20p`](#region_sum_20p)
- [`region_median_5p`](#region_median_5p)
- [`region_median_10p`](#region_median_10p)
- [`region_median_20p`](#region_median_20p)
- [`region_range_5p`](#region_range_5p)
- [`region_range_10p`](#region_range_10p)
- [`region_range_20p`](#region_range_20p)
- [`region_contrast_5p`](#region_contrast_5p)
- [`region_contrast_10p`](#region_contrast_10p)
- [`region_contrast_20p`](#region_contrast_20p)
- [`region_energy_5p`](#region_energy_5p)
- [`region_energy_10p`](#region_energy_10p)
- [`region_energy_20p`](#region_energy_20p)
- [`region_entropy_5p`](#region_entropy_5p)
- [`region_entropy_10p`](#region_entropy_10p)
- [`region_entropy_20p`](#region_entropy_20p)

```@eval
using UTCGP
using FileIO
using Images
using Markdown

repo_root = normpath(joinpath(dirname(pathof(UTCGP)), ".."))
docs_assets_src = joinpath(repo_root, "docs", "src", "assets", "fns", "region_stats")
docs_assets_build = joinpath(repo_root, "docs", "build", "assets", "fns", "region_stats")
mkpath(docs_assets_src)
mkpath(docs_assets_build)

function _save_region_gray(name, img)
    vals = Float64.(img)
    minv = minimum(vals)
    maxv = maximum(vals)
    scaled = maxv == minv ? zeros(size(vals)) : (vals .- minv) ./ (maxv - minv)
    g = Gray.(scaled)
    save(joinpath(docs_assets_src, name), g)
    save(joinpath(docs_assets_build, name), g)
    return nothing
end

function _base_rgb(img)
    vals = Float64.(img)
    minv = minimum(vals)
    maxv = maximum(vals)
    scaled = maxv == minv ? zeros(size(vals)) : (vals .- minv) ./ (maxv - minv)
    return RGB.(Gray.(scaled))
end

function _draw_bbox!(img, row_lo, row_hi, col_lo, col_hi, color)
    img[row_lo, col_lo:col_hi] .= color
    img[row_hi, col_lo:col_hi] .= color
    img[row_lo:row_hi, col_lo] .= color
    img[row_lo:row_hi, col_hi] .= color
    return img
end

function _save_region_overlay(name, img, boxes)
    rgb = _base_rgb(img)
    for (row_lo, row_hi, col_lo, col_hi, color) in boxes
        _draw_bbox!(rgb, row_lo, row_hi, col_lo, col_hi, color)
    end
    rgb = repeat(rgb, inner = (4, 4))
    save(joinpath(docs_assets_src, name), rgb)
    save(joinpath(docs_assets_build, name), rgb)
    return nothing
end

region_intensity_arr = [0.5 * (i / 30) + 0.5 * (j / 30) for i in 1:30, j in 1:30]
region_intensity_arr[8:14, 8:14] .= 0.9
region_intensity_arr[16:25, 18:27] .= 0.2
region_intensity_arr[20:24, 5:10] .= 1.0
region_intensity_arr[3:6, 22:28] .= 0.05

region_binary_arr = falses(30, 30)
region_binary_arr[5:12, 5:12] .= true
region_binary_arr[10:18, 18:27] .= true
region_binary_arr[20:27, 8:14] .= true
region_binary_arr[22:25, 22:28] .= true

region_segment_arr = fill(1, 30, 30)
region_segment_arr[:, 11:20] .= 2
region_segment_arr[12:22, 21:30] .= 3
region_segment_arr[20:30, 1:10] .= 4

region_intensity = UTCGP.SImageND(UTCGP.IntensityPixel{N0f8}.(region_intensity_arr))
region_binary = UTCGP.SImageND(UTCGP.BinaryPixel{Bool}.(region_binary_arr))
region_segment = UTCGP.SImageND(UTCGP.SegmentPixel{Int}.(region_segment_arr))

_save_region_gray("region_intensity.png", region_intensity_arr)
_save_region_gray("region_binary.png", Float64.(region_binary_arr))
_save_region_gray("region_segment.png", Float64.(region_segment_arr))

function _region_examples_md(specs)
    io = IOBuffer()
    for (idx, (fn_name, desc)) in enumerate(specs)
        fn = UTCGP.bundle_number_regionFromImg[fn_name].fn
        cx = mod(3 * idx + 1, 9) / 10
        cy = mod(5 * idx + 2, 9) / 10
        result = (
            fn(region_intensity, cx, cy),
            fn(region_binary, cx, cy),
            fn(region_segment, cx, cy),
        )
        half_size =
            if endswith(String(fn_name), "_5p")
                UTCGP.number_regionFromImg._region_half_size_from_percent(region_intensity, 0.05)
            elseif endswith(String(fn_name), "_10p")
                UTCGP.number_regionFromImg._region_half_size_from_percent(region_intensity, 0.10)
            elseif endswith(String(fn_name), "_20p")
                UTCGP.number_regionFromImg._region_half_size_from_percent(region_intensity, 0.20)
            else
                UTCGP.number_regionFromImg._REGION_HALF_SIZE
            end

        function _boxes_for(from)
            inner = UTCGP.number_regionFromImg._region_bounds(from, cx, cy, half_size)
            boxes = [(inner[1], inner[2], inner[3], inner[4], RGB(1, 0, 0))]
            if occursin("contrast", String(fn_name))
                outer = UTCGP.number_regionFromImg._region_contrast_bounds(from, cx, cy, half_size)
                push!(boxes, (outer[1], outer[2], outer[3], outer[4], RGB(0, 1, 0)))
            end
            return boxes
        end

        intensity_img = string(fn_name, "_intensity.png")
        binary_img = string(fn_name, "_binary.png")
        segment_img = string(fn_name, "_segment.png")
        _save_region_overlay(intensity_img, region_intensity_arr, _boxes_for(region_intensity))
        _save_region_overlay(binary_img, Float64.(region_binary_arr), _boxes_for(region_binary))
        _save_region_overlay(segment_img, Float64.(region_segment_arr), _boxes_for(region_segment))

        println(io, "### `", fn_name, "`")
        println(io)
        println(io, desc)
        println(io)
        println(io, "```julia")
        println(io, "fn = UTCGP.bundle_number_regionFromImg[:", fn_name, "].fn")
        println(io, "(")
        println(io, "    fn(region_intensity, ", cx, ", ", cy, "),")
        println(io, "    fn(region_binary, ", cx, ", ", cy, "),")
        println(io, "    fn(region_segment, ", cx, ", ", cy, "),")
        println(io, ")")
        println(io, "```")
        println(io)
        println(io, "Coordinates: `(", cx, ", ", cy, ")`")
        println(io)
        println(io, "Result: `", repr(result), "`")
        println(io)
        println(io, "| Intensity | Binary | Segment |")
        println(io, "| --- | --- | --- |")
        println(io, "| ![](../assets/fns/region_stats/", intensity_img, ") | ![](../assets/fns/region_stats/", binary_img, ") | ![](../assets/fns/region_stats/", segment_img, ") |")
        println(io)
    end
    return Markdown.parse(String(take!(io)))
end

region_fn_specs = [
    (:region_mean, "Mean over a fixed 3x3 local patch."),
    (:region_std, "Standard deviation over a fixed 3x3 local patch."),
    (:region_min, "Minimum over a fixed 3x3 local patch."),
    (:region_max, "Maximum over a fixed 3x3 local patch."),
    (:region_sum, "Sum over a fixed 3x3 local patch."),
    (:region_median, "Median over a fixed 3x3 local patch."),
    (:region_range, "Range over a fixed 3x3 local patch."),
    (:region_contrast, "Mean(center 3x3) minus mean(surrounding 5x5 ring)."),
    (:region_energy, "Mean squared value over a fixed 3x3 local patch."),
    (:region_entropy, "Cheap 8-bin entropy over a fixed 3x3 local patch."),
    (:region_mean_5p, "Mean over a local patch sized from 5% of min(image side)."),
    (:region_mean_10p, "Mean over a local patch sized from 10% of min(image side)."),
    (:region_mean_20p, "Mean over a local patch sized from 20% of min(image side)."),
    (:region_std_5p, "Standard deviation over a local patch sized from 5% of min(image side)."),
    (:region_std_10p, "Standard deviation over a local patch sized from 10% of min(image side)."),
    (:region_std_20p, "Standard deviation over a local patch sized from 20% of min(image side)."),
    (:region_min_5p, "Minimum over a local patch sized from 5% of min(image side)."),
    (:region_min_10p, "Minimum over a local patch sized from 10% of min(image side)."),
    (:region_min_20p, "Minimum over a local patch sized from 20% of min(image side)."),
    (:region_max_5p, "Maximum over a local patch sized from 5% of min(image side)."),
    (:region_max_10p, "Maximum over a local patch sized from 10% of min(image side)."),
    (:region_max_20p, "Maximum over a local patch sized from 20% of min(image side)."),
    (:region_sum_5p, "Sum over a local patch sized from 5% of min(image side)."),
    (:region_sum_10p, "Sum over a local patch sized from 10% of min(image side)."),
    (:region_sum_20p, "Sum over a local patch sized from 20% of min(image side)."),
    (:region_median_5p, "Median over a local patch sized from 5% of min(image side)."),
    (:region_median_10p, "Median over a local patch sized from 10% of min(image side)."),
    (:region_median_20p, "Median over a local patch sized from 20% of min(image side)."),
    (:region_range_5p, "Range over a local patch sized from 5% of min(image side)."),
    (:region_range_10p, "Range over a local patch sized from 10% of min(image side)."),
    (:region_range_20p, "Range over a local patch sized from 20% of min(image side)."),
    (:region_contrast_5p, "Center-versus-ring contrast with a 5% local center scale."),
    (:region_contrast_10p, "Center-versus-ring contrast with a 10% local center scale."),
    (:region_contrast_20p, "Center-versus-ring contrast with a 20% local center scale."),
    (:region_energy_5p, "Mean squared value over a local patch sized from 5% of min(image side)."),
    (:region_energy_10p, "Mean squared value over a local patch sized from 10% of min(image side)."),
    (:region_energy_20p, "Mean squared value over a local patch sized from 20% of min(image side)."),
    (:region_entropy_5p, "Cheap 8-bin entropy over a local patch sized from 5% of min(image side)."),
    (:region_entropy_10p, "Cheap 8-bin entropy over a local patch sized from 10% of min(image side)."),
    (:region_entropy_20p, "Cheap 8-bin entropy over a local patch sized from 20% of min(image side)."),
]

_region_examples_md(region_fn_specs)
```

## Haar Features From Image

These scalar Haar-like features are exposed through:

- `bundle_number_haarFromImg`

`position` is a normalized column-major flattened position in `[0, 1]`. `size`
is converted to a positive integer half-extent in pixels. The region is clipped
to the image; no padding is used.

### Haar Function Index

- [`haar_lr`](#haar_lr)
- [`haar_tb`](#haar_tb)
- [`haar_diag_main`](#haar_diag_main)
- [`haar_diag_anti`](#haar_diag_anti)
- [`haar_center_surround`](#haar_center_surround)
- [`haar_three_h`](#haar_three_h)
- [`haar_three_v`](#haar_three_v)

```@setup haar_from_img_assets
using UTCGP
using FileIO
using Images
using ImageCore: N0f8

repo_root = normpath(joinpath(dirname(pathof(UTCGP)), ".."))
docs_assets_src = joinpath(repo_root, "docs", "src", "assets", "fns", "haar_from_img")
docs_assets_build = joinpath(repo_root, "docs", "build", "assets", "fns", "haar_from_img")
mkpath(docs_assets_src)
mkpath(docs_assets_build)

haar_intensity_image(arr::AbstractMatrix{<:Real}) =
    UTCGP.SImageND(UTCGP.IntensityPixel{N0f8}.(Float64.(arr)))
haar_binary_image(arr::AbstractMatrix{Bool}) =
    UTCGP.SImageND(UTCGP.BinaryPixel{Bool}.(arr))

function _save_haar_gray(name, img)
    vals = Float64.(img)
    minv = minimum(vals)
    maxv = maximum(vals)
    scaled = maxv == minv ? zeros(size(vals)) : (vals .- minv) ./ (maxv - minv)
    g = Gray.(scaled)
    save(joinpath(docs_assets_src, name), g)
    save(joinpath(docs_assets_build, name), g)
    return nothing
end

function _save_haar_rgb(name, img)
    save(joinpath(docs_assets_src, name), img)
    save(joinpath(docs_assets_build, name), img)
    return nothing
end

function _save_haar_set(prefix, intensity_img, binary_img, kind, position, region_size)
    _save_haar_gray(prefix * "_intensity_orig.png", reinterpret(intensity_img.img))
    _save_haar_rgb(prefix * "_intensity_overlay.png", UTCGP.number_haarFromImg._haar_overlay_canvas(intensity_img, kind, position, region_size))
    _save_haar_gray(prefix * "_binary_orig.png", Float64.(reinterpret(binary_img.img)))
    _save_haar_rgb(prefix * "_binary_overlay.png", UTCGP.number_haarFromImg._haar_overlay_canvas(binary_img, kind, position, region_size))
    return nothing
end

haar_lr_intensity = haar_intensity_image([
    0.10 0.15 0.20 0.50 0.80 0.85 0.90;
    0.10 0.15 0.20 0.50 0.80 0.85 0.90;
    0.10 0.15 0.20 0.50 0.80 0.85 0.90;
    0.10 0.15 0.20 0.50 0.80 0.85 0.90;
    0.10 0.15 0.20 0.50 0.80 0.85 0.90;
    0.10 0.15 0.20 0.50 0.80 0.85 0.90;
    0.10 0.15 0.20 0.50 0.80 0.85 0.90;
])
haar_lr_binary = haar_binary_image(Bool[
    1 1 1 1 0 0 0;
    1 1 1 1 0 0 0;
    1 1 1 1 0 0 0;
    1 1 1 1 0 0 0;
    1 1 1 1 0 0 0;
    1 1 1 1 0 0 0;
    1 1 1 1 0 0 0;
])

haar_tb_intensity = haar_intensity_image([
    1 1 1 1 1 1 1;
    1 1 1 1 1 1 1;
    1 1 1 1 1 1 1;
    0 0 0 0 0 0 0;
    0 0 0 0 0 0 0;
    0 0 0 0 0 0 0;
    0 0 0 0 0 0 0;
])
haar_tb_binary = haar_binary_image(Bool[
    1 1 1 1 1 1 1;
    1 1 1 1 1 1 1;
    1 1 1 1 1 1 1;
    0 0 0 0 0 0 0;
    0 0 0 0 0 0 0;
    0 0 0 0 0 0 0;
    0 0 0 0 0 0 0;
])

haar_diag_main_intensity = haar_intensity_image([
    1 1 0 0 0 0 0;
    1 1 0 0 0 0 0;
    0 0 1 1 0 0 0;
    0 0 1 1 0 0 0;
    0 0 0 0 1 1 0;
    0 0 0 0 1 1 0;
    0 0 0 0 0 0 1;
])
haar_diag_main_binary = haar_binary_image(Bool[
    1 1 0 0 0 0 0;
    1 1 0 0 0 0 0;
    0 0 1 1 0 0 0;
    0 0 1 1 0 0 0;
    0 0 0 0 1 1 0;
    0 0 0 0 1 1 0;
    0 0 0 0 0 0 1;
])

haar_diag_anti_intensity = haar_intensity_image([
    0 0 0 0 0 1 1;
    0 0 0 0 0 1 1;
    0 0 0 0 1 1 0;
    0 0 0 0 1 1 0;
    0 0 1 1 0 0 0;
    0 0 1 1 0 0 0;
    1 1 0 0 0 0 0;
])
haar_diag_anti_binary = haar_binary_image(Bool[
    0 0 0 0 0 1 1;
    0 0 0 0 0 1 1;
    0 0 0 0 1 1 0;
    0 0 0 0 1 1 0;
    0 0 1 1 0 0 0;
    0 0 1 1 0 0 0;
    1 1 0 0 0 0 0;
])

haar_center_surround_intensity = haar_intensity_image([
    0 0 0 0 0 0 0;
    0 0 0 0 0 0 0;
    0 0 1 1 1 0 0;
    0 0 1 1 1 0 0;
    0 0 1 1 1 0 0;
    0 0 0 0 0 0 0;
    0 0 0 0 0 0 0;
])
haar_center_surround_binary = haar_binary_image(Bool[
    0 0 0 0 0 0 0;
    0 0 0 0 0 0 0;
    0 0 1 1 1 0 0;
    0 0 1 1 1 0 0;
    0 0 1 1 1 0 0;
    0 0 0 0 0 0 0;
    0 0 0 0 0 0 0;
])

haar_three_h_intensity = haar_intensity_image([
    1 1 0 0 1 1 0;
    1 1 0 0 1 1 0;
    1 1 0 0 1 1 0;
    1 1 0 0 1 1 0;
    1 1 0 0 1 1 0;
    1 1 0 0 1 1 0;
    1 1 0 0 1 1 0;
])
haar_three_h_binary = haar_binary_image(Bool[
    1 1 0 0 1 1 0;
    1 1 0 0 1 1 0;
    1 1 0 0 1 1 0;
    1 1 0 0 1 1 0;
    1 1 0 0 1 1 0;
    1 1 0 0 1 1 0;
    1 1 0 0 1 1 0;
])

haar_three_v_intensity = haar_intensity_image([
    1 1 1 1 1 1 1;
    1 1 1 1 1 1 1;
    0 0 0 0 0 0 0;
    0 0 0 0 0 0 0;
    1 1 1 1 1 1 1;
    1 1 1 1 1 1 1;
    0 0 0 0 0 0 0;
])
haar_three_v_binary = haar_binary_image(Bool[
    1 1 1 1 1 1 1;
    1 1 1 1 1 1 1;
    0 0 0 0 0 0 0;
    0 0 0 0 0 0 0;
    1 1 1 1 1 1 1;
    1 1 1 1 1 1 1;
    0 0 0 0 0 0 0;
])

haar_specs = [
    ("haar_tb", :haar_tb, haar_tb_intensity, haar_tb_binary, 0.5, 2),
    ("haar_diag_main", :haar_diag_main, haar_diag_main_intensity, haar_diag_main_binary, 0.5, 2),
    ("haar_diag_anti", :haar_diag_anti, haar_diag_anti_intensity, haar_diag_anti_binary, 0.5, 2),
    ("haar_center_surround", :haar_center_surround, haar_center_surround_intensity, haar_center_surround_binary, 0.5, 2),
    ("haar_three_h", :haar_three_h, haar_three_h_intensity, haar_three_h_binary, 0.5, 2),
    ("haar_three_v", :haar_three_v, haar_three_v_intensity, haar_three_v_binary, 0.5, 2),
]

for (prefix, kind, intensity_img, binary_img, position, region_size) in haar_specs
    _save_haar_set(prefix, intensity_img, binary_img, kind, position, region_size)
end

_save_haar_set("haar_lr_intensity_s1", haar_lr_intensity, haar_lr_binary, :haar_lr, 0.5, 1)
_save_haar_set("haar_lr_intensity_s2", haar_lr_intensity, haar_lr_binary, :haar_lr, 0.5, 2)
_save_haar_set("haar_lr_intensity_s3", haar_lr_intensity, haar_lr_binary, :haar_lr, 0.5, 3)
_save_haar_set("haar_lr_binary_p02_s2", haar_lr_intensity, haar_lr_binary, :haar_lr, 0.2, 2)
_save_haar_set("haar_lr_binary_row4_col1_s2", haar_lr_intensity, haar_lr_binary, :haar_lr, 0.0625, 2)
```

### `haar_lr`

Left-versus-right rectangular contrast.

Current size convention in this implementation:

- `size = 1` means a clipped `3×3` local region
- `size = 2` means a clipped `5×5` local region
- `size = 3` means a clipped `7×7` local region

The intensity examples below keep the same center position and vary only the
size. The binary example keeps `size = 2` and moves the flattened position to
`0.2` so the effect of the position parameter is visible too. The last binary
example uses `position = 0.0625`, which maps to `(row=4, col=1)` in a `7x7`
image under Julia's column-major flattening.

```@example haar_from_img_assets
fn = UTCGP.bundle_number_haarFromImg[:haar_lr].fn
(
    intensity_size_1 = fn(haar_lr_intensity, 0.5, 1),
    intensity_size_2 = fn(haar_lr_intensity, 0.5, 2),
    intensity_size_3 = fn(haar_lr_intensity, 0.5, 3),
    binary_pos_02_size_2 = fn(haar_lr_binary, 0.2, 2),
    binary_row4_col1_size_2 = fn(haar_lr_binary, 0.0625, 2),
)
```

```@raw html
<div style="display:flex; gap:1rem; align-items:flex-start; flex-wrap:wrap;">
<div style="width:22%;"><div style="text-align:center; font-size:0.9em;">intensity size=1 orig</div><img src="../assets/fns/haar_from_img/haar_lr_intensity_s1_intensity_orig.png" alt="haar_lr intensity size 1 original" style="width:100%; image-rendering:pixelated; image-rendering:crisp-edges;" /></div>
<div style="width:22%;"><div style="text-align:center; font-size:0.9em;">intensity size=1 overlay</div><img src="../assets/fns/haar_from_img/haar_lr_intensity_s1_intensity_overlay.png" alt="haar_lr intensity size 1 overlay" style="width:100%; image-rendering:pixelated; image-rendering:crisp-edges;" /></div>
<div style="width:22%;"><div style="text-align:center; font-size:0.9em;">intensity size=2 orig</div><img src="../assets/fns/haar_from_img/haar_lr_intensity_s2_intensity_orig.png" alt="haar_lr intensity size 2 original" style="width:100%; image-rendering:pixelated; image-rendering:crisp-edges;" /></div>
<div style="width:22%;"><div style="text-align:center; font-size:0.9em;">intensity size=2 overlay</div><img src="../assets/fns/haar_from_img/haar_lr_intensity_s2_intensity_overlay.png" alt="haar_lr intensity size 2 overlay" style="width:100%; image-rendering:pixelated; image-rendering:crisp-edges;" /></div>
</div>
<div style="display:flex; gap:1rem; align-items:flex-start; flex-wrap:wrap; margin-top:1rem;">
<div style="width:22%;"><div style="text-align:center; font-size:0.9em;">intensity size=3 orig</div><img src="../assets/fns/haar_from_img/haar_lr_intensity_s3_intensity_orig.png" alt="haar_lr intensity size 3 original" style="width:100%; image-rendering:pixelated; image-rendering:crisp-edges;" /></div>
<div style="width:22%;"><div style="text-align:center; font-size:0.9em;">intensity size=3 overlay</div><img src="../assets/fns/haar_from_img/haar_lr_intensity_s3_intensity_overlay.png" alt="haar_lr intensity size 3 overlay" style="width:100%; image-rendering:pixelated; image-rendering:crisp-edges;" /></div>
<div style="width:22%;"><div style="text-align:center; font-size:0.9em;">binary pos=0.2 size=2 orig</div><img src="../assets/fns/haar_from_img/haar_lr_binary_p02_s2_binary_orig.png" alt="haar_lr binary position 0.2 size 2 original" style="width:100%; image-rendering:pixelated; image-rendering:crisp-edges;" /></div>
<div style="width:22%;"><div style="text-align:center; font-size:0.9em;">binary pos=0.2 size=2 overlay</div><img src="../assets/fns/haar_from_img/haar_lr_binary_p02_s2_binary_overlay.png" alt="haar_lr binary position 0.2 size 2 overlay" style="width:100%; image-rendering:pixelated; image-rendering:crisp-edges;" /></div>
</div>
<div style="display:flex; gap:1rem; align-items:flex-start; flex-wrap:wrap; margin-top:1rem;">
<div style="width:22%;"><div style="text-align:center; font-size:0.9em;">binary row=4 col=1 orig</div><img src="../assets/fns/haar_from_img/haar_lr_binary_row4_col1_s2_binary_orig.png" alt="haar_lr binary row 4 col 1 original" style="width:100%; image-rendering:pixelated; image-rendering:crisp-edges;" /></div>
<div style="width:22%;"><div style="text-align:center; font-size:0.9em;">binary row=4 col=1 overlay</div><img src="../assets/fns/haar_from_img/haar_lr_binary_row4_col1_s2_binary_overlay.png" alt="haar_lr binary row 4 col 1 overlay" style="width:100%; image-rendering:pixelated; image-rendering:crisp-edges;" /></div>
</div>
```

### `haar_tb`

Top-versus-bottom rectangular contrast.

```@example haar_from_img_assets
fn = UTCGP.bundle_number_haarFromImg[:haar_tb].fn
(fn(haar_tb_intensity, 0.5, 2), fn(haar_tb_binary, 0.5, 2))
```

```@raw html
<div style="display:flex; gap:1rem; align-items:flex-start; flex-wrap:wrap;">
<div style="width:22%;"><div style="text-align:center; font-size:0.9em;">intensity orig</div><img src="../assets/fns/haar_from_img/haar_tb_intensity_orig.png" alt="haar_tb intensity original" style="width:100%; image-rendering:pixelated; image-rendering:crisp-edges;" /></div>
<div style="width:22%;"><div style="text-align:center; font-size:0.9em;">intensity overlay</div><img src="../assets/fns/haar_from_img/haar_tb_intensity_overlay.png" alt="haar_tb intensity overlay" style="width:100%; image-rendering:pixelated; image-rendering:crisp-edges;" /></div>
<div style="width:22%;"><div style="text-align:center; font-size:0.9em;">binary orig</div><img src="../assets/fns/haar_from_img/haar_tb_binary_orig.png" alt="haar_tb binary original" style="width:100%; image-rendering:pixelated; image-rendering:crisp-edges;" /></div>
<div style="width:22%;"><div style="text-align:center; font-size:0.9em;">binary overlay</div><img src="../assets/fns/haar_from_img/haar_tb_binary_overlay.png" alt="haar_tb binary overlay" style="width:100%; image-rendering:pixelated; image-rendering:crisp-edges;" /></div>
</div>
```

### `haar_diag_main`

Checkerboard contrast between the main-diagonal quadrants and the opposite quadrants.

```@example haar_from_img_assets
fn = UTCGP.bundle_number_haarFromImg[:haar_diag_main].fn
(fn(haar_diag_main_intensity, 0.5, 2), fn(haar_diag_main_binary, 0.5, 2))
```

```@raw html
<div style="display:flex; gap:1rem; align-items:flex-start; flex-wrap:wrap;">
<div style="width:22%;"><div style="text-align:center; font-size:0.9em;">intensity orig</div><img src="../assets/fns/haar_from_img/haar_diag_main_intensity_orig.png" alt="haar_diag_main intensity original" style="width:100%; image-rendering:pixelated; image-rendering:crisp-edges;" /></div>
<div style="width:22%;"><div style="text-align:center; font-size:0.9em;">intensity overlay</div><img src="../assets/fns/haar_from_img/haar_diag_main_intensity_overlay.png" alt="haar_diag_main intensity overlay" style="width:100%; image-rendering:pixelated; image-rendering:crisp-edges;" /></div>
<div style="width:22%;"><div style="text-align:center; font-size:0.9em;">binary orig</div><img src="../assets/fns/haar_from_img/haar_diag_main_binary_orig.png" alt="haar_diag_main binary original" style="width:100%; image-rendering:pixelated; image-rendering:crisp-edges;" /></div>
<div style="width:22%;"><div style="text-align:center; font-size:0.9em;">binary overlay</div><img src="../assets/fns/haar_from_img/haar_diag_main_binary_overlay.png" alt="haar_diag_main binary overlay" style="width:100%; image-rendering:pixelated; image-rendering:crisp-edges;" /></div>
</div>
```

### `haar_diag_anti`

Checkerboard contrast between the anti-diagonal quadrants and the opposite quadrants.

```@example haar_from_img_assets
fn = UTCGP.bundle_number_haarFromImg[:haar_diag_anti].fn
(fn(haar_diag_anti_intensity, 0.5, 2), fn(haar_diag_anti_binary, 0.5, 2))
```

```@raw html
<div style="display:flex; gap:1rem; align-items:flex-start; flex-wrap:wrap;">
<div style="width:22%;"><div style="text-align:center; font-size:0.9em;">intensity orig</div><img src="../assets/fns/haar_from_img/haar_diag_anti_intensity_orig.png" alt="haar_diag_anti intensity original" style="width:100%; image-rendering:pixelated; image-rendering:crisp-edges;" /></div>
<div style="width:22%;"><div style="text-align:center; font-size:0.9em;">intensity overlay</div><img src="../assets/fns/haar_from_img/haar_diag_anti_intensity_overlay.png" alt="haar_diag_anti intensity overlay" style="width:100%; image-rendering:pixelated; image-rendering:crisp-edges;" /></div>
<div style="width:22%;"><div style="text-align:center; font-size:0.9em;">binary orig</div><img src="../assets/fns/haar_from_img/haar_diag_anti_binary_orig.png" alt="haar_diag_anti binary original" style="width:100%; image-rendering:pixelated; image-rendering:crisp-edges;" /></div>
<div style="width:22%;"><div style="text-align:center; font-size:0.9em;">binary overlay</div><img src="../assets/fns/haar_from_img/haar_diag_anti_binary_overlay.png" alt="haar_diag_anti binary overlay" style="width:100%; image-rendering:pixelated; image-rendering:crisp-edges;" /></div>
</div>
```

### `haar_center_surround`

Center-versus-surround rectangular contrast.

```@example haar_from_img_assets
fn = UTCGP.bundle_number_haarFromImg[:haar_center_surround].fn
(fn(haar_center_surround_intensity, 0.5, 2), fn(haar_center_surround_binary, 0.5, 2))
```

```@raw html
<div style="display:flex; gap:1rem; align-items:flex-start; flex-wrap:wrap;">
<div style="width:22%;"><div style="text-align:center; font-size:0.9em;">intensity orig</div><img src="../assets/fns/haar_from_img/haar_center_surround_intensity_orig.png" alt="haar_center_surround intensity original" style="width:100%; image-rendering:pixelated; image-rendering:crisp-edges;" /></div>
<div style="width:22%;"><div style="text-align:center; font-size:0.9em;">intensity overlay</div><img src="../assets/fns/haar_from_img/haar_center_surround_intensity_overlay.png" alt="haar_center_surround intensity overlay" style="width:100%; image-rendering:pixelated; image-rendering:crisp-edges;" /></div>
<div style="width:22%;"><div style="text-align:center; font-size:0.9em;">binary orig</div><img src="../assets/fns/haar_from_img/haar_center_surround_binary_orig.png" alt="haar_center_surround binary original" style="width:100%; image-rendering:pixelated; image-rendering:crisp-edges;" /></div>
<div style="width:22%;"><div style="text-align:center; font-size:0.9em;">binary overlay</div><img src="../assets/fns/haar_from_img/haar_center_surround_binary_overlay.png" alt="haar_center_surround binary overlay" style="width:100%; image-rendering:pixelated; image-rendering:crisp-edges;" /></div>
</div>
```

### `haar_three_h`

Three-rectangle horizontal contrast.

```@example haar_from_img_assets
fn = UTCGP.bundle_number_haarFromImg[:haar_three_h].fn
(fn(haar_three_h_intensity, 0.5, 2), fn(haar_three_h_binary, 0.5, 2))
```

```@raw html
<div style="display:flex; gap:1rem; align-items:flex-start; flex-wrap:wrap;">
<div style="width:22%;"><div style="text-align:center; font-size:0.9em;">intensity orig</div><img src="../assets/fns/haar_from_img/haar_three_h_intensity_orig.png" alt="haar_three_h intensity original" style="width:100%; image-rendering:pixelated; image-rendering:crisp-edges;" /></div>
<div style="width:22%;"><div style="text-align:center; font-size:0.9em;">intensity overlay</div><img src="../assets/fns/haar_from_img/haar_three_h_intensity_overlay.png" alt="haar_three_h intensity overlay" style="width:100%; image-rendering:pixelated; image-rendering:crisp-edges;" /></div>
<div style="width:22%;"><div style="text-align:center; font-size:0.9em;">binary orig</div><img src="../assets/fns/haar_from_img/haar_three_h_binary_orig.png" alt="haar_three_h binary original" style="width:100%; image-rendering:pixelated; image-rendering:crisp-edges;" /></div>
<div style="width:22%;"><div style="text-align:center; font-size:0.9em;">binary overlay</div><img src="../assets/fns/haar_from_img/haar_three_h_binary_overlay.png" alt="haar_three_h binary overlay" style="width:100%; image-rendering:pixelated; image-rendering:crisp-edges;" /></div>
</div>
```

### `haar_three_v`

Three-rectangle vertical contrast.

```@example haar_from_img_assets
fn = UTCGP.bundle_number_haarFromImg[:haar_three_v].fn
(fn(haar_three_v_intensity, 0.5, 2), fn(haar_three_v_binary, 0.5, 2))
```

```@raw html
<div style="display:flex; gap:1rem; align-items:flex-start; flex-wrap:wrap;">
<div style="width:22%;"><div style="text-align:center; font-size:0.9em;">intensity orig</div><img src="../assets/fns/haar_from_img/haar_three_v_intensity_orig.png" alt="haar_three_v intensity original" style="width:100%; image-rendering:pixelated; image-rendering:crisp-edges;" /></div>
<div style="width:22%;"><div style="text-align:center; font-size:0.9em;">intensity overlay</div><img src="../assets/fns/haar_from_img/haar_three_v_intensity_overlay.png" alt="haar_three_v intensity overlay" style="width:100%; image-rendering:pixelated; image-rendering:crisp-edges;" /></div>
<div style="width:22%;"><div style="text-align:center; font-size:0.9em;">binary orig</div><img src="../assets/fns/haar_from_img/haar_three_v_binary_orig.png" alt="haar_three_v binary original" style="width:100%; image-rendering:pixelated; image-rendering:crisp-edges;" /></div>
<div style="width:22%;"><div style="text-align:center; font-size:0.9em;">binary overlay</div><img src="../assets/fns/haar_from_img/haar_three_v_binary_overlay.png" alt="haar_three_v binary overlay" style="width:100%; image-rendering:pixelated; image-rendering:crisp-edges;" /></div>
</div>
```

## Basic operations 

### Module 

### Functions 


## Reduce functions

### Module
```@docs
UTCGP.number_arithmetic
```

### Functions

```@docs
UTCGP.number_arithmetic.number_sum
```
```jldoctest
julia> number_sum(0,1)
1
```

```@docs
UTCGP.number_arithmetic.number_minus
```
```jldoctest
julia> number_minus(0,1)
-1
```

```@docs
UTCGP.number_arithmetic.number_mult
```
```jldoctest
julia> number_mult(3,3)
9
```

```@docs
UTCGP.number_arithmetic.number_div
```
```jldoctest
julia> number_div(3,3)
1.0
```

```@docs
UTCGP.number_arithmetic.safe_div
```
```jldoctest
julia> safe_div(3,0)
0
```

## Reduce functions

### Module
```@docs
UTCGP.number_reduce
```

### Functions

```@docs
UTCGP.number_reduce.reduce_sum
```
```jldoctest
julia> reduce_sum([1,2,3])
6
```

```@docs
UTCGP.number_reduce.reduce_min
```
```jldoctest
julia> reduce_min([1,2,3])
1
```

```@docs
UTCGP.number_reduce.reduce_max
```
```jldoctest
julia> reduce_max([1,2,3])
3
```

```@docs
UTCGP.number_reduce.reduce_argmin
```
```jldoctest
julia> reduce_argmin([1,2,3])
1
```

```@docs
UTCGP.number_reduce.reduce_argmax
```
```jldoctest
julia> reduce_argmax([1,2,3])
3
```

```@docs
UTCGP.number_reduce.reduce_length
```
```jldoctest
julia> reduce_length(collect(1:10))
10
```
