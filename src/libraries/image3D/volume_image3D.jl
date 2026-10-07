"""
Volume → volume operators for 3D grayscale images (CT, MRI, microscopy):
filtering, intensity transforms, morphology, binarisation, mask clean-up,
distance maps and geometry, plus 2D → 3D extrusion.

# Bundles

- bundle_image3DIntensity_volume_factory
- bundle_image3DBinary_volume_factory

The exhaustive operator list is on the Bundle Catalogue page.

# How this file is organised

Each operator is a *kernel* (plain Julia on arrays) wrapped by a *factory*.

Kernels come in three kinds:

| Kind | Input | Output |
|:--|:--|:--|
| intensity kernels | `Array{Float64,3}` of voxel values (from `voxel_values`) | `Array{Float64,3}` |
| binary kernels | `Array{Bool,3}` foreground (from `voxel_foreground`) | `Array{Bool,3}` |
| geometry kernels | the voxel array itself (`src.img`) | an array of the same pixels |

A factory is a function of the output volume type `I` (e.g.
`SImage3D{28,28,28,IntensityPixel{N0f8}}`): it defines the operator's methods
for that type and returns the function. Each method unpacks its inputs into
what the kernel expects (`_kernel_input`), sanitises scalar arguments with
`clamp_unit` (clamped to `[0, 1]`, `NaN` → default), calls the kernel and
converts the result back into pixels (`_as_output_pixels`). The factory
builders below each document the exact methods they create. Every method also
accepts and ignores extra trailing arguments (`args...`), which is how MAGE
passes unused inputs.
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
using ..image2D_object_common: scratch, clamp_unit, IsSet, AtLeast
using ..image2D_zoom: zero_pixel
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
# Intensity kernels: voxel values (Array{Float64,3}) → Array{Float64,3}
# ---------------------------------------------------------------------------

"Gaussian blur with standard deviation `sigma` (voxels), separable, edges replicated."
_gaussian(v, sigma) = (k = gaussian_kernel(sigma); separable_convolve!(similar(v), v, k[1], k[2]))

"Mean over the `(2r+1)³` cube around each voxel, edges replicated."
_box_mean(v, r) = separable_convolve!(similar(v), v, fill(1.0 / (2r + 1), 2r + 1), r)

"Gradient magnitude from central differences along y, x and z (one-sided at the edges)."
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

"Absolute 6-neighbour Laplacian: |Σ neighbours − 6 · voxel|, edges replicated."
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

"Difference of Gaussians `G(σ) − G(1.6σ)` with `σ = 0.5 + 1.5p`, doubled and centred on `0.5`."
function _dog(v, p)
    sigma = 0.5 + 1.5p
    fine = _gaussian(v, sigma)
    coarse = _gaussian(v, 1.6sigma)
    @inbounds @simd for i in eachindex(fine)
        fine[i] = 0.5 + 2.0 * (fine[i] - coarse[i])
    end
    return fine
end

"Twice the standard deviation over the 3³ cube around each voxel (local texture)."
function _local_std(v)
    mean = _box_mean(v, 1)
    squares = similar(v)
    @inbounds @simd for i in eachindex(v)
        squares[i] = v[i]^2
    end
    mean_of_squares = _box_mean(squares, 1)
    @inbounds @simd for i in eachindex(mean)
        mean[i] = 2.0 * sqrt(max(mean_of_squares[i] - mean[i]^2, 0.0))
    end
    return mean
end

"Unsharp masking: `v + 2p · (v − G₁(v))`, sharpening edges (`p = 0.5` doubles the detail)."
function _unsharp(v, p)
    blurred = _gaussian(v, 1.0)
    amount = 2.0 * p
    out = similar(v)
    @inbounds @simd for i in eachindex(v)
        out[i] = v[i] + amount * (v[i] - blurred[i])
    end
    return out
end

"Min–max normalisation to `[0, 1]`; a constant volume becomes all zeros."
function _normalize(v)
    lo, hi = extrema(v)
    hi - lo <= 1e-12 && return zeros(size(v))
    return (v .- lo) ./ (hi - lo)
end

"256-level histogram of `clamp(v, 0, 1)` (level `k` ↔ value `(k − 1)/255`)."
function _levels(v)
    hist = zeros(Int, 256)
    @inbounds for x in v
        hist[clamp(round(Int, clamp(x, 0.0, 1.0) * 255), 0, 255) + 1] += 1
    end
    return hist
end

"Smallest level value whose cumulative count reaches the fraction `p` of `n` voxels."
function _level_quantile(hist::Vector{Int}, n::Int, p::Float64)
    target = max(1, ceil(Int, p * n))
    running = 0
    @inbounds for b in 1:256
        running += hist[b]
        running >= target && return (b - 1) / 255
    end
    return 1.0
end

"Normalisation between the 2nd and 98th percentiles, clamped to `[0, 1]`: robust to a few extreme voxels."
function _robust_normalize(v)
    hist = _levels(v)
    lo = _level_quantile(hist, length(v), 0.02)
    hi = _level_quantile(hist, length(v), 0.98)
    hi - lo <= 1e-12 && return _normalize(v)
    return clamp.((v .- lo) ./ (hi - lo), 0.0, 1.0)
end

"CT windowing: map `[level − width/2, level + width/2]` linearly to `[0, 1]`, clamping outside."
function _window(v, level, width)
    width = max(width, 1 / 255)
    lo = level - width / 2
    return clamp.((v .- lo) ./ width, 0.0, 1.0)
end

"Gamma correction with exponent `2^(4p − 2)` (from 0.25 to 4; `p = 0.5` is the identity)."
_gamma(v, p) = clamp.(v, 0.0, 1.0) .^ (2.0^(4p - 2))

"`1 − v`."
_invert(v) = 1.0 .- v

"Histogram equalisation: each voxel becomes the fraction of voxels at or below its level."
function _equalize(v)
    hist = _levels(v)
    cdf = cumsum(hist) ./ length(v)
    return [cdf[clamp(round(Int, clamp(x, 0.0, 1.0) * 255), 0, 255) + 1] for x in v]
end

"Keep voxels at or above `t`, set the others to zero."
_threshold_zero(v, t) = ifelse.(v .>= t, v, 0.0)

"Structuring-element radius for morphology parameter `p`: 1, 2 or 3 voxels."
_radius(p) = 1 + round(Int, 2p)

"Grey erosion: minimum over the `(2r+1)³` cube."
_erode(v, p) = box_extremum!(similar(v), v, _radius(p), fmin)
"Grey dilation: maximum over the `(2r+1)³` cube."
_dilate(v, p) = box_extremum!(similar(v), v, _radius(p), fmax)
"Grey opening: erosion then dilation (removes small bright structures)."
_open(v, p) = (r = _radius(p); box_extremum!(similar(v), box_extremum!(similar(v), v, r, fmin), r, fmax))
"Grey closing: dilation then erosion (removes small dark structures)."
_close(v, p) = (r = _radius(p); box_extremum!(similar(v), box_extremum!(similar(v), v, r, fmax), r, fmin))
"Dilation minus erosion: large where intensity changes."
_morph_gradient(v, p) = _dilate(v, p) .- _erode(v, p)
"White top-hat: the small bright structures removed by the opening."
_tophat(v, p) = v .- _open(v, p)
"Black top-hat: the small dark structures removed by the closing."
_bothat(v, p) = _close(v, p) .- v
"Grey erosion with the 6-neighbour cross."
_erode_cross(v) = cross_extremum!(similar(v), v, fmin)
"Grey dilation with the 6-neighbour cross."
_dilate_cross(v) = cross_extremum!(similar(v), v, fmax)

"Distance from each foreground voxel to the background, divided by the largest such distance (`0` outside)."
function _distance_inside(fg::AbstractArray{Bool,3})
    any(fg) || return zeros(size(fg))
    all(fg) && return ones(size(fg))
    background = map(!, fg)                                   # Array{Bool}: faster to read than a BitArray
    d = volume_distance_map!(Array{Float64,3}(undef, size(fg)), background)
    largest = 0.0
    @inbounds for i in eachindex(d)
        d[i] = fg[i] ? sqrt(d[i]) : 0.0
        largest = max(largest, d[i])
    end
    return largest > 0 ? d ./ largest : d
end

"`1 − distance to the foreground / volume diagonal`: `1` on the mask, fading with distance."
function _proximity(fg::AbstractArray{Bool,3})
    any(fg) || return zeros(size(fg))
    scale = 1.0 / max(sqrt(sum(abs2, size(fg) .- 1)), 1.0)
    d = volume_distance_map!(Array{Float64,3}(undef, size(fg)), fg)
    return clamp.(1.0 .- sqrt.(d) .* scale, 0.0, 1.0)
end

# ---------------------------------------------------------------------------
# Binary kernels: foreground (Array{Bool,3}) → Array{Bool,3}
# ---------------------------------------------------------------------------

"A mask as 0/1 values (scratch), so binary morphology can reuse the grey filters."
_as_float(fg) = (v = scratch(:vb_float, Float64, size(fg)...); v .= fg; v)
"Values back to a mask (`> 0.5`)."
_as_bool(v) = v .> 0.5

"Binary erosion with a `(2r+1)³` cube."
_binary_erode(fg, p) = _as_bool(_erode(_as_float(fg), p))
"Binary dilation with a `(2r+1)³` cube."
_binary_dilate(fg, p) = _as_bool(_dilate(_as_float(fg), p))
"Binary opening with a `(2r+1)³` cube."
_binary_open(fg, p) = _as_bool(_open(_as_float(fg), p))
"Binary closing with a `(2r+1)³` cube."
_binary_close(fg, p) = _as_bool(_close(_as_float(fg), p))
"Dilation minus erosion: a shell around the object boundaries."
_binary_morph_gradient(fg, p) = _binary_dilate(fg, p) .& .!_binary_erode(fg, p)
"Binary erosion with the 6-neighbour cross."
_binary_erode_cross(fg) = _as_bool(_erode_cross(_as_float(fg)))
"Binary dilation with the 6-neighbour cross."
_binary_dilate_cross(fg) = _as_bool(_dilate_cross(_as_float(fg)))

"The mask with its enclosed cavities filled."
function _fill_holes(fg)
    holes = Array{Bool,3}(undef, size(fg))
    volume_holes!(holes, fg)
    return holes .| fg
end

"The enclosed cavities of the mask alone."
_holes(fg) = (holes = Array{Bool,3}(undef, size(fg)); volume_holes!(holes, fg); holes)

"Keep only the component `choose(table)` of the 26-connected components."
function _keep_component(fg, choose)
    t = volume_table(fg, identity)
    t.n == 0 && return zeros(Bool, size(fg))
    id = choose(t)
    return t.labels .== id
end

"Keep the largest component."
_largest_component(fg) = _keep_component(fg, t -> argmax(t.area))

"Keep the component whose centroid is closest to the volume centre."
function _central_component(fg)
    centre = (size(fg) .+ 1) ./ 2
    return _keep_component(fg, t -> argmin([sum(abs2, centroid(t, i) .- centre) for i in 1:t.n]))
end

"Keep the components for which `keep(table, id)` holds."
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

"Remove components smaller than the fraction `p` of all voxels."
_remove_small(fg, p) = _filter_components(fg, (t, i) -> t.area[i] >= p * length(fg))

"Remove components whose bounding box touches the volume border."
_clear_border(fg) = _filter_components(fg, (t, i) -> !any(t.lo[i, k] == 1 || t.hi[i, k] == t.dims[k] for k in 1:3))

"3³ majority vote: a voxel is set when most of its cube is (edges replicated)."
function _majority(fg)
    share = _box_mean(_as_float(fg), 1)
    return share .> 0.5
end

"Replace each component by its filled bounding box."
function _bbox_fill(fg)
    t = volume_table(fg, identity)
    out = zeros(Bool, size(fg))
    for i in 1:t.n
        out[t.lo[i, 1]:t.hi[i, 1], t.lo[i, 2]:t.hi[i, 2], t.lo[i, 3]:t.hi[i, 3]] .= true
    end
    return out
end

"Otsu's threshold on the 256-level histogram: voxels above the level that best separates two classes."
function _otsu_mask(v)
    hist = _levels(v)
    n = length(v)
    total = sum((b - 1) / 255 * hist[b] for b in 1:256)
    best_between, best_level, weight, partial = -1.0, 1, 0, 0.0
    for b in 1:255
        weight += hist[b]                          # voxels at levels ≤ b
        partial += hist[b] * (b - 1) / 255         # their intensity sum
        (weight == 0 || weight == n) && continue
        w0 = weight / n
        between = w0 * (1 - w0) * (partial / weight - (total - partial) / (n - weight))^2
        between > best_between && ((best_between, best_level) = (between, b))
    end
    threshold = (best_level - 1) / 255
    return v .> threshold
end

"The brightest fraction `p` of the voxels (ties at the cut-off level are kept)."
function _top_fraction(v, p)
    hist = _levels(v)
    threshold = _level_quantile(hist, length(v), 1.0 - p)
    return v .>= threshold
end

# ---------------------------------------------------------------------------
# Geometry kernels on the voxel arrays (shared by both bundles)
# ---------------------------------------------------------------------------

"Mirror along `axis`."
_flip(src, axis) = reverse(src; dims = axis)

"Quarter turn in the plane of axes `(a, b)`; returns an unchanged copy when that plane is not square."
function _rot90(src, a, b)
    size(src, a) == size(src, b) || return copy(src)
    perm = collect(1:3)
    perm[a], perm[b] = b, a
    return reverse(permutedims(src, perm); dims = a)
end

"Shift along `axis` by `round((u − 0.5) · size)` voxels; uncovered voxels are zero."
function _shift(src::AbstractArray{P,3}, axis::Int, u::Float64) where {P}
    n = size(src, axis)
    k = round(Int, (u - 0.5) * n)
    out = similar(src)
    zero = zero_pixel(P)
    @inbounds for idx in CartesianIndices(src)
        source = Tuple(idx)
        j = source[axis] - k
        out[idx] = 1 <= j <= n ? src[Base.setindex(source, j, axis)...] : zero
    end
    return out
end

"""
Bounding box `(lo, hi)` of the foreground (or of its largest component when
`largest`), grown by `margin` of its size on each side and clipped; `nothing`
for an empty mask.
"""
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

"Crop the box of the mask and resize it back to full size (trilinear for intensity, nearest otherwise); unchanged when the mask is empty."
function _crop(src::AbstractArray{P,3}, fg, largest::Bool, margin::Float64) where {P}
    box = _box(fg, largest, margin)
    box === nothing && return src
    if P <: IntensityPixel
        return to_pixels(P, resample_box(voxel_values(:crop_values, src), box...))
    end
    return resample_box_nearest(src, box...)
end

"Translate so the mask's centroid (or its largest component's) lands on the volume centre; uncovered voxels are zero."
function _recenter(src::AbstractArray{P,3}, fg, largest::Bool) where {P}
    t = volume_table(fg, identity)
    t.n == 0 && return src
    target = largest ? centroid(t, argmax(t.area)) : _overall_centroid(t)
    h, w, d = size(src)
    shift_r = round(Int, target[1] - (h + 1) / 2)
    shift_c = round(Int, target[2] - (w + 1) / 2)
    shift_s = round(Int, target[3] - (d + 1) / 2)
    out = similar(src)
    zero = zero_pixel(P)
    @inbounds for s in 1:d, c in 1:w, r in 1:h
        rr, cc, ss = r + shift_r, c + shift_c, s + shift_s
        out[r, c, s] = (1 <= rr <= h && 1 <= cc <= w && 1 <= ss <= d) ? src[rr, cc, ss] : zero
    end
    return out
end

"Centroid `(y, x, z)` of all components together."
function _overall_centroid(t)
    total = sum(t.area)
    return (sum(t.s1[:, 1]) / total, sum(t.s1[:, 2]) / total, sum(t.s1[:, 3]) / total)
end

# ---------------------------------------------------------------------------
# 2D → 3D kernels
# ---------------------------------------------------------------------------

"Indices in a 2D plane of the voxel `idx` when the plane spans every axis but `axis`."
@inline _plane_index(idx, axis) = axis == 1 ? (idx[2], idx[3]) : axis == 2 ? (idx[1], idx[3]) : (idx[1], idx[2])

"Repeat a 2D image along `axis` into a volume of size `dims` and pixel type `P`."
function _extrude(::Type{P}, plane::AbstractMatrix, axis::Int, dims) where {P}
    out = Array{P,3}(undef, dims)
    @inbounds for idx in CartesianIndices(out)
        out[idx] = _convert_pixel(P, plane[_plane_index(Tuple(idx), axis)...])
    end
    return out
end

"Convert a 2D pixel to the volume's pixel type (intensity ↔ binary at 0.5)."
_convert_pixel(::Type{IntensityPixel{T}}, p::IntensityPixel) where {T} = IntensityPixel{T}(convert(T, clamp(Float64(p), 0.0, 1.0)))
_convert_pixel(::Type{IntensityPixel{T}}, p::BinaryPixel) where {T} = IntensityPixel{T}(p.pixel ? one(T) : zero(T))
_convert_pixel(::Type{BinaryPixel{T}}, p::BinaryPixel) where {T} = BinaryPixel{T}(p.pixel)
_convert_pixel(::Type{BinaryPixel{T}}, p::IntensityPixel) where {T} = BinaryPixel{T}(Float64(p) >= 0.5)

"Whether a 2D mask pixel is set (binary, or intensity at `0.5`)."
@inline _plane_in(p::BinaryPixel) = p.pixel == true
@inline _plane_in(p) = Float64(p) >= 0.5

"Zero every voxel whose position, projected along `axis`, falls outside the 2D mask."
function _apply_plane(src::AbstractArray{P,3}, plane::AbstractMatrix, axis::Int) where {P}
    out = similar(src)
    zero = zero_pixel(P)
    @inbounds for idx in CartesianIndices(src)
        out[idx] = _plane_in(plane[_plane_index(Tuple(idx), axis)...]) ? src[idx] : zero
    end
    return out
end

# ---------------------------------------------------------------------------
# Factory plumbing
# ---------------------------------------------------------------------------

"""
    _factory_setup(I, operator) -> (pixel_type, size_type, function_name)

