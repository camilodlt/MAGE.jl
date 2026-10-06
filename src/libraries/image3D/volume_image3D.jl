"""
Volume → volume operators for 3D grayscale images (CT, MRI, microscopy):
filtering, intensity transforms, morphology, binarisation, mask clean-up,
distance maps and geometry, plus 2D → 3D extrusion.

# Bundles

- bundle_image3DIntensity_volume_factory
- bundle_image3DBinary_volume_factory

The exhaustive operator list is on the Bundle Catalogue page.
"""
module image3D_volume

using ..UTCGP: FunctionBundle, append_method!
using ..UTCGP:
    BinaryPixel,
    IntensityPixel,
    SImageND,
    SizedImage,
    SizedImage3D,
    _get_image_pixel_type,
    _get_image_tuple_size,
    _get_image_type,
    _validate_factory_type
using ..image2D_object_common: scratch, _unit, IsSet, AtLeast
using ..image2D_zoom: _zero
using ..image3D_volume_common:
    voxel_values,
    voxel_foreground,
    to_pixels,
    volume_table,
    centroid,
    volume_holes!,
    volume_distance_map!,
    box_extremum!,
    cross_extremum!,
    fmin,
    fmax,
    gaussian_kernel,
    separable_convolve!,
    resample_box,
    resample_box_nearest

fallback(args...) = return nothing

const _CONVENTIONS = """
Axes: dimension 1 is `y` (rows), 2 is `x` (columns), 3 is `z` (slices).
Scalar parameters are clamped to `[0, 1]` and mapped to each operator's range;
`NaN` falls back to the default. Masks are binary volumes, or intensity
volumes thresholded at `0.5`, of the same size. Intensity outputs are clamped
to the storage range of the pixel type.
"""

"""
    bundle_image3DIntensity_volume_factory

Operators returning a same-size intensity volume.

- Filters: `vol_gaussian` (`σ = 0.3 + 2.7p`) and fixed `vol_gaussian_s05`,
  `_s1`, `_s2`; `vol_mean_3`, `vol_mean_5`; `vol_gradient` (central
  differences); `vol_laplacian` (absolute, 6-neighbour); `vol_dog`
  (difference of Gaussians, centred on `0.5`); `vol_local_std`; `vol_unsharp`.
- Intensity: `vol_normalize` (min–max), `vol_robust_normalize` (2nd–98th
  percentile), `vol_window(vol, level, width)` (CT windowing), `vol_gamma`,
  `vol_invert`, `vol_equalize`, `vol_threshold_zero`.
- Two volumes: `vol_add`, `vol_sub`, `vol_absdiff`, `vol_mult`, `vol_min`,
  `vol_max`, `vol_average`.
- Grey morphology with a `(2r+1)³` cube (`r = 1 + round(2p)`):
  `vol_erode`, `vol_dilate`, `vol_open`, `vol_close`, `vol_morph_gradient`,
  `vol_tophat`, `vol_bothat`; `vol_erode_cross`, `vol_dilate_cross` use the
  6-neighbour cross.
- Masks: `vol_mask_keep(vol, mask)`, `vol_mask_zero(vol, mask)`;
  `vol_distance_inside(mask)` and `vol_proximity(mask)` turn a mask into a
  distance map.
- Geometry (shared with the binary bundle): `vol_flip_x/y/z`,
  `vol_rot90_xy/xz/yz` (identity on non-square planes), `vol_shift_x/y/z(vol,
  s)` (`(s − 0.5)` of the size), `vol_crop_bbox[_largest](vol, mask[, margin])`
  (crop and resize back, trilinear), `vol_recenter[_largest](vol, mask)`.
- From 2D: `vol_extrude_x/y/z(img2d)` repeats a 2D image through the volume;
  `vol_mask2d_x/y/z(vol, mask2d)` applies a 2D mask to every slice.

$_CONVENTIONS
"""
const bundle_image3DIntensity_volume_factory = FunctionBundle(fallback)

"""
    bundle_image3DBinary_volume_factory

Operators returning a same-size binary volume (mask).

- Binarisation of an intensity volume: `vol_threshold(vol, t)`, `vol_otsu`,
  `vol_top_fraction(vol, p)` (brightest `p` of the voxels, default 10%).
- Binary morphology with a `(2r+1)³` cube: `vol_erode`, `vol_dilate`,
  `vol_open`, `vol_close`, `vol_morph_gradient` (boundary shell);
  `vol_erode_cross`, `vol_dilate_cross`.
- Clean-up: `vol_fill_holes`, `vol_holes` (enclosed cavities),
  `vol_largest_component`, `vol_central_component`, `vol_remove_small(p)`
  (objects under `p` of the voxels, default 0.001), `vol_clear_border`,
  `vol_majority` (3³ vote), `vol_bbox_fill`.
- Logic: `vol_and`, `vol_or`, `vol_xor`, `vol_not`.
- Geometry and 2D extrusion as in the intensity bundle (nearest neighbour).

$_CONVENTIONS
"""
const bundle_image3DBinary_volume_factory = FunctionBundle(fallback)

