```@meta
CurrentModule = UTCGP
DocTestSetup = quote
    using UTCGP
end
```

```@contents
Pages = ["image.md"]
```

# Image Lib

## Pooling Functions

```@setup pool_gallery
using UTCGP
using FileIO
using Images

repo_root = normpath(joinpath(dirname(pathof(UTCGP)), ".."))
input_path = joinpath(repo_root, "assets", "000_img.png")
docs_assets_src = joinpath(repo_root, "docs", "src", "assets", "fns", "image_pool")
docs_assets_build = joinpath(repo_root, "docs", "build", "assets", "fns", "image_pool")
mkpath(docs_assets_src)
mkpath(docs_assets_build)

raw = load(input_path)
gray = Gray.(raw)

function _save_gray_pair(name, img)
    g = Gray.(img)
    save(joinpath(docs_assets_src, name), g)
    save(joinpath(docs_assets_build, name), g)
    return nothing
end

function _save_segment_pair(name, img)
    vals = Float64.(float.(img))
    scale = max(maximum(vals), 1.0)
    g = Gray.(vals ./ scale)
    save(joinpath(docs_assets_src, name), g)
    save(joinpath(docs_assets_build, name), g)
    return nothing
end

img_intensity = UTCGP.SImageND(UTCGP.IntensityPixel{Float64}.(Float64.(gray)))
img_binary = UTCGP.SImageND(UTCGP.BinaryPixel{Bool}.(Float64.(gray) .> 0.3))
segment_template = UTCGP.SImageND(UTCGP.SegmentPixel{Int}.(zeros(Int, size(gray)...)))
seg_fn = UTCGP.bundle_image2DSegment_segmentation_factory[:fastscanning_image2D].fn(typeof(segment_template))
img_segment = seg_fn(img_intensity, 0.1)

avg_intensity = UTCGP.bundle_image2DIntensity_pool_factory[:avgpool_resize].fn(typeof(img_intensity))
avg_binary = UTCGP.bundle_image2DBinary_pool_factory[:avgpool_resize].fn(typeof(img_binary))
avg_segment = UTCGP.bundle_image2DSegment_pool_factory[:avgpool_resize].fn(typeof(img_segment))

max_intensity = UTCGP.bundle_image2DIntensity_pool_factory[:maxpool_resize].fn(typeof(img_intensity))
max_binary = UTCGP.bundle_image2DBinary_pool_factory[:maxpool_resize].fn(typeof(img_binary))
max_segment = UTCGP.bundle_image2DSegment_pool_factory[:maxpool_resize].fn(typeof(img_segment))
```

### Avg Pool

```@docs
UTCGP.image_pool.avgpool_resize_image2D_factory
```

#### Intensity image, `k = 2`

```@example pool_gallery
pooled = avg_intensity(img_intensity, 2)
_save_gray_pair("avgpool_resize_intensity_k2_before.png", Float64.(gray)) # hide
_save_gray_pair("avgpool_resize_intensity_k2_after.png", float.(pooled)) # hide
nothing # hide
```

```@raw html
<div style="display:flex; gap:1rem; align-items:flex-start;">
  <img src="../assets/fns/image_pool/avgpool_resize_intensity_k2_before.png" alt="Before avgpool_resize intensity k=2" style="width:50%;" />
  <img src="../assets/fns/image_pool/avgpool_resize_intensity_k2_after.png" alt="After avgpool_resize intensity k=2" style="width:50%;" />
</div>
```

#### Intensity image, `k = 10`

```@example pool_gallery
pooled = avg_intensity(img_intensity, 10)
_save_gray_pair("avgpool_resize_intensity_k10_before.png", Float64.(gray)) # hide
_save_gray_pair("avgpool_resize_intensity_k10_after.png", float.(pooled)) # hide
nothing # hide
```

```@raw html
<div style="display:flex; gap:1rem; align-items:flex-start;">
  <img src="../assets/fns/image_pool/avgpool_resize_intensity_k10_before.png" alt="Before avgpool_resize intensity k=10" style="width:50%;" />
  <img src="../assets/fns/image_pool/avgpool_resize_intensity_k10_after.png" alt="After avgpool_resize intensity k=10" style="width:50%;" />
</div>
```

#### Binary image, `> 0.3`, `k = 5`

```@example pool_gallery
pooled = avg_binary(img_binary, 5)
_save_gray_pair("avgpool_resize_binary_k5_before.png", Float64.(reinterpret(img_binary.img))) # hide
_save_gray_pair("avgpool_resize_binary_k5_after.png", Float64.(reinterpret(pooled.img))) # hide
nothing # hide
```

