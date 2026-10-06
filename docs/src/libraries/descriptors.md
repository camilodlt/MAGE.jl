```@meta
CurrentModule = UTCGP
```

# Descriptors for Image Classification

To tell classes apart, a program needs numbers that describe *what* is in the
image regardless of *where*: how intensities are distributed, what shapes the
objects have, how big the structures are. These four bundles provide such
position-free descriptors. Most also work inside a region of interest (ROI),
so a program can describe "the cell" rather than "the slide", or compare a
region with its surroundings.

| Getter | Bundles |
|:--|:--|
| `get_extension_descriptors_nb()` | `bundle_number_intensityStatsFromImg`, `bundle_number_shapeFromImg`, `bundle_number_objectStatsFromImg`, `bundle_number_granulometryFromImg` |

Every operator returns a `Float64`, takes at most three inputs, and returns
`0.0` for an empty selection. A ROI is a binary mask, or an intensity map
thresholded at `0.5`, so any MAGE mask (saliency, blobs, clean-up) can be one.

## Example classes

Four synthetic cell classes, 64×64 (shown at 3×), each with a textured interior
on a darker textured background. The masks are the images thresholded at
`0.5`.

```@setup desc
using UTCGP
include(joinpath(dirname(pathof(UTCGP)), "..", "docs", "gallery_helpers.jl"))
I = UTCGP.number_intensityStatsFromImg
Sh = UTCGP.number_shapeFromImg
G = UTCGP.number_granulometryFromImg
assets = g_assets("descriptors")
noise(r, c, seed) = 0.5 + 0.5 * sin(12.9898r + 78.233c + 37.719seed)       # deterministic texture

function cell(kind; n = 64)
    v = [0.15 + 0.08 * noise(r, c, 1) for r in 1:n, c in 1:n]
    for r in 1:n, c in 1:n
        y, x = r - n / 2, c - n / 2
        inside = if kind == :round
            x^2 + y^2 <= 18^2
        elseif kind == :elongated
            u = x * cosd(30) - y * sind(30)
            w = x * sind(30) + y * cosd(30)
            (u / 26)^2 + (w / 10)^2 <= 1
        elseif kind == :lobed
            θ = atan(y, x)
            sqrt(x^2 + y^2) <= 13 + 7 * cos(5θ)
        else                                                         # vacuolated
            x^2 + y^2 <= 20^2 && (x - 7)^2 + (y + 4)^2 > 25 && (x + 8)^2 + (y - 6)^2 > 16 && (x + 2)^2 + (y + 10)^2 > 9
        end
        inside || continue
        base = kind == :lobed ? 0.75 : 0.65
        v[r, c] = base + 0.2 * noise(r, c, kind == :round ? 2 : kind == :elongated ? 3 : 4)
    end
    return v
end
kinds = (:round, :elongated, :lobed, :vacuolated)
images = Dict(k => g_intensity(cell(k)) for k in kinds)
masks = Dict(k => g_binary(cell(k) .>= 0.5) for k in kinds)
for k in kinds
    g_save(assets, "$(k).png", g_up(g_canvas(images[k]), 3))
    g_save(assets, "$(k)_mask.png", g_up(g_canvas(masks[k]), 3))
end
table(rows, columns) = begin
    println(rpad("", 26), join(rpad.(string.(columns), 13)))
    for (name, values) in rows
        println(rpad(name, 26), join(rpad.(string.(round.(values, digits = 3)), 13)))
    end
end
```

| | round | elongated | lobed | vacuolated |
|:--|:--:|:--:|:--:|:--:|
| image | ![round](../assets/fns/descriptors/round.png) | ![elongated](../assets/fns/descriptors/elongated.png) | ![lobed](../assets/fns/descriptors/lobed.png) | ![vacuolated](../assets/fns/descriptors/vacuolated.png) |
| mask (`≥ 0.5`) | ![round mask](../assets/fns/descriptors/round_mask.png) | ![elongated mask](../assets/fns/descriptors/elongated_mask.png) | ![lobed mask](../assets/fns/descriptors/lobed_mask.png) | ![vacuolated mask](../assets/fns/descriptors/vacuolated_mask.png) |

## 1. Intensity distribution — `bundle_number_intensityStatsFromImg`