# ---------------------------------------------------------------------------
# Intensity kernels: Array{Float64,3} → Array{Float64,3}
# ---------------------------------------------------------------------------

_gaussian(v, sigma) = (k = gaussian_kernel(sigma); separable_convolve!(similar(v), v, k[1], k[2]))
_box_mean(v, r) = separable_convolve!(similar(v), v, fill(1.0 / (2r + 1), 2r + 1), r)

function _gradient(v)
    h, w, d = size(v)
    out = similar(v)
    @inbounds for s in 1:d, c in 1:w, r in 1:h
        gy = (v[min(r + 1, h), c, s] - v[max(r - 1, 1), c, s]) / 2
        gx = (v[r, min(c + 1, w), s] - v[r, max(c - 1, 1), s]) / 2
        gz = (v[r, c, min(s + 1, d)] - v[r, c, max(s - 1, 1)]) / 2
        out[r, c, s] = sqrt(gy^2 + gx^2 + gz^2)
    end
    return out
end

function _laplacian(v)
    h, w, d = size(v)
    out = similar(v)
    @inbounds for s in 1:d, c in 1:w, r in 1:h
        x = v[r, c, s]
        l = v[max(r - 1, 1), c, s] + v[min(r + 1, h), c, s] + v[r, max(c - 1, 1), s] +
            v[r, min(c + 1, w), s] + v[r, c, max(s - 1, 1)] + v[r, c, min(s + 1, d)] - 6x
        out[r, c, s] = abs(l)
    end
    return out
end

function _dog(v, p)
    s1 = 0.5 + 1.5p
    a = _gaussian(v, s1)
    b = _gaussian(v, 1.6s1)
    @inbounds @simd for i in eachindex(a)
        a[i] = 0.5 + 2.0 * (a[i] - b[i])
    end
    return a
end

function _local_std(v)
    m = _box_mean(v, 1)
    sq = similar(v)
    @inbounds @simd for i in eachindex(v)
        sq[i] = v[i]^2
    end
    m2 = _box_mean(sq, 1)
    @inbounds @simd for i in eachindex(m)
        m[i] = 2.0 * sqrt(max(m2[i] - m[i]^2, 0.0))
    end
    return m
end

function _unsharp(v, p)
    blurred = _gaussian(v, 1.0)
    amount = 2.0 * p
    out = similar(v)
    @inbounds @simd for i in eachindex(v)
        out[i] = v[i] + amount * (v[i] - blurred[i])
    end
    return out
end

function _normalize(v)
    lo, hi = extrema(v)
    hi - lo <= 1e-12 && return zeros(size(v))
    return (v .- lo) ./ (hi - lo)
end

"Value at quantile `p` from a 256-level histogram of `clamp(v, 0, 1)`."
function _level_quantile(hist::Vector{Int}, n::Int, p::Float64)
    target = max(1, ceil(Int, p * n))
    running = 0
    @inbounds for b in 1:256
        running += hist[b]
        running >= target && return (b - 1) / 255
    end
    return 1.0
end

function _levels(v)
    hist = zeros(Int, 256)
    @inbounds for x in v
        hist[clamp(round(Int, clamp(x, 0.0, 1.0) * 255), 0, 255) + 1] += 1
    end
    return hist
end

function _robust_normalize(v)
    hist = _levels(v)
    lo = _level_quantile(hist, length(v), 0.02)
    hi = _level_quantile(hist, length(v), 0.98)
    hi - lo <= 1e-12 && return _normalize(v)
    return clamp.((v .- lo) ./ (hi - lo), 0.0, 1.0)
end

function _window(v, level, width)
    width = max(width, 1 / 255)
    lo = level - width / 2
    return clamp.((v .- lo) ./ width, 0.0, 1.0)
end

_gamma(v, p) = clamp.(v, 0.0, 1.0) .^ (2.0^(4p - 2))
_invert(v) = 1.0 .- v

function _equalize(v)
    hist = _levels(v)
    cdf = cumsum(hist) ./ length(v)
    return [cdf[clamp(round(Int, clamp(x, 0.0, 1.0) * 255), 0, 255) + 1] for x in v]
end

_threshold_zero(v, t) = ifelse.(v .>= t, v, 0.0)

_radius(p) = 1 + round(Int, 2p)
_erode(v, p) = box_extremum!(similar(v), v, _radius(p), fmin)
_dilate(v, p) = box_extremum!(similar(v), v, _radius(p), fmax)
_open(v, p) = (r = _radius(p); box_extremum!(similar(v), box_extremum!(similar(v), v, r, fmin), r, fmax))
_close(v, p) = (r = _radius(p); box_extremum!(similar(v), box_extremum!(similar(v), v, r, fmax), r, fmin))
_morph_gradient(v, p) = _dilate(v, p) .- _erode(v, p)
_tophat(v, p) = v .- _open(v, p)
_bothat(v, p) = _close(v, p) .- v
_erode_cross(v) = cross_extremum!(similar(v), v, fmin)
_dilate_cross(v) = cross_extremum!(similar(v), v, fmax)

