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

# Example

```julia
using UTCGP, ImageCore
vol = SImageND(IntensityPixel{N0f8}.(rand(28, 28, 28)))     # a 28³ intensity volume
I = typeof(vol)

# Specialise the operator on the volume type, then call it.
blur = bundle_image3DIntensity_volume_factory[:vol_gaussian].fn(I)
blur(vol)          # σ = 1 voxel (the default p = 0.26 gives 0.3 + 2.7·0.26 ≈ 1)
blur(vol, 1.0)     # σ = 3 voxels
blur(vol, 0.0, 7)  # trailing extra inputs are ignored: σ = 0.3 voxel
```
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

# Returned by the bundle when no method matches the inputs (MAGE then skips the node).
fallback(args...) = return nothing

# Shared paragraph appended to both bundle docstrings below.
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
#
# `v` is always the volume's values as Float64 (usually in [0, 1]); kernels
# return a new array and never modify `v` (it is a scratch buffer reused by
# the next call).
# ---------------------------------------------------------------------------

# gaussian_kernel returns (weights, radius); the same 1D kernel is applied along y, x and z.
"Gaussian blur with standard deviation `sigma` (voxels), separable, edges replicated."
_gaussian(v, sigma) = (k = gaussian_kernel(sigma); separable_convolve!(similar(v), v, k[1], k[2]))

"""
Mean over the `(2r+1)³` cube around each voxel, edges replicated.

Example: `r = 1` averages each voxel with its 26 neighbours (a 3³ cube).
A box mean is a convolution with `2r + 1` equal weights `1/(2r + 1)` along each axis.
"""
_box_mean(v, r) = separable_convolve!(similar(v), v, fill(1.0 / (2r + 1), 2r + 1), r)

"""
Gradient magnitude from central differences along y, x and z (one-sided at the edges).

Example along one axis: values `0, 0, 1, 1` give differences
`0, 0.5, 0.5, 0` (each voxel looks one step before and after).
"""
function _gradient(v)
    h, w, d = size(v)                       # rows (y), columns (x), slices (z)
    out = similar(v)
    @inbounds for s in 1:d, c in 1:w, r in 1:h
        # (next − previous) / 2 along each axis; at a border the voxel itself
        # stands in for the missing neighbour (min/max clamp the index).
        gy = (v[min(r + 1, h), c, s] - v[max(r - 1, 1), c, s]) / 2
        gx = (v[r, min(c + 1, w), s] - v[r, max(c - 1, 1), s]) / 2
        gz = (v[r, c, min(s + 1, d)] - v[r, c, max(s - 1, 1)]) / 2
        out[r, c, s] = sqrt(gy^2 + gx^2 + gz^2)     # length of the gradient vector
    end
    return out
end

"""
Absolute 6-neighbour Laplacian: |Σ neighbours − 6 · voxel|, edges replicated.

It is `0` on flat and linear regions and large on spots, ridges and edges.
"""
function _laplacian(v)
    h, w, d = size(v)
    out = similar(v)
    @inbounds for s in 1:d, c in 1:w, r in 1:h
        x = v[r, c, s]
        # Sum of the 6 face neighbours (above/below, left/right, previous/next
        # slice), with the border voxel repeated outside the volume, minus 6 × centre.
        l = v[max(r - 1, 1), c, s] + v[min(r + 1, h), c, s] + v[r, max(c - 1, 1), s] +
            v[r, min(c + 1, w), s] + v[r, c, max(s - 1, 1)] + v[r, c, min(s + 1, d)] - 6x
        out[r, c, s] = abs(l)
    end
    return out
end

"""
Difference of Gaussians `G(σ) − G(1.6σ)` with `σ = 0.5 + 1.5p`, doubled and centred on `0.5`.

A band-pass filter: blobs of radius ≈ σ come out bright (> 0.5), their
surroundings dark (< 0.5), flat regions at 0.5.
"""
function _dog(v, p)
    sigma = 0.5 + 1.5p                      # p ∈ [0, 1] → σ ∈ [0.5, 2] voxels
    fine = _gaussian(v, sigma)
    coarse = _gaussian(v, 1.6sigma)         # 1.6 is the classic ratio approximating a Laplacian of Gaussian
    @inbounds @simd for i in eachindex(fine)
        fine[i] = 0.5 + 2.0 * (fine[i] - coarse[i])   # reuse `fine` as the output buffer
    end
    return fine
end

"""
Twice the standard deviation over the 3³ cube around each voxel (local texture).

Uses `std² = mean(v²) − mean(v)²`, so two box means replace a loop over the cube.
"""
function _local_std(v)
    mean = _box_mean(v, 1)                  # local mean of v
    squares = similar(v)
    @inbounds @simd for i in eachindex(v)
        squares[i] = v[i]^2
    end
    mean_of_squares = _box_mean(squares, 1) # local mean of v²
    @inbounds @simd for i in eachindex(mean)
        # max(…, 0) guards against tiny negative values from rounding; ×2 spreads
        # the typical range of std (≤ 0.5 for values in [0, 1]) over [0, 1].
        mean[i] = 2.0 * sqrt(max(mean_of_squares[i] - mean[i]^2, 0.0))
    end
    return mean
end

"""
Unsharp masking: `v + 2p · (v − G₁(v))`, sharpening edges (`p = 0.5` doubles the detail).

`v − G₁(v)` is the fine detail (what a σ = 1 blur removes); adding it back
amplifies edges. `p = 0` returns the volume unchanged.
"""
function _unsharp(v, p)
    blurred = _gaussian(v, 1.0)
    amount = 2.0 * p                        # p ∈ [0, 1] → amount ∈ [0, 2]
    out = similar(v)
    @inbounds @simd for i in eachindex(v)
        out[i] = v[i] + amount * (v[i] - blurred[i])
    end
    return out
