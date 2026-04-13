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

## Sliding Window Poolers

In this set of bundles we currently find:

- `meanpool`
- `maxpool`
- `minpool`
- `stdpool`
- `medianpool`
- `uniquecountpool`
- `argmaxcountpool`
- `argmincountpool`
- `iqrpool`

These functions use full sliding `k × k` windows with no padding. Only windows
that fully fit in the image are reduced, using the provided `stride`, and the
reduced image is then resized back to the original size with nearest-neighbor
sampling.

The sliding-window poolers are exposed through:

- `bundle_image2DIntensity_pooler_factory`
- `bundle_image2DBinary_pooler_factory`
- `bundle_image2DSegment_pooler_factory`

```@example
using UTCGP

img = UTCGP.SImageND(UTCGP.IntensityPixel{Float64}.(rand(8, 8)))
mean_intensity = UTCGP.bundle_image2DIntensity_pooler_factory[:meanpool].fn(typeof(img))
iqr_intensity = UTCGP.bundle_image2DIntensity_pooler_factory[:iqrpool].fn(typeof(img))

(typeof(mean_intensity), typeof(iqr_intensity))
```

```@setup pooler_gallery
using UTCGP
using FileIO
using Images

repo_root = normpath(joinpath(dirname(pathof(UTCGP)), ".."))
input_path = joinpath(repo_root, "assets", "000_img.png")
docs_assets_src = joinpath(repo_root, "docs", "src", "assets", "fns", "image_pooler")
docs_assets_build = joinpath(repo_root, "docs", "build", "assets", "fns", "image_pooler")
mkpath(docs_assets_src)
mkpath(docs_assets_build)

raw = load(input_path)
gray = Gray.(raw)

function _save_pooler_gray_pair(name, img)
    vals = Float64.(img)
    if minimum(vals) < 0.0 || maximum(vals) > 1.0
        minv = minimum(vals)
        maxv = maximum(vals)
        vals = maxv == minv ? zeros(size(vals)) : (vals .- minv) ./ (maxv - minv)
    end
    g = Gray.(vals)
    save(joinpath(docs_assets_src, name), g)
    save(joinpath(docs_assets_build, name), g)
    return nothing
end

function _save_pooler_segment_pair(name, img)
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

pooler_syms = (
    :meanpool,
    :maxpool,
    :minpool,
    :stdpool,
    :medianpool,
    :uniquecountpool,
    :argmaxcountpool,
    :argmincountpool,
    :iqrpool,
)
pooler_intensity = Dict(sym => UTCGP.bundle_image2DIntensity_pooler_factory[sym].fn(typeof(img_intensity)) for sym in pooler_syms)
pooler_binary = Dict(sym => UTCGP.bundle_image2DBinary_pooler_factory[sym].fn(typeof(img_binary)) for sym in pooler_syms)
pooler_segment = Dict(sym => UTCGP.bundle_image2DSegment_pooler_factory[sym].fn(typeof(img_segment)) for sym in pooler_syms)
```

### Mean Pool

```@docs
UTCGP.image_pooler.meanpool_image2D_factory
```

#### Intensity image, `k = 3`, `stride = 1`

```@example pooler_gallery
pooled = pooler_intensity[:meanpool](img_intensity, 3, 1)
_save_pooler_gray_pair("meanpool_intensity_k3_s1_before.png", Float64.(gray)) # hide
_save_pooler_gray_pair("meanpool_intensity_k3_s1_after.png", float.(pooled)) # hide
nothing # hide
```

```@raw html
<div id="meanpool-intensity-k3-s1" style="display:flex; gap:1rem; align-items:flex-start;"></div>
<script>
(() => {
  const base = (window.documenterBaseURL || "..").replace(/\/$/, "");
  document.getElementById("meanpool-intensity-k3-s1").innerHTML =
    `<img src="${base}/assets/fns/image_pooler/meanpool_intensity_k3_s1_before.png" alt="Before meanpool intensity k=3 stride=1" style="width:50%;" />
     <img src="${base}/assets/fns/image_pooler/meanpool_intensity_k3_s1_after.png" alt="After meanpool intensity k=3 stride=1" style="width:50%;" />`;
})();
</script>
```

#### Intensity image, `k = 5`, `stride = 2`

```@example pooler_gallery
pooled = pooler_intensity[:meanpool](img_intensity, 5, 2)
_save_pooler_gray_pair("meanpool_intensity_k5_s2_before.png", Float64.(gray)) # hide
_save_pooler_gray_pair("meanpool_intensity_k5_s2_after.png", float.(pooled)) # hide
nothing # hide
```

```@raw html
<div id="meanpool-intensity-k5-s2" style="display:flex; gap:1rem; align-items:flex-start;"></div>
<script>
(() => {
  const base = (window.documenterBaseURL || "..").replace(/\/$/, "");
  document.getElementById("meanpool-intensity-k5-s2").innerHTML =
    `<img src="${base}/assets/fns/image_pooler/meanpool_intensity_k5_s2_before.png" alt="Before meanpool intensity k=5 stride=2" style="width:50%;" />
     <img src="${base}/assets/fns/image_pooler/meanpool_intensity_k5_s2_after.png" alt="After meanpool intensity k=5 stride=2" style="width:50%;" />`;
})();
</script>
```

#### Binary image, `k = 5`, `stride = 2`

```@example pooler_gallery
pooled = pooler_binary[:meanpool](img_binary, 5, 2)
_save_pooler_gray_pair("meanpool_binary_k5_s2_before.png", Float64.(reinterpret(img_binary.img))) # hide
_save_pooler_gray_pair("meanpool_binary_k5_s2_after.png", Float64.(reinterpret(pooled.img))) # hide
nothing # hide
```

```@raw html
<div id="meanpool-binary-k5-s2" style="display:flex; gap:1rem; align-items:flex-start;"></div>
<script>
(() => {
  const base = (window.documenterBaseURL || "..").replace(/\/$/, "");
  document.getElementById("meanpool-binary-k5-s2").innerHTML =
    `<img src="${base}/assets/fns/image_pooler/meanpool_binary_k5_s2_before.png" alt="Before meanpool binary k=5 stride=2" style="width:50%;" />
     <img src="${base}/assets/fns/image_pooler/meanpool_binary_k5_s2_after.png" alt="After meanpool binary k=5 stride=2" style="width:50%;" />`;
})();
</script>
```

#### Segmented image from `fastscanning_image2D`, `k = 5`, `stride = 2`

```@example pooler_gallery
pooled = pooler_segment[:meanpool](img_segment, 5, 2)
_save_pooler_segment_pair("meanpool_segment_k5_s2_before.png", reinterpret(img_segment.img)) # hide
_save_pooler_segment_pair("meanpool_segment_k5_s2_after.png", reinterpret(pooled.img)) # hide
nothing # hide
```

```@raw html
<div id="meanpool-segment-k5-s2" style="display:flex; gap:1rem; align-items:flex-start;"></div>
<script>
(() => {
  const base = (window.documenterBaseURL || "..").replace(/\/$/, "");
  document.getElementById("meanpool-segment-k5-s2").innerHTML =
    `<img src="${base}/assets/fns/image_pooler/meanpool_segment_k5_s2_before.png" alt="Before meanpool segment k=5 stride=2" style="width:50%;" />
     <img src="${base}/assets/fns/image_pooler/meanpool_segment_k5_s2_after.png" alt="After meanpool segment k=5 stride=2" style="width:50%;" />`;
})();
</script>
```

### Max Pool

```@docs
UTCGP.image_pooler.maxpool_image2D_factory
```

#### Intensity image, `k = 3`, `stride = 1`

```@example pooler_gallery
pooled = pooler_intensity[:maxpool](img_intensity, 3, 1)
_save_pooler_gray_pair("maxpool_intensity_k3_s1_before.png", Float64.(gray)) # hide
_save_pooler_gray_pair("maxpool_intensity_k3_s1_after.png", float.(pooled)) # hide
nothing # hide
```

```@raw html
<div id="maxpool-intensity-k3-s1" style="display:flex; gap:1rem; align-items:flex-start;"></div>
<script>
(() => {
  const base = (window.documenterBaseURL || "..").replace(/\/$/, "");
  document.getElementById("maxpool-intensity-k3-s1").innerHTML =
    `<img src="${base}/assets/fns/image_pooler/maxpool_intensity_k3_s1_before.png" alt="Before maxpool intensity k=3 stride=1" style="width:50%;" />
     <img src="${base}/assets/fns/image_pooler/maxpool_intensity_k3_s1_after.png" alt="After maxpool intensity k=3 stride=1" style="width:50%;" />`;
})();
</script>
```

#### Intensity image, `k = 5`, `stride = 2`

```@example pooler_gallery
pooled = pooler_intensity[:maxpool](img_intensity, 5, 2)
_save_pooler_gray_pair("maxpool_intensity_k5_s2_before.png", Float64.(gray)) # hide
_save_pooler_gray_pair("maxpool_intensity_k5_s2_after.png", float.(pooled)) # hide
nothing # hide
```

```@raw html
<div id="maxpool-intensity-k5-s2" style="display:flex; gap:1rem; align-items:flex-start;"></div>
<script>
(() => {
  const base = (window.documenterBaseURL || "..").replace(/\/$/, "");
  document.getElementById("maxpool-intensity-k5-s2").innerHTML =
    `<img src="${base}/assets/fns/image_pooler/maxpool_intensity_k5_s2_before.png" alt="Before maxpool intensity k=5 stride=2" style="width:50%;" />
     <img src="${base}/assets/fns/image_pooler/maxpool_intensity_k5_s2_after.png" alt="After maxpool intensity k=5 stride=2" style="width:50%;" />`;
})();
</script>
```