Validate the output type `I` and return its pixel type (e.g.
`IntensityPixel{N0f8}`), its size as a tuple type (e.g. `Tuple{28,28,28}`) and
the name of the specialised function (`operator` followed by the type).
"""
function _factory_setup(::Type{I}, operator::Symbol) where {I}
    _validate_factory_type(_get_image_type(I))
    return _get_image_pixel_type(I), _get_image_tuple_size(I), Symbol(operator, :_, Symbol(I))
end

"""
    _kernel_input(src) -> Array

The source volume in the form its kernels expect: voxel values
(`Array{Float64,3}`) for an intensity volume, the foreground (`Array{Bool,3}`)
for a binary one. Both live in per-task scratch buffers.
"""
_kernel_input(src::SizedImage{S,<:IntensityPixel}) where {S} = voxel_values(:vol_in, src.img)
_kernel_input(src::SizedImage{S,<:BinaryPixel}) where {S} = voxel_foreground(:vol_in_fg, src.img, IsSet())

"""
    _as_output_pixels(pixel_type, result) -> Array{pixel_type,3}

Convert a kernel result into pixels of the output type: values are stored
(rounded and clamped to the storage range), Booleans become `BinaryPixel`s,
and pixel arrays (from geometry kernels) are returned as they are.
"""
_as_output_pixels(::Type{P}, result::AbstractArray{Float64,3}) where {P<:IntensityPixel} = to_pixels(P, result)
_as_output_pixels(::Type{P}, result::AbstractArray{Bool,3}) where {P<:BinaryPixel} = to_pixels(P, result)
_as_output_pixels(::Type{P}, result::AbstractArray{P,3}) where {P} = result

"""
    _one_param_factory(I, operator, kernel, default) -> Function