| Statistic | Meaning |
|:--|:--|
| `stat_q05`, `stat_q25`, `stat_q50`, `stat_q75`, `stat_q95`, `stat_iqr` | quantiles (as `Statistics.quantile`) and the interquartile range |
| `stat_mean`, `stat_std`, `stat_mad` | mean, standard deviation, mean absolute deviation |
| `stat_skewness`, `stat_kurtosis` | asymmetry and tail weight (excess kurtosis: `0` for a Gaussian) |
| `stat_entropy`, `stat_uniformity` | spread of the 32-bin histogram: entropy over its maximum, sum of squared probabilities |
| `stat_bimodality` | bimodality coefficient; above `5/9 ≈ 0.56` suggests two populations |
| `stat_otsu_threshold`, `stat_otsu_separability` | Otsu's threshold, and how well it splits the pixels (between-class over total variance, `1` = two clean levels) |
| `stat_frac_above` | fraction of pixels at or above a threshold (last argument, default `0.5`) |

Each comes in four forms:

| Call | Pixels summarised |
|:--|:--|
| `stat_x(img)` | the whole image |
| `stat_x(img, roi)` | inside the region |
| `stat_x_out(img, roi)` | outside the region |
| `stat_x_diff(img, roi)` | inside value minus outside value |

The histograms below are of the round and the lobed cell (whole image). Grey
bars: 64-bin histogram; blue lines: `q25`, `q50`, `q75`; red line: Otsu
threshold.

```@setup desc
function histogram_plot(img; bins = 64, size = (120, 260))
    v = Float64.(reinterpret(img.img))
    counts = zeros(bins)
    for x in v
        counts[clamp(floor(Int, x * bins) + 1, 1, bins)] += 1
    end
    h, w = size
    canvas = fill(RGB{Float64}(1, 1, 1), h, w)
    peak = maximum(counts)
    for b in 1:bins
        c0 = round(Int, (b - 1) / bins * (w - 1)) + 1
        c1 = max(round(Int, b / bins * (w - 1)), c0)
        top = h - round(Int, counts[b] / peak * (h - 6))
        canvas[clamp(top, 1, h):h, c0:c1] .= RGB{Float64}(0.6, 0.62, 0.66)
    end
    mark(x, color) = (c = clamp(round(Int, x * (w - 1)) + 1, 1, w); canvas[:, c] .= color; canvas[:, min(c + 1, w)] .= color)
    for q in (I.stat_q25(img), I.stat_q50(img), I.stat_q75(img))
        mark(q, G_BLUE)
    end
    mark(I.stat_otsu_threshold(img), G_RED)
    return canvas
end
g_save(assets, "hist_round.png", histogram_plot(images[:round]))
g_save(assets, "hist_lobed.png", histogram_plot(images[:lobed]))
```

| round | lobed |
|:--:|:--:|
| ![round histogram](../assets/fns/descriptors/hist_round.png) | ![lobed histogram](../assets/fns/descriptors/hist_lobed.png) |

Whole-image statistics of the four classes:

```@example desc
stats = (:q05, :q50, :q95, :iqr, :std, :skewness, :kurtosis, :entropy, :bimodality, :otsu_threshold, :otsu_separability)
table([("stat_$(s)", [getfield(I, Symbol(:stat_, s))(images[k]) for k in kinds]) for s in stats], kinds)
```

The ROI forms separate the cell from its background. Here the ROI is each
image's own mask: inside, the texture of the cell; outside, the background;
`_diff`, the contrast between them.

```@example desc
rows = []
for s in (:mean, :std, :entropy)
    push!(rows, ("stat_$(s)(img, mask)", [getfield(I, Symbol(:stat_, s))(images[k], masks[k]) for k in kinds]))
    push!(rows, ("stat_$(s)_out(img, mask)", [getfield(I, Symbol(:stat_, s, :_out))(images[k], masks[k]) for k in kinds]))
    push!(rows, ("stat_$(s)_diff(img, mask)", [getfield(I, Symbol(:stat_, s, :_diff))(images[k], masks[k]) for k in kinds]))
end
table(rows, kinds)
```

## 2. Shape — `bundle_number_shapeFromImg`

Descriptors of the whole foreground, treated as one shape:

| Operator | Meaning |
|:--|:--|
| `shape_hu1` … `shape_hu7` | Hu's moment invariants, as `−sign(h) log10(abs(h))`: unchanged by translation, rotation and scale; `hu7` changes sign under mirroring |
| `shape_hu1_weighted` … `shape_hu7_weighted` | the same on the intensity image (weights divided by their maximum, so contrast does not matter); `(img, roi)` restricts to a region |
| `shape_solidity` | area over the pixel area of the convex hull: `1` for convex shapes, low for lobed ones |
| `shape_circularity`, `shape_elongation`, `shape_extent` | moment circularity, `1 − sqrt(λmin / λmax)`, area over bounding-box area |
| `shape_fill`, `shape_hole_fraction`, `shape_euler` | area over image area, holes over filled area, objects minus holes |

Inputs: `(mask)`, `(img)` at `0.5`, `(img, threshold)`; `(mask, roi)` keeps only
the foreground inside the region.

```@example desc
ops = (:solidity, :circularity, :elongation, :extent, :fill, :hole_fraction, :euler, :hu1, :hu2, :hu3)
table([("shape_$(s)", [getfield(Sh, Symbol(:shape_, s))(masks[k]) for k in kinds]) for s in ops], kinds)
```

The lobed cell has the lowest solidity, the elongated one the highest
elongation, and only the vacuolated cell has holes (Euler number `1 − 3 = −2`).

### Invariance of the Hu moments

The same shape moved, rotated by 90°, scaled ×2 and mirrored. The first six
invariants stay (almost) equal — scaling only changes them through
pixelisation — while `hu7` flips sign for the mirror image.

```@setup desc
base = falses(64, 64)
for r in 1:64, c in 1:64
    ((r - 30) / 12)^2 + ((c - 24) / 6)^2 <= 1 && (base[r, c] = true)
end
base[18:24, 24:34] .= true
moved = circshift(base, (8, 20))
scaled = falses(128, 128)
scaled[1:128, 1:128] .= repeat(base, inner = (2, 2))
variants = [("original", base), ("moved", moved), ("rotated 90°", rotl90(base)), ("mirrored", base[:, end:-1:1]), ("scaled ×2", scaled)]
for (k, (_, m)) in enumerate(variants)
    g_save(assets, "hu_variant_$(k).png", g_up(g_canvas(g_binary(m)), k == 5 ? 1 : 2))
end
```

| original | moved | rotated 90° | mirrored | scaled ×2 |
|:--:|:--:|:--:|:--:|:--:|
| ![1](../assets/fns/descriptors/hu_variant_1.png) | ![2](../assets/fns/descriptors/hu_variant_2.png) | ![3](../assets/fns/descriptors/hu_variant_3.png) | ![4](../assets/fns/descriptors/hu_variant_4.png) | ![5](../assets/fns/descriptors/hu_variant_5.png) |

```@example desc
table([("shape_hu$(k)", [getfield(Sh, Symbol(:shape_hu, k))(g_binary(m)) for (_, m) in variants]) for k in 1:7],
      first.(variants))
```

## Aggregates over objects — `bundle_number_objectStatsFromImg`

When a mask holds many objects (cells in a field, grains, letters), the
distribution of their properties often separates classes better than any
single object. `objs_<descriptor>_<aggregate>` computes a descriptor for every
8-connected object and aggregates it.

| Descriptors | Aggregates |
|:--|:--|
| `area` (fraction of the image), `circularity`, `elongation`, `extent`, `solidity`, `nn_distance` (distance to the nearest other centroid) | `mean`, `std`, `min`, `max`, `median`, `cv` (std / mean) |

Plus `objs_area_gini` (inequality of sizes: `0` all equal) and
`objs_intensity_<aggregate>(img, mask)` (each object's mean intensity,
aggregated). `(mask, roi)` keeps the objects whose centroid lies inside the
region.

```@setup desc
function field(kind)
    m = falses(96, 96)
    centers = [(12 + 24 * i + (kind == :mixed ? 4 * ((i + j) % 3) : 0), 12 + 24 * j) for i in 0:3, j in 0:3]
    for (k, (cr, cc)) in enumerate(centers)
        for r in 1:96, c in 1:96
            y, x = r - cr, c - cc
            inside = if kind == :uniform
                x^2 + y^2 <= 25
            else                                      # mixed sizes and shapes
                s = 2 + k % 5
                (x / (s + 3))^2 + (y / s)^2 <= 1
            end
            inside && (m[r, c] = true)
        end
    end
    return m
end
fields = [("uniform", field(:uniform)), ("mixed", field(:mixed))]
for (name, m) in fields
    g_save(assets, "field_$(name).png", g_up(g_canvas(g_binary(m)), 2))
end
top_half = g_binary([r <= 48 for r in 1:96, c in 1:96])
```

