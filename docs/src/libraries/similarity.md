```@meta
CurrentModule = UTCGP
```

# Image Similarity and Template Matching

Two questions no other MAGE library answers: *how alike are these two
images?* and *where in this image is the thing I saw in that one?* Both return
numbers, so they live in the number libraries and feed the float chromosome.

| Getter | Bundles |
|:--|:--|
| `get_extension_similarity_nb()` | `bundle_number_similarityFromImg`, `bundle_number_templateFromImg` |

## Comparing two images

Every `sim_*` operator takes two same-size images (intensity or binary). The
reference below is a Pong frame; each column is one variant of it.

```@setup sim
using UTCGP
include(joinpath(dirname(pathof(UTCGP)), "..", "docs", "gallery_helpers.jl"))
S = UTCGP.number_similarityFromImg
assets = g_assets("similarity")

function pong(ball; left = 40, right = 55)
    v = fill(0.1, 80, 120)
    for r in 2:6:76
        v[r:r+2, 60] .= 0.35
    end
    v[left-5:left+5, 6:7] .= 0.8
    v[right-5:right+5, 113:114] .= 0.8
    v[ball[1]:ball[1]+1, ball[2]:ball[2]+1] .= 1.0
    return v
end
base = pong((32, 58))
reference = g_intensity(base)
shift_fn = bundle_image2DIntensity_transform_factory[:transform_shift].fn(typeof(reference))
flip_fn = bundle_image2DIntensity_transform_factory[:transform_flip_h].fn(typeof(reference))
noise = [0.06 * sin(12.9898r + 78.233c) for r in 1:80, c in 1:120]   # deterministic pseudo-noise
variants = [
    ("same", reference),
    ("ball moved", g_intensity(pong((50, 30)))),
    ("shifted 6 px", g_call(shift_fn, reference, 0.55, 0.5)),
    ("mirrored", g_call(flip_fn, reference)),
    ("inverted", g_intensity(1 .- base)),
    ("noisy", g_intensity(base .+ noise)),
    ("other rally", g_intensity(pong((60, 90); left = 20, right = 25))),
]
g_save(assets, "reference.png", g_up(g_canvas(reference), 2))
for (k, (name, img)) in enumerate(variants)
    g_save(assets, "variant_$(k).png", g_up(g_canvas(img), 2))
end
```

| Reference | same | ball moved | shifted 6 px | mirrored | inverted | noisy | other rally |
|:--:|:--:|:--:|:--:|:--:|:--:|:--:|:--:|
| ![reference](../assets/fns/similarity/reference.png) | ![1](../assets/fns/similarity/variant_1.png) | ![2](../assets/fns/similarity/variant_2.png) | ![3](../assets/fns/similarity/variant_3.png) | ![4](../assets/fns/similarity/variant_4.png) | ![5](../assets/fns/similarity/variant_5.png) | ![6](../assets/fns/similarity/variant_6.png) | ![7](../assets/fns/similarity/variant_7.png) |

Scores of each variant against the reference (`sim_x(reference, variant)`):

```@example sim
metrics = (:sim_mse, :sim_mae, :sim_correlation, :sim_ssim, :sim_hist_intersection,
           :sim_hist_bhattacharyya, :sim_iou, :sim_dice, :sim_coverage, :sim_hamming,
           :sim_chamfer, :sim_shift_x, :sim_shift_y)
println(rpad("", 24), join(rpad.(first.(variants), 12)))
for m in metrics
    f = getfield(S, m)
    println(rpad(m, 24), join(rpad.(string.(round.([f(reference, img) for (_, img) in variants], digits = 3)), 12)))
end
```

How to read them:

| Operator | Range | Meaning |
|:--|:--|:--|
| `sim_mse`, `sim_mae` | `0` = identical | mean squared / absolute pixel difference |
| `sim_correlation` | `[-1, 1]` | Pearson correlation; `-1` for the inverted frame |
| `sim_ssim` | `[-1, 1]` | structural similarity, mean over 8×8 blocks: compares local brightness, contrast and structure. Noise on flat areas lowers it a lot (`0.38` for the noisy frame), small moves barely do (`0.98`) |
| `sim_hist_intersection`, `sim_hist_bhattacharyya` | `[0, 1]`, `1` = same | compare value histograms only: blind to *where* things are, so a shift or mirror scores `≈ 1` |
| `sim_iou`, `sim_dice`, `sim_coverage`, `sim_hamming` | `[0, 1]` | compare foregrounds (pixels `>= 0.5`, or a third-argument threshold); `sim_coverage(a, b)` is the share of `a` inside `b` |
| `sim_chamfer` | `0` = overlapping | mean distance between the two foregrounds over the image diagonal; grows smoothly as objects drift apart |
| `sim_shift_x`, `sim_shift_y` | `[-0.5, 0.5]` | estimated translation of `b` relative to `a` (fraction of the size); `0.05` = the 6 px shift. Only meaningful when `b` really is a moved copy of `a`: for the inverted frame or another rally the value is arbitrary, so pair it with `sim_correlation` |

`sim_mse`, `sim_mae` and `sim_correlation` take an optional binary mask as
third argument and compare only the pixels inside it. Below, the mask covers
the right half of the court. The ball is in the left half in both the
reference (column 58) and the "ball moved" frame (column 30), so on the whole
frame they differ, but inside the mask they are identical.

```@example sim
right_half = g_binary([c > 61 for r in 1:80, c in 1:120])
moved_ball = variants[2][2]
(
    mse_whole = round(S.sim_mse(reference, moved_ball), digits = 5),
    mse_right_half = round(S.sim_mse(reference, moved_ball, right_half), digits = 5),
    correlation_whole = round(S.sim_correlation(reference, moved_ball), digits = 3),
    correlation_right_half = round(S.sim_correlation(reference, moved_ball, right_half), digits = 3),
)
```

The foreground scores (`sim_iou`, `sim_dice`, `sim_coverage`, `sim_hamming`,
`sim_chamfer`) threshold both images at `0.5` by default, or at a third
argument. The threshold decides what counts as "the objects": at `0.3` the
net (`0.35`) joins the paddles and the ball, at `0.9` only the ball remains.

```@example sim
for t in (0.3, 0.5, 0.9)
    println(rpad("threshold $t", 16),
        "sim_iou(reference, ball moved) = ", rpad(round(S.sim_iou(reference, moved_ball, t), digits = 3), 8),
        "sim_chamfer = ", round(S.sim_chamfer(reference, moved_ball, t), digits = 3))
end
```

## Template matching

`match_x_<p>(img, ref)` / `match_y_<p>` cut a template covering `p` (10%, 20%
or 30%) of each side from the **centre** of `ref` (or around `(s, s)` with
`(img, ref, s)`), find where it best matches in `img` by normalised
cross-correlation, and return the match centre. `match_score_<p>` returns the
correlation itself, `[-1, 1]`: "how present is the thing".

The centre convention composes with the zoom library: `zoom_recenter_<sel>`
puts an object in the middle of a reference frame, then `match_*` finds the
same-looking thing in another frame.