Methods:

- `op(vol, p)` → `kernel(input, clamp_unit(p, default))`
- `op(vol)` → `kernel(input, default)`

where `input = _kernel_input(vol)`.
"""
function _one_param_factory(::Type{I}, operator::Symbol, kernel::K, default::Float64) where {I,K}
    pixel_type, size_type, name = _factory_setup(I, operator)
    fn = @eval function $name(src::Source, p::Real, args::Vararg{Any}) where {Source<:$I}
        return SImageND(_as_output_pixels($pixel_type, $kernel(_kernel_input(src), clamp_unit(p, $default))), $size_type)
    end
    @eval function $name(src::Source, args::Vararg{Any}) where {Source<:$I}
        return SImageND(_as_output_pixels($pixel_type, $kernel(_kernel_input(src), $default)), $size_type)
    end
    return fn
end

"""
    _two_param_factory(I, operator, kernel, default_first, default_second) -> Function

Methods, with `input = _kernel_input(vol)`:

- `op(vol, p1, p2)` → `kernel(input, clamp_unit(p1, default_first), clamp_unit(p2, default_second))`
- `op(vol, p1)` → `kernel(input, clamp_unit(p1, default_first), default_second)`
- `op(vol)` → `kernel(input, default_first, default_second)`
"""
function _two_param_factory(::Type{I}, operator::Symbol, kernel::K, default_first::Float64, default_second::Float64) where {I,K}
    pixel_type, size_type, name = _factory_setup(I, operator)
    fn = @eval function $name(src::Source, p1::Real, p2::Real, args::Vararg{Any}) where {Source<:$I}
        input = _kernel_input(src)
        return SImageND(_as_output_pixels($pixel_type, $kernel(input, clamp_unit(p1, $default_first), clamp_unit(p2, $default_second))), $size_type)
    end
    @eval function $name(src::Source, p1::Real, args::Vararg{Any}) where {Source<:$I}
        input = _kernel_input(src)
        return SImageND(_as_output_pixels($pixel_type, $kernel(input, clamp_unit(p1, $default_first), $default_second)), $size_type)
    end
    @eval function $name(src::Source, args::Vararg{Any}) where {Source<:$I}
        return SImageND(_as_output_pixels($pixel_type, $kernel(_kernel_input(src), $default_first, $default_second)), $size_type)
    end
    return fn
end

"""
    _two_volumes_factory(I, operator, kernel) -> Function