end

"""
Min–max normalisation to `[0, 1]`; a constant volume becomes all zeros.

Example: values in `[0.2, 0.6]` are stretched so `0.2 → 0`, `0.4 → 0.5`, `0.6 → 1`.
"""
function _normalize(v)
    lo, hi = extrema(v)
    hi - lo <= 1e-12 && return zeros(size(v))   # constant volume: avoid dividing by ~0
    return (v .- lo) ./ (hi - lo)
end

"""
256-level histogram of `clamp(v, 0, 1)` (level `k` ↔ value `(k − 1)/255`).

`hist[k]` counts the voxels whose value rounds to `(k − 1)/255`; e.g. a voxel
at `0.5` lands in level `round(127.5) + 1 = 129`.
"""
function _levels(v)
    hist = zeros(Int, 256)
    @inbounds for x in v
        # clamp to [0, 1] first, then map to 0…255 (the outer clamp is a safety net), +1 for 1-based indexing.
        hist[clamp(round(Int, clamp(x, 0.0, 1.0) * 255), 0, 255) + 1] += 1
    end
    return hist
end

"""
Smallest level value whose cumulative count reaches the fraction `p` of `n` voxels.

Example: with `p = 0.5` this is the median level; with `p = 0.98` the level
below which 98% of the voxels lie.
"""
function _level_quantile(hist::Vector{Int}, n::Int, p::Float64)
    target = max(1, ceil(Int, p * n))       # number of voxels that must be at or below the answer
    running = 0                              # voxels counted so far
    @inbounds for b in 1:256
        running += hist[b]
        running >= target && return (b - 1) / 255   # level index b ↔ value (b − 1)/255
    end
    return 1.0
end

"""
Normalisation between the 2nd and 98th percentiles, clamped to `[0, 1]`: robust to a few extreme voxels.

Example: a CT with a few metal voxels at `1.0` and tissue in `[0.3, 0.5]` is
stretched on the tissue range instead of being squashed by the outliers.
"""
function _robust_normalize(v)
    hist = _levels(v)
    lo = _level_quantile(hist, length(v), 0.02)
    hi = _level_quantile(hist, length(v), 0.98)
    hi - lo <= 1e-12 && return _normalize(v)       # percentiles coincide: fall back to min–max
    return clamp.((v .- lo) ./ (hi - lo), 0.0, 1.0)
end

"""
CT windowing: map `[level − width/2, level + width/2]` linearly to `[0, 1]`, clamping outside.

Example: `level = 0.5, width = 0.2` maps `0.4 → 0`, `0.5 → 0.5`, `0.6 → 1`;
everything below 0.4 is black, everything above 0.6 white.
"""
function _window(v, level, width)
    width = max(width, 1 / 255)             # never narrower than one 8-bit level (no division by 0)
    lo = level - width / 2                  # bottom of the window
    return clamp.((v .- lo) ./ width, 0.0, 1.0)
end

"""
Gamma correction with exponent `2^(4p − 2)` (from 0.25 to 4; `p = 0.5` is the identity).

`p < 0.5` brightens dark regions (exponent < 1), `p > 0.5` darkens them.
"""
_gamma(v, p) = clamp.(v, 0.0, 1.0) .^ (2.0^(4p - 2))

"`1 − v` (dark becomes bright)."
_invert(v) = 1.0 .- v

"""
Histogram equalisation: each voxel becomes the fraction of voxels at or below its level.

The output histogram is roughly flat, so contrast is spread evenly; e.g. the
median voxel maps to about `0.5`.
"""
function _equalize(v)
    hist = _levels(v)
    cdf = cumsum(hist) ./ length(v)         # cdf[k] = share of voxels at level ≤ k
    # Look up each voxel's level (same mapping as `_levels`) in the cumulative distribution.
    return [cdf[clamp(round(Int, clamp(x, 0.0, 1.0) * 255), 0, 255) + 1] for x in v]
end

"Keep voxels at or above `t`, set the others to zero."
_threshold_zero(v, t) = ifelse.(v .>= t, v, 0.0)

"""
Structuring-element radius for morphology parameter `p`: 1, 2 or 3 voxels.

`p ≤ 0.25` → 1 (3³ cube), `0.25 < p < 0.75` → 2 (5³), `p ≥ 0.75` → 3 (7³)
(`round` sends halves to the even integer: `round(0.5) = 0`, `round(1.5) = 2`).
"""
_radius(p) = 1 + round(Int, 2p)

# Grey morphology with a (2r + 1)³ cube, r = _radius(p). `box_extremum!` takes the
# minimum (fmin) or maximum (fmax) over the cube around each voxel.
"Grey erosion: minimum over the `(2r+1)³` cube (bright regions shrink)."
_erode(v, p) = box_extremum!(similar(v), v, _radius(p), fmin)
"Grey dilation: maximum over the `(2r+1)³` cube (bright regions grow)."
_dilate(v, p) = box_extremum!(similar(v), v, _radius(p), fmax)
"Grey opening: erosion then dilation (removes bright structures smaller than the cube)."
_open(v, p) = (r = _radius(p); box_extremum!(similar(v), box_extremum!(similar(v), v, r, fmin), r, fmax))
"Grey closing: dilation then erosion (removes dark structures smaller than the cube)."
_close(v, p) = (r = _radius(p); box_extremum!(similar(v), box_extremum!(similar(v), v, r, fmax), r, fmin))
"Dilation minus erosion: large where intensity changes (edges), `0` on flat regions."
_morph_gradient(v, p) = _dilate(v, p) .- _erode(v, p)
"White top-hat: `v − opening`, the small bright structures the opening removed."
_tophat(v, p) = v .- _open(v, p)
"Black top-hat: `closing − v`, the small dark structures the closing removed."
_bothat(v, p) = _close(v, p) .- v
"Grey erosion with the 6-neighbour cross (the voxel and its 6 face neighbours)."
_erode_cross(v) = cross_extremum!(similar(v), v, fmin)
"Grey dilation with the 6-neighbour cross."
_dilate_cross(v) = cross_extremum!(similar(v), v, fmax)