function _distance_inside(fg::AbstractArray{Bool,3})
    any(fg) || return zeros(size(fg))
    all(fg) && return ones(size(fg))
    background = map(!, fg)                                   # Array{Bool}, not a BitArray
    d = volume_distance_map!(Array{Float64,3}(undef, size(fg)), background)
    m = 0.0
    @inbounds for i in eachindex(d)
        d[i] = fg[i] ? sqrt(d[i]) : 0.0
        m = max(m, d[i])
    end
    return m > 0 ? d ./ m : d
end

function _proximity(fg::AbstractArray{Bool,3})
    any(fg) || return zeros(size(fg))
    scale = 1.0 / max(sqrt(sum(abs2, size(fg) .- 1)), 1.0)
    d = volume_distance_map!(Array{Float64,3}(undef, size(fg)), fg)
    return clamp.(1.0 .- sqrt.(d) .* scale, 0.0, 1.0)
end

# ---------------------------------------------------------------------------
# Binary kernels: Array{Bool,3} → Array{Bool,3}
# ---------------------------------------------------------------------------

_as_float(fg) = (v = scratch(:vb_float, Float64, size(fg)...); v .= fg; v)
_as_bool(v) = v .> 0.5

_b_erode(fg, p) = _as_bool(_erode(_as_float(fg), p))
_b_dilate(fg, p) = _as_bool(_dilate(_as_float(fg), p))
_b_open(fg, p) = _as_bool(_open(_as_float(fg), p))
_b_close(fg, p) = _as_bool(_close(_as_float(fg), p))
_b_morph_gradient(fg, p) = _b_dilate(fg, p) .& .!_b_erode(fg, p)
_b_erode_cross(fg) = _as_bool(_erode_cross(_as_float(fg)))
_b_dilate_cross(fg) = _as_bool(_dilate_cross(_as_float(fg)))

function _fill_holes(fg)
    holes = Array{Bool,3}(undef, size(fg))
    volume_holes!(holes, fg)
    return holes .| fg
end
_holes(fg) = (holes = Array{Bool,3}(undef, size(fg)); volume_holes!(holes, fg); holes)

function _keep_component(fg, choose)
    t = volume_table(fg, identity)
    t.n == 0 && return zeros(Bool, size(fg))
    id = choose(t)
    return t.labels .== id
end
_largest_component(fg) = _keep_component(fg, t -> argmax(t.area))
function _central_component(fg)
    centre = (size(fg) .+ 1) ./ 2
    return _keep_component(fg, t -> argmin([sum(abs2, centroid(t, i) .- centre) for i in 1:t.n]))
end

function _filter_components(fg, keep)
    t = volume_table(fg, identity)
    kept = [keep(t, i) for i in 1:t.n]
    out = Array{Bool,3}(undef, size(fg))
    @inbounds for i in eachindex(out)
        l = t.labels[i]
        out[i] = l != 0 && kept[l]
    end
    return out
end
_remove_small(fg, p) = _filter_components(fg, (t, i) -> t.area[i] >= p * length(fg))
_clear_border(fg) = _filter_components(fg, (t, i) -> !any(t.lo[i, k] == 1 || t.hi[i, k] == t.dims[k] for k in 1:3))

function _majority(fg)
    counts = _box_mean(_as_float(fg), 1)            # replicate border: edge voxels vote as interior
    return counts .> 0.5
end

function _bbox_fill(fg)
    t = volume_table(fg, identity)
    out = zeros(Bool, size(fg))
    for i in 1:t.n
        out[t.lo[i, 1]:t.hi[i, 1], t.lo[i, 2]:t.hi[i, 2], t.lo[i, 3]:t.hi[i, 3]] .= true
    end
    return out
end

function _otsu_mask(v)
    hist = _levels(v)
    n = length(v)
    total = sum((b - 1) / 255 * hist[b] for b in 1:256)
    best, best_b, weight, partial = -1.0, 1, 0, 0.0
    for b in 1:255
        weight += hist[b]
        partial += hist[b] * (b - 1) / 255
        (weight == 0 || weight == n) && continue
        w0 = weight / n
        between = w0 * (1 - w0) * (partial / weight - (total - partial) / (n - weight))^2
        between > best && ((best, best_b) = (between, b))
    end
    t = (best_b - 1) / 255
    return v .> t
end

function _top_fraction(v, p)
    hist = _levels(v)
    t = _level_quantile(hist, length(v), 1.0 - p)
    return v .>= t
end

# ---------------------------------------------------------------------------
# Geometry kernels on pixel arrays (shared by both bundles)
# ---------------------------------------------------------------------------

_flip(src, axis) = reverse(src; dims = axis)

"Quarter turn in the plane of axes `(a, b)`; identity when that plane is not square."
function _rot90(src, a, b)
    size(src, a) == size(src, b) || return copy(src)
    perm = collect(1:3)
    perm[a], perm[b] = b, a
    return reverse(permutedims(src, perm); dims = a)
end