Method `op(vol_a, vol_b)` → `kernel(input_a, input_b)` for two volumes of the
output type. The first input is copied because both inputs come from the same
scratch buffer.
"""
function _two_volumes_factory(::Type{I}, operator::Symbol, kernel::K) where {I,K}
    pixel_type, size_type, name = _factory_setup(I, operator)
    return @eval function $name(src::Source, other::Other, args::Vararg{Any}) where {Source<:$I,Other<:$I}
        first_input = copy(_kernel_input(src))
        return SImageND(_as_output_pixels($pixel_type, $kernel(first_input, _kernel_input(other))), $size_type)
    end
end

"""
    _volume_and_mask_factory(I, operator, kernel, default) -> Function

Methods, with `fg` the mask's foreground:

- `op(vol, binary_mask, p)`, `op(vol, binary_mask)`
- `op(vol, intensity_mask, p)`, `op(vol, intensity_mask)` — thresholded at `0.5`

each calling `kernel(vol, fg, p)` (`p` = `clamp_unit(p, default)` or
`default`). The kernel receives the volume itself (`SImageND`), not its
values, because crop and recentre work on the voxels directly.
"""
function _volume_and_mask_factory(::Type{I}, operator::Symbol, kernel::K, default::Float64) where {I,K}
    pixel_type, size_type, name = _factory_setup(I, operator)
    fn = @eval function $name(src::Source, mask::Mask, p::Real, args::Vararg{Any}) where {Source<:$I,MaskBool,Mask<:SizedImage{$size_type,BinaryPixel{MaskBool}}}
        fg = voxel_foreground(:vol_mask, mask.img, IsSet())
        return SImageND(_as_output_pixels($pixel_type, $kernel(src, fg, clamp_unit(p, $default))), $size_type)
    end
    @eval function $name(src::Source, mask::Mask, args::Vararg{Any}) where {Source<:$I,MaskBool,Mask<:SizedImage{$size_type,BinaryPixel{MaskBool}}}
        fg = voxel_foreground(:vol_mask, mask.img, IsSet())
        return SImageND(_as_output_pixels($pixel_type, $kernel(src, fg, $default)), $size_type)
    end
    @eval function $name(src::Source, mask::Mask, p::Real, args::Vararg{Any}) where {Source<:$I,MaskStorage,Mask<:SizedImage{$size_type,IntensityPixel{MaskStorage}}}
        fg = voxel_foreground(:vol_mask, mask.img, AtLeast(0.5))
        return SImageND(_as_output_pixels($pixel_type, $kernel(src, fg, clamp_unit(p, $default))), $size_type)
    end
    @eval function $name(src::Source, mask::Mask, args::Vararg{Any}) where {Source<:$I,MaskStorage,Mask<:SizedImage{$size_type,IntensityPixel{MaskStorage}}}
        fg = voxel_foreground(:vol_mask, mask.img, AtLeast(0.5))
        return SImageND(_as_output_pixels($pixel_type, $kernel(src, fg, $default)), $size_type)
    end
    return fn
end

"""
    _mask_input_factory(I, operator, kernel, default) -> Function