#### Binary image, `k = 5`, `stride = 2`

```@example pooler_gallery
pooled = pooler_binary[:maxpool](img_binary, 5, 2)
_save_pooler_gray_pair("maxpool_binary_k5_s2_before.png", Float64.(reinterpret(img_binary.img))) # hide
_save_pooler_gray_pair("maxpool_binary_k5_s2_after.png", Float64.(reinterpret(pooled.img))) # hide
nothing # hide
```

```@raw html
<div id="maxpool-binary-k5-s2" style="display:flex; gap:1rem; align-items:flex-start;"></div>
<script>
(() => {
  const base = (window.documenterBaseURL || "..").replace(/\/$/, "");
  document.getElementById("maxpool-binary-k5-s2").innerHTML =
    `<img src="${base}/assets/fns/image_pooler/maxpool_binary_k5_s2_before.png" alt="Before maxpool binary k=5 stride=2" style="width:50%;" />
     <img src="${base}/assets/fns/image_pooler/maxpool_binary_k5_s2_after.png" alt="After maxpool binary k=5 stride=2" style="width:50%;" />`;
})();
</script>
```

#### Segmented image from `fastscanning_image2D`, `k = 5`, `stride = 2`

```@example pooler_gallery
pooled = pooler_segment[:maxpool](img_segment, 5, 2)
_save_pooler_segment_pair("maxpool_segment_k5_s2_before.png", reinterpret(img_segment.img)) # hide
_save_pooler_segment_pair("maxpool_segment_k5_s2_after.png", reinterpret(pooled.img)) # hide
nothing # hide
```

```@raw html
<div id="maxpool-segment-k5-s2" style="display:flex; gap:1rem; align-items:flex-start;"></div>
<script>
(() => {
  const base = (window.documenterBaseURL || "..").replace(/\/$/, "");
  document.getElementById("maxpool-segment-k5-s2").innerHTML =
    `<img src="${base}/assets/fns/image_pooler/maxpool_segment_k5_s2_before.png" alt="Before maxpool segment k=5 stride=2" style="width:50%;" />
     <img src="${base}/assets/fns/image_pooler/maxpool_segment_k5_s2_after.png" alt="After maxpool segment k=5 stride=2" style="width:50%;" />`;
})();
</script>
```

### Min Pool

```@docs
UTCGP.image_pooler.minpool_image2D_factory
```

#### Intensity image, `k = 3`, `stride = 1`

```@example pooler_gallery
pooled = pooler_intensity[:minpool](img_intensity, 3, 1)
_save_pooler_gray_pair("minpool_intensity_k3_s1_before.png", Float64.(gray)) # hide
_save_pooler_gray_pair("minpool_intensity_k3_s1_after.png", float.(pooled)) # hide
nothing # hide
```

```@raw html
<div id="minpool-intensity-k3-s1" style="display:flex; gap:1rem; align-items:flex-start;"></div>
<script>
(() => {
  const base = (window.documenterBaseURL || "..").replace(/\/$/, "");
  document.getElementById("minpool-intensity-k3-s1").innerHTML =
    `<img src="${base}/assets/fns/image_pooler/minpool_intensity_k3_s1_before.png" alt="Before minpool intensity k=3 stride=1" style="width:50%;" />
     <img src="${base}/assets/fns/image_pooler/minpool_intensity_k3_s1_after.png" alt="After minpool intensity k=3 stride=1" style="width:50%;" />`;
})();
</script>
```

#### Intensity image, `k = 5`, `stride = 2`

```@example pooler_gallery
pooled = pooler_intensity[:minpool](img_intensity, 5, 2)
_save_pooler_gray_pair("minpool_intensity_k5_s2_before.png", Float64.(gray)) # hide
_save_pooler_gray_pair("minpool_intensity_k5_s2_after.png", float.(pooled)) # hide
nothing # hide
```

```@raw html
<div id="minpool-intensity-k5-s2" style="display:flex; gap:1rem; align-items:flex-start;"></div>
<script>
(() => {
  const base = (window.documenterBaseURL || "..").replace(/\/$/, "");
  document.getElementById("minpool-intensity-k5-s2").innerHTML =
    `<img src="${base}/assets/fns/image_pooler/minpool_intensity_k5_s2_before.png" alt="Before minpool intensity k=5 stride=2" style="width:50%;" />
     <img src="${base}/assets/fns/image_pooler/minpool_intensity_k5_s2_after.png" alt="After minpool intensity k=5 stride=2" style="width:50%;" />`;
})();
</script>
```

#### Binary image, `k = 5`, `stride = 2`

```@example pooler_gallery
pooled = pooler_binary[:minpool](img_binary, 5, 2)
_save_pooler_gray_pair("minpool_binary_k5_s2_before.png", Float64.(reinterpret(img_binary.img))) # hide
_save_pooler_gray_pair("minpool_binary_k5_s2_after.png", Float64.(reinterpret(pooled.img))) # hide
nothing # hide
```

```@raw html
<div id="minpool-binary-k5-s2" style="display:flex; gap:1rem; align-items:flex-start;"></div>
<script>
(() => {
  const base = (window.documenterBaseURL || "..").replace(/\/$/, "");
  document.getElementById("minpool-binary-k5-s2").innerHTML =
    `<img src="${base}/assets/fns/image_pooler/minpool_binary_k5_s2_before.png" alt="Before minpool binary k=5 stride=2" style="width:50%;" />
     <img src="${base}/assets/fns/image_pooler/minpool_binary_k5_s2_after.png" alt="After minpool binary k=5 stride=2" style="width:50%;" />`;
})();
</script>
```

#### Segmented image from `fastscanning_image2D`, `k = 5`, `stride = 2`

```@example pooler_gallery
pooled = pooler_segment[:minpool](img_segment, 5, 2)
_save_pooler_segment_pair("minpool_segment_k5_s2_before.png", reinterpret(img_segment.img)) # hide
_save_pooler_segment_pair("minpool_segment_k5_s2_after.png", reinterpret(pooled.img)) # hide
nothing # hide
```

```@raw html
<div id="minpool-segment-k5-s2" style="display:flex; gap:1rem; align-items:flex-start;"></div>
<script>
(() => {
  const base = (window.documenterBaseURL || "..").replace(/\/$/, "");
  document.getElementById("minpool-segment-k5-s2").innerHTML =
    `<img src="${base}/assets/fns/image_pooler/minpool_segment_k5_s2_before.png" alt="Before minpool segment k=5 stride=2" style="width:50%;" />
     <img src="${base}/assets/fns/image_pooler/minpool_segment_k5_s2_after.png" alt="After minpool segment k=5 stride=2" style="width:50%;" />`;
})();
</script>
```

### Std Pool

```@docs
UTCGP.image_pooler.stdpool_image2D_factory
```

#### Intensity image, `k = 3`, `stride = 1`

```@example pooler_gallery
pooled = pooler_intensity[:stdpool](img_intensity, 3, 1)
_save_pooler_gray_pair("stdpool_intensity_k3_s1_before.png", Float64.(gray)) # hide
_save_pooler_gray_pair("stdpool_intensity_k3_s1_after.png", float.(pooled)) # hide
nothing # hide
```

```@raw html
<div id="stdpool-intensity-k3-s1" style="display:flex; gap:1rem; align-items:flex-start;"></div>
<script>
(() => {
  const base = (window.documenterBaseURL || "..").replace(/\/$/, "");
  document.getElementById("stdpool-intensity-k3-s1").innerHTML =
    `<img src="${base}/assets/fns/image_pooler/stdpool_intensity_k3_s1_before.png" alt="Before stdpool intensity k=3 stride=1" style="width:50%;" />
     <img src="${base}/assets/fns/image_pooler/stdpool_intensity_k3_s1_after.png" alt="After stdpool intensity k=3 stride=1" style="width:50%;" />`;
})();
</script>
```

#### Intensity image, `k = 5`, `stride = 2`

```@example pooler_gallery
pooled = pooler_intensity[:stdpool](img_intensity, 5, 2)
_save_pooler_gray_pair("stdpool_intensity_k5_s2_before.png", Float64.(gray)) # hide
_save_pooler_gray_pair("stdpool_intensity_k5_s2_after.png", float.(pooled)) # hide
nothing # hide
```

```@raw html
<div id="stdpool-intensity-k5-s2" style="display:flex; gap:1rem; align-items:flex-start;"></div>
<script>
(() => {
  const base = (window.documenterBaseURL || "..").replace(/\/$/, "");
  document.getElementById("stdpool-intensity-k5-s2").innerHTML =
    `<img src="${base}/assets/fns/image_pooler/stdpool_intensity_k5_s2_before.png" alt="Before stdpool intensity k=5 stride=2" style="width:50%;" />
     <img src="${base}/assets/fns/image_pooler/stdpool_intensity_k5_s2_after.png" alt="After stdpool intensity k=5 stride=2" style="width:50%;" />`;
})();
</script>
```

#### Binary image, `k = 5`, `stride = 2`