"""
Distance from each foreground voxel to the background, divided by the largest such distance (`0` outside).

Example: for a ball of radius 5, the centre gets `1`, voxels on the surface
about `0.2`, and the background `0`.
"""
function _distance_inside(fg::AbstractArray{Bool,3})
    any(fg) || return zeros(size(fg))       # no foreground: all zero
    all(fg) && return ones(size(fg))        # no background to measure from: all one
    background = map(!, fg)                                   # Array{Bool}: faster to read than a BitArray
    # Squared Euclidean distance from every voxel to the nearest background voxel.
    d = volume_distance_map!(Array{Float64,3}(undef, size(fg)), background)
    largest = 0.0
    @inbounds for i in eachindex(d)
        d[i] = fg[i] ? sqrt(d[i]) : 0.0     # real distance inside, 0 outside
        largest = max(largest, d[i])
    end
    return largest > 0 ? d ./ largest : d   # scale so the deepest voxel is 1
end

"""
`1 − distance to the foreground / volume diagonal`: `1` on the mask, fading with distance.

Example: in a 28³ volume (diagonal ≈ 46.8 voxels), a voxel 10 voxels away from
the mask gets `1 − 10/46.8 ≈ 0.79`.
"""
function _proximity(fg::AbstractArray{Bool,3})
    any(fg) || return zeros(size(fg))       # nothing to be close to
    scale = 1.0 / max(sqrt(sum(abs2, size(fg) .- 1)), 1.0)   # 1 / diagonal length (corner to corner)
    # Squared distance from every voxel to the nearest foreground voxel (0 on the mask).
    d = volume_distance_map!(Array{Float64,3}(undef, size(fg)), fg)
    return clamp.(1.0 .- sqrt.(d) .* scale, 0.0, 1.0)
end

# ---------------------------------------------------------------------------
# Binary kernels: foreground (Array{Bool,3}) → Array{Bool,3}
#
# Binary morphology reuses the grey kernels: the mask becomes 0/1 values, the
# grey min/max filter runs, and the result is thresholded back at 0.5.
# Min over a cube of 0/1 values is 1 only if every voxel is set (erosion);
# max is 1 if any voxel is set (dilation).
# ---------------------------------------------------------------------------

"A mask as 0/1 values (scratch), so binary morphology can reuse the grey filters."
_as_float(fg) = (v = scratch(:vb_float, Float64, size(fg)...); v .= fg; v)
"Values back to a mask (`> 0.5`)."
_as_bool(v) = v .> 0.5

"Binary erosion with a `(2r+1)³` cube: a voxel stays set only if its whole cube is set."
_binary_erode(fg, p) = _as_bool(_erode(_as_float(fg), p))
"Binary dilation with a `(2r+1)³` cube: a voxel becomes set if any voxel of its cube is."
_binary_dilate(fg, p) = _as_bool(_dilate(_as_float(fg), p))
"Binary opening with a `(2r+1)³` cube: removes specks and thin bridges."
_binary_open(fg, p) = _as_bool(_open(_as_float(fg), p))
"Binary closing with a `(2r+1)³` cube: fills small gaps and dents."
_binary_close(fg, p) = _as_bool(_close(_as_float(fg), p))
"Dilation minus erosion: a shell around the object boundaries (`dilated AND NOT eroded`)."
_binary_morph_gradient(fg, p) = _binary_dilate(fg, p) .& .!_binary_erode(fg, p)
"Binary erosion with the 6-neighbour cross."
_binary_erode_cross(fg) = _as_bool(_erode_cross(_as_float(fg)))
"Binary dilation with the 6-neighbour cross."
_binary_dilate_cross(fg) = _as_bool(_dilate_cross(_as_float(fg)))

"""
The mask with its enclosed cavities filled.

Example: a hollow sphere (a shell) becomes a solid ball; a cup open to the
border stays a cup, because its inside is connected to the outside.
"""
function _fill_holes(fg)
    holes = Array{Bool,3}(undef, size(fg))
    volume_holes!(holes, fg)                # background regions that do not reach the border
    return holes .| fg                      # mask OR holes
end

"The enclosed cavities of the mask alone (background not connected to the volume border)."
_holes(fg) = (holes = Array{Bool,3}(undef, size(fg)); volume_holes!(holes, fg); holes)

"""
Keep only the component `choose(table)` of the 26-connected components.

`choose` receives the `VolumeTable` (areas, centroids, boxes of every
component) and returns the number of the component to keep.
"""
function _keep_component(fg, choose)
    t = volume_table(fg, identity)          # label the components; `identity` = voxels already Bool
    t.n == 0 && return zeros(Bool, size(fg))
    id = choose(t)
    return t.labels .== id                  # voxels whose label is the chosen component
end

"Keep the largest component (by voxel count)."
_largest_component(fg) = _keep_component(fg, t -> argmax(t.area))

"Keep the component whose centroid is closest to the volume centre."
function _central_component(fg)
    centre = (size(fg) .+ 1) ./ 2           # e.g. (14.5, 14.5, 14.5) for a 28³ volume
    # Squared distance from each component's centroid to the centre; pick the smallest.
    return _keep_component(fg, t -> argmin([sum(abs2, centroid(t, i) .- centre) for i in 1:t.n]))