function _shift(src::AbstractArray{P,3}, axis::Int, u::Float64) where {P}
    n = size(src, axis)
    k = round(Int, (u - 0.5) * n)
    out = similar(src)
    z = _zero(P)
    @inbounds for idx in CartesianIndices(src)
        source = Tuple(idx)
        j = source[axis] - k
        out[idx] = 1 <= j <= n ? src[Base.setindex(source, j, axis)...] : z
    end
    return out
end

"Bounding box of the foreground (or of its largest component), grown by `margin` of its size."
function _box(fg::AbstractArray{Bool,3}, largest::Bool, margin::Float64)
    t = volume_table(fg, identity)
    t.n == 0 && return nothing
    ids = largest ? (argmax(t.area):argmax(t.area)) : (1:t.n)
    lo = ntuple(k -> minimum(t.lo[i, k] for i in ids), 3)
    hi = ntuple(k -> maximum(t.hi[i, k] for i in ids), 3)
    dims = size(fg)
    grow = ntuple(k -> round(Int, margin * (hi[k] - lo[k] + 1)), 3)
    return ntuple(k -> max(lo[k] - grow[k], 1), 3), ntuple(k -> min(hi[k] + grow[k], dims[k]), 3)
end

function _crop(src::AbstractArray{P,3}, fg, largest::Bool, margin::Float64) where {P}
    box = _box(fg, largest, margin)
    box === nothing && return src
    if P <: IntensityPixel
        return to_pixels(P, resample_box(voxel_values(:crop_values, src), box...))
    end
    return resample_box_nearest(src, box...)
end

function _recenter(src::AbstractArray{P,3}, fg, largest::Bool) where {P}
    t = volume_table(fg, identity)
    t.n == 0 && return src
    target = largest ? centroid(t, argmax(t.area)) : _overall_centroid(t)
    h, w, d = size(src)
    dr = round(Int, target[1] - (h + 1) / 2)
    dc = round(Int, target[2] - (w + 1) / 2)
    ds = round(Int, target[3] - (d + 1) / 2)
    out = similar(src)
    z = _zero(P)
    @inbounds for s in 1:d, c in 1:w, r in 1:h
        rr, cc, ss = r + dr, c + dc, s + ds
        out[r, c, s] = (1 <= rr <= h && 1 <= cc <= w && 1 <= ss <= d) ? src[rr, cc, ss] : z
    end
    return out
end

function _overall_centroid(t)
    total = sum(t.area)
    return (sum(t.s1[:, 1]) / total, sum(t.s1[:, 2]) / total, sum(t.s1[:, 3]) / total)
end

# ---------------------------------------------------------------------------
# Factory builders
# ---------------------------------------------------------------------------

function _prelude(::Type{I}, operator::Symbol) where {I}
    IT = _get_image_type(I)
    _validate_factory_type(IT)
    return _get_image_pixel_type(I), _get_image_tuple_size(I), Symbol(operator, :_, Symbol(I))
end

_wrap(::Type{P}, result::AbstractArray{Float64,3}) where {P<:IntensityPixel} = to_pixels(P, result)
_wrap(::Type{P}, result::AbstractArray{Bool,3}) where {P<:BinaryPixel} = to_pixels(P, result)
_wrap(::Type{P}, result::AbstractArray{P,3}) where {P} = result

"Read the source volume as the kernel expects it."
_read(src::SizedImage{S,<:IntensityPixel}) where {S} = voxel_values(:vol_in, src.img)
_read(src::SizedImage{S,<:BinaryPixel}) where {S} = voxel_foreground(:vol_in_fg, src.img, IsSet())

"`kernel(read(src), p)`: `(vol)` with the default, `(vol, p)`."
function _unary_factory(::Type{I}, operator::Symbol, kernel::K, default::Float64) where {I,K}
    PT, S, name = _prelude(I, operator)
    fn = @eval function $name(src::CONCT, p::Real, args::Vararg{Any}) where {CONCT<:$I}
        return SImageND(_wrap($PT, $kernel(_read(src), _unit(p, $default))), $S)
    end
    @eval function $name(src::CONCT, args::Vararg{Any}) where {CONCT<:$I}
        return SImageND(_wrap($PT, $kernel(_read(src), $default)), $S)
    end
    return fn
end

"`kernel(read(src), p1, p2)`: `(vol)`, `(vol, p1)`, `(vol, p1, p2)`."
function _binary_param_factory(::Type{I}, operator::Symbol, kernel::K, d1::Float64, d2::Float64) where {I,K}
    PT, S, name = _prelude(I, operator)
    fn = @eval function $name(src::CONCT, p1::Real, p2::Real, args::Vararg{Any}) where {CONCT<:$I}
        return SImageND(_wrap($PT, $kernel(_read(src), _unit(p1, $d1), _unit(p2, $d2))), $S)
    end
    @eval function $name(src::CONCT, p1::Real, args::Vararg{Any}) where {CONCT<:$I}
        return SImageND(_wrap($PT, $kernel(_read(src), _unit(p1, $d1), $d2)), $S)
    end
    @eval function $name(src::CONCT, args::Vararg{Any}) where {CONCT<:$I}
        return SImageND(_wrap($PT, $kernel(_read(src), $d1, $d2)), $S)
    end
    return fn