Operators whose input is a mask (distance maps, binary thresholding). Methods:

- `op(binary_mask, p)`, `op(binary_mask)` → `kernel(fg, p)` / `kernel(fg, default)`
- `op(intensity_vol, t)` → `kernel(fg, default)` with `fg = intensity_vol ≥ t`
- `op(intensity_vol)` → same with `t = 0.5`

`fg` is a fresh copy, so kernels may modify or return it.
"""
function _mask_input_factory(::Type{I}, operator::Symbol, kernel::K, default::Float64) where {I,K}
    pixel_type, size_type, name = _factory_setup(I, operator)
    fn = @eval function $name(mask::Mask, p::Real, args::Vararg{Any}) where {MaskBool,Mask<:SizedImage{$size_type,BinaryPixel{MaskBool}}}
        fg = copy(voxel_foreground(:vol_mask, mask.img, IsSet()))
        return SImageND(_as_output_pixels($pixel_type, $kernel(fg, clamp_unit(p, $default))), $size_type)
    end
    @eval function $name(mask::Mask, args::Vararg{Any}) where {MaskBool,Mask<:SizedImage{$size_type,BinaryPixel{MaskBool}}}
        fg = copy(voxel_foreground(:vol_mask, mask.img, IsSet()))
        return SImageND(_as_output_pixels($pixel_type, $kernel(fg, $default)), $size_type)
    end
    @eval function $name(vol::Vol, t::Real, args::Vararg{Any}) where {VolStorage,Vol<:SizedImage{$size_type,IntensityPixel{VolStorage}}}
        fg = copy(voxel_foreground(:vol_mask, vol.img, AtLeast(clamp_unit(t))))
        return SImageND(_as_output_pixels($pixel_type, $kernel(fg, $default)), $size_type)
    end
    @eval function $name(vol::Vol, args::Vararg{Any}) where {VolStorage,Vol<:SizedImage{$size_type,IntensityPixel{VolStorage}}}
        fg = copy(voxel_foreground(:vol_mask, vol.img, AtLeast(0.5)))
        return SImageND(_as_output_pixels($pixel_type, $kernel(fg, $default)), $size_type)
    end
    return fn
end

"""
    _binarize_factory(I, operator, kernel, default) -> Function

