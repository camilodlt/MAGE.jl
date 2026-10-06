"""
Image comparison: how similar two images are, how far one is shifted from the
other, and where a template taken from one image appears in another.

# Bundles

- [`bundle_number_similarityFromImg`](@ref)
- [`bundle_number_templateFromImg`](@ref)

The exhaustive, always-current list of operators in each bundle is on the
[Bundle Catalogue](@ref) page.
"""
module number_similarityFromImg

using ImageCore: N0f8
using ..UTCGP: FunctionBundle, append_method!
using ..UTCGP: SImageND, IntensityPixel, BinaryPixel
using ..image2D_object_common: _unit, _to_unit, _value, scratch, squared_distance_map!

fallback(args...) = return 0.0

"""
    bundle_number_similarityFromImg

Scores comparing two same-size images `a` and `b` (intensity or binary).

- Pixel differences: `sim_mse`, `sim_mae` (`0` = identical).
- Structure: `sim_correlation` (Pearson, `[-1, 1]`), `sim_ssim` (mean SSIM over
  8×8 blocks, `[-1, 1]`).
- Value distributions, position-free: `sim_hist_intersection`,
  `sim_hist_bhattacharyya` (32 bins, `[0, 1]`, `1` = same histogram).
- Masks (intensity thresholded at `0.5`, or at a third argument): `sim_iou`,
  `sim_dice`, `sim_coverage` (share of `a` covered by `b`), `sim_hamming`
  (share of differing pixels), `sim_chamfer` (mean distance between the two
  foregrounds over the image diagonal, `0` = overlapping).
- Displacement: `sim_shift_x`, `sim_shift_y`: the translation of `b` relative
  to `a` that best aligns their column (row) profiles, as a signed fraction of
  the image size in `[-0.5, 0.5]`.

`sim_mse`, `sim_mae` and `sim_correlation` also accept a binary mask as third
argument and then compare only the pixels inside it.
"""
bundle_number_similarityFromImg = FunctionBundle(fallback)

"""
    bundle_number_templateFromImg

Template matching by normalised cross-correlation. `match_x_<p>(img, ref)`
takes the central window of `ref` covering `p` of each side as the template,
finds where it best matches in `img`, and returns the normalised column of the
match centre (`match_y_<p>` the row, `match_score_<p>` the correlation in
`[-1, 1]`). `(img, ref, s)` takes the template around `(s, s)` in `ref`
instead of the centre.

Templates wider than 16 pixels are searched coarse-to-fine: a grid of step
`side ÷ 8` first, then every row of the columns around the best grid position.
This is exact whenever the correlation peak is not narrower than the grid
step.

Combine with `zoom_recenter_<sel>` to centre an object in a reference frame,
then find the same-looking object in later frames.
"""
bundle_number_templateFromImg = FunctionBundle(fallback)

const _Img = SImageND{S,T,2,C} where {S,T<:Union{IntensityPixel,BinaryPixel},C}
const _Mask = SImageND{S,T,2,C} where {S,T<:BinaryPixel,C}
const _HIST_BINS = 32
const _SSIM_BLOCK = 8
const _SSIM_C1 = 0.01^2
const _SSIM_C2 = 0.03^2

function _check(a, b)
    size(a) == size(b) || throw(DimensionMismatch("images must have the same size"))
    return nothing
end

@inline _in(mask::Nothing, i) = true
@inline _in(mask::AbstractMatrix, i) = @inbounds mask[i].pixel == true

function _mse(a, b, mask)
    _check(a, b)
    s = 0.0
    n = 0
    @inbounds for i in eachindex(a)
        _in(mask, i) || continue
        d = _value(a[i]) - _value(b[i])
        s += d * d
        n += 1
    end
    return n == 0 ? 0.0 : s / n
end

function _mae(a, b, mask)
    _check(a, b)
    s = 0.0
    n = 0
    @inbounds for i in eachindex(a)
        _in(mask, i) || continue
        s += abs(_value(a[i]) - _value(b[i]))
        n += 1
    end
    return n == 0 ? 0.0 : s / n
end