end

"`kernel(values(src), values(other))` for two same-type volumes."
function _pair_factory(::Type{I}, operator::Symbol, kernel::K) where {I,K}
    PT, S, name = _prelude(I, operator)
    return @eval function $name(src::CONCT, other::CONCT2, args::Vararg{Any}) where {CONCT<:$I,CONCT2<:$I}
        a = copy(_read(src))
        return SImageND(_wrap($PT, $kernel(a, _read(other))), $S)
    end
end

"`kernel(read(src), fg)` with a mask: `(vol, mask[, p])`; masks binary or intensity at 0.5."
function _masked_factory(::Type{I}, operator::Symbol, kernel::K, default::Float64) where {I,K}
    PT, S, name = _prelude(I, operator)
    fn = @eval function $name(src::CONCT, mask::M, p::Real, args::Vararg{Any}) where {CONCT<:$I,BT,M<:SizedImage{$S,BinaryPixel{BT}}}
        return SImageND(_wrap($PT, $kernel(src, voxel_foreground(:vol_mask, mask.img, IsSet()), _unit(p, $default))), $S)
    end
    @eval function $name(src::CONCT, mask::M, args::Vararg{Any}) where {CONCT<:$I,BT,M<:SizedImage{$S,BinaryPixel{BT}}}
        return SImageND(_wrap($PT, $kernel(src, voxel_foreground(:vol_mask, mask.img, IsSet()), $default)), $S)
    end
    @eval function $name(src::CONCT, mask::M, p::Real, args::Vararg{Any}) where {CONCT<:$I,ST,M<:SizedImage{$S,IntensityPixel{ST}}}
        return SImageND(_wrap($PT, $kernel(src, voxel_foreground(:vol_mask, mask.img, AtLeast(0.5)), _unit(p, $default))), $S)
    end
    @eval function $name(src::CONCT, mask::M, args::Vararg{Any}) where {CONCT<:$I,ST,M<:SizedImage{$S,IntensityPixel{ST}}}
        return SImageND(_wrap($PT, $kernel(src, voxel_foreground(:vol_mask, mask.img, AtLeast(0.5)), $default)), $S)
    end
    return fn
end

"`kernel(fg, p)` from a mask: `(mask[, p])`, `(intensity)` at 0.5, `(intensity, t)`."
function _from_mask_factory(::Type{I}, operator::Symbol, kernel::K, default::Float64) where {I,K}
    PT, S, name = _prelude(I, operator)
    fn = @eval function $name(mask::M, p::Real, args::Vararg{Any}) where {BT,M<:SizedImage{$S,BinaryPixel{BT}}}
        return SImageND(_wrap($PT, $kernel(copy(voxel_foreground(:vol_mask, mask.img, IsSet())), _unit(p, $default))), $S)
    end
    @eval function $name(mask::M, args::Vararg{Any}) where {BT,M<:SizedImage{$S,BinaryPixel{BT}}}
        return SImageND(_wrap($PT, $kernel(copy(voxel_foreground(:vol_mask, mask.img, IsSet())), $default)), $S)
    end
    @eval function $name(vol::M, t::Real, args::Vararg{Any}) where {ST,M<:SizedImage{$S,IntensityPixel{ST}}}
        return SImageND(_wrap($PT, $kernel(copy(voxel_foreground(:vol_mask, vol.img, AtLeast(_unit(t)))), $default)), $S)
    end
    @eval function $name(vol::M, args::Vararg{Any}) where {ST,M<:SizedImage{$S,IntensityPixel{ST}}}
        return SImageND(_wrap($PT, $kernel(copy(voxel_foreground(:vol_mask, vol.img, AtLeast(0.5))), $default)), $S)
    end
    return fn
end

"Geometry on the voxels themselves: `kernel(src.img, u)`, `(vol)` or `(vol, u)`."
function _geom_factory(::Type{I}, operator::Symbol, kernel::K, default::Float64) where {I,K}
    PT, S, name = _prelude(I, operator)
    fn = @eval function $name(src::CONCT, u::Real, args::Vararg{Any}) where {CONCT<:$I}
        return SImageND($kernel(src.img, _unit(u, $default)), $S)
    end
    @eval function $name(src::CONCT, args::Vararg{Any}) where {CONCT<:$I}
        return SImageND($kernel(src.img, $default), $S)
    end
    return fn
end

"""
2D → 3D along `axis`: `(img2d)` extrudes it; with `combine`, `(vol, img2d)`
applies it to every slice. The 2D size must match the volume's other axes.
"""
function _from2d_factory(::Type{I}, operator::Symbol, axis::Int, mode::Symbol) where {I}
    PT, S, name = _prelude(I, operator)
    dims = Tuple(S.parameters)
    keep = Tuple(k for k in 1:3 if k != axis)
    A, B = dims[keep[1]], dims[keep[2]]
    if mode === :extrude
        return @eval function $name(img::M, args::Vararg{Any}) where {P2,M<:SizedImage{Tuple{$A,$B},P2}}
            plane = img.img
            return SImageND(_extrude($PT, plane, $axis, $dims), $S)
        end
    end
    return @eval function $name(src::CONCT, mask::M, args::Vararg{Any}) where {CONCT<:$I,P2,M<:SizedImage{Tuple{$A,$B},P2}}
        return SImageND(_apply_plane(src.img, mask.img, $axis), $S)
    end