end

"""
Keep the components for which `keep(table, id)` holds.

Example: `_filter_components(fg, (t, i) -> t.area[i] >= 100)` keeps the
components of at least 100 voxels.
"""
function _filter_components(fg, keep)
    t = volume_table(fg, identity)
    kept = [keep(t, i) for i in 1:t.n]      # one verdict per component number
    out = Array{Bool,3}(undef, size(fg))
    @inbounds for i in eachindex(out)
        l = t.labels[i]                     # 0 = background, otherwise component number
        out[i] = l != 0 && kept[l]
    end
    return out
end

"Remove components smaller than the fraction `p` of all voxels (e.g. `p = 0.001` of 28³ ≈ 22 voxels)."
_remove_small(fg, p) = _filter_components(fg, (t, i) -> t.area[i] >= p * length(fg))

# A component touches the border when its bounding box starts at index 1 or ends at the
# last index along any of the three axes (t.lo / t.hi are the box corners, t.dims the size).
"Remove components whose bounding box touches the volume border."
_clear_border(fg) = _filter_components(fg, (t, i) -> !any(t.lo[i, k] == 1 || t.hi[i, k] == t.dims[k] for k in 1:3))

"""
3³ majority vote: a voxel is set when most of its cube is (edges replicated).

Removes isolated voxels and fills one-voxel pits: the share of set voxels in
the cube is a 3³ box mean of the 0/1 mask.
"""
function _majority(fg)
    share = _box_mean(_as_float(fg), 1)     # fraction of the 27 voxels that are set
    return share .> 0.5
end

"Replace each component by its filled bounding box."
function _bbox_fill(fg)
    t = volume_table(fg, identity)
    out = zeros(Bool, size(fg))
    for i in 1:t.n
        # t.lo[i, k] : t.hi[i, k] is the extent of component i along axis k (y, x, z).
        out[t.lo[i, 1]:t.hi[i, 1], t.lo[i, 2]:t.hi[i, 2], t.lo[i, 3]:t.hi[i, 3]] .= true
    end
    return out
end

"""
Otsu's threshold on the 256-level histogram: voxels above the level that best separates two classes.

For every candidate level `b`, voxels at levels `≤ b` form the dark class and
the others the bright class; the chosen level maximises the between-class
variance `w0 (1 − w0) (mean_dark − mean_bright)²`.
"""
function _otsu_mask(v)
    hist = _levels(v)
    n = length(v)
    total = sum((b - 1) / 255 * hist[b] for b in 1:256)       # sum of all voxel values (from the histogram)
    best_between, best_level, weight, partial = -1.0, 1, 0, 0.0
    for b in 1:255
        weight += hist[b]                          # voxels at levels ≤ b
        partial += hist[b] * (b - 1) / 255         # their intensity sum
        (weight == 0 || weight == n) && continue   # one class empty: not a split
        w0 = weight / n                            # share of voxels in the dark class
        # between-class variance: w0 · w1 · (mean_dark − mean_bright)²
        between = w0 * (1 - w0) * (partial / weight - (total - partial) / (n - weight))^2
        between > best_between && ((best_between, best_level) = (between, b))
    end
    threshold = (best_level - 1) / 255             # value of the last dark level
    return v .> threshold
end

"""
The brightest fraction `p` of the voxels (ties at the cut-off level are kept).

Example: `p = 0.1` keeps the voxels at or above the 90th-percentile level.
"""
function _top_fraction(v, p)
    hist = _levels(v)
    threshold = _level_quantile(hist, length(v), 1.0 - p)    # level with a share 1 − p below it
    return v .>= threshold
end

# ---------------------------------------------------------------------------
# Geometry kernels on the voxel arrays (shared by both bundles)
#
# They move voxels around without converting values, so they work on any
# pixel type: `src` is the volume's pixel array, the result has the same type.
# ---------------------------------------------------------------------------

"Mirror along `axis` (1: top ↔ bottom, 2: left ↔ right, 3: first ↔ last slice)."
_flip(src, axis) = reverse(src; dims = axis)

"""
Quarter turn in the plane of axes `(a, b)`; returns an unchanged copy when that plane is not square.

Swapping axes `a` and `b` (a transpose in that plane) then reversing axis `a`
is a 90° rotation. Example for `(a, b) = (1, 2)` on one slice:
`[1 2; 3 4]` → transpose `[1 3; 2 4]` → reverse rows `[2 4; 1 3]`.
"""
function _rot90(src, a, b)
    size(src, a) == size(src, b) || return copy(src)   # a non-square plane would change the size
    perm = collect(1:3)
    perm[a], perm[b] = b, a                 # axis permutation swapping a and b
    return reverse(permutedims(src, perm); dims = a)
end

"""
Shift along `axis` by `round((u − 0.5) · size)` voxels; uncovered voxels are zero.

Example: 28 slices along z, `u = 0.75` → shift by `round(0.25 · 28) = 7`:
output slice 10 shows input slice 3, output slices 1–7 are zero.
"""
function _shift(src::AbstractArray{P,3}, axis::Int, u::Float64) where {P}
    n = size(src, axis)
    k = round(Int, (u - 0.5) * n)           # shift in voxels; u = 0.5 → 0, negative moves towards index 1
    out = similar(src)
    zero = zero_pixel(P)                    # the "empty" voxel of this pixel type
    @inbounds for idx in CartesianIndices(src)
        source = Tuple(idx)                 # (r, c, s) of the output voxel
        j = source[axis] - k                # where it comes from along `axis`
        # Base.setindex(t, j, axis) is the tuple t with entry `axis` replaced by j.
        out[idx] = 1 <= j <= n ? src[Base.setindex(source, j, axis)...] : zero
    end
    return out