Binary output from an intensity volume. Methods:
`op(intensity_vol, p)` → `kernel(values, clamp_unit(p, default))` and
`op(intensity_vol)` → `kernel(values, default)`, where `kernel` returns a
`Bool` array.
"""
function _binarize_factory(::Type{I}, operator::Symbol, kernel::K, default::Float64) where {I,K}
    pixel_type, size_type, name = _factory_setup(I, operator)
    fn = @eval function $name(vol::Vol, p::Real, args::Vararg{Any}) where {VolStorage,Vol<:SizedImage{$size_type,IntensityPixel{VolStorage}}}
        return SImageND(to_pixels($pixel_type, $kernel(voxel_values(:vol_in, vol.img), clamp_unit(p, $default))), $size_type)
    end
    @eval function $name(vol::Vol, args::Vararg{Any}) where {VolStorage,Vol<:SizedImage{$size_type,IntensityPixel{VolStorage}}}
        return SImageND(to_pixels($pixel_type, $kernel(voxel_values(:vol_in, vol.img), $default)), $size_type)
    end
    return fn
end

"""
    _voxel_geometry_factory(I, operator, kernel, default) -> Function

Geometry on the voxels themselves (no value conversion, so it works for both
bundles). Methods: `op(vol, u)` → `kernel(vol.img, clamp_unit(u, default))`
and `op(vol)` → `kernel(vol.img, default)`.
"""
function _voxel_geometry_factory(::Type{I}, operator::Symbol, kernel::K, default::Float64) where {I,K}
    pixel_type, size_type, name = _factory_setup(I, operator)
    fn = @eval function $name(src::Source, u::Real, args::Vararg{Any}) where {Source<:$I}
        return SImageND($kernel(src.img, clamp_unit(u, $default)), $size_type)
    end
    @eval function $name(src::Source, args::Vararg{Any}) where {Source<:$I}
        return SImageND($kernel(src.img, $default), $size_type)
    end
    return fn
end

"""
    _plane_to_volume_factory(I, operator, axis, mode) -> Function

