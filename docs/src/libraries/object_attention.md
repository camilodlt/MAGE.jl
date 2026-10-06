```@meta
CurrentModule = UTCGP
```

# Object Attention: Locate and Zoom

A program often cares about *one thing* in the image — the ball, the paddle,
the cell — wherever it happens to be. Fixed coordinates or fixed crops break as
soon as the object moves. These libraries make attention translation-invariant
by splitting it in two:

1. **Where is it?** Image → normalised coordinate (`x` = column, `y` = row,
   both in `[0, 1]`), or image → descriptor of a selected object.
2. **Look there.** Crop around a mask, a selected object or a coordinate, and
   resize back to the original size, so every downstream operator keeps
   working on a same-size image.

Locator outputs use the same convention as `region_*`
(`bundle_number_regionFromImg`), so a locator can drive a region statistic or a
zoom directly:

```
mask ─► obj_x_most_circular ─┐
     └► obj_y_most_circular ─┴─► region_mean(img, x, y)
                              └─► zoom_glimpse_25p(img, x, y)
```

| Getter | Bundles |
|:--|:--|
| `get_extension_locate_nb()` | `bundle_number_locateFromImg`, `bundle_number_objectLocateFromImg`, `bundle_number_objectDescribeFromImg` |
| `get_extension_zoom_intensityimg()` | `bundle_image2DIntensity_zoom_factory` |
| `get_extension_zoom_binaryimg()` | `bundle_image2DBinary_zoom_factory` |
| `get_extension_zoom_segmentimg()` | `bundle_image2DSegment_zoom_factory` |

## Arity and gradual coordinates

Every operator keeps MAGE's three-input ceiling, and each name carries several
methods so evolution can start with fewer connections and refine later:

| Inputs | Meaning |
|:--|:--|
| `(img)` | defaults: image centre, threshold `0.5`, margin `0.1` |
| `(img, s)` | one scalar drives both axes: `x = y = s` |
| `(img, x, y)` | full control |

Scalars are clamped to `[0, 1]`; `NaN` and `Inf` fall back to the default.
Every `*_x` operator has a `*_y` twin with identical arguments.

## Example inputs

All examples run on the same 80×120 Atari-like frame (shown at 2×): a square
(`0.45`), a disk (`0.9`), a ring (`0.75`), a paddle (`0.6`), a 2×2 ball
(`1.0`) and a thin vertical bar (`0.35`) on a `0.15` background. The mask is
`frame > 0.3`, so it holds all six objects; the segment map gives each object
its own label. The second frame moves the ball, for `motion_*`.