function _correlation(a, b, mask)
    _check(a, b)
    n = 0
    sa = sb = saa = sbb = sab = 0.0
    @inbounds for i in eachindex(a)
        _in(mask, i) || continue
        x = _value(a[i])
        y = _value(b[i])
        n += 1
        sa += x
        sb += y
        saa += x * x
        sbb += y * y
        sab += x * y
    end
    n < 2 && return 0.0
    va = saa - sa * sa / n
    vb = sbb - sb * sb / n
    (va <= 1e-12 || vb <= 1e-12) && return 0.0
    return clamp((sab - sa * sb / n) / sqrt(va * vb), -1.0, 1.0)
end

function _ssim(a, b)
    _check(a, b)
    h, w = size(a)
    total = 0.0
    blocks = 0
    for c0 in 1:_SSIM_BLOCK:w, r0 in 1:_SSIM_BLOCK:h
        r1 = min(r0 + _SSIM_BLOCK - 1, h)
        c1 = min(c0 + _SSIM_BLOCK - 1, w)
        n = (r1 - r0 + 1) * (c1 - c0 + 1)
        sa = sb = saa = sbb = sab = 0.0
        @inbounds for c in c0:c1, r in r0:r1
            x = _value(a[r, c])
            y = _value(b[r, c])
            sa += x
            sb += y
            saa += x * x
            sbb += y * y
            sab += x * y
        end
        ma, mb = sa / n, sb / n
        va = max(saa / n - ma^2, 0.0)
        vb = max(sbb / n - mb^2, 0.0)
        cov = sab / n - ma * mb
        total += ((2ma * mb + _SSIM_C1) * (2cov + _SSIM_C2)) /
                 ((ma^2 + mb^2 + _SSIM_C1) * (va + vb + _SSIM_C2))
        blocks += 1
    end
    return clamp(total / blocks, -1.0, 1.0)
end

@inline _hist_bin(v::Float64) = min(unsafe_trunc(Int, clamp(v, 0.0, 1.0) * _HIST_BINS), _HIST_BINS - 1) + 1
@inline _hist_bin(p) = _hist_bin(_value(p))
# 8-bit pixels: the bin of every raw byte, computed once with the same formula.
const _HIST_BIN_N0F8 = ntuple(k -> _hist_bin(Float64(reinterpret(N0f8, UInt8(k - 1)))), 256)
@inline _hist_bin(p::IntensityPixel{N0f8}) = @inbounds _HIST_BIN_N0F8[Int(reinterpret(p.pixel)) + 1]

function _histogram(pixels)
    counts = zeros(Int, _HIST_BINS)
    @inbounds for p in pixels
        counts[_hist_bin(p)] += 1
    end
    return counts ./ length(pixels)
end

_hist_intersection(a, b) = sum(min.(_histogram(a), _histogram(b)))
_hist_bhattacharyya(a, b) = clamp(sum(sqrt.(_histogram(a) .* _histogram(b))), 0.0, 1.0)

@inline _fg(p, threshold) = _value(p) >= threshold

function _overlap(a, b, threshold)
    _check(a, b)
    na = nb = nab = 0
    @inbounds for i in eachindex(a)
        x = _fg(a[i], threshold)
        y = _fg(b[i], threshold)
        na += x
        nb += y
        nab += x & y
    end
    return na, nb, nab
end

function _iou(a, b, t)
    na, nb, nab = _overlap(a, b, t)
    union = na + nb - nab
    return union == 0 ? 1.0 : nab / union
end

function _dice(a, b, t)
    na, nb, nab = _overlap(a, b, t)
    return na + nb == 0 ? 1.0 : 2nab / (na + nb)
end

function _coverage(a, b, t)
    na, _, nab = _overlap(a, b, t)
    return na == 0 ? 1.0 : nab / na
end

function _hamming(a, b, t)
    _check(a, b)
    d = 0
    @inbounds for i in eachindex(a)
        d += _fg(a[i], t) != _fg(b[i], t)
    end
    return d / length(a)
end