end

@inline _plane_index(idx, axis) = axis == 1 ? (idx[2], idx[3]) : axis == 2 ? (idx[1], idx[3]) : (idx[1], idx[2])

function _extrude(::Type{P}, plane::AbstractMatrix, axis::Int, dims) where {P}
    out = Array{P,3}(undef, dims)
    @inbounds for idx in CartesianIndices(out)
        out[idx] = _convert_pixel(P, plane[_plane_index(Tuple(idx), axis)...])
    end
    return out
end

_convert_pixel(::Type{IntensityPixel{T}}, p::IntensityPixel) where {T} = IntensityPixel{T}(convert(T, clamp(Float64(p), 0.0, 1.0)))
_convert_pixel(::Type{IntensityPixel{T}}, p::BinaryPixel) where {T} = IntensityPixel{T}(p.pixel ? one(T) : zero(T))
_convert_pixel(::Type{BinaryPixel{T}}, p::BinaryPixel) where {T} = BinaryPixel{T}(p.pixel)
_convert_pixel(::Type{BinaryPixel{T}}, p::IntensityPixel) where {T} = BinaryPixel{T}(Float64(p) >= 0.5)

@inline _plane_in(p::BinaryPixel) = p.pixel == true
@inline _plane_in(p) = Float64(p) >= 0.5

function _apply_plane(src::AbstractArray{P,3}, plane::AbstractMatrix, axis::Int) where {P}
    out = similar(src)
    z = _zero(P)
    @inbounds for idx in CartesianIndices(src)
        out[idx] = _plane_in(plane[_plane_index(Tuple(idx), axis)...]) ? src[idx] : z
    end
    return out
end

# ---------------------------------------------------------------------------
# Registration
# ---------------------------------------------------------------------------

_bundle(kind::Symbol) = kind === :intensity ? bundle_image3DIntensity_volume_factory : bundle_image3DBinary_volume_factory

function _define!(operator::Symbol, kinds, builder, description::String)
    # Operators existing in both bundles with different kernels get one factory
    # per kind; shared geometry operators have a single factory.
    factory_name = length(kinds) == 1 ? Symbol(operator, :_, kinds[1], :_image3D_factory) :
                   Symbol(operator, :_image3D_factory)
    @eval function $factory_name(output_type::Type{I}) where {S1,S2,S3,P,I<:SizedImage3D{S1,S2,S3,P}}
        return $builder(output_type)
    end
    doc = """
        $(factory_name)(::Type{I})

    Specialises `$operator`. $description
    """
    @eval @doc $doc $factory_name
    for kind in kinds
        append_method!(_bundle(kind), getfield(@__MODULE__, factory_name), operator; description = description)
    end
end

_unary(op, kernel, default) = I -> _unary_factory(I, op, kernel, default)

# Intensity filters and transforms.
for (op, kernel, default, description) in (
        (:vol_gaussian, (v, p) -> _gaussian(v, 0.3 + 2.7p), 0.26, "Gaussian blur, σ = 0.3 + 2.7p voxels (default 1)."),
        (:vol_gaussian_s05, (v, p) -> _gaussian(v, 0.5), 0.0, "Gaussian blur, σ = 0.5 voxel."),
        (:vol_gaussian_s1, (v, p) -> _gaussian(v, 1.0), 0.0, "Gaussian blur, σ = 1 voxel."),
        (:vol_gaussian_s2, (v, p) -> _gaussian(v, 2.0), 0.0, "Gaussian blur, σ = 2 voxels."),
        (:vol_mean_3, (v, p) -> _box_mean(v, 1), 0.0, "Mean over a 3³ cube."),
        (:vol_mean_5, (v, p) -> _box_mean(v, 2), 0.0, "Mean over a 5³ cube."),
        (:vol_gradient, (v, p) -> _gradient(v), 0.0, "Gradient magnitude (central differences)."),
        (:vol_laplacian, (v, p) -> _laplacian(v), 0.0, "Absolute 6-neighbour Laplacian."),
        (:vol_dog, _dog, 0.33, "Difference of Gaussians (σ and 1.6σ, σ = 0.5 + 1.5p), centred on 0.5."),
        (:vol_local_std, (v, p) -> _local_std(v), 0.0, "Twice the standard deviation over a 3³ cube."),
        (:vol_unsharp, _unsharp, 0.5, "Unsharp masking, amount 2p (default 1)."),
        (:vol_normalize, (v, p) -> _normalize(v), 0.0, "Min–max normalisation to [0, 1]."),
        (:vol_robust_normalize, (v, p) -> _robust_normalize(v), 0.0, "Normalisation between the 2nd and 98th percentiles."),
        (:vol_gamma, _gamma, 0.5, "Gamma correction, exponent 2^(4p − 2) (default 1)."),
        (:vol_invert, (v, p) -> _invert(v), 0.0, "1 − v."),
        (:vol_equalize, (v, p) -> _equalize(v), 0.0, "Histogram equalisation (256 levels)."),
        (:vol_threshold_zero, _threshold_zero, 0.5, "Keep voxels at or above t (default 0.5), zero the rest."),
        (:vol_erode, _erode, 0.0, "Grey erosion with a (2r+1)³ cube, r = 1 + round(2p)."),
        (:vol_dilate, _dilate, 0.0, "Grey dilation with a (2r+1)³ cube, r = 1 + round(2p)."),
        (:vol_open, _open, 0.0, "Grey opening with a (2r+1)³ cube."),
        (:vol_close, _close, 0.0, "Grey closing with a (2r+1)³ cube."),
        (:vol_morph_gradient, _morph_gradient, 0.0, "Dilation minus erosion."),
        (:vol_tophat, _tophat, 0.0, "Volume minus its opening: small bright structures."),
        (:vol_bothat, _bothat, 0.0, "Closing minus volume: small dark structures."),
        (:vol_erode_cross, (v, p) -> _erode_cross(v), 0.0, "Grey erosion with the 6-neighbour cross."),
        (:vol_dilate_cross, (v, p) -> _dilate_cross(v), 0.0, "Grey dilation with the 6-neighbour cross."),
    )
    _define!(op, (:intensity,), _unary(op, kernel, default), description)