```@setup oa
# Generates every image of `object_attention.md`. Included from the page's
# `@setup` block, so the gallery always reflects the current implementation.

using UTCGP
using FileIO
using Images
using ImageCore: N0f8, N0f16

const OA_L = UTCGP.number_locateFromImg
const OA_O = UTCGP.number_objectFromImg
const OA_SCALE = 2

oa_repo_root = normpath(joinpath(dirname(pathof(UTCGP)), ".."))
oa_assets = [
    joinpath(oa_repo_root, "docs", "src", "assets", "fns", "object_attention"),
    joinpath(oa_repo_root, "docs", "build", "assets", "fns", "object_attention"),
]
foreach(mkpath, oa_assets)

# ---------------------------------------------------------------------------
# Scene: an Atari-like frame on a non-black background
# ---------------------------------------------------------------------------

const OA_H, OA_W = 80, 120

function oa_scene(; ball = (42, 52))
    v = fill(0.15, OA_H, OA_W)
    v[8:19, 8:19] .= 0.45                                        # square
    for r in 1:OA_H, c in 1:OA_W
        d2 = (r - 22)^2 + (c - 70)^2
        d2 <= 88 && (v[r, c] = 0.9)                              # disk
        d2r = (r - 58)^2 + (c - 95)^2
        40 < d2r <= 108 && (v[r, c] = 0.75)                      # ring
    end
    v[70:72, 15:44] .= 0.6                                       # paddle
    v[ball[1]:ball[1]+1, ball[2]:ball[2]+1] .= 1.0               # ball
    v[25:55, 112:114] .= 0.35                                    # vertical bar
    return v
end

oa_values = oa_scene()
scene = SImageND(IntensityPixel{N0f8}.(oa_values))
scene_next = SImageND(IntensityPixel{N0f8}.(oa_scene(ball = (38, 60))))
mask = SImageND(BinaryPixel.(oa_values .> 0.3))
oa_table = UTCGP.image2D_object_common.object_table(mask.img, UTCGP.image2D_object_common.IsSet())
segment = SImageND(SegmentPixel.(Int.(oa_table.labels)))

# ---------------------------------------------------------------------------
# Rendering
# ---------------------------------------------------------------------------

const OA_RED = RGB{Float64}(0.95, 0.1, 0.1)
const OA_BLUE = RGB{Float64}(0.1, 0.45, 1.0)
const OA_GREEN = RGB{Float64}(0.1, 0.85, 0.3)
const OA_PALETTE = [
    RGB{Float64}(0, 0, 0), RGB{Float64}(0.9, 0.6, 0.0), RGB{Float64}(0.35, 0.7, 0.9),
    RGB{Float64}(0.0, 0.6, 0.5), RGB{Float64}(0.95, 0.9, 0.25), RGB{Float64}(0.0, 0.45, 0.7),
    RGB{Float64}(0.8, 0.4, 0.0), RGB{Float64}(0.8, 0.6, 0.7),
]

oa_gray(values) = RGB{Float64}.(Gray.(clamp.(values, 0.0, 1.0)))
oa_canvas(img::SizedImage{S,<:IntensityPixel}) where {S} = oa_gray(Float64.(reinterpret(img.img)))
oa_canvas(img::SizedImage{S,<:BinaryPixel}) where {S} = oa_gray(Float64.(reinterpret(img.img)))
oa_canvas(img::SizedImage{S,<:SegmentPixel}) where {S} =
    [OA_PALETTE[mod1(Int(p.pixel) + 1, length(OA_PALETTE))] for p in img.img]
oa_upscale(canvas) = repeat(canvas, inner = (OA_SCALE, OA_SCALE))

"Normalised coordinate → centre pixel in the upscaled canvas."
oa_px(u, n) = round(Int, (u * (n - 1)) * OA_SCALE + (OA_SCALE + 1) / 2)

oa_blend(a, b, t) = RGB{Float64}(a.r + t * (b.r - a.r), a.g + t * (b.g - a.g), a.b + t * (b.b - a.b))

"Vertical line at `x` and horizontal line at `y` (either may be `nothing`), plus a marker."
function oa_cross!(canvas, x, y; color = OA_RED)
    H, W = size(canvas)
    h, w = H ÷ OA_SCALE, W ÷ OA_SCALE
    c = x === nothing ? nothing : clamp(oa_px(x, w), 1, W)
    r = y === nothing ? nothing : clamp(oa_px(y, h), 1, H)
    if c !== nothing
        for cc in c:min(c + 1, W)
            canvas[:, cc] .= oa_blend.(canvas[:, cc], color, 0.85)
        end
    end
    if r !== nothing
        for rr in r:min(r + 1, H)
            canvas[rr, :] .= oa_blend.(canvas[rr, :], color, 0.85)
        end
    end
    if r !== nothing && c !== nothing
        for d in -5:5, e in -1:1
            canvas[clamp(r + d, 1, H), clamp(c + e, 1, W)] = color
            canvas[clamp(r + e, 1, H), clamp(c + d, 1, W)] = color
        end
    end
    return canvas
end

"Outline of the pixel box `r0:r1, c0:c1` (original coordinates)."
function oa_rect!(canvas, r0, r1, c0, c1; color = OA_GREEN)
    R0, R1 = (r0 - 1) * OA_SCALE + 1, r1 * OA_SCALE
    C0, C1 = (c0 - 1) * OA_SCALE + 1, c1 * OA_SCALE
    canvas[R0:R1, C0] .= color
    canvas[R0:R1, C1] .= color
    canvas[R0, C0:C1] .= color
    canvas[R1, C0:C1] .= color
    return canvas
end

function oa_save(name, canvas)
    for directory in oa_assets
        save(joinpath(directory, name), canvas)
    end
end

oa_save_image(name, img) = oa_save(name, oa_upscale(oa_canvas(img)))

"Save `img` with a crosshair at `(x, y)`."
function oa_save_point(name, img, x, y; color = OA_RED)
    canvas = oa_upscale(oa_canvas(img))
    oa_cross!(canvas, x, y; color = color)
    oa_save(name, canvas)
end

"Save `img` with a query point (blue) and the located point (red)."
function oa_save_query(name, img, query, found; window = nothing)
    canvas = oa_upscale(oa_canvas(img))
    window === nothing || oa_rect!(canvas, window...)
    oa_cross!(canvas, query...; color = OA_BLUE)
    oa_cross!(canvas, found...)
    oa_save(name, canvas)
end

oa_zoom(bundle, name, prototype) = bundle[name].fn(typeof(prototype))
oa_call(fn, args...) = Base.invokelatest(fn, args...)

# ---------------------------------------------------------------------------
# Inputs
# ---------------------------------------------------------------------------

oa_save_image("scene.png", scene)
oa_save_image("scene_next.png", scene_next)
oa_save_image("mask.png", mask)
oa_save_image("segment.png", segment)

# ---------------------------------------------------------------------------
# Mask-free locators
# ---------------------------------------------------------------------------

for (name, args...) in (
        (:com, ), (:com, 0.5), (:median, ), (:median, 0.5),
        (:argmax, ), (:argmin, ), (:projpeak, ), (:projpeak, 0.5),
        (:contrast, ), (:odd, ), (:rare, ), (:rare, 0.01),
    )
    x = getfield(OA_L, Symbol(name, :_x))(scene, args...)
    y = getfield(OA_L, Symbol(name, :_y))(scene, args...)
    suffix = isempty(args) ? "" : "_" * replace(string(args[1]), "." => "")
    oa_save_point("loc_$(name)$(suffix).png", scene, x, y)
end

for threshold in (0.0, 0.5)
    canvas = oa_upscale(oa_canvas(scene))
    x, y = OA_L.com_x(scene, threshold), OA_L.com_y(scene, threshold)
    sx, sy = OA_L.spread_x(scene, threshold), OA_L.spread_y(scene, threshold)
    to_r(u) = clamp(round(Int, 1 + u * (OA_H - 1)), 1, OA_H)
    to_c(u) = clamp(round(Int, 1 + u * (OA_W - 1)), 1, OA_W)
    oa_rect!(canvas, to_r(y - sy), to_r(y + sy), to_c(x - sx), to_c(x + sx))
    oa_cross!(canvas, x, y)
    oa_save("loc_spread_$(replace(string(threshold), "." => "")).png", canvas)
end

for threshold in (0.3, 0.5, 0.8)
    canvas = oa_upscale(oa_canvas(scene))
    oa_cross!(canvas, OA_L.first_x(scene, threshold), nothing)
    oa_cross!(canvas, OA_L.last_x(scene, threshold), nothing; color = OA_BLUE)
    oa_cross!(canvas, nothing, OA_L.first_y(scene, threshold))
    oa_cross!(canvas, nothing, OA_L.last_y(scene, threshold); color = OA_BLUE)
    oa_save("loc_extremes_$(replace(string(threshold), "." => "")).png", canvas)
end

oa_save_point("loc_motion.png", scene_next, OA_L.motion_x(scene, scene_next), OA_L.motion_y(scene, scene_next))

"Window drawn by refine/peak, in original pixel coordinates."
function oa_window(x, y, fraction)
    half_r = max(round(Int, fraction * OA_H / 2), 1)
    half_c = max(round(Int, fraction * OA_W / 2), 1)
    cr = round(Int, 1 + y * (OA_H - 1))
    cc = round(Int, 1 + x * (OA_W - 1))
    return (max(cr - half_r, 1), min(cr + half_r, OA_H), max(cc - half_c, 1), min(cc + half_c, OA_W))
end

oa_query = (0.38, 0.45)
for (stem, pct) in Iterators.product((:refine, :peak), (10, 25, 50))
    fx = getfield(OA_L, Symbol(stem, :_x_, pct, :p))
    fy = getfield(OA_L, Symbol(stem, :_y_, pct, :p))
    found = (fx(scene, oa_query...), fy(scene, oa_query...))
    oa_save_query("loc_$(stem)_$(pct).png", scene, oa_query, found;
        window = oa_window(oa_query..., pct / 100))
end
# Chained refine: each step starts where the previous one landed.
let point = (0.2, 0.2), canvas = oa_upscale(oa_canvas(scene))
    oa_cross!(canvas, point...; color = OA_BLUE)
    for step in 1:3
        point = (OA_L.refine_x_25p(scene, point...), OA_L.refine_y_25p(scene, point...))
        oa_cross!(canvas, point...; color = step == 3 ? OA_RED : OA_GREEN)
    end
    oa_save("loc_refine_chain.png", canvas)
end
let s = 0.2
    found = (OA_L.refine_x_25p(scene, s), OA_L.refine_y_25p(scene, s))
    oa_save_query("loc_refine_diagonal.png", scene, (s, s), found; window = oa_window(s, s, 0.25))
end

# ---------------------------------------------------------------------------
# Object locators
# ---------------------------------------------------------------------------

oa_selectors = (first.(UTCGP.image2D_object_common.SELECTOR_FUNCTIONS)...,)
for selector in oa_selectors
    x = getfield(OA_O, Symbol(:obj_x_, selector))(mask)
    y = getfield(OA_O, Symbol(:obj_y_, selector))(mask)
    oa_save_point("obj_$(selector).png", scene, x, y)
end
for selector in (:brightest, :darkest)
    x = getfield(OA_O, Symbol(:obj_x_, selector))(mask, scene)
    y = getfield(OA_O, Symbol(:obj_y_, selector))(mask, scene)
    oa_save_point("obj_$(selector).png", scene, x, y)
end
for threshold in (0.3, 0.5, 0.8)
    oa_save_point("obj_largest_t$(replace(string(threshold), "." => "")).png", scene,
        OA_O.obj_x_largest(scene, threshold), OA_O.obj_y_largest(scene, threshold))
end
for k in (0.0, 0.5, 1.0)
    oa_save_point("obj_rank_$(replace(string(k), "." => "")).png", scene,
        OA_O.obj_x_rank_area(mask, k), OA_O.obj_y_rank_area(mask, k))
end
oa_like_examples = (
    (:area, 0.0005), (:area, 0.03), (:width, 0.25), (:height, 0.4),
    (:elongation, 0.0), (:elongation, 1.0), (:circularity, 0.7), (:extent, 0.6),
)
for (property, v) in oa_like_examples
    oa_save_point("obj_like_$(property)_$(replace(string(v), "." => "")).png", scene,
        getfield(OA_O, Symbol(:obj_x_like_, property))(mask, v),
        getfield(OA_O, Symbol(:obj_y_like_, property))(mask, v))
end
for (label, query) in (("diag", (0.3, 0.3)), ("xy", (0.9, 0.2)))
    args = label == "diag" ? (query[1],) : query
    found = (OA_O.obj_x_nearest(mask, args...), OA_O.obj_y_nearest(mask, args...))
    oa_save_query("obj_nearest_$(label).png", scene, query, found)
end
for (a, b) in ((:smallest, :largest), (:smallest, :most_elongated), (:second_largest, :largest))
    canvas = oa_upscale(oa_canvas(scene))
    oa_cross!(canvas, getfield(OA_O, Symbol(:obj_x_, b))(mask), getfield(OA_O, Symbol(:obj_y_, b))(mask); color = OA_BLUE)
    oa_cross!(canvas, getfield(OA_O, Symbol(:obj_x_, a))(mask), getfield(OA_O, Symbol(:obj_y_, a))(mask))
    oa_save("obj_delta_$(a)_$(b).png", canvas)
end

# ---------------------------------------------------------------------------
# Zoom
# ---------------------------------------------------------------------------

oa_zi = bundle_image2DIntensity_zoom_factory
oa_zb = bundle_image2DBinary_zoom_factory
oa_zs = bundle_image2DSegment_zoom_factory

for selector in (nothing, oa_selectors..., :brightest, :darkest)
    tag = selector === nothing ? "all" : string(selector)
    for prefix in (:zoom_crop_bbox, :zoom_crop_aspect, :zoom_crop_isolate, :zoom_recenter)
        name = selector === nothing ? prefix : Symbol(prefix, :_, selector)
        fn = oa_zoom(oa_zi, name, scene)
        oa_save_image("$(prefix)_$(tag).png", oa_call(fn, scene, mask, 0.3))
    end
end

for margin in (0.0, 0.1, 0.5, 1.0)
    fn = oa_zoom(oa_zi, :zoom_crop_bbox_most_circular, scene)
    oa_save_image("margin_$(replace(string(margin), "." => "")).png", oa_call(fn, scene, mask, margin))
end
let fn = oa_zoom(oa_zi, :zoom_crop_bbox, scene)
    oa_save_image("self_default.png", oa_call(fn, scene))
    for threshold in (0.3, 0.8)
        oa_save_image("self_t$(replace(string(threshold), "." => "")).png", oa_call(fn, scene, threshold, 0.0))
    end
end
for selector in (:largest, :most_elongated, :tallest)
    oa_save_image("binary_bbox_$(selector).png",
        oa_call(oa_zoom(oa_zb, Symbol(:zoom_crop_bbox_, selector), mask), mask))
    oa_save_image("segment_bbox_$(selector).png",
        oa_call(oa_zoom(oa_zs, Symbol(:zoom_crop_bbox_, selector), segment), segment, mask, 0.3))
end

oa_point = (0.45, 0.55)
let canvas = oa_upscale(oa_canvas(scene))
    oa_cross!(canvas, oa_point...; color = OA_BLUE)
    oa_save("glimpse_point.png", canvas)
end
for pct in (10, 25, 50)
    fn = oa_zoom(oa_zi, Symbol(:zoom_glimpse_, pct, :p), scene)
    oa_save_image("glimpse_$(pct).png", oa_call(fn, scene, oa_point...))
end
oa_save_image("glimpse_25_diag.png", oa_call(oa_zoom(oa_zi, :zoom_glimpse_25p, scene), scene, 0.9))
oa_save_image("glimpse_25_corner.png", oa_call(oa_zoom(oa_zi, :zoom_glimpse_25p, scene), scene, 0.0, 0.0))
for z in (0.25, 0.5, 0.75)
    oa_save_image("center_$(replace(string(z), "." => "")).png",
        oa_call(oa_zoom(oa_zi, :zoom_center, scene), scene, z))
end
oa_save_image("rows_band.png", oa_call(oa_zoom(oa_zi, :zoom_rows, scene), scene, 0.6, 0.95))
oa_save_image("rows_single.png", oa_call(oa_zoom(oa_zi, :zoom_rows, scene), scene, 0.88))
oa_save_image("cols_band.png", oa_call(oa_zoom(oa_zi, :zoom_cols, scene), scene, 0.65, 1.0))
oa_save_image("recenter_point.png", oa_call(oa_zoom(oa_zi, :zoom_recenter_point, scene), scene, 0.8, 0.7))
oa_save_image("recenter_point_diag.png", oa_call(oa_zoom(oa_zi, :zoom_recenter_point, scene), scene, 0.2))

# ---------------------------------------------------------------------------
# Real image: Lena, Itti-Koch saliency
# ---------------------------------------------------------------------------

oa_lena_values = Float64.(Gray.(load(joinpath(oa_repo_root, "assets", "lena_gray_16bit.png"))))[1:2:end, 1:2:end]
lena = SImageND(IntensityPixel{N0f16}.(oa_lena_values))
oa_lena_saliency = oa_call(
    bundle_image2DIntensity_saliency_fixation_factory[:itti_koch_saliency].fn(typeof(lena)), lena)

"Save at native resolution, optionally with a crosshair."
function oa_save_native(name, img; point = nothing)
    canvas = oa_canvas(img)
    if point !== nothing
        h, w = size(canvas)
        r = round(Int, 1 + point[2] * (h - 1))
        c = round(Int, 1 + point[1] * (w - 1))
        canvas[:, c] .= oa_blend.(canvas[:, c], OA_RED, 0.85)
        canvas[r, :] .= oa_blend.(canvas[r, :], OA_RED, 0.85)
    end
    oa_save(name, canvas)
end

oa_save_native("lena.png", lena)
oa_save_native("lena_saliency.png", oa_lena_saliency)
oa_save_native("lena_obj_largest.png", lena;
    point = (OA_O.obj_x_largest(oa_lena_saliency), OA_O.obj_y_largest(oa_lena_saliency)))
oa_save_native("lena_rare.png", lena; point = (OA_L.rare_x(lena), OA_L.rare_y(lena)))
for (name, file) in (
        (:zoom_crop_bbox_largest, "lena_bbox_largest.png"),
        (:zoom_crop_aspect_largest, "lena_aspect_largest.png"),
        (:zoom_crop_isolate_largest, "lena_isolate_largest.png"),
        (:zoom_crop_bbox_brightest, "lena_bbox_brightest.png"),
    )
    oa_save_native(file, oa_call(oa_zoom(oa_zi, name, lena), lena, oa_lena_saliency, 0.2))
end
oa_save_native("lena_glimpse.png", oa_call(oa_zoom(oa_zi, :zoom_glimpse_25p, lena), lena,
    OA_O.obj_x_largest(oa_lena_saliency), OA_O.obj_y_largest(oa_lena_saliency)))
```