```@raw html
<div style="display:flex; gap:1rem; align-items:flex-start;">
  <img src="../assets/fns/image_pool/avgpool_resize_binary_k5_before.png" alt="Before avgpool_resize binary k=5" style="width:50%;" />
  <img src="../assets/fns/image_pool/avgpool_resize_binary_k5_after.png" alt="After avgpool_resize binary k=5" style="width:50%;" />
</div>
```

#### Segmented image from `fastscanning_image2D`, `k = 5`

```@example pool_gallery
pooled = avg_segment(img_segment, 5)
_save_segment_pair("avgpool_resize_segment_k5_before.png", reinterpret(img_segment.img)) # hide
_save_segment_pair("avgpool_resize_segment_k5_after.png", reinterpret(pooled.img)) # hide
nothing # hide
```

```@raw html
<div style="display:flex; gap:1rem; align-items:flex-start;">
  <img src="../assets/fns/image_pool/avgpool_resize_segment_k5_before.png" alt="Before avgpool_resize segment k=5" style="width:50%;" />
  <img src="../assets/fns/image_pool/avgpool_resize_segment_k5_after.png" alt="After avgpool_resize segment k=5" style="width:50%;" />
</div>
```

### Max Pool

```@docs
UTCGP.image_pool.maxpool_resize_image2D_factory
```

#### Intensity image, `k = 2`

```@example pool_gallery
pooled = max_intensity(img_intensity, 2)
_save_gray_pair("maxpool_resize_intensity_k2_before.png", Float64.(gray)) # hide
_save_gray_pair("maxpool_resize_intensity_k2_after.png", float.(pooled)) # hide
nothing # hide
```

```@raw html
<div style="display:flex; gap:1rem; align-items:flex-start;">
  <img src="../assets/fns/image_pool/maxpool_resize_intensity_k2_before.png" alt="Before maxpool_resize intensity k=2" style="width:50%;" />
  <img src="../assets/fns/image_pool/maxpool_resize_intensity_k2_after.png" alt="After maxpool_resize intensity k=2" style="width:50%;" />
</div>
```

#### Intensity image, `k = 10`

```@example pool_gallery
pooled = max_intensity(img_intensity, 10)
_save_gray_pair("maxpool_resize_intensity_k10_before.png", Float64.(gray)) # hide
_save_gray_pair("maxpool_resize_intensity_k10_after.png", float.(pooled)) # hide
nothing # hide
```

```@raw html
<div style="display:flex; gap:1rem; align-items:flex-start;">
  <img src="../assets/fns/image_pool/maxpool_resize_intensity_k10_before.png" alt="Before maxpool_resize intensity k=10" style="width:50%;" />
  <img src="../assets/fns/image_pool/maxpool_resize_intensity_k10_after.png" alt="After maxpool_resize intensity k=10" style="width:50%;" />
</div>
```

#### Binary image, `> 0.3`, `k = 5`

```@example pool_gallery
pooled = max_binary(img_binary, 5)
_save_gray_pair("maxpool_resize_binary_k5_before.png", Float64.(reinterpret(img_binary.img))) # hide
_save_gray_pair("maxpool_resize_binary_k5_after.png", Float64.(reinterpret(pooled.img))) # hide
nothing # hide
```

```@raw html
<div style="display:flex; gap:1rem; align-items:flex-start;">
  <img src="../assets/fns/image_pool/maxpool_resize_binary_k5_before.png" alt="Before maxpool_resize binary k=5" style="width:50%;" />
  <img src="../assets/fns/image_pool/maxpool_resize_binary_k5_after.png" alt="After maxpool_resize binary k=5" style="width:50%;" />
</div>
```

#### Segmented image from `fastscanning_image2D`, `k = 5`

```@example pool_gallery
pooled = max_segment(img_segment, 5)
_save_segment_pair("maxpool_resize_segment_k5_before.png", reinterpret(img_segment.img)) # hide
_save_segment_pair("maxpool_resize_segment_k5_after.png", reinterpret(pooled.img)) # hide
nothing # hide
```

```@raw html
<div style="display:flex; gap:1rem; align-items:flex-start;">
  <img src="../assets/fns/image_pool/maxpool_resize_segment_k5_before.png" alt="Before maxpool_resize segment k=5" style="width:50%;" />
  <img src="../assets/fns/image_pool/maxpool_resize_segment_k5_after.png" alt="After maxpool_resize segment k=5" style="width:50%;" />
</div>
```