end
_define!(:vol_window, (:intensity,),
    I -> _binary_param_factory(I, :vol_window, (v, level, width) -> _window(v, level, width), 0.5, 0.5),
    "CT windowing: maps [level − width/2, level + width/2] to [0, 1] (defaults 0.5, 0.5).")

for (op, kernel, description) in (
        (:vol_add, (a, b) -> a .+ b, "Sum of two volumes."),
        (:vol_sub, (a, b) -> a .- b, "Difference of two volumes (clamped at 0)."),
        (:vol_absdiff, (a, b) -> abs.(a .- b), "Absolute difference."),
        (:vol_mult, (a, b) -> a .* b, "Voxel-wise product."),
        (:vol_min, (a, b) -> min.(a, b), "Voxel-wise minimum."),
        (:vol_max, (a, b) -> max.(a, b), "Voxel-wise maximum."),
        (:vol_average, (a, b) -> (a .+ b) ./ 2, "Voxel-wise mean."),
    )
    _define!(op, (:intensity,), I -> _pair_factory(I, op, kernel), description)
end

_keep(src, fg, p) = (v = copy(voxel_values(:vol_in, src.img)); v[.!fg] .= 0.0; v)
_zero_inside(src, fg, p) = (v = copy(voxel_values(:vol_in, src.img)); v[fg] .= 0.0; v)
_define!(:vol_mask_keep, (:intensity,), I -> _masked_factory(I, :vol_mask_keep, _keep, 0.0),
    "Keeps the voxels inside the mask, zeroes the rest.")
_define!(:vol_mask_zero, (:intensity,), I -> _masked_factory(I, :vol_mask_zero, _zero_inside, 0.0),
    "Zeroes the voxels inside the mask.")
_define!(:vol_distance_inside, (:intensity,), I -> _from_mask_factory(I, :vol_distance_inside, (fg, p) -> _distance_inside(fg), 0.0),
    "Distance from each mask voxel to the background, normalised by its maximum.")
_define!(:vol_proximity, (:intensity,), I -> _from_mask_factory(I, :vol_proximity, (fg, p) -> _proximity(fg), 0.0),
    "1 on the mask, decreasing with the distance to it (over the volume diagonal).")

# Binarisation (intensity in, binary out).
_define!(:vol_threshold, (:binary,), I -> _from_mask_factory(I, :vol_threshold, (fg, p) -> fg, 0.5),
    "Voxels at or above a threshold (default 0.5); a binary input is returned as is.")
_bin_from_values(op, kernel, default) = I -> begin
    PT, S, name = _prelude(I, op)
    fn = @eval function $name(vol::M, p::Real, args::Vararg{Any}) where {ST,M<:SizedImage{$S,IntensityPixel{ST}}}
        return SImageND(to_pixels($PT, $kernel(voxel_values(:vol_in, vol.img), _unit(p, $default))), $S)
    end
    @eval function $name(vol::M, args::Vararg{Any}) where {ST,M<:SizedImage{$S,IntensityPixel{ST}}}
        return SImageND(to_pixels($PT, $kernel(voxel_values(:vol_in, vol.img), $default)), $S)
    end
    fn
end
_define!(:vol_otsu, (:binary,), _bin_from_values(:vol_otsu, (v, p) -> _otsu_mask(v), 0.0),
    "Otsu threshold of an intensity volume.")
_define!(:vol_top_fraction, (:binary,), _bin_from_values(:vol_top_fraction, _top_fraction, 0.1),
    "The brightest fraction p of the voxels (default 0.1).")