| uniform | mixed |
|:--:|:--:|
| ![uniform field](../assets/fns/descriptors/field_uniform.png) | ![mixed field](../assets/fns/descriptors/field_mixed.png) |

```@example desc
O = UTCGP.number_shapeFromImg
names_ = (:objs_area_mean, :objs_area_cv, :objs_area_gini, :objs_circularity_min, :objs_elongation_max,
          :objs_nn_distance_mean, :objs_nn_distance_std)
rows = [(String(n), [getfield(O, n)(g_binary(m)) for (_, m) in fields]) for n in names_]
push!(rows, ("objs_area_mean(mask, top)", [O.objs_area_mean(g_binary(m), top_half) for (_, m) in fields]))
table(rows, first.(fields))
```

## 5. Size distribution — `bundle_number_granulometryFromImg`

An *opening* of radius `r` removes every structure narrower than a disk of
that radius and keeps the rest unchanged. The fraction that survives, as `r`
grows, is the size distribution of the structures: it drops where most of the
grains have their size.

| Operator | Meaning |
|:--|:--|
| `gran_open_r<k>(mask)`, `k ∈ {1, 2, 3, 4, 6, 8}` | fraction of the foreground surviving an exact Euclidean disk opening of radius `k` |
| `gran_open(mask, r)` | the same with the radius as a scalar: `1 + round(15 r)` pixels |
| `gran_open_bg_r<k>(mask)` | fraction of the background surviving: low when the background is made of narrow gaps |
| `gran_thickness_mean`, `gran_thickness_max` | mean and largest distance to the background, over half the shorter side |
| `gran_grey_open_r<k>(img[, roi])` | share of the total intensity surviving a grey opening by a `(2k+1)²` square: bright structures at least that wide |
| `gran_grey_close_r<k>(img[, roi])` | share of the total darkness surviving a grey closing: dark structures at least that wide |

```@setup desc
function grains(radius_range; n = 96, count_ = 60, seed = 1)
    m = falses(n, n)
    for k in 1:count_
        cr = 1 + mod(37k * seed + 11, n)
        cc = 1 + mod(53k * seed + 29, n)
        rad = radius_range[1 + mod(7k, length(radius_range))]
        for r in max(1, cr - rad):min(n, cr + rad), c in max(1, cc - rad):min(n, cc + rad)
            (r - cr)^2 + (c - cc)^2 <= rad^2 && (m[r, c] = true)
        end
    end
    return m
end
fine = grains(1:3)
coarse = grains(5:8; count_ = 18)
open_fn = bundle_image2DBinary_maskshape_factory          # (for the side-by-side images below)
for (name, m) in (("fine", fine), ("coarse", coarse))
    g_save(assets, "grains_$(name).png", g_up(g_canvas(g_binary(m)), 2))
end
radii = (1, 2, 3, 4, 6, 8)
curve(values) = x -> begin
    x <= radii[1] && return values[1]
    for k in 2:length(radii)
        x <= radii[k] && return values[k-1] + (x - radii[k-1]) / (radii[k] - radii[k-1]) * (values[k] - values[k-1])
    end
    return values[end]
end
fine_curve = [getfield(G, Symbol(:gran_open_r, r))(g_binary(fine)) for r in radii]
coarse_curve = [getfield(G, Symbol(:gran_open_r, r))(g_binary(coarse)) for r in radii]
g_save(assets, "spectrum_binary.png", g_plot([(curve(fine_curve), G_RED), (curve(coarse_curve), G_BLUE)];
    xlim = (0.0, 9.0), ylim = (-0.1, 1.1)))

# Opened masks, by brute-force disk openings, to show what survives.
function disk_open(fg, r)
    h, w = size(fg)
    disk = [(dr, dc) for dr in -r:r, dc in -r:r if dr^2 + dc^2 <= r^2]
    er = [fg[i, j] && all(!(1 <= i + dr <= h && 1 <= j + dc <= w) || fg[i+dr, j+dc] for (dr, dc) in disk) for i in 1:h, j in 1:w]
    return [any(1 <= i + dr <= h && 1 <= j + dc <= w && er[i+dr, j+dc] for (dr, dc) in disk) for i in 1:h, j in 1:w]
end
for (name, m) in (("fine", fine), ("coarse", coarse)), r in (2, 4)
    g_save(assets, "opened_$(name)_$(r).png", g_up(g_canvas(g_binary(disk_open(m, r))), 2))
end

fine_texture = g_intensity([0.5 + 0.4 * sin(1.3r) * sin(1.1c) for r in 1:96, c in 1:96])
coarse_texture = g_intensity([0.5 + 0.4 * sin(0.25r) * sin(0.2c) for r in 1:96, c in 1:96])
g_save(assets, "texture_fine.png", g_up(g_canvas(fine_texture), 2))
g_save(assets, "texture_coarse.png", g_up(g_canvas(coarse_texture), 2))
grey_fine = [getfield(G, Symbol(:gran_grey_open_r, r))(fine_texture) for r in radii]
grey_coarse = [getfield(G, Symbol(:gran_grey_open_r, r))(coarse_texture) for r in radii]
g_save(assets, "spectrum_grey.png", g_plot([(curve(grey_fine), G_RED), (curve(grey_coarse), G_BLUE)];
    xlim = (0.0, 9.0), ylim = (-0.1, 1.1)))
```