end

"""
Bounding box `(lo, hi)` of the foreground (or of its largest component when
`largest`), grown by `margin` of its size on each side and clipped; `nothing`
for an empty mask.

Example: a box `y 10:19` with `margin = 0.1` grows by `round(0.1 · 10) = 1`
voxel on each side, to `9:20`.
"""
function _box(fg::AbstractArray{Bool,3}, largest::Bool, margin::Float64)
    t = volume_table(fg, identity)
    t.n == 0 && return nothing
    # Components that define the box: just the largest, or all of them.
    ids = largest ? (argmax(t.area):argmax(t.area)) : (1:t.n)
    lo = ntuple(k -> minimum(t.lo[i, k] for i in ids), 3)    # smallest start along y, x, z
    hi = ntuple(k -> maximum(t.hi[i, k] for i in ids), 3)    # largest end along y, x, z
    dims = size(fg)
    grow = ntuple(k -> round(Int, margin * (hi[k] - lo[k] + 1)), 3)   # margin in voxels per axis
    return ntuple(k -> max(lo[k] - grow[k], 1), 3), ntuple(k -> min(hi[k] + grow[k], dims[k]), 3)
end

"Crop the box of the mask and resize it back to full size (trilinear for intensity, nearest otherwise); unchanged when the mask is empty."
function _crop(src::AbstractArray{P,3}, fg, largest::Bool, margin::Float64) where {P}
    box = _box(fg, largest, margin)
    box === nothing && return src           # empty mask: nothing to zoom on
    if P <: IntensityPixel
        # Interpolate on Float64 values, then store back as pixels of type P.
        return to_pixels(P, resample_box(voxel_values(:crop_values, src), box...))
    end
    # Binary pixels cannot be blended: pick the nearest voxel.
    return resample_box_nearest(src, box...)
end

"""
Translate so the mask's centroid (or its largest component's) lands on the volume centre; uncovered voxels are zero.

Example: centroid at `y = 20` in a 28-row volume (centre 14.5) → shift by
`round(5.5) = 6` rows: output row `r` shows input row `r + 6`.
"""
function _recenter(src::AbstractArray{P,3}, fg, largest::Bool) where {P}
    t = volume_table(fg, identity)
    t.n == 0 && return src
    target = largest ? centroid(t, argmax(t.area)) : _overall_centroid(t)   # (y, x, z) to bring to the centre
    h, w, d = size(src)
    # Offset from the volume centre to the target, per axis.
    shift_r = round(Int, target[1] - (h + 1) / 2)
    shift_c = round(Int, target[2] - (w + 1) / 2)
    shift_s = round(Int, target[3] - (d + 1) / 2)
    out = similar(src)
    zero = zero_pixel(P)
    @inbounds for s in 1:d, c in 1:w, r in 1:h
        rr, cc, ss = r + shift_r, c + shift_c, s + shift_s     # source voxel
        out[r, c, s] = (1 <= rr <= h && 1 <= cc <= w && 1 <= ss <= d) ? src[rr, cc, ss] : zero
    end
    return out
end

"Centroid `(y, x, z)` of all components together (voxel-weighted, from the per-component sums `t.s1`)."
function _overall_centroid(t)
    total = sum(t.area)                     # voxels in all components
    return (sum(t.s1[:, 1]) / total, sum(t.s1[:, 2]) / total, sum(t.s1[:, 3]) / total)
end

# ---------------------------------------------------------------------------
# 2D → 3D kernels
#
# A 2D image is laid across the volume perpendicular to `axis`: for every
# voxel, drop its coordinate along `axis` and read the 2D image at the two
# that remain.
# ---------------------------------------------------------------------------

"""
Indices in a 2D plane of the voxel `idx` when the plane spans every axis but `axis`.

The coordinate along `axis` is dropped, the other two keep their order:

| `axis` | voxel `(r, c, s)` reads plane pixel | plane size |
|:--|:--|:--|
| 1 (`y`) | `(c, s)` | `(x, z)` |
| 2 (`x`) | `(r, s)` | `(y, z)` |
| 3 (`z`) | `(r, c)` | `(y, x)` |

Example: `_plane_index((5, 7, 2), 3) == (5, 7)`: with `axis = 3`, every slice
`s` reads the same pixel `(5, 7)` of the 2D image.
"""
@inline _plane_index(idx, axis) = axis == 1 ? (idx[2], idx[3]) : axis == 2 ? (idx[1], idx[3]) : (idx[1], idx[2])

"""
Repeat a 2D image along `axis` into a volume of size `dims` and pixel type `P`.

Example: a `28 × 28` image extruded along `z` (`axis = 3`) into `28 × 28 × 16`
gives 16 identical slices, each equal to the image.
"""
function _extrude(::Type{P}, plane::AbstractMatrix, axis::Int, dims) where {P}
    out = Array{P,3}(undef, dims)
    @inbounds for idx in CartesianIndices(out)
        # Voxel (r, c, s) takes the plane pixel at its two coordinates other than `axis`
        # (see `_plane_index`), converted to the volume's pixel type.
        # E.g. axis = 3: out[r, c, s] = plane[r, c] for every slice s.
        out[idx] = _convert_pixel(P, plane[_plane_index(Tuple(idx), axis)...])
    end
    return out
end