# Binary morphology and clean-up.
for (op, kernel, default, description) in (
        (:vol_erode, _b_erode, 0.0, "Binary erosion with a (2r+1)³ cube, r = 1 + round(2p)."),
        (:vol_dilate, _b_dilate, 0.0, "Binary dilation with a (2r+1)³ cube."),
        (:vol_open, _b_open, 0.0, "Binary opening with a (2r+1)³ cube."),
        (:vol_close, _b_close, 0.0, "Binary closing with a (2r+1)³ cube."),
        (:vol_morph_gradient, _b_morph_gradient, 0.0, "Dilation minus erosion: a shell around the boundary."),
        (:vol_erode_cross, (fg, p) -> _b_erode_cross(fg), 0.0, "Binary erosion with the 6-neighbour cross."),
        (:vol_dilate_cross, (fg, p) -> _b_dilate_cross(fg), 0.0, "Binary dilation with the 6-neighbour cross."),
        (:vol_fill_holes, (fg, p) -> _fill_holes(fg), 0.0, "Fills enclosed cavities (6-connected background)."),
        (:vol_holes, (fg, p) -> _holes(fg), 0.0, "The enclosed cavities alone."),
        (:vol_largest_component, (fg, p) -> _largest_component(fg), 0.0, "Keeps the largest 26-connected component."),
        (:vol_central_component, (fg, p) -> _central_component(fg), 0.0, "Keeps the component closest to the centre."),
        (:vol_remove_small, _remove_small, 0.001, "Removes components smaller than p of the voxels (default 0.001)."),
        (:vol_clear_border, (fg, p) -> _clear_border(fg), 0.0, "Removes components touching the border."),
        (:vol_majority, (fg, p) -> _majority(fg), 0.0, "3³ majority vote."),
        (:vol_bbox_fill, (fg, p) -> _bbox_fill(fg), 0.0, "Replaces each component by its filled bounding box."),
        (:vol_not, (fg, p) -> .!fg, 0.0, "Logical not."),
    )
    _define!(op, (:binary,), _unary(op, kernel, default), description)
end
for (op, kernel, description) in (
        (:vol_and, (a, b) -> a .& b, "Logical and."),
        (:vol_or, (a, b) -> a .| b, "Logical or."),
        (:vol_xor, (a, b) -> a .⊻ b, "Logical exclusive or."),
    )
    _define!(op, (:binary,), I -> _pair_factory(I, op, kernel), description)
end

# Geometry, both bundles.
for (op, kernel, default, description) in (
        (:vol_flip_y, (src, u) -> _flip(src, 1), 0.0, "Mirrors along y (rows)."),
        (:vol_flip_x, (src, u) -> _flip(src, 2), 0.0, "Mirrors along x (columns)."),
        (:vol_flip_z, (src, u) -> _flip(src, 3), 0.0, "Mirrors along z (slices)."),
        (:vol_rot90_xy, (src, u) -> _rot90(src, 1, 2), 0.0, "Quarter turn in the x–y plane (identity if not square)."),
        (:vol_rot90_xz, (src, u) -> _rot90(src, 2, 3), 0.0, "Quarter turn in the x–z plane (identity if not square)."),
        (:vol_rot90_yz, (src, u) -> _rot90(src, 1, 3), 0.0, "Quarter turn in the y–z plane (identity if not square)."),
        (:vol_shift_y, (src, u) -> _shift(src, 1, u), 0.5, "Shifts along y by (u − 0.5) of the size, zero fill."),
        (:vol_shift_x, (src, u) -> _shift(src, 2, u), 0.5, "Shifts along x by (u − 0.5) of the size, zero fill."),
        (:vol_shift_z, (src, u) -> _shift(src, 3, u), 0.5, "Shifts along z by (u − 0.5) of the size, zero fill."),
    )
    _define!(op, (:intensity, :binary), I -> _geom_factory(I, op, kernel, default), description)
end
for (op, largest, description) in (
        (:vol_crop_bbox, false, "Crops the bounding box of the mask (grown by margin, default 0.1) and resizes it back."),
        (:vol_crop_bbox_largest, true, "Crops the bounding box of the mask's largest component and resizes it back."),
    )
    _define!(op, (:intensity, :binary), I -> _masked_factory(I, op, (src, fg, m) -> _crop(src.img, fg, largest, m), 0.1), description)
end
for (op, largest, description) in (
        (:vol_recenter, false, "Translates the mask's centroid to the centre of the volume."),
        (:vol_recenter_largest, true, "Translates the largest component's centroid to the centre."),
    )
    _define!(op, (:intensity, :binary), I -> _masked_factory(I, op, (src, fg, m) -> _recenter(src.img, fg, largest), 0.0), description)
end

# 2D → 3D.
for (axis, letter) in ((1, :y), (2, :x), (3, :z))
    op = Symbol(:vol_extrude_, letter)
    _define!(op, (:intensity, :binary), I -> _from2d_factory(I, op, axis, :extrude),
        "Repeats a 2D image along $letter to fill the volume.")
    op = Symbol(:vol_mask2d_, letter)
    _define!(op, (:intensity, :binary), I -> _from2d_factory(I, op, axis, :apply),
        "Applies a 2D mask (binary, or intensity at 0.5) to every slice along $letter.")
end

end