function _chamfer(a, b, t)
    _check(a, b)
    h, w = size(a)
    fa = scratch(:chamfer_a, Bool, h, w)
    fb = scratch(:chamfer_b, Bool, h, w)
    @inbounds for i in eachindex(a)
        fa[i] = _fg(a[i], t)
        fb[i] = _fg(b[i], t)
    end
    na, nb = count(fa), count(fb)
    (na == 0 && nb == 0) && return 0.0
    (na == 0 || nb == 0) && return 1.0
    d = scratch(:chamfer_d, Float64, h, w)
    diagonal = max(hypot(h - 1, w - 1), 1.0)
    squared_distance_map!(d, fb)                 # distance to b's foreground
    mean_ab = 0.0
    @inbounds for i in eachindex(d)
        fa[i] && (mean_ab += sqrt(d[i]))
    end
    squared_distance_map!(d, fa)                 # distance to a's foreground
    mean_ba = 0.0
    @inbounds for i in eachindex(d)
        fb[i] && (mean_ba += sqrt(d[i]))
    end
    return clamp((mean_ab / na + mean_ba / nb) / (2diagonal), 0.0, 1.0)
end

"Best lag (in pixels) of `q` against `p` by cross-correlation of mean-removed profiles."
function _best_lag(p::Vector{Float64}, q::Vector{Float64})
    n = length(p)
    p = p .- sum(p) / n
    q = q .- sum(q) / n
    max_lag = n ÷ 2
    best_lag = 0
    best = -Inf
    for lag in -max_lag:max_lag
        s = 0.0
        overlap = 0
        @inbounds for i in max(1, 1 - lag):min(n, n - lag)
            s += p[i] * q[i+lag]
            overlap += 1
        end
        overlap == 0 && continue
        score = s / overlap
        if score > best + 1e-12
            best = score
            best_lag = lag
        end
    end
    return best_lag
end

"Column (`axis = 1`) or row mass profile of an image, one SIMD pass."
function _profile(axis::Int, pixels)
    h, w = size(pixels)
    if axis == 1
        profile = Vector{Float64}(undef, w)
        @inbounds for c in 1:w
            acc = 0.0
            @simd for r in 1:h
                acc += _value(pixels[r, c])
            end
            profile[c] = acc
        end
        return profile
    end
    profile = zeros(h)
    @inbounds for c in 1:w
        @simd for r in 1:h
            profile[r] += _value(pixels[r, c])
        end
    end
    return profile
end

function _shift(axis::Int, a, b)
    _check(a, b)
    pa = _profile(axis, a)
    pb = _profile(axis, b)
    return _best_lag(pa, pb) / length(pa)
end

# ---------------------------------------------------------------------------
# Template matching
# ---------------------------------------------------------------------------

"Central (or around `(x, y)`) window of `fraction` of `ref`'s sides."
function _template(ref::AbstractMatrix, x::Float64, y::Float64, fraction::Float64)
    h, w = size(ref)
    th = clamp(round(Int, fraction * h), 3, h)
    tw = clamp(round(Int, fraction * w), 3, w)
    cr = round(Int, 1 + y * (h - 1))
    cc = round(Int, 1 + x * (w - 1))
    r0 = clamp(cr - th ÷ 2, 1, h - th + 1)
    c0 = clamp(cc - tw ÷ 2, 1, w - tw + 1)
    return [_value(ref[r, c]) for r in r0:r0+th-1, c in c0:c0+tw-1]
end

"""
Accumulate the dot products of template `t` with the candidate rows
`1, 1 + stride, 1 + 2stride, …` at column `c0` (one entry of `acc` each).
"""
function _correlate_column!(acc::Vector{Float64}, values::Matrix{Float64}, t::Matrix{Float64}, c0::Int, stride::Int)
    th, tw = size(t)
    fill!(acc, 0.0)
    @inbounds for dc in 0:tw-1
        c = c0 + dc
        for dr in 0:th-1
            tv = t[dr+1, dc+1]
            @simd ivdep for k in eachindex(acc)
                acc[k] += values[1 + (k - 1) * stride + dr, c] * tv
            end
        end
    end
    return acc
end