```@setup sim
lena_values = Float64.(Gray.(load(joinpath(g_repo_root(), "assets", "lena_gray_16bit.png"))))[1:4:end, 1:4:end]
lena = g_intensity(lena_values)
h, w = size(lena_values)
moved_values = fill(0.2, h, w)
moved_values[1:end-20, 1:end-14] .= lena_values[21:end, 15:end]    # the face moves up-left
moved = g_intensity(moved_values)
let canvas = g_up(g_canvas(lena), 3)
    for (p, color) in ((0.1, G_RED), (0.2, G_GREEN), (0.3, G_BLUE))
        th, tw = round(Int, p * h), round(Int, p * w)
        r0 = (h + 1) ÷ 2 - th ÷ 2
        c0 = (w + 1) ÷ 2 - tw ÷ 2
        g_rect!(canvas, r0, r0 + th - 1, c0, c0 + tw - 1, 3; color = color)
    end
    g_save(assets, "template_ref.png", canvas)
end
let canvas = g_up(g_canvas(moved), 3)
    for (p, color) in ((10, G_RED), (20, G_GREEN), (30, G_BLUE))
        x = getfield(S, Symbol(:match_x_, p, :p))(moved, lena)
        y = getfield(S, Symbol(:match_y_, p, :p))(moved, lena)
        g_cross!(canvas, x, y, 3; color = color, lines = false)
    end
    g_save(assets, "template_match.png", canvas)
end

# Tracking a sprite: recentre the ball in the previous frame, find it in the next.
previous = reference
next_frame = g_intensity(pong((50, 30)))
recenter_fn = bundle_image2DIntensity_zoom_factory[:zoom_recenter_smallest].fn(typeof(previous))
ball_template = g_call(recenter_fn, previous, previous)
let canvas = g_up(g_canvas(ball_template), 3)
    th, tw = round(Int, 0.1 * 80), round(Int, 0.1 * 120)
    g_rect!(canvas, 40 - th ÷ 2, 40 - th ÷ 2 + th - 1, 60 - tw ÷ 2, 60 - tw ÷ 2 + tw - 1, 3)
    g_save(assets, "ball_template.png", canvas)
end
let canvas = g_up(g_canvas(next_frame), 3)
    g_cross!(canvas, S.match_x_10p(next_frame, ball_template), S.match_y_10p(next_frame, ball_template), 3)
    g_save(assets, "ball_match.png", canvas)
end
```

| Reference: templates of 10% (red), 20% (green), 30% (blue) | Moved image: match centres |
|:--:|:--:|
| ![template reference](../assets/fns/similarity/template_ref.png) | ![template match](../assets/fns/similarity/template_match.png) |

Every template operator on this pair (`match_x_<p>`, `match_y_<p>`: where the
centre of the template was found in the moved image; `match_score_<p>`: how
well it matched). The face moved 14 columns left and 20 rows up, so the match
centre is up-left of the image centre (`0.5`, `0.5`):

```@example sim
for p in (10, 20, 30)
    x = getfield(S, Symbol(:match_x_, p, :p))(moved, lena)
    y = getfield(S, Symbol(:match_y_, p, :p))(moved, lena)
    score = getfield(S, Symbol(:match_score_, p, :p))(moved, lena)
    println(rpad("match_x_$(p)p / match_y_$(p)p / match_score_$(p)p", 44), "x = ", rpad(round(x, digits = 3), 8),
            "y = ", rpad(round(y, digits = 3), 8), "score = ", round(score, digits = 3))
end
```

`(img, ref, s)` takes the template around `(s, s)` in `ref` instead of its
centre, e.g. `match_x_20p(moved, lena, 0.3)` looks for the region around
`(0.3, 0.3)` of the reference.

Tracking a sprite between two Pong frames: `zoom_recenter_smallest(previous,
previous)` puts the ball at the centre (green box = the 10% template), and
`match_*_10p(next, centred)` finds it in the next frame.

| `zoom_recenter_smallest(previous)` | `match_x_10p` / `match_y_10p` on the next frame |
|:--:|:--:|
| ![ball template](../assets/fns/similarity/ball_template.png) | ![ball match](../assets/fns/similarity/ball_match.png) |

A flat template (nothing at the centre of `ref`) has no shape to match:
`match_x`/`match_y` return `0.5` and `match_score` returns `0`.

## Performance

On an 84×84 frame: pixel and mask scores 3–10 µs, histograms ~22 µs,
`sim_shift_*` ~5 µs, `sim_chamfer` ~110 µs (two exact distance transforms).
Template matching takes ~105 µs (10%), ~125 µs (20%) and ~160 µs (30%):
correlations are accumulated over whole columns of candidate positions in SIMD
loops, and templates wider than 16 pixels are searched coarse-to-fine (a grid
of step `side ÷ 8`, then every row of the columns around the best grid
position).

## Bundles

```@docs
UTCGP.number_similarityFromImg
UTCGP.number_similarityFromImg.bundle_number_similarityFromImg
UTCGP.number_similarityFromImg.bundle_number_templateFromImg
```