Two grain masks: fine grains (radius 1–3) and coarse grains (radius 5–8).

| | fine | coarse |
|:--|:--:|:--:|
| mask | ![fine](../assets/fns/descriptors/grains_fine.png) | ![coarse](../assets/fns/descriptors/grains_coarse.png) |
| after an opening of radius 2 | ![fine 2](../assets/fns/descriptors/opened_fine_2.png) | ![coarse 2](../assets/fns/descriptors/opened_coarse_2.png) |
| after an opening of radius 4 | ![fine 4](../assets/fns/descriptors/opened_fine_4.png) | ![coarse 4](../assets/fns/descriptors/opened_coarse_4.png) |

Surviving fraction against the radius (horizontal `0`–`9`, vertical `0`–`1`,
grid every `0.5`): red fine grains, blue coarse grains. The fine curve
collapses at radius 4; the coarse one holds until radius 6–8.

![binary size distribution](../assets/fns/descriptors/spectrum_binary.png)

```@example desc
table([("gran_open_r$(r)", [getfield(G, Symbol(:gran_open_r, r))(g_binary(m)) for m in (fine, coarse)]) for r in radii] ∪
      [("gran_thickness_mean", [G.gran_thickness_mean(g_binary(m)) for m in (fine, coarse)]),
       ("gran_open_bg_r4", [G.gran_open_bg_r4(g_binary(m)) for m in (fine, coarse)])],
      ("fine", "coarse"))
```

The grey versions work on intensity images directly, without a mask: the
share of intensity surviving grey openings separates a fine texture (red) from
a coarse one (blue).

| fine texture | coarse texture | surviving intensity against the radius |
|:--:|:--:|:--:|
| ![fine texture](../assets/fns/descriptors/texture_fine.png) | ![coarse texture](../assets/fns/descriptors/texture_coarse.png) | ![grey spectrum](../assets/fns/descriptors/spectrum_grey.png) |

## Performance

On an 84×84 image (median per family):

| Family | Time |
|:--|:--|
| intensity statistics, 8-bit (one exact 256-level histogram) | ~9 µs |
| intensity statistics, 16-bit (exact radix selection for quantiles) | ~22 µs |
| Hu moments of a mask / of an intensity image | ~4 µs / ~11 µs |
| other shape descriptors (solidity, Euler number, …) | ~4 µs |
| object aggregates | ~7 µs |
| binary openings (distance transforms bounded by the radius) | 20–85 µs, ~36 µs median |
| grey openings and closings (shifted whole-column comparisons) | 19–57 µs |
| thickness (exact distance transform) | ~55 µs |

## Bundles

```@docs
UTCGP.number_intensityStatsFromImg
UTCGP.number_intensityStatsFromImg.bundle_number_intensityStatsFromImg
UTCGP.number_shapeFromImg
UTCGP.number_shapeFromImg.bundle_number_shapeFromImg
UTCGP.number_shapeFromImg.bundle_number_objectStatsFromImg
UTCGP.number_granulometryFromImg
UTCGP.number_granulometryFromImg.bundle_number_granulometryFromImg
```