2D → 3D operators. The 2D input must have the size of the volume's two other
axes (for `axis = 3`: `(y, x)`).

- `mode = :extrude`: `op(img2d)` repeats the 2D image along `axis`.
- `mode = :apply`: `op(vol, mask2d)` zeroes every voxel outside the 2D mask
  (binary, or intensity at `0.5`), slice by slice along `axis`.

The 2D input must hold intensity or binary pixels; segment images have no
method, so MAGE skips them instead of crashing inside the kernel.
"""
function _plane_to_volume_factory(::Type{I}, operator::Symbol, axis::Int, mode::Symbol) where {I}
    pixel_type, size_type, name = _factory_setup(I, operator)
    dims = Tuple(size_type.parameters)
    plane_axes = Tuple(k for k in 1:3 if k != axis)
    A, B = dims[plane_axes[1]], dims[plane_axes[2]]
    if mode === :extrude
        return @eval function $name(img::Plane, args::Vararg{Any}) where {PlanePixel<:Union{IntensityPixel,BinaryPixel},Plane<:SizedImage{Tuple{$A,$B},PlanePixel}}
            return SImageND(_extrude($pixel_type, img.img, $axis, $dims), $size_type)
        end
    end
    return @eval function $name(src::Source, mask::Plane, args::Vararg{Any}) where {Source<:$I,PlanePixel<:Union{IntensityPixel,BinaryPixel},Plane<:SizedImage{Tuple{$A,$B},PlanePixel}}
        return SImageND(_apply_plane(src.img, mask.img, $axis), $size_type)
    end
end

# ---------------------------------------------------------------------------
# Registration
# ---------------------------------------------------------------------------

"The bundle of a pixel kind (`:intensity` or `:binary`)."
_bundle(kind::Symbol) = kind === :intensity ? bundle_image3DIntensity_volume_factory : bundle_image3DBinary_volume_factory

"""
    _define!(operator, kinds, builder, description)