```@example pooler_gallery
pooled = pooler_binary[:stdpool](img_binary, 5, 2)
_save_pooler_gray_pair("stdpool_binary_k5_s2_before.png", Float64.(reinterpret(img_binary.img))) # hide
_save_pooler_gray_pair("stdpool_binary_k5_s2_after.png", Float64.(reinterpret(pooled.img))) # hide
nothing # hide
```

```@raw html
<div id="stdpool-binary-k5-s2" style="display:flex; gap:1rem; align-items:flex-start;"></div>
<script>
(() => {
  const base = (window.documenterBaseURL || "..").replace(/\/$/, "");
  document.getElementById("stdpool-binary-k5-s2").innerHTML =
    `<img src="${base}/assets/fns/image_pooler/stdpool_binary_k5_s2_before.png" alt="Before stdpool binary k=5 stride=2" style="width:50%;" />
     <img src="${base}/assets/fns/image_pooler/stdpool_binary_k5_s2_after.png" alt="After stdpool binary k=5 stride=2" style="width:50%;" />`;
})();
</script>
```

#### Segmented image from `fastscanning_image2D`, `k = 5`, `stride = 2`

```@example pooler_gallery
pooled = pooler_segment[:stdpool](img_segment, 5, 2)
_save_pooler_segment_pair("stdpool_segment_k5_s2_before.png", reinterpret(img_segment.img)) # hide
_save_pooler_segment_pair("stdpool_segment_k5_s2_after.png", reinterpret(pooled.img)) # hide
nothing # hide
```

```@raw html
<div id="stdpool-segment-k5-s2" style="display:flex; gap:1rem; align-items:flex-start;"></div>
<script>
(() => {
  const base = (window.documenterBaseURL || "..").replace(/\/$/, "");
  document.getElementById("stdpool-segment-k5-s2").innerHTML =
    `<img src="${base}/assets/fns/image_pooler/stdpool_segment_k5_s2_before.png" alt="Before stdpool segment k=5 stride=2" style="width:50%;" />
     <img src="${base}/assets/fns/image_pooler/stdpool_segment_k5_s2_after.png" alt="After stdpool segment k=5 stride=2" style="width:50%;" />`;
})();
</script>
```

### Median Pool

```@docs
UTCGP.image_pooler.medianpool_image2D_factory
```

#### Intensity image, `k = 3`, `stride = 1`

```@example pooler_gallery
pooled = pooler_intensity[:medianpool](img_intensity, 3, 1)
_save_pooler_gray_pair("medianpool_intensity_k3_s1_before.png", Float64.(gray)) # hide
_save_pooler_gray_pair("medianpool_intensity_k3_s1_after.png", float.(pooled)) # hide
nothing # hide
```

```@raw html
<div id="medianpool-intensity-k3-s1" style="display:flex; gap:1rem; align-items:flex-start;"></div>
<script>
(() => {
  const base = (window.documenterBaseURL || "..").replace(/\/$/, "");
  document.getElementById("medianpool-intensity-k3-s1").innerHTML =
    `<img src="${base}/assets/fns/image_pooler/medianpool_intensity_k3_s1_before.png" alt="Before medianpool intensity k=3 stride=1" style="width:50%;" />
     <img src="${base}/assets/fns/image_pooler/medianpool_intensity_k3_s1_after.png" alt="After medianpool intensity k=3 stride=1" style="width:50%;" />`;
})();
</script>
```

#### Intensity image, `k = 5`, `stride = 2`

```@example pooler_gallery
pooled = pooler_intensity[:medianpool](img_intensity, 5, 2)
_save_pooler_gray_pair("medianpool_intensity_k5_s2_before.png", Float64.(gray)) # hide
_save_pooler_gray_pair("medianpool_intensity_k5_s2_after.png", float.(pooled)) # hide
nothing # hide
```

```@raw html
<div id="medianpool-intensity-k5-s2" style="display:flex; gap:1rem; align-items:flex-start;"></div>
<script>
(() => {
  const base = (window.documenterBaseURL || "..").replace(/\/$/, "");
  document.getElementById("medianpool-intensity-k5-s2").innerHTML =
    `<img src="${base}/assets/fns/image_pooler/medianpool_intensity_k5_s2_before.png" alt="Before medianpool intensity k=5 stride=2" style="width:50%;" />
     <img src="${base}/assets/fns/image_pooler/medianpool_intensity_k5_s2_after.png" alt="After medianpool intensity k=5 stride=2" style="width:50%;" />`;
})();
</script>
```

#### Binary image, `k = 5`, `stride = 2`

```@example pooler_gallery
pooled = pooler_binary[:medianpool](img_binary, 5, 2)
_save_pooler_gray_pair("medianpool_binary_k5_s2_before.png", Float64.(reinterpret(img_binary.img))) # hide
_save_pooler_gray_pair("medianpool_binary_k5_s2_after.png", Float64.(reinterpret(pooled.img))) # hide
nothing # hide
```

```@raw html
<div id="medianpool-binary-k5-s2" style="display:flex; gap:1rem; align-items:flex-start;"></div>
<script>
(() => {
  const base = (window.documenterBaseURL || "..").replace(/\/$/, "");
  document.getElementById("medianpool-binary-k5-s2").innerHTML =
    `<img src="${base}/assets/fns/image_pooler/medianpool_binary_k5_s2_before.png" alt="Before medianpool binary k=5 stride=2" style="width:50%;" />
     <img src="${base}/assets/fns/image_pooler/medianpool_binary_k5_s2_after.png" alt="After medianpool binary k=5 stride=2" style="width:50%;" />`;
})();
</script>
```

#### Segmented image from `fastscanning_image2D`, `k = 5`, `stride = 2`

```@example pooler_gallery
pooled = pooler_segment[:medianpool](img_segment, 5, 2)
_save_pooler_segment_pair("medianpool_segment_k5_s2_before.png", reinterpret(img_segment.img)) # hide
_save_pooler_segment_pair("medianpool_segment_k5_s2_after.png", reinterpret(pooled.img)) # hide
nothing # hide
```

```@raw html
<div id="medianpool-segment-k5-s2" style="display:flex; gap:1rem; align-items:flex-start;"></div>
<script>
(() => {
  const base = (window.documenterBaseURL || "..").replace(/\/$/, "");
  document.getElementById("medianpool-segment-k5-s2").innerHTML =
    `<img src="${base}/assets/fns/image_pooler/medianpool_segment_k5_s2_before.png" alt="Before medianpool segment k=5 stride=2" style="width:50%;" />
     <img src="${base}/assets/fns/image_pooler/medianpool_segment_k5_s2_after.png" alt="After medianpool segment k=5 stride=2" style="width:50%;" />`;
})();
</script>
```

### Unique Count Pool

```@docs
UTCGP.image_pooler.uniquecountpool_image2D_factory
```

#### Intensity image, `k = 3`, `stride = 1`

```@example pooler_gallery
pooled = pooler_intensity[:uniquecountpool](img_intensity, 3, 1)
_save_pooler_gray_pair("uniquecountpool_intensity_k3_s1_before.png", Float64.(gray)) # hide
_save_pooler_gray_pair("uniquecountpool_intensity_k3_s1_after.png", float.(pooled)) # hide
nothing # hide
```

```@raw html
<div id="uniquecountpool-intensity-k3-s1" style="display:flex; gap:1rem; align-items:flex-start;"></div>
<script>
(() => {
  const base = (window.documenterBaseURL || "..").replace(/\/$/, "");
  document.getElementById("uniquecountpool-intensity-k3-s1").innerHTML =
    `<img src="${base}/assets/fns/image_pooler/uniquecountpool_intensity_k3_s1_before.png" alt="Before uniquecountpool intensity k=3 stride=1" style="width:50%;" />
     <img src="${base}/assets/fns/image_pooler/uniquecountpool_intensity_k3_s1_after.png" alt="After uniquecountpool intensity k=3 stride=1" style="width:50%;" />`;
})();
</script>
```

#### Intensity image, `k = 5`, `stride = 2`

```@example pooler_gallery
pooled = pooler_intensity[:uniquecountpool](img_intensity, 5, 2)
_save_pooler_gray_pair("uniquecountpool_intensity_k5_s2_before.png", Float64.(gray)) # hide
_save_pooler_gray_pair("uniquecountpool_intensity_k5_s2_after.png", float.(pooled)) # hide
nothing # hide
```

```@raw html
<div id="uniquecountpool-intensity-k5-s2" style="display:flex; gap:1rem; align-items:flex-start;"></div>
<script>
(() => {
  const base = (window.documenterBaseURL || "..").replace(/\/$/, "");
  document.getElementById("uniquecountpool-intensity-k5-s2").innerHTML =
    `<img src="${base}/assets/fns/image_pooler/uniquecountpool_intensity_k5_s2_before.png" alt="Before uniquecountpool intensity k=5 stride=2" style="width:50%;" />
     <img src="${base}/assets/fns/image_pooler/uniquecountpool_intensity_k5_s2_after.png" alt="After uniquecountpool intensity k=5 stride=2" style="width:50%;" />`;
})();
</script>
```

#### Binary image, `k = 5`, `stride = 2`

```@example pooler_gallery
pooled = pooler_binary[:uniquecountpool](img_binary, 5, 2)
_save_pooler_gray_pair("uniquecountpool_binary_k5_s2_before.png", Float64.(reinterpret(img_binary.img))) # hide
_save_pooler_gray_pair("uniquecountpool_binary_k5_s2_after.png", Float64.(reinterpret(pooled.img))) # hide
nothing # hide
```