# Convert a 2D pixel to the volume's pixel type; between intensity and binary,
# a pixel is "set" at or above 0.5 and set ↔ 1.0.
"Convert a 2D pixel to the volume's pixel type (intensity ↔ binary at 0.5)."
_convert_pixel(::Type{IntensityPixel{T}}, p::IntensityPixel) where {T} = IntensityPixel{T}(convert(T, clamp(Float64(p), 0.0, 1.0)))   # intensity → intensity (e.g. N0f16 → N0f8)
_convert_pixel(::Type{IntensityPixel{T}}, p::BinaryPixel) where {T} = IntensityPixel{T}(p.pixel ? one(T) : zero(T))                   # set → 1.0, unset → 0.0
_convert_pixel(::Type{BinaryPixel{T}}, p::BinaryPixel) where {T} = BinaryPixel{T}(p.pixel)                                             # binary → binary
_convert_pixel(::Type{BinaryPixel{T}}, p::IntensityPixel) where {T} = BinaryPixel{T}(Float64(p) >= 0.5)                                # ≥ 0.5 → set

"Whether a 2D mask pixel is set (binary, or intensity at `0.5`)."
@inline _plane_in(p::BinaryPixel) = p.pixel == true
@inline _plane_in(p) = Float64(p) >= 0.5

"""
Zero every voxel whose position, projected along `axis`, falls outside the 2D mask.

Example: `axis = 3` and a 2D disk mask → every slice is cut to the disk, so
the volume is cut to a cylinder along z.
"""
function _apply_plane(src::AbstractArray{P,3}, plane::AbstractMatrix, axis::Int) where {P}
    out = similar(src)
    zero = zero_pixel(P)
    @inbounds for idx in CartesianIndices(src)
        # Keep the voxel when the mask pixel under it (along `axis`) is set.
        out[idx] = _plane_in(plane[_plane_index(Tuple(idx), axis)...]) ? src[idx] : zero
    end
    return out
end

# ---------------------------------------------------------------------------
# Factory plumbing
#
# Factories run once per output type, when a library is specialised. They use
# `@eval` to define named methods whose types are fixed (pixel type, size), so
# the generated code is as fast as hand-written code for that type.
# Inside `@eval`, `$x` splices the *value* of x into the generated code.
# ---------------------------------------------------------------------------

"""
    _factory_setup(I, operator) -> (pixel_type, size_type, function_name)

Validate the output type `I` and return its pixel type (e.g.
`IntensityPixel{N0f8}`), its size as a tuple type (e.g. `Tuple{28,28,28}`) and
the name of the specialised function (`operator` followed by the type).
"""
function _factory_setup(::Type{I}, operator::Symbol) where {I}
    _validate_factory_type(_get_image_type(I))       # throws for unsupported storage types
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
_as_output_pixels(::Type{P}, result::AbstractArray{Float64,3}) where {P<:IntensityPixel} = to_pixels(P, result)   # values → intensity pixels
_as_output_pixels(::Type{P}, result::AbstractArray{Bool,3}) where {P<:BinaryPixel} = to_pixels(P, result)         # Booleans → binary pixels
_as_output_pixels(::Type{P}, result::AbstractArray{P,3}) where {P} = result                                       # already pixels of type P

"""
    _one_param_factory(I, operator, kernel, default) -> Function

Methods:

- `op(vol, p)` → `kernel(input, clamp_unit(p, default))`
- `op(vol)` → `kernel(input, default)`

where `input = _kernel_input(vol)`.
"""
function _one_param_factory(::Type{I}, operator::Symbol, kernel::K, default::Float64) where {I,K}
    pixel_type, size_type, name = _factory_setup(I, operator)
    # op(vol, p, extra...): the parameter is clamped to [0, 1] (NaN → default).
    fn = @eval function $name(src::Source, p::Real, args::Vararg{Any}) where {Source<:$I}
        return SImageND(_as_output_pixels($pixel_type, $kernel(_kernel_input(src), clamp_unit(p, $default))), $size_type)
    end
    # op(vol, extra...): no number given, use the default.
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