Define the factory function for `operator` (calling `builder(output_type)`)
and register it in the bundle of each kind in `kinds`. An operator present in
both bundles with different kernels (e.g. grey and binary `vol_erode`) is
registered once per kind under a kind-specific factory name; a shared operator
(geometry) has a single factory.
"""
function _define!(operator::Symbol, kinds, builder, description::String)
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

# Builders return `output_type -> factory(output_type, …)`. They are functions,
# not inline closures, so each closure captures its own arguments: a loop
# variable reassigned later in the same loop body would otherwise be seen by
# every closure created in that body.
_one_param(op, kernel, default) = I -> _one_param_factory(I, op, kernel, default)
_two_params(op, kernel, first, second) = I -> _two_param_factory(I, op, kernel, first, second)
_two_volumes(op, kernel) = I -> _two_volumes_factory(I, op, kernel)
_volume_and_mask(op, kernel, default) = I -> _volume_and_mask_factory(I, op, kernel, default)
_mask_input(op, kernel, default) = I -> _mask_input_factory(I, op, kernel, default)
_binarize(op, kernel, default) = I -> _binarize_factory(I, op, kernel, default)
_voxel_geometry(op, kernel, default) = I -> _voxel_geometry_factory(I, op, kernel, default)
_plane_to_volume(op, axis, mode) = I -> _plane_to_volume_factory(I, op, axis, mode)
_crop_kernel(largest::Bool) = (src, fg, margin) -> _crop(src.img, fg, largest, margin)
_recenter_kernel(largest::Bool) = (src, fg, margin) -> _recenter(src.img, fg, largest)

# --- Intensity bundle: filters, intensity transforms, grey morphology.
#     Each kernel is (values, p) -> values; `p` is ignored when the operator has no parameter.
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
    _define!(op, (:intensity,), _one_param(op, kernel, default), description)
end
_define!(:vol_window, (:intensity,),
    _two_params(:vol_window, (v, level, width) -> _window(v, level, width), 0.5, 0.5),
    "CT windowing: maps [level − width/2, level + width/2] to [0, 1] (defaults 0.5, 0.5).")

# --- Intensity bundle: two volumes, voxel by voxel.
for (op, kernel, description) in (
        (:vol_add, (a, b) -> a .+ b, "Sum of two volumes (clamped to the pixel range)."),
        (:vol_sub, (a, b) -> a .- b, "Difference of two volumes (clamped to the pixel range)."),
        (:vol_absdiff, (a, b) -> abs.(a .- b), "Absolute difference."),
        (:vol_mult, (a, b) -> a .* b, "Voxel-wise product."),
        (:vol_min, (a, b) -> min.(a, b), "Voxel-wise minimum."),
        (:vol_max, (a, b) -> max.(a, b), "Voxel-wise maximum."),
        (:vol_average, (a, b) -> (a .+ b) ./ 2, "Voxel-wise mean."),
    )
    _define!(op, (:intensity,), _two_volumes(op, kernel), description)
end

# --- Intensity bundle: masks.
"Keep the voxels inside the mask and zero the others (kernel of `vol_mask_keep`)."
_keep_inside(src, fg, p) = (v = copy(voxel_values(:vol_in, src.img)); v[.!fg] .= 0.0; v)
"Zero the voxels inside the mask (kernel of `vol_mask_zero`)."
_zero_inside(src, fg, p) = (v = copy(voxel_values(:vol_in, src.img)); v[fg] .= 0.0; v)
_define!(:vol_mask_keep, (:intensity,), _volume_and_mask(:vol_mask_keep, _keep_inside, 0.0),
    "Keeps the voxels inside the mask, zeroes the rest.")
_define!(:vol_mask_zero, (:intensity,), _volume_and_mask(:vol_mask_zero, _zero_inside, 0.0),
    "Zeroes the voxels inside the mask.")
_define!(:vol_distance_inside, (:intensity,), _mask_input(:vol_distance_inside, (fg, p) -> _distance_inside(fg), 0.0),
    "Distance from each mask voxel to the background, normalised by its maximum.")
_define!(:vol_proximity, (:intensity,), _mask_input(:vol_proximity, (fg, p) -> _proximity(fg), 0.0),
    "1 on the mask, decreasing with the distance to it (over the volume diagonal).")

# --- Binary bundle: binarisation of intensity volumes.
_define!(:vol_threshold, (:binary,), _mask_input(:vol_threshold, (fg, p) -> fg, 0.5),
    "Voxels at or above a threshold (default 0.5); a binary input is returned as is.")
_define!(:vol_otsu, (:binary,), _binarize(:vol_otsu, (v, p) -> _otsu_mask(v), 0.0),
    "Otsu threshold of an intensity volume.")
_define!(:vol_top_fraction, (:binary,), _binarize(:vol_top_fraction, _top_fraction, 0.1),
    "The brightest fraction p of the voxels (default 0.1).")

# --- Binary bundle: morphology and clean-up. Each kernel is (fg, p) -> fg.
for (op, kernel, default, description) in (
        (:vol_erode, _binary_erode, 0.0, "Binary erosion with a (2r+1)³ cube, r = 1 + round(2p)."),
        (:vol_dilate, _binary_dilate, 0.0, "Binary dilation with a (2r+1)³ cube."),
        (:vol_open, _binary_open, 0.0, "Binary opening with a (2r+1)³ cube."),
        (:vol_close, _binary_close, 0.0, "Binary closing with a (2r+1)³ cube."),
        (:vol_morph_gradient, _binary_morph_gradient, 0.0, "Dilation minus erosion: a shell around the boundary."),
        (:vol_erode_cross, (fg, p) -> _binary_erode_cross(fg), 0.0, "Binary erosion with the 6-neighbour cross."),
        (:vol_dilate_cross, (fg, p) -> _binary_dilate_cross(fg), 0.0, "Binary dilation with the 6-neighbour cross."),
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
    _define!(op, (:binary,), _one_param(op, kernel, default), description)
end
for (op, kernel, description) in (
        (:vol_and, (a, b) -> a .& b, "Logical and."),
        (:vol_or, (a, b) -> a .| b, "Logical or."),
        (:vol_xor, (a, b) -> a .⊻ b, "Logical exclusive or."),
    )
    _define!(op, (:binary,), _two_volumes(op, kernel), description)
end

# --- Both bundles: geometry. Each kernel is (voxels, u) -> voxels.
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
    _define!(op, (:intensity, :binary), _voxel_geometry(op, kernel, default), description)
end
for (op, largest, description) in (
        (:vol_crop_bbox, false, "Crops the bounding box of the mask (grown by margin, default 0.1) and resizes it back."),
        (:vol_crop_bbox_largest, true, "Crops the bounding box of the mask's largest component and resizes it back."),
    )
    _define!(op, (:intensity, :binary), _volume_and_mask(op, _crop_kernel(largest), 0.1), description)
end
for (op, largest, description) in (
        (:vol_recenter, false, "Translates the mask's centroid to the centre of the volume."),
        (:vol_recenter_largest, true, "Translates the largest component's centroid to the centre."),
    )
    _define!(op, (:intensity, :binary), _volume_and_mask(op, _recenter_kernel(largest), 0.0), description)
end

# --- Both bundles: 2D → 3D.
for (axis, letter) in ((1, :y), (2, :x), (3, :z))
    extrude_op = Symbol(:vol_extrude_, letter)
    _define!(extrude_op, (:intensity, :binary), _plane_to_volume(extrude_op, axis, :extrude),
        "Repeats a 2D image along $letter to fill the volume.")
    mask2d_op = Symbol(:vol_mask2d_, letter)
    _define!(mask2d_op, (:intensity, :binary), _plane_to_volume(mask2d_op, axis, :apply),
        "Applies a 2D mask (binary, or intensity at 0.5) to every slice along $letter.")
end

end