```@raw html
<div id="uniquecountpool-binary-k5-s2" style="display:flex; gap:1rem; align-items:flex-start;"></div>
<script>
(() => {
  const base = (window.documenterBaseURL || "..").replace(/\/$/, "");
  document.getElementById("uniquecountpool-binary-k5-s2").innerHTML =
    `<img src="${base}/assets/fns/image_pooler/uniquecountpool_binary_k5_s2_before.png" alt="Before uniquecountpool binary k=5 stride=2" style="width:50%;" />
     <img src="${base}/assets/fns/image_pooler/uniquecountpool_binary_k5_s2_after.png" alt="After uniquecountpool binary k=5 stride=2" style="width:50%;" />`;
})();
</script>
```

#### Segmented image from `fastscanning_image2D`, `k = 5`, `stride = 2`

```@example pooler_gallery
pooled = pooler_segment[:uniquecountpool](img_segment, 5, 2)
_save_pooler_segment_pair("uniquecountpool_segment_k5_s2_before.png", reinterpret(img_segment.img)) # hide
_save_pooler_segment_pair("uniquecountpool_segment_k5_s2_after.png", reinterpret(pooled.img)) # hide
nothing # hide
```

```@raw html
<div id="uniquecountpool-segment-k5-s2" style="display:flex; gap:1rem; align-items:flex-start;"></div>
<script>
(() => {
  const base = (window.documenterBaseURL || "..").replace(/\/$/, "");
  document.getElementById("uniquecountpool-segment-k5-s2").innerHTML =
    `<img src="${base}/assets/fns/image_pooler/uniquecountpool_segment_k5_s2_before.png" alt="Before uniquecountpool segment k=5 stride=2" style="width:50%;" />
     <img src="${base}/assets/fns/image_pooler/uniquecountpool_segment_k5_s2_after.png" alt="After uniquecountpool segment k=5 stride=2" style="width:50%;" />`;
})();
</script>
```

### Argmax Count Pool

```@docs
UTCGP.image_pooler.argmaxcountpool_image2D_factory
```

#### Intensity image, `k = 3`, `stride = 1`

```@example pooler_gallery
pooled = pooler_intensity[:argmaxcountpool](img_intensity, 3, 1)
_save_pooler_gray_pair("argmaxcountpool_intensity_k3_s1_before.png", Float64.(gray)) # hide
_save_pooler_gray_pair("argmaxcountpool_intensity_k3_s1_after.png", float.(pooled)) # hide
nothing # hide
```

```@raw html
<div id="argmaxcountpool-intensity-k3-s1" style="display:flex; gap:1rem; align-items:flex-start;"></div>
<script>
(() => {
  const base = (window.documenterBaseURL || "..").replace(/\/$/, "");
  document.getElementById("argmaxcountpool-intensity-k3-s1").innerHTML =
    `<img src="${base}/assets/fns/image_pooler/argmaxcountpool_intensity_k3_s1_before.png" alt="Before argmaxcountpool intensity k=3 stride=1" style="width:50%;" />
     <img src="${base}/assets/fns/image_pooler/argmaxcountpool_intensity_k3_s1_after.png" alt="After argmaxcountpool intensity k=3 stride=1" style="width:50%;" />`;
})();
</script>
```

#### Intensity image, `k = 5`, `stride = 2`

```@example pooler_gallery
pooled = pooler_intensity[:argmaxcountpool](img_intensity, 5, 2)
_save_pooler_gray_pair("argmaxcountpool_intensity_k5_s2_before.png", Float64.(gray)) # hide
_save_pooler_gray_pair("argmaxcountpool_intensity_k5_s2_after.png", float.(pooled)) # hide
nothing # hide
```

```@raw html
<div id="argmaxcountpool-intensity-k5-s2" style="display:flex; gap:1rem; align-items:flex-start;"></div>
<script>
(() => {
  const base = (window.documenterBaseURL || "..").replace(/\/$/, "");
  document.getElementById("argmaxcountpool-intensity-k5-s2").innerHTML =
    `<img src="${base}/assets/fns/image_pooler/argmaxcountpool_intensity_k5_s2_before.png" alt="Before argmaxcountpool intensity k=5 stride=2" style="width:50%;" />
     <img src="${base}/assets/fns/image_pooler/argmaxcountpool_intensity_k5_s2_after.png" alt="After argmaxcountpool intensity k=5 stride=2" style="width:50%;" />`;
})();
</script>
```

#### Binary image, `k = 5`, `stride = 2`

```@example pooler_gallery
pooled = pooler_binary[:argmaxcountpool](img_binary, 5, 2)
_save_pooler_gray_pair("argmaxcountpool_binary_k5_s2_before.png", Float64.(reinterpret(img_binary.img))) # hide
_save_pooler_gray_pair("argmaxcountpool_binary_k5_s2_after.png", Float64.(reinterpret(pooled.img))) # hide
nothing # hide
```

```@raw html
<div id="argmaxcountpool-binary-k5-s2" style="display:flex; gap:1rem; align-items:flex-start;"></div>
<script>
(() => {
  const base = (window.documenterBaseURL || "..").replace(/\/$/, "");
  document.getElementById("argmaxcountpool-binary-k5-s2").innerHTML =
    `<img src="${base}/assets/fns/image_pooler/argmaxcountpool_binary_k5_s2_before.png" alt="Before argmaxcountpool binary k=5 stride=2" style="width:50%;" />
     <img src="${base}/assets/fns/image_pooler/argmaxcountpool_binary_k5_s2_after.png" alt="After argmaxcountpool binary k=5 stride=2" style="width:50%;" />`;
})();
</script>
```

#### Segmented image from `fastscanning_image2D`, `k = 5`, `stride = 2`

```@example pooler_gallery
pooled = pooler_segment[:argmaxcountpool](img_segment, 5, 2)
_save_pooler_segment_pair("argmaxcountpool_segment_k5_s2_before.png", reinterpret(img_segment.img)) # hide
_save_pooler_segment_pair("argmaxcountpool_segment_k5_s2_after.png", reinterpret(pooled.img)) # hide
nothing # hide
```

```@raw html
<div id="argmaxcountpool-segment-k5-s2" style="display:flex; gap:1rem; align-items:flex-start;"></div>
<script>
(() => {
  const base = (window.documenterBaseURL || "..").replace(/\/$/, "");
  document.getElementById("argmaxcountpool-segment-k5-s2").innerHTML =
    `<img src="${base}/assets/fns/image_pooler/argmaxcountpool_segment_k5_s2_before.png" alt="Before argmaxcountpool segment k=5 stride=2" style="width:50%;" />
     <img src="${base}/assets/fns/image_pooler/argmaxcountpool_segment_k5_s2_after.png" alt="After argmaxcountpool segment k=5 stride=2" style="width:50%;" />`;
})();
</script>
```

### Argmin Count Pool

```@docs
UTCGP.image_pooler.argmincountpool_image2D_factory
```

#### Intensity image, `k = 3`, `stride = 1`

```@example pooler_gallery
pooled = pooler_intensity[:argmincountpool](img_intensity, 3, 1)
_save_pooler_gray_pair("argmincountpool_intensity_k3_s1_before.png", Float64.(gray)) # hide
_save_pooler_gray_pair("argmincountpool_intensity_k3_s1_after.png", float.(pooled)) # hide
nothing # hide
```

```@raw html
<div id="argmincountpool-intensity-k3-s1" style="display:flex; gap:1rem; align-items:flex-start;"></div>
<script>
(() => {
  const base = (window.documenterBaseURL || "..").replace(/\/$/, "");
  document.getElementById("argmincountpool-intensity-k3-s1").innerHTML =
    `<img src="${base}/assets/fns/image_pooler/argmincountpool_intensity_k3_s1_before.png" alt="Before argmincountpool intensity k=3 stride=1" style="width:50%;" />
     <img src="${base}/assets/fns/image_pooler/argmincountpool_intensity_k3_s1_after.png" alt="After argmincountpool intensity k=3 stride=1" style="width:50%;" />`;
})();
</script>
```

#### Intensity image, `k = 5`, `stride = 2`

```@example pooler_gallery
pooled = pooler_intensity[:argmincountpool](img_intensity, 5, 2)
_save_pooler_gray_pair("argmincountpool_intensity_k5_s2_before.png", Float64.(gray)) # hide
_save_pooler_gray_pair("argmincountpool_intensity_k5_s2_after.png", float.(pooled)) # hide
nothing # hide
```

```@raw html
<div id="argmincountpool-intensity-k5-s2" style="display:flex; gap:1rem; align-items:flex-start;"></div>
<script>
(() => {
  const base = (window.documenterBaseURL || "..").replace(/\/$/, "");
  document.getElementById("argmincountpool-intensity-k5-s2").innerHTML =
    `<img src="${base}/assets/fns/image_pooler/argmincountpool_intensity_k5_s2_before.png" alt="Before argmincountpool intensity k=5 stride=2" style="width:50%;" />
     <img src="${base}/assets/fns/image_pooler/argmincountpool_intensity_k5_s2_after.png" alt="After argmincountpool intensity k=5 stride=2" style="width:50%;" />`;
})();
</script>
```

#### Binary image, `k = 5`, `stride = 2`