| Frame (`N0f8`) | Mask | Segment labels | Next frame |
|:--:|:--:|:--:|:--:|
| ![frame](../assets/fns/object_attention/scene.png) | ![mask](../assets/fns/object_attention/mask.png) | ![segments](../assets/fns/object_attention/segment.png) | ![next frame](../assets/fns/object_attention/scene_next.png) |

**Reading the pictures.** The red crosshair is the pair returned by `*_x`
(vertical line) and `*_y` (horizontal line). A blue crosshair is the point given
as input, and a green box is the window an operator looked at.

## Mask-free locators

`bundle_number_locateFromImg` reads the intensity image directly; no mask, no
labelling. Thresholds count only pixels `>= threshold`.

| Operator | Call | Result |
|:--|:--|:--:|
| `com_x` / `com_y` | `(img)` — every pixel weighted by its value; the background pulls it to the centre | ![com_x / com_y](../assets/fns/object_attention/loc_com.png) |
| `com_x` / `com_y` | `(img, 0.5)` — only the bright objects count | ![com_x / com_y](../assets/fns/object_attention/loc_com_05.png) |
| `median_x` / `median_y` | `(img)` — weighted median, robust to one heavy object | ![median_x / median_y](../assets/fns/object_attention/loc_median.png) |
| `median_x` / `median_y` | `(img, 0.5)` | ![median_x / median_y](../assets/fns/object_attention/loc_median_05.png) |
| `spread_x` / `spread_y` | `(img)` — green box is `com ± spread` | ![spread_x / spread_y](../assets/fns/object_attention/loc_spread_00.png) |
| `spread_x` / `spread_y` | `(img, 0.5)` | ![spread_x / spread_y](../assets/fns/object_attention/loc_spread_05.png) |
| `argmax_x` / `argmax_y` | `(img)` — brightest pixel (the ball) | ![argmax_x / argmax_y](../assets/fns/object_attention/loc_argmax.png) |
| `argmin_x` / `argmin_y` | `(img)` — darkest pixel (first background pixel) | ![argmin_x / argmin_y](../assets/fns/object_attention/loc_argmin.png) |
| `projpeak_x` / `projpeak_y` | `(img)` — column and row with the most mass | ![projpeak_x / projpeak_y](../assets/fns/object_attention/loc_projpeak.png) |
| `projpeak_x` / `projpeak_y` | `(img, 0.5)` | ![projpeak_x / projpeak_y](../assets/fns/object_attention/loc_projpeak_05.png) |
| `first_*` (red) / `last_*` (blue) | `(img, 0.3)` — extreme foreground lines | ![first_* (red) / last_* (blue)](../assets/fns/object_attention/loc_extremes_03.png) |
| `first_*` / `last_*` | `(img)` — default threshold `0.5` | ![first_* / last_*](../assets/fns/object_attention/loc_extremes_05.png) |
| `first_*` / `last_*` | `(img, 0.8)` — only disk and ball | ![first_* / last_*](../assets/fns/object_attention/loc_extremes_08.png) |
| `contrast_x` / `contrast_y` | `(img)` — weight `abs(v - mean)` | ![contrast_x / contrast_y](../assets/fns/object_attention/loc_contrast.png) |
| `odd_x` / `odd_y` | `(img)` — weight `abs(v - background)`, background pixels excluded | ![odd_x / odd_y](../assets/fns/object_attention/loc_odd.png) |
| `rare_x` / `rare_y` | `(img)` — values covering at most 5% of the image: every object | ![rare_x / rare_y](../assets/fns/object_attention/loc_rare.png) |
| `rare_x` / `rare_y` | `(img, 0.01)` — at most 1% (96 px): the ball, the paddle and the bar | ![rare_x / rare_y](../assets/fns/object_attention/loc_rare_001.png) |
| `motion_x` / `motion_y` | `(frame, next_frame)` — where the ball moved (shown on the next frame) | ![motion_x / motion_y](../assets/fns/object_attention/loc_motion.png) |