Example: `vol_window(vol, 0.4)` uses level `0.4` and the default width `0.5`.
"""
function _two_param_factory(::Type{I}, operator::Symbol, kernel::K, default_first::Float64, default_second::Float64) where {I,K}
    pixel_type, size_type, name = _factory_setup(I, operator)
    # Both parameters given.
    fn = @eval function $name(src::Source, p1::Real, p2::Real, args::Vararg{Any}) where {Source<:$I}
        input = _kernel_input(src)
        return SImageND(_as_output_pixels($pixel_type, $kernel(input, clamp_unit(p1, $default_first), clamp_unit(p2, $default_second))), $size_type)
    end
    # Only the first: the second takes its default.
    @eval function $name(src::Source, p1::Real, args::Vararg{Any}) where {Source<:$I}
        input = _kernel_input(src)
        return SImageND(_as_output_pixels($pixel_type, $kernel(input, clamp_unit(p1, $default_first), $default_second)), $size_type)
    end
    # Neither.
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
        # Without the copy, reading `other` would overwrite the buffer holding `src`'s values.
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
    # The mask must have the volume's size ($size_type) but may be binary or intensity.
    # Binary mask, with a parameter.
    fn = @eval function $name(src::Source, mask::Mask, p::Real, args::Vararg{Any}) where {Source<:$I,MaskBool,Mask<:SizedImage{$size_type,BinaryPixel{MaskBool}}}
        fg = voxel_foreground(:vol_mask, mask.img, IsSet())
        return SImageND(_as_output_pixels($pixel_type, $kernel(src, fg, clamp_unit(p, $default))), $size_type)
    end
    # Binary mask, default parameter.
    @eval function $name(src::Source, mask::Mask, args::Vararg{Any}) where {Source<:$I,MaskBool,Mask<:SizedImage{$size_type,BinaryPixel{MaskBool}}}
        fg = voxel_foreground(:vol_mask, mask.img, IsSet())
        return SImageND(_as_output_pixels($pixel_type, $kernel(src, fg, $default)), $size_type)
    end
    # Intensity mask (voxels ≥ 0.5 are inside), with a parameter.
    @eval function $name(src::Source, mask::Mask, p::Real, args::Vararg{Any}) where {Source<:$I,MaskStorage,Mask<:SizedImage{$size_type,IntensityPixel{MaskStorage}}}
        fg = voxel_foreground(:vol_mask, mask.img, AtLeast(0.5))
        return SImageND(_as_output_pixels($pixel_type, $kernel(src, fg, clamp_unit(p, $default))), $size_type)
    end
    # Intensity mask, default parameter.
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

Example: `vol_threshold(vol, 0.3)` is the mask of voxels `≥ 0.3`
(its kernel returns `fg` unchanged).
"""
function _mask_input_factory(::Type{I}, operator::Symbol, kernel::K, default::Float64) where {I,K}
    pixel_type, size_type, name = _factory_setup(I, operator)
    # Binary input, with the kernel's parameter.
    fn = @eval function $name(mask::Mask, p::Real, args::Vararg{Any}) where {MaskBool,Mask<:SizedImage{$size_type,BinaryPixel{MaskBool}}}
        fg = copy(voxel_foreground(:vol_mask, mask.img, IsSet()))
        return SImageND(_as_output_pixels($pixel_type, $kernel(fg, clamp_unit(p, $default))), $size_type)
    end
    # Binary input, default parameter.
    @eval function $name(mask::Mask, args::Vararg{Any}) where {MaskBool,Mask<:SizedImage{$size_type,BinaryPixel{MaskBool}}}
        fg = copy(voxel_foreground(:vol_mask, mask.img, IsSet()))
        return SImageND(_as_output_pixels($pixel_type, $kernel(fg, $default)), $size_type)
    end
    # Intensity input: the number is the threshold that makes the mask.
    @eval function $name(vol::Vol, t::Real, args::Vararg{Any}) where {VolStorage,Vol<:SizedImage{$size_type,IntensityPixel{VolStorage}}}
        fg = copy(voxel_foreground(:vol_mask, vol.img, AtLeast(clamp_unit(t))))
        return SImageND(_as_output_pixels($pixel_type, $kernel(fg, $default)), $size_type)
    end
    # Intensity input, threshold 0.5.
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
    # With a parameter (e.g. the fraction for vol_top_fraction).
    fn = @eval function $name(vol::Vol, p::Real, args::Vararg{Any}) where {VolStorage,Vol<:SizedImage{$size_type,IntensityPixel{VolStorage}}}
        return SImageND(to_pixels($pixel_type, $kernel(voxel_values(:vol_in, vol.img), clamp_unit(p, $default))), $size_type)
    end
    # Default parameter.
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
    # With the geometry parameter (e.g. the shift amount).
    fn = @eval function $name(src::Source, u::Real, args::Vararg{Any}) where {Source<:$I}
        return SImageND($kernel(src.img, clamp_unit(u, $default)), $size_type)
    end
    # Default parameter (flips and rotations ignore it).
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

Example: for a `28 × 28 × 16` volume type, `vol_extrude_z` accepts a
`28 × 28` image and `vol_extrude_x` a `28 × 16` image `(y, z)`.
"""
function _plane_to_volume_factory(::Type{I}, operator::Symbol, axis::Int, mode::Symbol) where {I}
    pixel_type, size_type, name = _factory_setup(I, operator)
    dims = Tuple(size_type.parameters)                # e.g. (28, 28, 16)
    plane_axes = Tuple(k for k in 1:3 if k != axis)   # the two axes the 2D image spans
    A, B = dims[plane_axes[1]], dims[plane_axes[2]]   # required size of the 2D input
    if mode === :extrude
        # op(img2d): the volume is built from the 2D image alone.
        return @eval function $name(img::Plane, args::Vararg{Any}) where {PlanePixel<:Union{IntensityPixel,BinaryPixel},Plane<:SizedImage{Tuple{$A,$B},PlanePixel}}
            return SImageND(_extrude($pixel_type, img.img, $axis, $dims), $size_type)
        end
    end
    # op(vol, mask2d): the 2D mask cuts the volume.
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

Example: `_define!(:vol_erode, (:binary,), …)` defines
`vol_erode_binary_image3D_factory`; `_define!(:vol_flip_x, (:intensity, :binary), …)`
defines `vol_flip_x_image3D_factory` and registers it in both bundles.
"""
function _define!(operator::Symbol, kinds, builder, description::String)
    # One kind → kind in the name (avoids clashes between the grey and binary versions).
    factory_name = length(kinds) == 1 ? Symbol(operator, :_, kinds[1], :_image3D_factory) :
                   Symbol(operator, :_image3D_factory)
    # The factory accepts any 3D image type and forwards it to the builder.
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
# Kernels for _volume_and_mask_factory: (vol, fg, p). Crop uses p as the margin; recentre ignores it.
_crop_kernel(largest::Bool) = (src, fg, margin) -> _crop(src.img, fg, largest, margin)
_recenter_kernel(largest::Bool) = (src, fg, margin) -> _recenter(src.img, fg, largest)

# --- Intensity bundle: filters, intensity transforms, grey morphology.
#
# Each entry is (operator name, kernel, default p, description):
#   - kernel(values, p) -> values; operators without a parameter ignore p,
#     e.g. (v, p) -> _gradient(v);
#   - default p is used when the program passes no number (0.0 when unused);
#   - the description is shown in the Bundle Catalogue.
# All become op(vol) / op(vol, p) through _one_param_factory.
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
# vol_window takes two parameters (level, width): kernel(values, level, width).
_define!(:vol_window, (:intensity,),
    _two_params(:vol_window, (v, level, width) -> _window(v, level, width), 0.5, 0.5),
    "CT windowing: maps [level − width/2, level + width/2] to [0, 1] (defaults 0.5, 0.5).")