```@example pooler_gallery
pooled = pooler_binary[:argmincountpool](img_binary, 5, 2)
_save_pooler_gray_pair("argmincountpool_binary_k5_s2_before.png", Float64.(reinterpret(img_binary.img))) # hide
_save_pooler_gray_pair("argmincountpool_binary_k5_s2_after.png", Float64.(reinterpret(pooled.img))) # hide
nothing # hide
```

```@raw html
<div id="argmincountpool-binary-k5-s2" style="display:flex; gap:1rem; align-items:flex-start;"></div>
<script>
(() => {
  const base = (window.documenterBaseURL || "..").replace(/\/$/, "");
  document.getElementById("argmincountpool-binary-k5-s2").innerHTML =
    `<img src="${base}/assets/fns/image_pooler/argmincountpool_binary_k5_s2_before.png" alt="Before argmincountpool binary k=5 stride=2" style="width:50%;" />
     <img src="${base}/assets/fns/image_pooler/argmincountpool_binary_k5_s2_after.png" alt="After argmincountpool binary k=5 stride=2" style="width:50%;" />`;
})();
</script>
```

#### Segmented image from `fastscanning_image2D`, `k = 5`, `stride = 2`

```@example pooler_gallery
pooled = pooler_segment[:argmincountpool](img_segment, 5, 2)
_save_pooler_segment_pair("argmincountpool_segment_k5_s2_before.png", reinterpret(img_segment.img)) # hide
_save_pooler_segment_pair("argmincountpool_segment_k5_s2_after.png", reinterpret(pooled.img)) # hide
nothing # hide
```

```@raw html
<div id="argmincountpool-segment-k5-s2" style="display:flex; gap:1rem; align-items:flex-start;"></div>
<script>
(() => {
  const base = (window.documenterBaseURL || "..").replace(/\/$/, "");
  document.getElementById("argmincountpool-segment-k5-s2").innerHTML =
    `<img src="${base}/assets/fns/image_pooler/argmincountpool_segment_k5_s2_before.png" alt="Before argmincountpool segment k=5 stride=2" style="width:50%;" />
     <img src="${base}/assets/fns/image_pooler/argmincountpool_segment_k5_s2_after.png" alt="After argmincountpool segment k=5 stride=2" style="width:50%;" />`;
})();
</script>
```

### IQR Pool

```@docs
UTCGP.image_pooler.iqrpool_image2D_factory
```

#### Intensity image, `k = 3`, `stride = 1`

```@example pooler_gallery
pooled = pooler_intensity[:iqrpool](img_intensity, 3, 1)
_save_pooler_gray_pair("iqrpool_intensity_k3_s1_before.png", Float64.(gray)) # hide
_save_pooler_gray_pair("iqrpool_intensity_k3_s1_after.png", float.(pooled)) # hide
nothing # hide
```

```@raw html
<div id="iqrpool-intensity-k3-s1" style="display:flex; gap:1rem; align-items:flex-start;"></div>
<script>
(() => {
  const base = (window.documenterBaseURL || "..").replace(/\/$/, "");
  document.getElementById("iqrpool-intensity-k3-s1").innerHTML =
    `<img src="${base}/assets/fns/image_pooler/iqrpool_intensity_k3_s1_before.png" alt="Before iqrpool intensity k=3 stride=1" style="width:50%;" />
     <img src="${base}/assets/fns/image_pooler/iqrpool_intensity_k3_s1_after.png" alt="After iqrpool intensity k=3 stride=1" style="width:50%;" />`;
})();
</script>
```

#### Intensity image, `k = 5`, `stride = 2`

```@example pooler_gallery
pooled = pooler_intensity[:iqrpool](img_intensity, 5, 2)
_save_pooler_gray_pair("iqrpool_intensity_k5_s2_before.png", Float64.(gray)) # hide
_save_pooler_gray_pair("iqrpool_intensity_k5_s2_after.png", float.(pooled)) # hide
nothing # hide
```

```@raw html
<div id="iqrpool-intensity-k5-s2" style="display:flex; gap:1rem; align-items:flex-start;"></div>
<script>
(() => {
  const base = (window.documenterBaseURL || "..").replace(/\/$/, "");
  document.getElementById("iqrpool-intensity-k5-s2").innerHTML =
    `<img src="${base}/assets/fns/image_pooler/iqrpool_intensity_k5_s2_before.png" alt="Before iqrpool intensity k=5 stride=2" style="width:50%;" />
     <img src="${base}/assets/fns/image_pooler/iqrpool_intensity_k5_s2_after.png" alt="After iqrpool intensity k=5 stride=2" style="width:50%;" />`;
})();
</script>
```

#### Binary image, `k = 5`, `stride = 2`

```@example pooler_gallery
pooled = pooler_binary[:iqrpool](img_binary, 5, 2)
_save_pooler_gray_pair("iqrpool_binary_k5_s2_before.png", Float64.(reinterpret(img_binary.img))) # hide
_save_pooler_gray_pair("iqrpool_binary_k5_s2_after.png", Float64.(reinterpret(pooled.img))) # hide
nothing # hide
```

```@raw html
<div id="iqrpool-binary-k5-s2" style="display:flex; gap:1rem; align-items:flex-start;"></div>
<script>
(() => {
  const base = (window.documenterBaseURL || "..").replace(/\/$/, "");
  document.getElementById("iqrpool-binary-k5-s2").innerHTML =
    `<img src="${base}/assets/fns/image_pooler/iqrpool_binary_k5_s2_before.png" alt="Before iqrpool binary k=5 stride=2" style="width:50%;" />
     <img src="${base}/assets/fns/image_pooler/iqrpool_binary_k5_s2_after.png" alt="After iqrpool binary k=5 stride=2" style="width:50%;" />`;
})();
</script>
```

#### Segmented image from `fastscanning_image2D`, `k = 5`, `stride = 2`

```@example pooler_gallery
pooled = pooler_segment[:iqrpool](img_segment, 5, 2)
_save_pooler_segment_pair("iqrpool_segment_k5_s2_before.png", reinterpret(img_segment.img)) # hide
_save_pooler_segment_pair("iqrpool_segment_k5_s2_after.png", reinterpret(pooled.img)) # hide
nothing # hide
```

```@raw html
<div id="iqrpool-segment-k5-s2" style="display:flex; gap:1rem; align-items:flex-start;"></div>
<script>
(() => {
  const base = (window.documenterBaseURL || "..").replace(/\/$/, "");
  document.getElementById("iqrpool-segment-k5-s2").innerHTML =
    `<img src="${base}/assets/fns/image_pooler/iqrpool_segment_k5_s2_before.png" alt="Before iqrpool segment k=5 stride=2" style="width:50%;" />
     <img src="${base}/assets/fns/image_pooler/iqrpool_segment_k5_s2_after.png" alt="After iqrpool segment k=5 stride=2" style="width:50%;" />`;
})();
</script>
```

## Block Pooling Functions

In this set of bundles we currently find:

- `avgpool_blocks`
- `maxpool_blocks`
- `minpool_blocks`
- `avgpool_cross_blocks`
- `maxpool_cross_blocks`
- `minpool_cross_blocks`

The pooling functions are exposed through the typed image pooling bundles:

- `bundle_image2DIntensity_pool_factory`
- `bundle_image2DBinary_pool_factory`
- `bundle_image2DSegment_pool_factory`

These functions use non-overlapping block windows scanned from left to right and
top to bottom. Each block is reduced to a single value, and that value is
written back over the covered block. There is no padding; the last block on the
right or bottom may be partial if the image size is not divisible by `k`.

To obtain a callable function, first select the function from the bundle, then
specialize it on the concrete image type.

```@example
using UTCGP

img = UTCGP.SImageND(UTCGP.IntensityPixel{Float64}.(rand(4, 4)))
avg_intensity = UTCGP.bundle_image2DIntensity_pool_factory[:avgpool_blocks].fn(typeof(img))
max_intensity = UTCGP.bundle_image2DIntensity_pool_factory[:maxpool_blocks].fn(typeof(img))

(typeof(avg_intensity), typeof(max_intensity))
```

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

avg_intensity = UTCGP.bundle_image2DIntensity_pool_factory[:avgpool_blocks].fn(typeof(img_intensity))
avg_binary = UTCGP.bundle_image2DBinary_pool_factory[:avgpool_blocks].fn(typeof(img_binary))
avg_segment = UTCGP.bundle_image2DSegment_pool_factory[:avgpool_blocks].fn(typeof(img_segment))

max_intensity = UTCGP.bundle_image2DIntensity_pool_factory[:maxpool_blocks].fn(typeof(img_intensity))
max_binary = UTCGP.bundle_image2DBinary_pool_factory[:maxpool_blocks].fn(typeof(img_binary))
max_segment = UTCGP.bundle_image2DSegment_pool_factory[:maxpool_blocks].fn(typeof(img_segment))

min_intensity = UTCGP.bundle_image2DIntensity_pool_factory[:minpool_blocks].fn(typeof(img_intensity))
min_binary = UTCGP.bundle_image2DBinary_pool_factory[:minpool_blocks].fn(typeof(img_binary))
min_segment = UTCGP.bundle_image2DSegment_pool_factory[:minpool_blocks].fn(typeof(img_segment))

cross_demo = zeros(Float64, 10, 10)
cross_demo[3, 1:5] .= 1.0
cross_demo[1:5, 3] .= 1.0
cross_demo[3, 6:10] .= 0.8
cross_demo[1:5, 8] .= 0.8
cross_demo[8, 1:5] .= 0.6
cross_demo[6:10, 3] .= 0.6
cross_demo[8, 6:10] .= 0.4
cross_demo[6:10, 8] .= 0.4