### Around a point: `refine` and `peak`

`refine_*_<p>` returns the centre of mass inside a window of `p` of the image
around the input point; `peak_*_<p>` returns the brightest pixel there. An
empty window returns the input unchanged. This is how an evolved constant gets
*snapped* onto an object: the input does not have to be accurate, only close.
All calls below start from the blue point `(x, y) = (0.38, 0.45)`.

| Window | `refine_x_<p>` / `refine_y_<p>` | `peak_x_<p>` / `peak_y_<p>` |
|:--|:--:|:--:|
| `10p` | ![refine 10%](../assets/fns/object_attention/loc_refine_10.png) | ![peak 10%](../assets/fns/object_attention/loc_peak_10.png) |
| `25p` | ![refine 25%](../assets/fns/object_attention/loc_refine_25.png) | ![peak 25%](../assets/fns/object_attention/loc_peak_25.png) |
| `50p` | ![refine 50%](../assets/fns/object_attention/loc_refine_50.png) | ![peak 50%](../assets/fns/object_attention/loc_peak_50.png) |

| `refine_x_25p(img, 0.2)` — one scalar, `x = y = 0.2` | Three chained refines from `(0.2, 0.2)`: blue start, green steps, red end |
|:--:|:--:|
| ![refine diagonal](../assets/fns/object_attention/loc_refine_diagonal.png) | ![refine chain](../assets/fns/object_attention/loc_refine_chain.png) |

## Object locators

`bundle_number_objectLocateFromImg` labels the 8-connected objects of the mask,
selects one and returns its centroid. Inputs are a binary mask, or an
intensity image thresholded at `0.5` (or at an explicit last-argument
threshold). Ties go to the object met first in a column-major scan. An empty
mask returns `0.5`.

### Fixed selectors

Every call below is `obj_x_<sel>(mask)` / `obj_y_<sel>(mask)`.