# --- Intensity bundle: two volumes, voxel by voxel.
#
# Each entry is (operator name, kernel(values_a, values_b) -> values, description);
# all become op(vol_a, vol_b). Results outside [0, 1] are clamped when stored.
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
# Kernels of _volume_and_mask_factory receive (volume, foreground mask, p).
"Keep the voxels inside the mask and zero the others (kernel of `vol_mask_keep`)."
_keep_inside(src, fg, p) = (v = copy(voxel_values(:vol_in, src.img)); v[.!fg] .= 0.0; v)
"Zero the voxels inside the mask (kernel of `vol_mask_zero`)."
_zero_inside(src, fg, p) = (v = copy(voxel_values(:vol_in, src.img)); v[fg] .= 0.0; v)
_define!(:vol_mask_keep, (:intensity,), _volume_and_mask(:vol_mask_keep, _keep_inside, 0.0),
    "Keeps the voxels inside the mask, zeroes the rest.")
_define!(:vol_mask_zero, (:intensity,), _volume_and_mask(:vol_mask_zero, _zero_inside, 0.0),
    "Zeroes the voxels inside the mask.")
# Mask → intensity distance maps; kernels receive (foreground, p) and ignore p.
_define!(:vol_distance_inside, (:intensity,), _mask_input(:vol_distance_inside, (fg, p) -> _distance_inside(fg), 0.0),
    "Distance from each mask voxel to the background, normalised by its maximum.")
_define!(:vol_proximity, (:intensity,), _mask_input(:vol_proximity, (fg, p) -> _proximity(fg), 0.0),
    "1 on the mask, decreasing with the distance to it (over the volume diagonal).")

# --- Binary bundle: binarisation of intensity volumes.
# vol_threshold: _mask_input_factory already thresholds the input, so the kernel returns fg as is.
_define!(:vol_threshold, (:binary,), _mask_input(:vol_threshold, (fg, p) -> fg, 0.5),
    "Voxels at or above a threshold (default 0.5); a binary input is returned as is.")
_define!(:vol_otsu, (:binary,), _binarize(:vol_otsu, (v, p) -> _otsu_mask(v), 0.0),
    "Otsu threshold of an intensity volume.")
_define!(:vol_top_fraction, (:binary,), _binarize(:vol_top_fraction, _top_fraction, 0.1),
    "The brightest fraction p of the voxels (default 0.1).")

# --- Binary bundle: morphology and clean-up.
#
# Same layout as the intensity table: (operator name, kernel(fg, p) -> fg,
# default p, description), registered as op(mask) / op(mask, p).
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
# Two masks, voxel by voxel: (operator name, kernel(fg_a, fg_b) -> fg, description).
for (op, kernel, description) in (
        (:vol_and, (a, b) -> a .& b, "Logical and."),
        (:vol_or, (a, b) -> a .| b, "Logical or."),
        (:vol_xor, (a, b) -> a .⊻ b, "Logical exclusive or."),
    )
    _define!(op, (:binary,), _two_volumes(op, kernel), description)
end

# --- Both bundles: geometry.
#
# Each entry is (operator name, kernel, default u, description):
#   - kernel(voxels, u) -> voxels works on the pixel array itself, so one
#     definition serves intensity and binary volumes; flips and rotations
#     ignore u, shifts use it as the shift (u = 0.5: no shift);
#   - default u is used when the program passes no number;
#   - the description is shown in the Bundle Catalogue.
# Example: (:vol_flip_y, (src, u) -> _flip(src, 1), 0.0, "…") defines
# vol_flip_y(vol), which mirrors the rows whatever u is.
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
# Crops guided by a mask: (operator name, use only the largest component?, description).
# The parameter is the margin around the box (default 0.1 of its size).
for (op, largest, description) in (
        (:vol_crop_bbox, false, "Crops the bounding box of the mask (grown by margin, default 0.1) and resizes it back."),
        (:vol_crop_bbox_largest, true, "Crops the bounding box of the mask's largest component and resizes it back."),
    )
    _define!(op, (:intensity, :binary), _volume_and_mask(op, _crop_kernel(largest), 0.1), description)
end
# Recentring guided by a mask: (operator name, use only the largest component?, description).
for (op, largest, description) in (
        (:vol_recenter, false, "Translates the mask's centroid to the centre of the volume."),
        (:vol_recenter_largest, true, "Translates the largest component's centroid to the centre."),
    )
    _define!(op, (:intensity, :binary), _volume_and_mask(op, _recenter_kernel(largest), 0.0), description)
end

# --- Both bundles: 2D → 3D.
# For each axis, two operators: vol_extrude_<axis>(img2d) and vol_mask2d_<axis>(vol, mask2d),
# e.g. vol_extrude_z and vol_mask2d_z for axis 3.
for (axis, letter) in ((1, :y), (2, :x), (3, :z))
    extrude_op = Symbol(:vol_extrude_, letter)
    _define!(extrude_op, (:intensity, :binary), _plane_to_volume(extrude_op, axis, :extrude),
        "Repeats a 2D image along $letter to fill the volume.")
    mask2d_op = Symbol(:vol_mask2d_, letter)
    _define!(mask2d_op, (:intensity, :binary), _plane_to_volume(mask2d_op, axis, :apply),
        "Applies a 2D mask (binary, or intensity at 0.5) to every slice along $letter.")
end

end