img_cross_demo = UTCGP.SImageND(UTCGP.IntensityPixel{Float64}.(cross_demo))
avg_cross_intensity = UTCGP.bundle_image2DIntensity_pool_factory[:avgpool_cross_blocks].fn(typeof(img_cross_demo))
max_cross_intensity = UTCGP.bundle_image2DIntensity_pool_factory[:maxpool_cross_blocks].fn(typeof(img_cross_demo))
min_cross_intensity = UTCGP.bundle_image2DIntensity_pool_factory[:minpool_cross_blocks].fn(typeof(img_cross_demo))

avg_cross_binary = UTCGP.bundle_image2DBinary_pool_factory[:avgpool_cross_blocks].fn(typeof(img_binary))
avg_cross_segment = UTCGP.bundle_image2DSegment_pool_factory[:avgpool_cross_blocks].fn(typeof(img_segment))

max_cross_binary = UTCGP.bundle_image2DBinary_pool_factory[:maxpool_cross_blocks].fn(typeof(img_binary))
max_cross_segment = UTCGP.bundle_image2DSegment_pool_factory[:maxpool_cross_blocks].fn(typeof(img_segment))

min_cross_binary = UTCGP.bundle_image2DBinary_pool_factory[:minpool_cross_blocks].fn(typeof(img_binary))
min_cross_segment = UTCGP.bundle_image2DSegment_pool_factory[:minpool_cross_blocks].fn(typeof(img_segment))
```

### Avg Pool

```@docs
UTCGP.image_pool.avgpool_blocks_image2D_factory
```

#### Intensity image, `k = 2`

```@example pool_gallery
pooled = avg_intensity(img_intensity, 2)
_save_gray_pair("avgpool_blocks_intensity_k2_before.png", Float64.(gray)) # hide
_save_gray_pair("avgpool_blocks_intensity_k2_after.png", float.(pooled)) # hide
nothing # hide
```

```@raw html
<div id="avgpool-intensity-k2" style="display:flex; gap:1rem; align-items:flex-start;"></div>
<script>
(() => {
  const base = (window.documenterBaseURL || "..").replace(/\/$/, "");
  document.getElementById("avgpool-intensity-k2").innerHTML =
    `<img src="${base}/assets/fns/image_pool/avgpool_blocks_intensity_k2_before.png" alt="Before avgpool_blocks intensity k=2" style="width:50%;" />
     <img src="${base}/assets/fns/image_pool/avgpool_blocks_intensity_k2_after.png" alt="After avgpool_blocks intensity k=2" style="width:50%;" />`;
})();
</script>
```

#### Intensity image, `k = 10`

```@example pool_gallery
pooled = avg_intensity(img_intensity, 10)
_save_gray_pair("avgpool_blocks_intensity_k10_before.png", Float64.(gray)) # hide
_save_gray_pair("avgpool_blocks_intensity_k10_after.png", float.(pooled)) # hide
nothing # hide
```

```@raw html
<div id="avgpool-intensity-k10" style="display:flex; gap:1rem; align-items:flex-start;"></div>
<script>
(() => {
  const base = (window.documenterBaseURL || "..").replace(/\/$/, "");
  document.getElementById("avgpool-intensity-k10").innerHTML =
    `<img src="${base}/assets/fns/image_pool/avgpool_blocks_intensity_k10_before.png" alt="Before avgpool_blocks intensity k=10" style="width:50%;" />
     <img src="${base}/assets/fns/image_pool/avgpool_blocks_intensity_k10_after.png" alt="After avgpool_blocks intensity k=10" style="width:50%;" />`;
})();
</script>
```

#### Binary image, `> 0.3`, `k = 5`

```@example pool_gallery
pooled = avg_binary(img_binary, 5)
_save_gray_pair("avgpool_blocks_binary_k5_before.png", Float64.(reinterpret(img_binary.img))) # hide
_save_gray_pair("avgpool_blocks_binary_k5_after.png", Float64.(reinterpret(pooled.img))) # hide
nothing # hide
```

```@raw html
<div id="avgpool-binary-k5" style="display:flex; gap:1rem; align-items:flex-start;"></div>
<script>
(() => {
  const base = (window.documenterBaseURL || "..").replace(/\/$/, "");
  document.getElementById("avgpool-binary-k5").innerHTML =
    `<img src="${base}/assets/fns/image_pool/avgpool_blocks_binary_k5_before.png" alt="Before avgpool_blocks binary k=5" style="width:50%;" />
     <img src="${base}/assets/fns/image_pool/avgpool_blocks_binary_k5_after.png" alt="After avgpool_blocks binary k=5" style="width:50%;" />`;
})();
</script>
```

#### Segmented image from `fastscanning_image2D`, `k = 5`

```@example pool_gallery
pooled = avg_segment(img_segment, 5)
_save_segment_pair("avgpool_blocks_segment_k5_before.png", reinterpret(img_segment.img)) # hide
_save_segment_pair("avgpool_blocks_segment_k5_after.png", reinterpret(pooled.img)) # hide
nothing # hide
```

```@raw html
<div id="avgpool-segment-k5" style="display:flex; gap:1rem; align-items:flex-start;"></div>
<script>
(() => {
  const base = (window.documenterBaseURL || "..").replace(/\/$/, "");
  document.getElementById("avgpool-segment-k5").innerHTML =
    `<img src="${base}/assets/fns/image_pool/avgpool_blocks_segment_k5_before.png" alt="Before avgpool_blocks segment k=5" style="width:50%;" />
     <img src="${base}/assets/fns/image_pool/avgpool_blocks_segment_k5_after.png" alt="After avgpool_blocks segment k=5" style="width:50%;" />`;
})();
</script>
```

### Max Pool

```@docs
UTCGP.image_pool.maxpool_blocks_image2D_factory
```

#### Intensity image, `k = 2`

```@example pool_gallery
pooled = max_intensity(img_intensity, 2)
_save_gray_pair("maxpool_blocks_intensity_k2_before.png", Float64.(gray)) # hide
_save_gray_pair("maxpool_blocks_intensity_k2_after.png", float.(pooled)) # hide
nothing # hide
```

```@raw html
<div id="maxpool-intensity-k2" style="display:flex; gap:1rem; align-items:flex-start;"></div>
<script>
(() => {
  const base = (window.documenterBaseURL || "..").replace(/\/$/, "");
  document.getElementById("maxpool-intensity-k2").innerHTML =
    `<img src="${base}/assets/fns/image_pool/maxpool_blocks_intensity_k2_before.png" alt="Before maxpool_blocks intensity k=2" style="width:50%;" />
     <img src="${base}/assets/fns/image_pool/maxpool_blocks_intensity_k2_after.png" alt="After maxpool_blocks intensity k=2" style="width:50%;" />`;
})();
</script>
```

#### Intensity image, `k = 10`

```@example pool_gallery
pooled = max_intensity(img_intensity, 10)
_save_gray_pair("maxpool_blocks_intensity_k10_before.png", Float64.(gray)) # hide
_save_gray_pair("maxpool_blocks_intensity_k10_after.png", float.(pooled)) # hide
nothing # hide
```

```@raw html
<div id="maxpool-intensity-k10" style="display:flex; gap:1rem; align-items:flex-start;"></div>
<script>
(() => {
  const base = (window.documenterBaseURL || "..").replace(/\/$/, "");
  document.getElementById("maxpool-intensity-k10").innerHTML =
    `<img src="${base}/assets/fns/image_pool/maxpool_blocks_intensity_k10_before.png" alt="Before maxpool_blocks intensity k=10" style="width:50%;" />
     <img src="${base}/assets/fns/image_pool/maxpool_blocks_intensity_k10_after.png" alt="After maxpool_blocks intensity k=10" style="width:50%;" />`;
})();
</script>
```

#### Binary image, `> 0.3`, `k = 5`

```@example pool_gallery
pooled = max_binary(img_binary, 5)
_save_gray_pair("maxpool_blocks_binary_k5_before.png", Float64.(reinterpret(img_binary.img))) # hide
_save_gray_pair("maxpool_blocks_binary_k5_after.png", Float64.(reinterpret(pooled.img))) # hide
nothing # hide
```

```@raw html
<div id="maxpool-binary-k5" style="display:flex; gap:1rem; align-items:flex-start;"></div>
<script>
(() => {
  const base = (window.documenterBaseURL || "..").replace(/\/$/, "");
  document.getElementById("maxpool-binary-k5").innerHTML =
    `<img src="${base}/assets/fns/image_pool/maxpool_blocks_binary_k5_before.png" alt="Before maxpool_blocks binary k=5" style="width:50%;" />
     <img src="${base}/assets/fns/image_pool/maxpool_blocks_binary_k5_after.png" alt="After maxpool_blocks binary k=5" style="width:50%;" />`;
})();
</script>
```

#### Segmented image from `fastscanning_image2D`, `k = 5`

```@example pool_gallery
pooled = max_segment(img_segment, 5)
_save_segment_pair("maxpool_blocks_segment_k5_before.png", reinterpret(img_segment.img)) # hide
_save_segment_pair("maxpool_blocks_segment_k5_after.png", reinterpret(pooled.img)) # hide
nothing # hide
```

```@raw html
<div id="maxpool-segment-k5" style="display:flex; gap:1rem; align-items:flex-start;"></div>
<script>
(() => {
  const base = (window.documenterBaseURL || "..").replace(/\/$/, "");
  document.getElementById("maxpool-segment-k5").innerHTML =
    `<img src="${base}/assets/fns/image_pool/maxpool_blocks_segment_k5_before.png" alt="Before maxpool_blocks segment k=5" style="width:50%;" />
     <img src="${base}/assets/fns/image_pool/maxpool_blocks_segment_k5_after.png" alt="After maxpool_blocks segment k=5" style="width:50%;" />`;
})();
</script>
```

### Min Pool

```@docs
UTCGP.image_pool.minpool_blocks_image2D_factory
```

#### Intensity image, `k = 2`

```@example pool_gallery
pooled = min_intensity(img_intensity, 2)
_save_gray_pair("minpool_blocks_intensity_k2_before.png", Float64.(gray)) # hide
_save_gray_pair("minpool_blocks_intensity_k2_after.png", float.(pooled)) # hide
nothing # hide
```

```@raw html
<div id="minpool-intensity-k2" style="display:flex; gap:1rem; align-items:flex-start;"></div>
<script>
(() => {
  const base = (window.documenterBaseURL || "..").replace(/\/$/, "");
  document.getElementById("minpool-intensity-k2").innerHTML =
    `<img src="${base}/assets/fns/image_pool/minpool_blocks_intensity_k2_before.png" alt="Before minpool_blocks intensity k=2" style="width:50%;" />
     <img src="${base}/assets/fns/image_pool/minpool_blocks_intensity_k2_after.png" alt="After minpool_blocks intensity k=2" style="width:50%;" />`;
})();
</script>
```

#### Intensity image, `k = 10`

```@example pool_gallery
pooled = min_intensity(img_intensity, 10)
_save_gray_pair("minpool_blocks_intensity_k10_before.png", Float64.(gray)) # hide
_save_gray_pair("minpool_blocks_intensity_k10_after.png", float.(pooled)) # hide
nothing # hide
```

```@raw html
<div id="minpool-intensity-k10" style="display:flex; gap:1rem; align-items:flex-start;"></div>
<script>
(() => {
  const base = (window.documenterBaseURL || "..").replace(/\/$/, "");
  document.getElementById("minpool-intensity-k10").innerHTML =
    `<img src="${base}/assets/fns/image_pool/minpool_blocks_intensity_k10_before.png" alt="Before minpool_blocks intensity k=10" style="width:50%;" />
     <img src="${base}/assets/fns/image_pool/minpool_blocks_intensity_k10_after.png" alt="After minpool_blocks intensity k=10" style="width:50%;" />`;
})();
</script>
```

#### Binary image, `> 0.3`, `k = 5`

```@example pool_gallery
pooled = min_binary(img_binary, 5)
_save_gray_pair("minpool_blocks_binary_k5_before.png", Float64.(reinterpret(img_binary.img))) # hide
_save_gray_pair("minpool_blocks_binary_k5_after.png", Float64.(reinterpret(pooled.img))) # hide
nothing # hide
```

```@raw html
<div id="minpool-binary-k5" style="display:flex; gap:1rem; align-items:flex-start;"></div>
<script>
(() => {
  const base = (window.documenterBaseURL || "..").replace(/\/$/, "");
  document.getElementById("minpool-binary-k5").innerHTML =
    `<img src="${base}/assets/fns/image_pool/minpool_blocks_binary_k5_before.png" alt="Before minpool_blocks binary k=5" style="width:50%;" />
     <img src="${base}/assets/fns/image_pool/minpool_blocks_binary_k5_after.png" alt="After minpool_blocks binary k=5" style="width:50%;" />`;
})();
</script>
```

#### Segmented image from `fastscanning_image2D`, `k = 5`

```@example pool_gallery
pooled = min_segment(img_segment, 5)
_save_segment_pair("minpool_blocks_segment_k5_before.png", reinterpret(img_segment.img)) # hide
_save_segment_pair("minpool_blocks_segment_k5_after.png", reinterpret(pooled.img)) # hide
nothing # hide
```

```@raw html
<div id="minpool-segment-k5" style="display:flex; gap:1rem; align-items:flex-start;"></div>
<script>
(() => {
  const base = (window.documenterBaseURL || "..").replace(/\/$/, "");
  document.getElementById("minpool-segment-k5").innerHTML =
    `<img src="${base}/assets/fns/image_pool/minpool_blocks_segment_k5_before.png" alt="Before minpool_blocks segment k=5" style="width:50%;" />
     <img src="${base}/assets/fns/image_pool/minpool_blocks_segment_k5_after.png" alt="After minpool_blocks segment k=5" style="width:50%;" />`;
})();
</script>
```

## Cross Pooling Functions

### Avg Cross Pool

```@docs
UTCGP.image_pool.avgpool_cross_blocks_image2D_factory
```

#### Custom 10x10 intensity image, `k = 3`

```@example pool_gallery
pooled = avg_cross_intensity(img_cross_demo, 3)
_save_gray_pair("avgpool_cross_blocks_intensity_k3_before.png", cross_demo) # hide
_save_gray_pair("avgpool_cross_blocks_intensity_k3_after.png", float.(pooled)) # hide
nothing # hide
```

```@raw html
<div id="avgpool-cross-intensity-k3" style="display:flex; gap:1rem; align-items:flex-start;"></div>
<script>
(() => {
  const base = (window.documenterBaseURL || "..").replace(/\/$/, "");
  document.getElementById("avgpool-cross-intensity-k3").innerHTML =
    `<img src="${base}/assets/fns/image_pool/avgpool_cross_blocks_intensity_k3_before.png" alt="Before avgpool_cross_blocks intensity k=3" style="width:160px; image-rendering: pixelated; image-rendering: crisp-edges;" />
     <img src="${base}/assets/fns/image_pool/avgpool_cross_blocks_intensity_k3_after.png" alt="After avgpool_cross_blocks intensity k=3" style="width:160px; image-rendering: pixelated; image-rendering: crisp-edges;" />`;
})();
</script>
```

#### Custom 10x10 intensity image, `k = 5`

```@example pool_gallery
pooled = avg_cross_intensity(img_cross_demo, 5)
_save_gray_pair("avgpool_cross_blocks_intensity_k5_before.png", cross_demo) # hide
_save_gray_pair("avgpool_cross_blocks_intensity_k5_after.png", float.(pooled)) # hide
nothing # hide
```

```@raw html
<div id="avgpool-cross-intensity-k5" style="display:flex; gap:1rem; align-items:flex-start;"></div>
<script>
(() => {
  const base = (window.documenterBaseURL || "..").replace(/\/$/, "");
  document.getElementById("avgpool-cross-intensity-k5").innerHTML =
    `<img src="${base}/assets/fns/image_pool/avgpool_cross_blocks_intensity_k5_before.png" alt="Before avgpool_cross_blocks intensity k=5" style="width:160px; image-rendering: pixelated; image-rendering: crisp-edges;" />
     <img src="${base}/assets/fns/image_pool/avgpool_cross_blocks_intensity_k5_after.png" alt="After avgpool_cross_blocks intensity k=5" style="width:160px; image-rendering: pixelated; image-rendering: crisp-edges;" />`;
})();
</script>
```

#### Binary image, `> 0.3`, `k = 10`

```@example pool_gallery
pooled = avg_cross_binary(img_binary, 10)
_save_gray_pair("avgpool_cross_blocks_binary_k10_before.png", Float64.(reinterpret(img_binary.img))) # hide
_save_gray_pair("avgpool_cross_blocks_binary_k10_after.png", Float64.(reinterpret(pooled.img))) # hide
nothing # hide
```

```@raw html
<div id="avgpool-cross-binary-k10" style="display:flex; gap:1rem; align-items:flex-start;"></div>
<script>
(() => {
  const base = (window.documenterBaseURL || "..").replace(/\/$/, "");
  document.getElementById("avgpool-cross-binary-k10").innerHTML =
    `<img src="${base}/assets/fns/image_pool/avgpool_cross_blocks_binary_k10_before.png" alt="Before avgpool_cross_blocks binary k=10" style="width:50%;" />
     <img src="${base}/assets/fns/image_pool/avgpool_cross_blocks_binary_k10_after.png" alt="After avgpool_cross_blocks binary k=10" style="width:50%;" />`;
})();
</script>
```

#### Segmented image from `fastscanning_image2D`, `k = 10`

```@example pool_gallery
pooled = avg_cross_segment(img_segment, 10)
_save_segment_pair("avgpool_cross_blocks_segment_k10_before.png", reinterpret(img_segment.img)) # hide
_save_segment_pair("avgpool_cross_blocks_segment_k10_after.png", reinterpret(pooled.img)) # hide
nothing # hide
```

```@raw html
<div id="avgpool-cross-segment-k10" style="display:flex; gap:1rem; align-items:flex-start;"></div>
<script>
(() => {
  const base = (window.documenterBaseURL || "..").replace(/\/$/, "");
  document.getElementById("avgpool-cross-segment-k10").innerHTML =
    `<img src="${base}/assets/fns/image_pool/avgpool_cross_blocks_segment_k10_before.png" alt="Before avgpool_cross_blocks segment k=10" style="width:50%;" />
     <img src="${base}/assets/fns/image_pool/avgpool_cross_blocks_segment_k10_after.png" alt="After avgpool_cross_blocks segment k=10" style="width:50%;" />`;
})();
</script>
```

### Max Cross Pool

```@docs
UTCGP.image_pool.maxpool_cross_blocks_image2D_factory
```

#### Custom 10x10 intensity image, `k = 3`

```@example pool_gallery
pooled = max_cross_intensity(img_cross_demo, 3)
_save_gray_pair("maxpool_cross_blocks_intensity_k3_before.png", cross_demo) # hide
_save_gray_pair("maxpool_cross_blocks_intensity_k3_after.png", float.(pooled)) # hide
nothing # hide
```

```@raw html
<div id="maxpool-cross-intensity-k3" style="display:flex; gap:1rem; align-items:flex-start;"></div>
<script>
(() => {
  const base = (window.documenterBaseURL || "..").replace(/\/$/, "");
  document.getElementById("maxpool-cross-intensity-k3").innerHTML =
    `<img src="${base}/assets/fns/image_pool/maxpool_cross_blocks_intensity_k3_before.png" alt="Before maxpool_cross_blocks intensity k=3" style="width:160px; image-rendering: pixelated; image-rendering: crisp-edges;" />
     <img src="${base}/assets/fns/image_pool/maxpool_cross_blocks_intensity_k3_after.png" alt="After maxpool_cross_blocks intensity k=3" style="width:160px; image-rendering: pixelated; image-rendering: crisp-edges;" />`;
})();
</script>
```

#### Custom 10x10 intensity image, `k = 5`

```@example pool_gallery
pooled = max_cross_intensity(img_cross_demo, 5)
_save_gray_pair("maxpool_cross_blocks_intensity_k5_before.png", cross_demo) # hide
_save_gray_pair("maxpool_cross_blocks_intensity_k5_after.png", float.(pooled)) # hide
nothing # hide
```

```@raw html
<div id="maxpool-cross-intensity-k5" style="display:flex; gap:1rem; align-items:flex-start;"></div>
<script>
(() => {
  const base = (window.documenterBaseURL || "..").replace(/\/$/, "");
  document.getElementById("maxpool-cross-intensity-k5").innerHTML =
    `<img src="${base}/assets/fns/image_pool/maxpool_cross_blocks_intensity_k5_before.png" alt="Before maxpool_cross_blocks intensity k=5" style="width:160px; image-rendering: pixelated; image-rendering: crisp-edges;" />
     <img src="${base}/assets/fns/image_pool/maxpool_cross_blocks_intensity_k5_after.png" alt="After maxpool_cross_blocks intensity k=5" style="width:160px; image-rendering: pixelated; image-rendering: crisp-edges;" />`;
})();
</script>
```

#### Binary image, `> 0.3`, `k = 10`

```@example pool_gallery
pooled = max_cross_binary(img_binary, 10)
_save_gray_pair("maxpool_cross_blocks_binary_k10_before.png", Float64.(reinterpret(img_binary.img))) # hide
_save_gray_pair("maxpool_cross_blocks_binary_k10_after.png", Float64.(reinterpret(pooled.img))) # hide
nothing # hide
```

```@raw html
<div id="maxpool-cross-binary-k10" style="display:flex; gap:1rem; align-items:flex-start;"></div>
<script>
(() => {
  const base = (window.documenterBaseURL || "..").replace(/\/$/, "");
  document.getElementById("maxpool-cross-binary-k10").innerHTML =
    `<img src="${base}/assets/fns/image_pool/maxpool_cross_blocks_binary_k10_before.png" alt="Before maxpool_cross_blocks binary k=10" style="width:50%;" />
     <img src="${base}/assets/fns/image_pool/maxpool_cross_blocks_binary_k10_after.png" alt="After maxpool_cross_blocks binary k=10" style="width:50%;" />`;
})();
</script>
```

#### Segmented image from `fastscanning_image2D`, `k = 10`

```@example pool_gallery
pooled = max_cross_segment(img_segment, 10)
_save_segment_pair("maxpool_cross_blocks_segment_k10_before.png", reinterpret(img_segment.img)) # hide
_save_segment_pair("maxpool_cross_blocks_segment_k10_after.png", reinterpret(pooled.img)) # hide
nothing # hide
```

```@raw html
<div id="maxpool-cross-segment-k10" style="display:flex; gap:1rem; align-items:flex-start;"></div>
<script>
(() => {
  const base = (window.documenterBaseURL || "..").replace(/\/$/, "");
  document.getElementById("maxpool-cross-segment-k10").innerHTML =
    `<img src="${base}/assets/fns/image_pool/maxpool_cross_blocks_segment_k10_before.png" alt="Before maxpool_cross_blocks segment k=10" style="width:50%;" />
     <img src="${base}/assets/fns/image_pool/maxpool_cross_blocks_segment_k10_after.png" alt="After maxpool_cross_blocks segment k=10" style="width:50%;" />`;
})();
</script>
```

### Min Cross Pool

```@docs
UTCGP.image_pool.minpool_cross_blocks_image2D_factory
```

#### Custom 10x10 intensity image, `k = 3`

```@example pool_gallery
pooled = min_cross_intensity(img_cross_demo, 3)
_save_gray_pair("minpool_cross_blocks_intensity_k3_before.png", cross_demo) # hide
_save_gray_pair("minpool_cross_blocks_intensity_k3_after.png", float.(pooled)) # hide
nothing # hide
```

```@raw html
<div id="minpool-cross-intensity-k3" style="display:flex; gap:1rem; align-items:flex-start;"></div>
<script>
(() => {
  const base = (window.documenterBaseURL || "..").replace(/\/$/, "");
  document.getElementById("minpool-cross-intensity-k3").innerHTML =
    `<img src="${base}/assets/fns/image_pool/minpool_cross_blocks_intensity_k3_before.png" alt="Before minpool_cross_blocks intensity k=3" style="width:160px; image-rendering: pixelated; image-rendering: crisp-edges;" />
     <img src="${base}/assets/fns/image_pool/minpool_cross_blocks_intensity_k3_after.png" alt="After minpool_cross_blocks intensity k=3" style="width:160px; image-rendering: pixelated; image-rendering: crisp-edges;" />`;
})();
</script>
```

#### Custom 10x10 intensity image, `k = 5`

```@example pool_gallery
pooled = min_cross_intensity(img_cross_demo, 5)
_save_gray_pair("minpool_cross_blocks_intensity_k5_before.png", cross_demo) # hide
_save_gray_pair("minpool_cross_blocks_intensity_k5_after.png", float.(pooled)) # hide
nothing # hide
```

```@raw html
<div id="minpool-cross-intensity-k5" style="display:flex; gap:1rem; align-items:flex-start;"></div>
<script>
(() => {
  const base = (window.documenterBaseURL || "..").replace(/\/$/, "");
  document.getElementById("minpool-cross-intensity-k5").innerHTML =
    `<img src="${base}/assets/fns/image_pool/minpool_cross_blocks_intensity_k5_before.png" alt="Before minpool_cross_blocks intensity k=5" style="width:160px; image-rendering: pixelated; image-rendering: crisp-edges;" />
     <img src="${base}/assets/fns/image_pool/minpool_cross_blocks_intensity_k5_after.png" alt="After minpool_cross_blocks intensity k=5" style="width:160px; image-rendering: pixelated; image-rendering: crisp-edges;" />`;
})();
</script>
```

#### Binary image, `> 0.3`, `k = 10`

```@example pool_gallery
pooled = min_cross_binary(img_binary, 10)
_save_gray_pair("minpool_cross_blocks_binary_k10_before.png", Float64.(reinterpret(img_binary.img))) # hide
_save_gray_pair("minpool_cross_blocks_binary_k10_after.png", Float64.(reinterpret(pooled.img))) # hide
nothing # hide
```

```@raw html
<div id="minpool-cross-binary-k10" style="display:flex; gap:1rem; align-items:flex-start;"></div>
<script>
(() => {
  const base = (window.documenterBaseURL || "..").replace(/\/$/, "");
  document.getElementById("minpool-cross-binary-k10").innerHTML =
    `<img src="${base}/assets/fns/image_pool/minpool_cross_blocks_binary_k10_before.png" alt="Before minpool_cross_blocks binary k=10" style="width:50%;" />
     <img src="${base}/assets/fns/image_pool/minpool_cross_blocks_binary_k10_after.png" alt="After minpool_cross_blocks binary k=10" style="width:50%;" />`;
})();
</script>
```

#### Segmented image from `fastscanning_image2D`, `k = 10`

```@example pool_gallery
pooled = min_cross_segment(img_segment, 10)
_save_segment_pair("minpool_cross_blocks_segment_k10_before.png", reinterpret(img_segment.img)) # hide
_save_segment_pair("minpool_cross_blocks_segment_k10_after.png", reinterpret(pooled.img)) # hide
nothing # hide
```

```@raw html
<div id="minpool-cross-segment-k10" style="display:flex; gap:1rem; align-items:flex-start;"></div>
<script>
(() => {
  const base = (window.documenterBaseURL || "..").replace(/\/$/, "");
  document.getElementById("minpool-cross-segment-k10").innerHTML =
    `<img src="${base}/assets/fns/image_pool/minpool_cross_blocks_segment_k10_before.png" alt="Before minpool_cross_blocks segment k=10" style="width:50%;" />
     <img src="${base}/assets/fns/image_pool/minpool_cross_blocks_segment_k10_after.png" alt="After minpool_cross_blocks segment k=10" style="width:50%;" />`;
})();
</script>
```