| `<sel>` | Selects the object with the | Result |
|:--|:--|:--:|
| `largest` | greatest pixel area | ![largest](../assets/fns/object_attention/obj_largest.png) |
| `smallest` | least pixel area | ![smallest](../assets/fns/object_attention/obj_smallest.png) |
| `second_largest` | second-greatest pixel area | ![second_largest](../assets/fns/object_attention/obj_second_largest.png) |
| `most_elongated` | greatest elongation | ![most_elongated](../assets/fns/object_attention/obj_most_elongated.png) |
| `least_elongated` | least elongation | ![least_elongated](../assets/fns/object_attention/obj_least_elongated.png) |
| `most_circular` | greatest moment circularity | ![most_circular](../assets/fns/object_attention/obj_most_circular.png) |
| `least_circular` | least moment circularity | ![least_circular](../assets/fns/object_attention/obj_least_circular.png) |
| `most_rectangular` | greatest extent (bounding-box fill) | ![most_rectangular](../assets/fns/object_attention/obj_most_rectangular.png) |
| `least_rectangular` | least extent | ![least_rectangular](../assets/fns/object_attention/obj_least_rectangular.png) |
| `widest` | widest bounding box | ![widest](../assets/fns/object_attention/obj_widest.png) |
| `narrowest` | narrowest bounding box | ![narrowest](../assets/fns/object_attention/obj_narrowest.png) |
| `tallest` | tallest bounding box | ![tallest](../assets/fns/object_attention/obj_tallest.png) |
| `shortest` | shortest bounding box | ![shortest](../assets/fns/object_attention/obj_shortest.png) |
| `topmost` | topmost centroid | ![topmost](../assets/fns/object_attention/obj_topmost.png) |
| `bottommost` | bottommost centroid | ![bottommost](../assets/fns/object_attention/obj_bottommost.png) |
| `leftmost` | leftmost centroid | ![leftmost](../assets/fns/object_attention/obj_leftmost.png) |
| `rightmost` | rightmost centroid | ![rightmost](../assets/fns/object_attention/obj_rightmost.png) |
| `most_central` | centroid closest to the image centre | ![most_central](../assets/fns/object_attention/obj_most_central.png) |
| `most_peripheral` | centroid farthest from the centre | ![most_peripheral](../assets/fns/object_attention/obj_most_peripheral.png) |
| `most_isolated` | farthest from any other centroid | ![most_isolated](../assets/fns/object_attention/obj_most_isolated.png) |
| `least_isolated` | closest to another centroid | ![least_isolated](../assets/fns/object_attention/obj_least_isolated.png) |
| `brightest` | greatest mean of `source`; call `(mask, source)` | ![brightest](../assets/fns/object_attention/obj_brightest.png) |
| `darkest` | least mean of `source`; call `(mask, source)` | ![darkest](../assets/fns/object_attention/obj_darkest.png) |

The values behind the pictures:

```@example oa
for sel in (:largest, :smallest, :most_elongated, :most_circular, :least_circular, :tallest)
    x = getfield(OA_O, Symbol(:obj_x_, sel))(mask)
    y = getfield(OA_O, Symbol(:obj_y_, sel))(mask)
    println(rpad(sel, 16), "x = ", round(x, digits = 3), "  y = ", round(y, digits = 3))
end
```

### Effect of `threshold` on an intensity input

`obj_x_largest(img, threshold)`. At `0.5` the square (`0.45`) and the bar
(`0.35`) disappear; at `0.8` only the disk and the ball remain.

| `threshold = 0.3` | `0.5` (default) | `0.8` |
|:--:|:--:|:--:|
| ![t 0.3](../assets/fns/object_attention/obj_largest_t03.png) | ![t 0.5](../assets/fns/object_attention/obj_largest_t05.png) | ![t 0.8](../assets/fns/object_attention/obj_largest_t08.png) |

### `rank_area`: pick by relative size

`obj_x_rank_area(mask, k)`: `k = 0` smallest, `1` largest, default `0.5`.

| `k = 0` | `k = 0.5` | `k = 1` |
|:--:|:--:|:--:|
| ![k 0](../assets/fns/object_attention/obj_rank_00.png) | ![k 0.5](../assets/fns/object_attention/obj_rank_05.png) | ![k 1](../assets/fns/object_attention/obj_rank_10.png) |

### `like_<prop>`: the object whose property is closest to `v`

`obj_x_like_<prop>(mask, v)` with `<prop>` one of `area`, `width`, `height`,
`elongation`, `circularity`, `extent` (all in `[0, 1]`, see the descriptors
below). This is "the ball-sized thing" or "the paddle-shaped thing".

| Call | Result | Call | Result |
|:--|:--:|:--|:--:|
| `obj_x_like_area(mask, 0.0005)` — ball-sized | ![area 0.0005](../assets/fns/object_attention/obj_like_area_00005.png) | `obj_x_like_area(mask, 0.03)` — disk-sized | ![area 0.03](../assets/fns/object_attention/obj_like_area_003.png) |
| `obj_x_like_width(mask, 0.25)` — a quarter of the width | ![width 0.25](../assets/fns/object_attention/obj_like_width_025.png) | `obj_x_like_height(mask, 0.4)` — 40% of the height | ![height 0.4](../assets/fns/object_attention/obj_like_height_04.png) |
| `obj_x_like_elongation(mask, 0.0)` — isotropic | ![elongation 0.0](../assets/fns/object_attention/obj_like_elongation_00.png) | `obj_x_like_elongation(mask, 1.0)` — line-like | ![elongation 1.0](../assets/fns/object_attention/obj_like_elongation_10.png) |
| `obj_x_like_circularity(mask, 0.7)` — ring-like | ![circularity 0.7](../assets/fns/object_attention/obj_like_circularity_07.png) | `obj_x_like_extent(mask, 0.6)` — fills 60% of its box | ![extent 0.6](../assets/fns/object_attention/obj_like_extent_06.png) |

### `nearest`: track from a point

`obj_x_nearest(mask, s)` uses `x = y = s`; `obj_x_nearest(mask, x, y)` takes
both. Feed it the object's position from the previous frame to keep following
it. Blue is the query, red the object found.

| `obj_x_nearest(mask, 0.3)` | `obj_x_nearest(mask, 0.9, 0.2)` |
|:--:|:--:|
| ![nearest diagonal](../assets/fns/object_attention/obj_nearest_diag.png) | ![nearest xy](../assets/fns/object_attention/obj_nearest_xy.png) |

### `dx` / `dy`: offsets between two objects

`obj_dx_<a>_<b>(mask)` returns `x(a) - x(b)` in `[-1, 1]` (same for `dy`), e.g.
the ball relative to the paddle. Red is `<a>`, blue is `<b>`.

| `obj_d*_smallest_largest` | `obj_d*_smallest_most_elongated` | `obj_d*_second_largest_largest` |
|:--:|:--:|:--:|
| ![smallest vs largest](../assets/fns/object_attention/obj_delta_smallest_largest.png) | ![smallest vs elongated](../assets/fns/object_attention/obj_delta_smallest_most_elongated.png) | ![second vs largest](../assets/fns/object_attention/obj_delta_second_largest_largest.png) |

```@example oa
for name in (:obj_dx_smallest_largest, :obj_dy_smallest_largest,
             :obj_dx_smallest_most_elongated, :obj_dy_smallest_most_elongated)
    println(rpad(name, 32), round(getfield(OA_O, name)(mask), digits = 3))
end
```

## Object descriptors

`bundle_number_objectDescribeFromImg` uses the same selectors and inputs but
returns what the selected object *looks like*, independently of where it is:

| Descriptor | Meaning |
|:--|:--|
| `area` | fraction of the image's pixels |
| `width`, `height` | bounding box as a fraction of the image side |
| `elongation` | `1 − sqrt(λmin / λmax)` of the second moments: `0` round, `→ 1` line |
| `circularity` | `A / (2π(σ²_r + σ²_c))`: `1` for a disk, lower for rings and bars |
| `extent` | area over bounding-box area: `1` for an axis-aligned rectangle |
| `orientation` | principal-axis angle mapped to `[0, 1]`: `0.5` horizontal, `0` and `1` both vertical; `0.5` for shapes without an axis (disk, square) |

Each name is `obj_<descriptor>_<sel>`, plus `obj_<descriptor>_nearest(mask,
[s | x, y])`. Empty masks return `0.0`. Values for every selector on the
example mask:

```@example oa
descriptors = (:area, :width, :height, :elongation, :circularity, :extent, :orientation)
println(rpad("selector", 18), join(rpad.(string.(descriptors), 12)))
for sel in oa_selectors
    values = [getfield(OA_O, Symbol(:obj_, d, :_, sel))(mask) for d in descriptors]
    println(rpad(sel, 18), join(rpad.(string.(round.(values, digits = 3)), 12)))
end
```

`obj_count` and `obj_dist_nearest` (distance from a point to the nearest
centroid, divided by the image diagonal):

```@example oa
(
    count_mask = OA_O.obj_count(mask),
    count_t05 = OA_O.obj_count(scene, 0.5),
    count_t08 = OA_O.obj_count(scene, 0.8),
    dist_from_centre = round(OA_O.obj_dist_nearest(mask), digits = 3),
    dist_from_corner = round(OA_O.obj_dist_nearest(mask, 0.0, 0.0), digits = 3),
)
```

## Zoom

The zoom bundles are factories: specialise them with the image type to get
same-size, same-type outputs. Intensity images are resampled bilinearly;
binary masks and segment maps use nearest neighbour so labels are never
blended. Windows reaching past the border are clipped, never padded. An empty
mask returns the source unchanged.

Mask-driven operators accept `(src, mask)` and `(src, mask, margin)`, where
`mask` is a binary mask or an intensity map thresholded at `0.5`. Intensity
sources also accept `(img)`, `(img, threshold)` and
`(img, threshold, margin)`, using the image itself as the mask; binary sources
accept `(mask)` and `(mask, margin)`. `margin` grows the box by that fraction
of its own size on each side (default `0.1`).

### Every mask-driven operator

Each row is one selector, each column one operator family, all called as
`op(frame, mask, 0.3)`. The first row uses the whole foreground
(`zoom_crop_bbox`, `zoom_crop_aspect`, `zoom_crop_isolate`, `zoom_recenter`).