"""
Score candidate rows `1:stride:nr` of column `c0` and fold the best into
`best`. Window variances come from the integral images `s1`, `s2`; both loops
are branch-free and vectorise.
"""
function _scan_column(best::Tuple{Float64,Int,Int}, acc, scores, values, t, s1, s2, c0, n, tnorm, stride)
    th, tw = size(t)
    _correlate_column!(acc, values, t, c0, stride)
    c1 = c0 + tw
    @inbounds @simd for k in eachindex(acc)
        r0 = 1 + (k - 1) * stride
        r1 = r0 + th
        sum1 = s1[r1, c1] - s1[r0, c1] - s1[r1, c0] + s1[r0, c0]
        sum2 = s2[r1, c1] - s2[r0, c1] - s2[r1, c0] + s2[r0, c0]
        var = sum2 - sum1 * sum1 / n
        scores[k] = ifelse(var <= 1e-12, -Inf, acc[k] / (sqrt(max(var, 1e-12)) * tnorm))
    end
    best_score, best_r, best_c = best
    @inbounds for k in eachindex(scores)
        if scores[k] > best_score
            best_score, best_r, best_c = scores[k], 1 + (k - 1) * stride, c0
        end
    end
    return (best_score, best_r, best_c)
end

"""
Best normalised cross-correlation of `template` over `img`: `(row, col, score)`
of the match centre.

Dot products are accumulated per template coefficient over a column of
candidate rows (one long SIMD loop). Templates wider than 16 pixels are first
scored on a grid of step `stride = side ÷ 8` in both directions, then every row
of the columns within one step of the best grid position is scored. Window
variances come from integral images. Temporaries live in per-task scratch
buffers.
"""
function _match(img::AbstractMatrix, template::Matrix{Float64})
    h, w = size(img)
    th, tw = size(template)
    (th > h || tw > w) && return (h + 1) / 2, (w + 1) / 2, 0.0
    n = th * tw
    t = template .- sum(template) / n
    tnorm = sqrt(sum(abs2, t))
    tnorm <= 1e-12 && return (h + 1) / 2, (w + 1) / 2, 0.0
    values = scratch(:match_values, Float64, h, w)
    @inbounds for i in eachindex(values, img)
        values[i] = _value(img[i])
    end
    s1 = scratch(:match_s1, Float64, h + 1, w + 1)
    s2 = scratch(:match_s2, Float64, h + 1, w + 1)
    s1[1, :] .= 0.0
    s1[:, 1] .= 0.0
    s2[1, :] .= 0.0
    s2[:, 1] .= 0.0
    @inbounds for c in 1:w, r in 1:h
        v = values[r, c]
        s1[r+1, c+1] = v + s1[r, c+1] + s1[r+1, c] - s1[r, c]
        s2[r+1, c+1] = v * v + s2[r, c+1] + s2[r+1, c] - s2[r, c]
    end
    nr = h - th + 1
    nc = w - tw + 1
    stride = max(1, min(th, tw) ÷ 8)
    # Strided row loads only pay off from a step of 3; at 2 the coarse pass
    # scores every row of each grid column.
    row_stride = stride >= 3 ? stride : 1
    acc = scratch(:match_acc, Float64, cld(nr, row_stride))
    scores = scratch(:match_scores, Float64, cld(nr, row_stride))
    best = (-Inf, 1, 1)
    for c0 in 1:stride:nc
        best = _scan_column(best, acc, scores, values, t, s1, s2, c0, n, tnorm, row_stride)
    end
    if stride > 1 && best[1] > -Inf
        coarse_c = best[3]
        acc = scratch(:match_acc_fine, Float64, nr)
        scores = scratch(:match_scores_fine, Float64, nr)
        for c0 in max(1, coarse_c - stride + 1):min(nc, coarse_c + stride - 1)
            (c0 == coarse_c && row_stride == 1) && continue
            best = _scan_column(best, acc, scores, values, t, s1, s2, c0, n, tnorm, 1)
        end
    end
    best_score, best_r, best_c = best
    best_score == -Inf && return (h + 1) / 2, (w + 1) / 2, 0.0
    return best_r + (th - 1) / 2, best_c + (tw - 1) / 2, clamp(best_score, -1.0, 1.0)
end

function _match_output(what::Symbol, img::AbstractMatrix, ref::AbstractMatrix, x, y, fraction)
    r, c, score = _match(img, _template(ref, x, y, fraction))
    h, w = size(img)
    what === :x && return _to_unit(c, w)
    what === :y && return _to_unit(r, h)
    return score
end

# ---------------------------------------------------------------------------
# Registration
# ---------------------------------------------------------------------------

function _register!(bundle, name::Symbol, description::String, doc::String)
    @eval @doc $doc $name
    append_method!(bundle, getfield(@__MODULE__, name), name; description = description)
end

for (name, kernel, what) in (
        (:sim_mse, :_mse, "Mean squared difference (0 = identical)."),
        (:sim_mae, :_mae, "Mean absolute difference (0 = identical)."),
        (:sim_correlation, :_correlation, "Pearson correlation of pixel values, in [-1, 1]."),
    )
    @eval begin
        $name(a::_Img, b::_Img, args...) = $kernel(a.img, b.img, nothing)
        $name(a::_Img, b::_Img, mask::_Mask, args...) = ($(_check)(a, mask); $kernel(a.img, b.img, mask.img))
    end
    _register!(bundle_number_similarityFromImg, name, what, """
        $name(a, b, [mask], args...)

    $what With a binary `mask`, only pixels inside it are compared.
    """)
end

for (name, kernel, what) in (
        (:sim_ssim, :_ssim, "Mean structural similarity over 8x8 blocks, in [-1, 1]."),
        (:sim_hist_intersection, :_hist_intersection, "Histogram intersection (32 bins), in [0, 1]."),
        (:sim_hist_bhattacharyya, :_hist_bhattacharyya, "Bhattacharyya coefficient of the histograms (32 bins), in [0, 1]."),
    )
    @eval $name(a::_Img, b::_Img, args...) = ($(_check)(a, b); $kernel(a.img, b.img))
    _register!(bundle_number_similarityFromImg, name, what, """
        $name(a, b, args...)

    $what
    """)
end

for (name, kernel, what) in (
        (:sim_iou, :_iou, "Intersection over union of the foregrounds (1 when both are empty)."),
        (:sim_dice, :_dice, "Dice coefficient of the foregrounds (1 when both are empty)."),
        (:sim_coverage, :_coverage, "Share of a's foreground also in b's (1 when a is empty)."),
        (:sim_hamming, :_hamming, "Share of pixels whose foreground status differs."),
        (:sim_chamfer, :_chamfer, "Mean distance between the two foregrounds over the image diagonal."),
    )
    @eval begin
        $name(a::_Img, b::_Img, args...) = $kernel(a.img, b.img, 0.5)
        $name(a::_Img, b::_Img, threshold::Number, args...) = $kernel(a.img, b.img, _unit(threshold))
    end
    _register!(bundle_number_similarityFromImg, name, what, """
        $name(a, b, [threshold], args...)

    $what Pixels at or above `threshold` (default `0.5`) are foreground;
    binary masks use their own values.
    """)
end

for (name, axis, what) in ((:sim_shift_x, 1, "horizontal"), (:sim_shift_y, 2, "vertical"))
    @eval $name(a::_Img, b::_Img, args...) = _shift($axis, a.img, b.img)
    _register!(bundle_number_similarityFromImg, name,
        "Estimated $what shift of b relative to a, as a fraction of the size.", """
        $name(a, b, args...)

    Estimated $what translation of `b` relative to `a`, from the
    cross-correlation of their $(axis == 1 ? "column" : "row") profiles, as a
    signed fraction of the image size in `[-0.5, 0.5]`.
    """)
end

for (suffix, fraction) in ((:_10p, 0.10), (:_20p, 0.20), (:_30p, 0.30))
    pct = round(Int, 100fraction)
    for (stem, what, doc) in (
            (:match_x, :x, "normalised column of the best match centre"),
            (:match_y, :y, "normalised row of the best match centre"),
            (:match_score, :score, "normalised cross-correlation of the best match, in [-1, 1]"),
        )
        name = Symbol(stem, suffix)
        @eval begin
            $name(img::_Img, ref::_Img, args...) =
                _match_output($(QuoteNode(what)), img.img, ref.img, 0.5, 0.5, $fraction)
            $name(img::_Img, ref::_Img, s::Number, args...) =
                (u = _unit(s); _match_output($(QuoteNode(what)), img.img, ref.img, u, u, $fraction))
        end
        _register!(bundle_number_templateFromImg, name,
            "Template matching ($pct% template): $doc.", """
            $name(img, ref, [s], args...)

        Takes a template of $pct% of each side from the centre of `ref` (or
        around `(s, s)`) and returns the $doc in `img`. A flat template or
        image returns `0.5` (`0.0` for the score).
        """)
    end
end

end