| Selector | `zoom_crop_bbox_<sel>` | `zoom_crop_aspect_<sel>` | `zoom_crop_isolate_<sel>` | `zoom_recenter_<sel>` |
|:--|:--:|:--:|:--:|:--:|
| *(whole foreground)* | ![zoom_crop_bbox all](../assets/fns/object_attention/zoom_crop_bbox_all.png) | ![zoom_crop_aspect all](../assets/fns/object_attention/zoom_crop_aspect_all.png) | ![zoom_crop_isolate all](../assets/fns/object_attention/zoom_crop_isolate_all.png) | ![zoom_recenter all](../assets/fns/object_attention/zoom_recenter_all.png) |
| `largest` | ![zoom_crop_bbox largest](../assets/fns/object_attention/zoom_crop_bbox_largest.png) | ![zoom_crop_aspect largest](../assets/fns/object_attention/zoom_crop_aspect_largest.png) | ![zoom_crop_isolate largest](../assets/fns/object_attention/zoom_crop_isolate_largest.png) | ![zoom_recenter largest](../assets/fns/object_attention/zoom_recenter_largest.png) |
| `smallest` | ![zoom_crop_bbox smallest](../assets/fns/object_attention/zoom_crop_bbox_smallest.png) | ![zoom_crop_aspect smallest](../assets/fns/object_attention/zoom_crop_aspect_smallest.png) | ![zoom_crop_isolate smallest](../assets/fns/object_attention/zoom_crop_isolate_smallest.png) | ![zoom_recenter smallest](../assets/fns/object_attention/zoom_recenter_smallest.png) |
| `second_largest` | ![zoom_crop_bbox second_largest](../assets/fns/object_attention/zoom_crop_bbox_second_largest.png) | ![zoom_crop_aspect second_largest](../assets/fns/object_attention/zoom_crop_aspect_second_largest.png) | ![zoom_crop_isolate second_largest](../assets/fns/object_attention/zoom_crop_isolate_second_largest.png) | ![zoom_recenter second_largest](../assets/fns/object_attention/zoom_recenter_second_largest.png) |
| `most_elongated` | ![zoom_crop_bbox most_elongated](../assets/fns/object_attention/zoom_crop_bbox_most_elongated.png) | ![zoom_crop_aspect most_elongated](../assets/fns/object_attention/zoom_crop_aspect_most_elongated.png) | ![zoom_crop_isolate most_elongated](../assets/fns/object_attention/zoom_crop_isolate_most_elongated.png) | ![zoom_recenter most_elongated](../assets/fns/object_attention/zoom_recenter_most_elongated.png) |
| `least_elongated` | ![zoom_crop_bbox least_elongated](../assets/fns/object_attention/zoom_crop_bbox_least_elongated.png) | ![zoom_crop_aspect least_elongated](../assets/fns/object_attention/zoom_crop_aspect_least_elongated.png) | ![zoom_crop_isolate least_elongated](../assets/fns/object_attention/zoom_crop_isolate_least_elongated.png) | ![zoom_recenter least_elongated](../assets/fns/object_attention/zoom_recenter_least_elongated.png) |
| `most_circular` | ![zoom_crop_bbox most_circular](../assets/fns/object_attention/zoom_crop_bbox_most_circular.png) | ![zoom_crop_aspect most_circular](../assets/fns/object_attention/zoom_crop_aspect_most_circular.png) | ![zoom_crop_isolate most_circular](../assets/fns/object_attention/zoom_crop_isolate_most_circular.png) | ![zoom_recenter most_circular](../assets/fns/object_attention/zoom_recenter_most_circular.png) |
| `least_circular` | ![zoom_crop_bbox least_circular](../assets/fns/object_attention/zoom_crop_bbox_least_circular.png) | ![zoom_crop_aspect least_circular](../assets/fns/object_attention/zoom_crop_aspect_least_circular.png) | ![zoom_crop_isolate least_circular](../assets/fns/object_attention/zoom_crop_isolate_least_circular.png) | ![zoom_recenter least_circular](../assets/fns/object_attention/zoom_recenter_least_circular.png) |
| `most_rectangular` | ![zoom_crop_bbox most_rectangular](../assets/fns/object_attention/zoom_crop_bbox_most_rectangular.png) | ![zoom_crop_aspect most_rectangular](../assets/fns/object_attention/zoom_crop_aspect_most_rectangular.png) | ![zoom_crop_isolate most_rectangular](../assets/fns/object_attention/zoom_crop_isolate_most_rectangular.png) | ![zoom_recenter most_rectangular](../assets/fns/object_attention/zoom_recenter_most_rectangular.png) |
| `least_rectangular` | ![zoom_crop_bbox least_rectangular](../assets/fns/object_attention/zoom_crop_bbox_least_rectangular.png) | ![zoom_crop_aspect least_rectangular](../assets/fns/object_attention/zoom_crop_aspect_least_rectangular.png) | ![zoom_crop_isolate least_rectangular](../assets/fns/object_attention/zoom_crop_isolate_least_rectangular.png) | ![zoom_recenter least_rectangular](../assets/fns/object_attention/zoom_recenter_least_rectangular.png) |
| `widest` | ![zoom_crop_bbox widest](../assets/fns/object_attention/zoom_crop_bbox_widest.png) | ![zoom_crop_aspect widest](../assets/fns/object_attention/zoom_crop_aspect_widest.png) | ![zoom_crop_isolate widest](../assets/fns/object_attention/zoom_crop_isolate_widest.png) | ![zoom_recenter widest](../assets/fns/object_attention/zoom_recenter_widest.png) |
| `narrowest` | ![zoom_crop_bbox narrowest](../assets/fns/object_attention/zoom_crop_bbox_narrowest.png) | ![zoom_crop_aspect narrowest](../assets/fns/object_attention/zoom_crop_aspect_narrowest.png) | ![zoom_crop_isolate narrowest](../assets/fns/object_attention/zoom_crop_isolate_narrowest.png) | ![zoom_recenter narrowest](../assets/fns/object_attention/zoom_recenter_narrowest.png) |
| `tallest` | ![zoom_crop_bbox tallest](../assets/fns/object_attention/zoom_crop_bbox_tallest.png) | ![zoom_crop_aspect tallest](../assets/fns/object_attention/zoom_crop_aspect_tallest.png) | ![zoom_crop_isolate tallest](../assets/fns/object_attention/zoom_crop_isolate_tallest.png) | ![zoom_recenter tallest](../assets/fns/object_attention/zoom_recenter_tallest.png) |
| `shortest` | ![zoom_crop_bbox shortest](../assets/fns/object_attention/zoom_crop_bbox_shortest.png) | ![zoom_crop_aspect shortest](../assets/fns/object_attention/zoom_crop_aspect_shortest.png) | ![zoom_crop_isolate shortest](../assets/fns/object_attention/zoom_crop_isolate_shortest.png) | ![zoom_recenter shortest](../assets/fns/object_attention/zoom_recenter_shortest.png) |
| `topmost` | ![zoom_crop_bbox topmost](../assets/fns/object_attention/zoom_crop_bbox_topmost.png) | ![zoom_crop_aspect topmost](../assets/fns/object_attention/zoom_crop_aspect_topmost.png) | ![zoom_crop_isolate topmost](../assets/fns/object_attention/zoom_crop_isolate_topmost.png) | ![zoom_recenter topmost](../assets/fns/object_attention/zoom_recenter_topmost.png) |
| `bottommost` | ![zoom_crop_bbox bottommost](../assets/fns/object_attention/zoom_crop_bbox_bottommost.png) | ![zoom_crop_aspect bottommost](../assets/fns/object_attention/zoom_crop_aspect_bottommost.png) | ![zoom_crop_isolate bottommost](../assets/fns/object_attention/zoom_crop_isolate_bottommost.png) | ![zoom_recenter bottommost](../assets/fns/object_attention/zoom_recenter_bottommost.png) |
| `leftmost` | ![zoom_crop_bbox leftmost](../assets/fns/object_attention/zoom_crop_bbox_leftmost.png) | ![zoom_crop_aspect leftmost](../assets/fns/object_attention/zoom_crop_aspect_leftmost.png) | ![zoom_crop_isolate leftmost](../assets/fns/object_attention/zoom_crop_isolate_leftmost.png) | ![zoom_recenter leftmost](../assets/fns/object_attention/zoom_recenter_leftmost.png) |
| `rightmost` | ![zoom_crop_bbox rightmost](../assets/fns/object_attention/zoom_crop_bbox_rightmost.png) | ![zoom_crop_aspect rightmost](../assets/fns/object_attention/zoom_crop_aspect_rightmost.png) | ![zoom_crop_isolate rightmost](../assets/fns/object_attention/zoom_crop_isolate_rightmost.png) | ![zoom_recenter rightmost](../assets/fns/object_attention/zoom_recenter_rightmost.png) |
| `most_central` | ![zoom_crop_bbox most_central](../assets/fns/object_attention/zoom_crop_bbox_most_central.png) | ![zoom_crop_aspect most_central](../assets/fns/object_attention/zoom_crop_aspect_most_central.png) | ![zoom_crop_isolate most_central](../assets/fns/object_attention/zoom_crop_isolate_most_central.png) | ![zoom_recenter most_central](../assets/fns/object_attention/zoom_recenter_most_central.png) |
| `most_peripheral` | ![zoom_crop_bbox most_peripheral](../assets/fns/object_attention/zoom_crop_bbox_most_peripheral.png) | ![zoom_crop_aspect most_peripheral](../assets/fns/object_attention/zoom_crop_aspect_most_peripheral.png) | ![zoom_crop_isolate most_peripheral](../assets/fns/object_attention/zoom_crop_isolate_most_peripheral.png) | ![zoom_recenter most_peripheral](../assets/fns/object_attention/zoom_recenter_most_peripheral.png) |
| `most_isolated` | ![zoom_crop_bbox most_isolated](../assets/fns/object_attention/zoom_crop_bbox_most_isolated.png) | ![zoom_crop_aspect most_isolated](../assets/fns/object_attention/zoom_crop_aspect_most_isolated.png) | ![zoom_crop_isolate most_isolated](../assets/fns/object_attention/zoom_crop_isolate_most_isolated.png) | ![zoom_recenter most_isolated](../assets/fns/object_attention/zoom_recenter_most_isolated.png) |
| `least_isolated` | ![zoom_crop_bbox least_isolated](../assets/fns/object_attention/zoom_crop_bbox_least_isolated.png) | ![zoom_crop_aspect least_isolated](../assets/fns/object_attention/zoom_crop_aspect_least_isolated.png) | ![zoom_crop_isolate least_isolated](../assets/fns/object_attention/zoom_crop_isolate_least_isolated.png) | ![zoom_recenter least_isolated](../assets/fns/object_attention/zoom_recenter_least_isolated.png) |
| `brightest` | ![zoom_crop_bbox brightest](../assets/fns/object_attention/zoom_crop_bbox_brightest.png) | ![zoom_crop_aspect brightest](../assets/fns/object_attention/zoom_crop_aspect_brightest.png) | ![zoom_crop_isolate brightest](../assets/fns/object_attention/zoom_crop_isolate_brightest.png) | ![zoom_recenter brightest](../assets/fns/object_attention/zoom_recenter_brightest.png) |
| `darkest` | ![zoom_crop_bbox darkest](../assets/fns/object_attention/zoom_crop_bbox_darkest.png) | ![zoom_crop_aspect darkest](../assets/fns/object_attention/zoom_crop_aspect_darkest.png) | ![zoom_crop_isolate darkest](../assets/fns/object_attention/zoom_crop_isolate_darkest.png) | ![zoom_recenter darkest](../assets/fns/object_attention/zoom_recenter_darkest.png) |

`brightest` and `darkest` score each object by the mean of the source image and
exist only in the intensity bundle. `zoom_recenter_*` ignores `margin`.

!!! note "Tiny objects"
    The margin is relative to the object's own box, so a 2×2 ball with the
    default margin is cropped to exactly 2×2 and fills the output with one
    value (the `smallest` row uses `0.3`, i.e. one pixel of context). For small
    sprites, locate them with `obj_*` and use `zoom_glimpse_*` instead.

### Effect of `margin`

`zoom_crop_bbox_most_circular(frame, mask, margin)`:

| `margin = 0` | `0.1` (default) | `0.5` | `1.0` |
|:--:|:--:|:--:|:--:|
| ![margin 0](../assets/fns/object_attention/margin_00.png) | ![margin 0.1](../assets/fns/object_attention/margin_01.png) | ![margin 0.5](../assets/fns/object_attention/margin_05.png) | ![margin 1](../assets/fns/object_attention/margin_10.png) |

### Self-masking an intensity image

`zoom_crop_bbox(frame)` thresholds the frame itself at `0.5`;
`zoom_crop_bbox(frame, threshold, margin)` sets both.

| `(frame)` | `(frame, 0.3, 0.0)` | `(frame, 0.8, 0.0)` |
|:--:|:--:|:--:|
| ![self default](../assets/fns/object_attention/self_default.png) | ![self 0.3](../assets/fns/object_attention/self_t03.png) | ![self 0.8](../assets/fns/object_attention/self_t08.png) |

### Binary and segment outputs

The binary bundle zooms a mask on its own foreground with `(mask)`; the segment
bundle zooms a label map with `(labels, mask, margin)`. Both use nearest
neighbour, so outputs only contain values present in the input.

| Selector | Binary `op(mask)` | Segment `op(labels, mask, 0.3)` |
|:--|:--:|:--:|
| `zoom_crop_bbox_largest` | ![binary largest](../assets/fns/object_attention/binary_bbox_largest.png) | ![segment largest](../assets/fns/object_attention/segment_bbox_largest.png) |
| `zoom_crop_bbox_most_elongated` | ![binary most_elongated](../assets/fns/object_attention/binary_bbox_most_elongated.png) | ![segment most_elongated](../assets/fns/object_attention/segment_bbox_most_elongated.png) |
| `zoom_crop_bbox_tallest` | ![binary tallest](../assets/fns/object_attention/binary_bbox_tallest.png) | ![segment tallest](../assets/fns/object_attention/segment_bbox_tallest.png) |

### Coordinate-driven zooms

`zoom_glimpse_<p>(img, x, y)` crops a window of `p` of each side around the
point; `(img, s)` uses `x = y = s`, and `(img)` the centre. Near a border the
window is clipped, so it covers less and is stretched more.

| Input point `(0.45, 0.55)` | `zoom_glimpse_10p` | `zoom_glimpse_25p` | `zoom_glimpse_50p` |
|:--:|:--:|:--:|:--:|
| ![glimpse point](../assets/fns/object_attention/glimpse_point.png) | ![glimpse 10](../assets/fns/object_attention/glimpse_10.png) | ![glimpse 25](../assets/fns/object_attention/glimpse_25.png) | ![glimpse 50](../assets/fns/object_attention/glimpse_50.png) |

| `zoom_glimpse_25p(img, 0.9)` | `zoom_glimpse_25p(img, 0.0, 0.0)` (clipped corner) |
|:--:|:--:|
| ![glimpse diagonal](../assets/fns/object_attention/glimpse_25_diag.png) | ![glimpse corner](../assets/fns/object_attention/glimpse_25_corner.png) |

`zoom_center(img, z)` keeps the central fraction `z ∈ [0.05, 1]` of each side
(default `0.5`):

| `z = 0.25` | `z = 0.5` | `z = 0.75` |
|:--:|:--:|:--:|
| ![center 0.25](../assets/fns/object_attention/center_025.png) | ![center 0.5](../assets/fns/object_attention/center_05.png) | ![center 0.75](../assets/fns/object_attention/center_075.png) |

`zoom_rows(img, a, b)` and `zoom_cols(img, a, b)` keep a band between two
positions (any order) and stretch it; `(img, a)` keeps a 25% band centred on
`a`. `zoom_recenter_point(img, x, y)` translates without rescaling so the point
lands in the centre.

| `zoom_rows(img, 0.6, 0.95)` | `zoom_rows(img, 0.88)` | `zoom_cols(img, 0.65, 1.0)` |
|:--:|:--:|:--:|
| ![rows band](../assets/fns/object_attention/rows_band.png) | ![rows single](../assets/fns/object_attention/rows_single.png) | ![cols band](../assets/fns/object_attention/cols_band.png) |

| `zoom_recenter_point(img, 0.8, 0.7)` | `zoom_recenter_point(img, 0.2)` |
|:--:|:--:|
| ![recenter point](../assets/fns/object_attention/recenter_point.png) | ![recenter diagonal](../assets/fns/object_attention/recenter_point_diag.png) |

## On a real image

Lena (half resolution, `N0f16`) with its Itti-Koch saliency map as the mask.
The salient region is located with `obj_*_largest(saliency)`, then cropped in
several ways with margin `0.2`; the last image is a glimpse driven by the
locator output.

| Source | Saliency (mask at `0.5`) | `obj_*_largest(saliency)` | `rare_*(img)` |
|:--:|:--:|:--:|:--:|
| ![lena](../assets/fns/object_attention/lena.png) | ![saliency](../assets/fns/object_attention/lena_saliency.png) | ![largest salient object](../assets/fns/object_attention/lena_obj_largest.png) | ![rare values](../assets/fns/object_attention/lena_rare.png) |

| `zoom_crop_bbox_largest` | `zoom_crop_aspect_largest` | `zoom_crop_isolate_largest` | `zoom_crop_bbox_brightest` | `zoom_glimpse_25p(img, obj_x, obj_y)` |
|:--:|:--:|:--:|:--:|:--:|
| ![bbox](../assets/fns/object_attention/lena_bbox_largest.png) | ![aspect](../assets/fns/object_attention/lena_aspect_largest.png) | ![isolate](../assets/fns/object_attention/lena_isolate_largest.png) | ![brightest](../assets/fns/object_attention/lena_bbox_brightest.png) | ![glimpse](../assets/fns/object_attention/lena_glimpse.png) |

## Performance

Measured on an 84×84 frame with ten sprites (median of each family):

| Operator | Time |
|:--|:--|
| mask-free locators (`com`, `spread`, `median`, `projpeak`, `first`/`last`) | ~3 µs; `argmax` ~7 µs; `refine`/`peak` 1–4 µs; `rare`, `odd` ~12 µs |
| object locators and descriptors (labelling + all moments) | 6–10 µs |
| zooms (labelling included for selectors) | 11–20 µs |
| reference: `ImageMorphology.label_components` alone | 34 µs |

Labelling works on vertical runs of foreground pixels (moments of a run in
closed form), 8-bit thresholds go through a 256-entry lookup table, and large
temporaries live in per-task scratch buffers, so a hot loop does not allocate
them on every call.

## Bundles

```@docs
UTCGP.image2D_object_common
UTCGP.number_locateFromImg
UTCGP.number_locateFromImg.bundle_number_locateFromImg
UTCGP.number_objectFromImg
UTCGP.number_objectFromImg.bundle_number_objectLocateFromImg
UTCGP.number_objectFromImg.bundle_number_objectDescribeFromImg
UTCGP.image2D_zoom
UTCGP.image2D_zoom.bundle_image2DIntensity_zoom_factory
UTCGP.image2D_zoom.bundle_image2DBinary_zoom_factory
UTCGP.image2D_zoom.bundle_image2DSegment_zoom_factory
```
