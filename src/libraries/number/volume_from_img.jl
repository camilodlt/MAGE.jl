"""
Volume → number descriptors for classifying 3D images: shape of the
foreground and of its components, size distribution, and radial, slab and
symmetry profiles of the intensity.

# Bundles

- [`bundle_number_volumeShapeFromImg`](@ref)
- [`bundle_number_volumeGranulometryFromImg`](@ref)
- [`bundle_number_volumeProfileFromImg`](@ref)

Intensity statistics of volumes (quantiles, moments, entropy, Otsu, with ROI
forms) come from `bundle_number_intensityStatsFromImg`, which accepts 2D
images and 3D volumes alike.

The exhaustive, always-current list of operators in each bundle is on the
[Bundle Catalogue](@ref) page.

# How this file is organised

Each descriptor is a *kernel* `compute(fg) -> Float64` on a foreground
`Bool` array (shape, granulometry) or on the voxel values (profiles). The
macro `@_mask_methods` turns a kernel into the public methods (`(mask)`,
`(vol)`, `(vol, threshold)`, `(mask, roi)`), and `_register!` adds them to a
bundle. Unlike image factories, these are plain functions: their output type
is always `Float64`, so nothing needs specialising.

# Example

```julia
using UTCGP, ImageCore
v = zeros(28, 28, 28); v[10:18, 10:18, 10:18] .= 0.8      # a bright cube
vol = SImageND(IntensityPixel{N0f8}.(v))
mask = SImageND(BinaryPixel.(v .> 0.5))

UTCGP.number_volumeFromImg.vshape_fill(mask)        # 729 / 21952 ≈ 0.033
UTCGP.number_volumeFromImg.vshape_extent(vol)       # 1.0: the cube fills its bounding box
UTCGP.number_volumeFromImg.vprof_com_z(vol)         # (14 − 1) / 27 ≈ 0.48: slice 14 of 1…28
```
"""
module number_volumeFromImg

using LinearAlgebra: Symmetric, eigvals
using ..UTCGP: FunctionBundle, append_method!
using ..UTCGP: SImageND, IntensityPixel, BinaryPixel
using ..image2D_object_common: clamp_unit, pixel_value, IsSet, AtLeast, scratch
using ..image3D_volume_common:
    voxel_values,
    voxel_foreground,
    volume_table,
    VolumeTable,
    centroid,
    covariance3,
    volume_holes!,
    volume_distance_map!,
    volume_distance_map_upto!,
    box_extremum!,
    fmin,
    fmax

# Returned by the bundles when no method matches the inputs.
fallback(args...) = return 0.0

"""
    bundle_number_volumeShapeFromImg

Shape of the foreground of a 3D mask.

Whole foreground: `vshape_fill` (voxel fraction), `vshape_sphericity`
(`π^(1/3) (6V)^(2/3) / A`, with `A` the count of exposed voxel faces — a
voxelised ball scores about `0.65`, so compare values with each other),
`vshape_elongation` (`1 − sqrt(λ2/λ1)` of the principal axes),
`vshape_flatness` (`1 − sqrt(λ3/λ2)`), `vshape_extent` (bounding-box fill),
`vshape_components`, `vshape_largest_fraction`, `vshape_cavities`,
`vshape_cavity_fraction`, `vshape_centroid_x/y/z`.

Per component, aggregated: `vobjs_<volume|sphericity|elongation|extent>_<mean|std|min|max|median|cv>`.

Inputs: `(mask)`, `(vol)` thresholded at `0.5`, `(vol, threshold)`;
`(mask, roi)` keeps only the foreground inside a region. Empty → `0.0`.
"""
bundle_number_volumeShapeFromImg = FunctionBundle(fallback)

"""
    bundle_number_volumeGranulometryFromImg

Size distribution of 3D structures.

- `vgran_open_r<k>(mask)`, `k ∈ {1, 2, 3, 4}`: fraction of the foreground
  surviving an opening by a Euclidean ball of radius `k` (exact).
- `vgran_open_bg_r<k>`: the same for the background (narrow gaps).
- `vgran_thickness_mean`, `vgran_thickness_max`: distance from foreground
  voxels to the background, over half the shortest side.
- `vgran_grey_open_r<k>(vol[, roi])`, `vgran_grey_close_r<k>(vol[, roi])`,
  `k ∈ {1, 2}`: share of the intensity (darkness) surviving a grey opening
  (closing) by a `(2k+1)³` cube.

Mask inputs: `(mask)`, `(vol)` at `0.5`, `(vol, threshold)`.

Example: a mask made of thin tubes (radius 1) gives `vgran_open_r2 ≈ 0`,
because a ball of radius 2 fits nowhere; a solid ball of radius 6 keeps
`vgran_open_r2 ≈ 1`.
"""
bundle_number_volumeGranulometryFromImg = FunctionBundle(fallback)

"""
    bundle_number_volumeProfileFromImg

Where the intensity is, relative to the centre and the axes.

- `vprof_shell_inner`, `vprof_shell_middle`, `vprof_shell_outer`: mean
  intensity in the inner, middle and outer third of the radius around the
  volume centre, or around a mask's centroid with `(vol, mask)`;
  `vprof_center_contrast`: inner minus outer.
- `vprof_slab_<a>_low|mid|high`: mean intensity in the first, middle and last
  third along axis `<a>`.
- `vprof_symmetry_<a>`: `1 − mean |v − mirror(v)|` across the middle of axis
  `<a>` (`1` = perfectly symmetric).
- `vprof_com_<a>`, `vprof_spread_<a>`: intensity-weighted centre (normalised)
  and spread along `<a>`.

`<a>` is `x`, `y` or `z`.
"""
bundle_number_volumeProfileFromImg = FunctionBundle(fallback)

# Type aliases matching any size: `S` is the size tuple, `T` the pixel type,
# 3 the number of dimensions, `C` the storage container.
"Any intensity volume (3D image of `IntensityPixel`s)."
const _IntensityVolume = SImageND{S,T,3,C} where {S,T<:IntensityPixel,C}
"Any binary volume (3D mask)."
const _BinaryVolume = SImageND{S,T,3,C} where {S,T<:BinaryPixel,C}

"Whether a region voxel is inside: binary voxels when set, intensity voxels at or above `0.5`."
@inline _roi_in(p::BinaryPixel) = p.pixel == true
@inline _roi_in(p) = Float64(p) >= 0.5

"Restrict the foreground `fg` to the region `roi` (voxel array of the same size), in place."
function _intersect!(fg, roi)
    size(fg) == size(roi) || throw(DimensionMismatch("mask and region must have the same size"))
    @inbounds for i in eachindex(fg, roi)
        fg[i] &= _roi_in(roi[i])            # fg AND inside-region, voxel by voxel
    end
    return fg
end

# ---------------------------------------------------------------------------
# Shape
# ---------------------------------------------------------------------------

"""
Exposed voxel faces of the foreground (faces next to background or the border).

Each voxel is a unit cube with 6 faces; a face is exposed when the voxel on
the other side is background or outside the volume. This approximates the
surface area. Example: a lone voxel has 6 exposed faces, two touching voxels
10 (each loses the face they share), a solid `3³` cube `6 · 9 = 54`.
"""
function _surface(fg::AbstractArray{Bool,3})
    h, w, d = size(fg)                      # rows (y), columns (x), slices (z)
    faces = 0
    @inbounds for s in 1:d, c in 1:w, r in 1:h
        fg[r, c, s] || continue             # only foreground voxels have faces to count
        # Each term is true (1) when that face is exposed. For the face above
        # (r − 1): exposed if the voxel is on the top border (r == 1, no voxel
        # above) or if the voxel above is background. Same for below (r + 1),
        # left/right (c ∓ 1) and previous/next slice (s ∓ 1).
        # `||` short-circuits, so the neighbour is only read when it exists.
        faces += (r == 1 || !fg[r-1, c, s]) + (r == h || !fg[r+1, c, s]) +    # above, below
                 (c == 1 || !fg[r, c-1, s]) + (c == w || !fg[r, c+1, s]) +    # left, right
                 (s == 1 || !fg[r, c, s-1]) + (s == d || !fg[r, c, s+1])      # previous, next slice
    end
    return faces
end

"""
Sphericity `π^(1/3) (6V)^(2/3) / A`: `1` for a perfect sphere, lower for
less compact shapes (`V` voxels, `A` exposed faces; `0` when `A = 0`).

A sphere has the smallest surface for its volume, so the ratio of the
sphere's surface for volume `V` to the actual surface `A` is at most 1.
Because voxel faces overestimate a smooth surface, a voxelised ball scores
about `0.65` rather than `1`: compare values with each other, not with 1.
"""
_sphericity(volume, area) = area == 0 ? 0.0 : clamp(π^(1 / 3) * (6volume)^(2 / 3) / area, 0.0, 1.0)

"""
    _principal_axes(fg) -> (λ, n, mean) or nothing

Principal variances `λ = [λ1 ≥ λ2 ≥ λ3]` (eigenvalues of the covariance
matrix, each variance `+1/12` for the voxel width), voxel count `n` and mean
position `mean = [y, x, z]` of the whole foreground; `nothing` when empty.

`λ1` is the spread along the longest direction of the shape, `λ3` along the
shortest. Example: a rod along x has `λ1` large and `λ2 ≈ λ3` small; a flat
plate has `λ1 ≈ λ2` large and `λ3` small; a ball has all three equal.
"""
function _principal_axes(fg)
    n = 0
    sums = zeros(3)                  # Σ position along each axis
    cross_sums = zeros(3, 3)         # Σ position_a · position_b (upper triangle)
    @inbounds for idx in CartesianIndices(fg)
        fg[idx] || continue
        p = Tuple(idx)               # (y, x, z) of the voxel
        n += 1
        for a in 1:3
            sums[a] += p[a]
            for b in a:3             # only a ≤ b: the matrix is symmetric
                cross_sums[a, b] += p[a] * p[b]
            end
        end
    end
    n == 0 && return nothing
    mean = sums ./ n
    # Covariance C[a, b] = E[p_a p_b] − E[p_a] E[p_b]; the diagonal gets +1/12,
    # the variance of a position spread uniformly over one voxel width.
    C = [(a <= b ? cross_sums[a, b] : cross_sums[b, a]) / n - mean[a] * mean[b] + (a == b ? 1 / 12 : 0.0) for a in 1:3, b in 1:3]
    # Eigenvalues, negatives from rounding clipped to 0, largest first.
    return (λ = sort(max.(eigvals(Symmetric(C)), 0.0); rev = true), n = n, mean = mean)
end

"`1 − sqrt(λ2/λ1)`: `0` when the two longest axes are equal, towards `1` for a needle."
function _elongation(axes)
    axes === nothing && return 0.0          # empty mask
    λ = axes.λ
    return λ[1] <= 0 ? 0.0 : clamp(1 - sqrt(λ[2] / λ[1]), 0.0, 1.0)
end
"`1 − sqrt(λ3/λ2)`: `0` when the two shortest axes are equal, towards `1` for a plate."
function _flatness(axes)
    axes === nothing && return 0.0
    λ = axes.λ
    return λ[2] <= 0 ? 0.0 : clamp(1 - sqrt(λ[3] / λ[2]), 0.0, 1.0)
end

"""
Foreground voxels over the voxels of its bounding box (`0` when empty).

Example: a solid box gives `1`, a ball about `π/6 ≈ 0.52`, a diagonal rod
close to `0`.
"""
function _extent(fg)
    n = count(fg)
    n == 0 && return 0.0
    lo = [typemax(Int), typemax(Int), typemax(Int)]   # smallest index seen along y, x, z
    hi = [0, 0, 0]                                     # largest index seen
    @inbounds for idx in CartesianIndices(fg)
        fg[idx] || continue
        for a in 1:3
            lo[a] = min(lo[a], idx[a]); hi[a] = max(hi[a], idx[a])
        end
    end
    return n / prod(hi .- lo .+ 1)          # box volume = product of its side lengths
end

"""
Normalised position (`0` first, `1` last voxel) of the foreground's centroid along `axis`; `0.5` when empty.

Example: 28 slices, centroid at slice 21 → `(21 − 1) / 27 ≈ 0.74`.
"""
function _centroid_unit(fg, axis)
    axes = _principal_axes(fg)              # also returns the mean position
    axes === nothing && return 0.5
    n_axis = size(fg, axis)
    return n_axis <= 1 ? 0.5 : (axes.mean[axis] - 1) / (n_axis - 1)
end

"""
One value of `descriptor` per 26-connected component: `:volume` (share of
all voxels), `:extent`, `:elongation` or `:sphericity`. Empty when there is
no component.

Example: two components of 100 and 300 voxels in a 28³ volume with
`descriptor = :volume` give `[100, 300] ./ 21952`.
"""
function _component_values(fg, descriptor::Symbol)
    t = volume_table(fg, identity)          # label components; per-component area, box, moments
    t.n == 0 && return Float64[]
    if descriptor === :volume
        return t.area ./ length(fg)
    elseif descriptor === :extent
        # area / bounding-box volume, the box side along k being hi − lo + 1
        return [t.area[i] / prod(t.hi[i, k] - t.lo[i, k] + 1 for k in 1:3) for i in 1:t.n]
    elseif descriptor === :elongation
        # Same formula as `_elongation`, from each component's own covariance matrix.
        return [begin
            λ = sort(max.(eigvals(Symmetric(covariance3(t, i))), 0.0); rev = true)
            λ[1] <= 0 ? 0.0 : clamp(1 - sqrt(λ[2] / λ[1]), 0.0, 1.0)
        end for i in 1:t.n]
    else                                                    # sphericity: exposed faces per component
        faces = zeros(Int, t.n)
        L = t.labels                                        # a face is exposed when the neighbour has another label
        h, w, d = size(L)
        @inbounds for s in 1:d, c in 1:w, r in 1:h
            l = L[r, c, s]                                  # component of this voxel (0 = background)
            l == 0 && continue
            # As in `_surface`, but "exposed" means the neighbour is not in the same
            # component (background, another component, or outside the volume).
            faces[l] += (r == 1 || L[r-1, c, s] != l) + (r == h || L[r+1, c, s] != l) +   # above, below
                        (c == 1 || L[r, c-1, s] != l) + (c == w || L[r, c+1, s] != l) +   # left, right
                        (s == 1 || L[r, c, s-1] != l) + (s == d || L[r, c, s+1] != l)     # previous, next slice
        end
        return [_sphericity(t.area[i], faces[i]) for i in 1:t.n]
    end
end

# Aggregates of per-component values (population standard deviation).
_mean(v) = sum(v) / length(v)
_std(v) = (m = _mean(v); sqrt(sum(x -> (x - m)^2, v) / length(v)))
# Median: middle value of the sorted list, or the mean of the two middle values.
_median(v) = (s = sort(v); n = length(s); isodd(n) ? s[(n + 1) ÷ 2] : (s[n ÷ 2] + s[n ÷ 2 + 1]) / 2)
"""
`(name, reducer)` pairs: each descriptor gets one `vobjs_<descriptor>_<name>` operator per pair; `cv` is std / mean.

Example: `(:max, maximum)` with descriptor `:volume` defines `vobjs_volume_max`,
the share of voxels in the largest component.
"""
const _AGGREGATES = (
    (:mean, _mean), (:std, _std), (:min, minimum), (:max, maximum), (:median, _median),
    (:cv, v -> (m = _mean(v); m == 0 ? 0.0 : _std(v) / m)),    # coefficient of variation; 0 when the mean is 0
)

# ---------------------------------------------------------------------------
# Granulometry
# ---------------------------------------------------------------------------

"""
    _open_fraction(fg, radius, invert) -> Float64

Fraction of the foreground (of the background when `invert`) that survives a
binary opening by a Euclidean ball of `radius` voxels. The opening is done
with two bounded distance maps: erosion keeps the voxels farther than
`radius` from the other phase, dilation keeps the voxels within `radius` of
the eroded set.

An opening keeps exactly the parts of the shape that a ball of that radius
can reach while staying inside. Example with `radius = 2`: a solid ball of
radius 5 survives almost entirely (≈ 1), a tube of radius 1 disappears (0).
"""
function _open_fraction(fg, radius::Int, invert::Bool)
    phase = scratch(:vg_phase, Bool, size(fg)...)       # the set being opened
    other = scratch(:vg_other, Bool, size(fg)...)       # its complement, then reused for the eroded set
    @inbounds for i in eachindex(fg)
        phase[i] = fg[i] != invert                      # fg as is, or its complement when invert
        other[i] = !phase[i]
    end
    n = count(phase)
    n == 0 && return 0.0                                # nothing to open
    any(other) || return 1.0                            # the set fills the volume: nothing is removed
    r2 = Float64(radius^2)                              # distances are squared, so compare with radius²
    D = scratch(:vg_distance, Float64, size(fg)...)
    volume_distance_map_upto!(D, other, radius)         # squared distance to the complement (exact up to radius)
    @inbounds for i in eachindex(D)
        other[i] = phase[i] && D[i] > r2                   # eroded set
    end
    any(other) || return 0.0                                # erosion removed everything
    volume_distance_map_upto!(D, other, radius)             # distance to the eroded set
    survived = 0
    @inbounds for i in eachindex(D)
        survived += phase[i] && D[i] <= r2                  # dilation, restricted to the original set
    end
    return survived / n
end

"""
Mean (`statistic = :mean`) or largest (`:max`) distance from a foreground
voxel to the background, over half the shortest side, clamped to `[0, 1]`.
A volume entirely foreground gives `1`.

Example: in a 28³ volume, a ball of radius 7 has a largest inner distance of
about 6.4 voxels (its centre to the nearest background voxel), so `:max`
gives `6.4 · 2 / 28 ≈ 0.46`.
"""
function _thickness(fg, statistic::Symbol)
    n = count(fg)
    n == 0 && return 0.0
    background = map(!, fg)                                   # Array{Bool}, not a BitArray
    any(background) || return 1.0
    # Squared distance from every voxel to the nearest background voxel.
    D = volume_distance_map!(scratch(:vg_distance, Float64, size(fg)...), background)
    total = 0.0
    largest = 0.0
    @inbounds for i in eachindex(D)
        fg[i] || continue                   # only foreground voxels count
        v = sqrt(D[i])
        total += v
        largest = max(largest, v)
    end
    # Half the shortest side is the largest possible distance, hence × 2 / side.
    return clamp((statistic === :mean ? total / n : largest) * 2 / minimum(size(fg)), 0.0, 1.0)
end

"""
Share of the total intensity surviving a grey opening by a `(2r+1)³` cube
(`closing = false`), or of the total darkness `1 − v` surviving a closing
(`closing = true`). Only voxels inside `roi` count when it is not `nothing`.

A grey opening flattens bright structures smaller than the cube; the share
that survives is high for large bright regions and low for fine bright
texture (and the reverse for dark structures with a closing).
"""
function _grey_fraction(voxels, radius::Int, closing::Bool, roi)
    v = voxel_values(:vg_values, voxels)
    clamp!(v, 0.0, 1.0)
    # Opening = min filter then max filter; closing = max then min.
    first_pass = box_extremum!(scratch(:vg_first, Float64, size(v)...), v, radius, closing ? fmax : fmin)
    result = box_extremum!(scratch(:vg_result, Float64, size(v)...), first_pass, radius, closing ? fmin : fmax)
    before = 0.0                            # total intensity (or darkness) of the input
    after = 0.0                             # same after the opening (closing)
    @inbounds for i in eachindex(v)
        roi === nothing || _roi_in(roi[i]) || continue      # skip voxels outside the region
        before += closing ? 1.0 - v[i] : v[i]
        after += closing ? 1.0 - result[i] : result[i]
    end
    return before <= 0.0 ? 0.0 : clamp(after / before, 0.0, 1.0)
end

# ---------------------------------------------------------------------------
# Profiles
# ---------------------------------------------------------------------------

"""
Mean intensity in three concentric shells around `centre` (`(y, x, z)`):
the inner, middle and outer third of the distance to the farthest corner.

Example: a bright organ in the middle of a dark volume gives
`[high, medium, low]`; a bright rim (like a skull) gives `[low, …, high]`.
"""
function _shells(v, centre)
    dims = size(v)
    # Distance from the centre to the farthest corner: the largest possible radius.
    radius = sqrt(sum(abs2, max.(centre .- 1, dims .- centre)))
    sums = zeros(3)                         # intensity sum per shell
    counts = zeros(Int, 3)                  # voxels per shell
    @inbounds for idx in CartesianIndices(v)
        p = Tuple(idx)
        ρ = sqrt(sum(abs2, p .- centre)) / max(radius, 1e-9)      # relative distance, 0 to 1
        k = clamp(floor(Int, 3ρ) + 1, 1, 3)                       # shell 1, 2 or 3
        sums[k] += v[idx]
        counts[k] += 1
    end
    return [counts[k] == 0 ? 0.0 : sums[k] / counts[k] for k in 1:3]
end

"Centroid `(y, x, z)` of a region (voxel array); the volume centre when it is empty."
function _mask_centre(mask)
    n = 0
    s = (0.0, 0.0, 0.0)                     # Σ positions of the region's voxels
    @inbounds for idx in CartesianIndices(mask)
        _roi_in(mask[idx]) || continue
        n += 1
        s = s .+ Tuple(idx)
    end
    return n == 0 ? (size(mask) .+ 1) ./ 2 : s ./ n
end

"""
Mean intensity in the first (`part = :low`), middle (`:mid`) or last (`:high`) third along `axis`.

Example: 28 slices along z → `third = 9`: low = slices 1–9, mid = 10–19,
high = 20–28.
"""
function _slab(v, axis, part)
    n = size(v, axis)
    third = max(1, n ÷ 3)
    # Index range along `axis` for the requested part (mid takes what is left between).
    range = part === :low ? (1:third) : part === :high ? (n-third+1:n) : (third+1:max(third + 1, n - third))
    total = 0.0
    count = 0
    @inbounds for idx in CartesianIndices(v)
        idx[axis] in range || continue      # voxel outside the slab
        total += v[idx]
        count += 1
    end
    return count == 0 ? 0.0 : total / count
end

"""
`1 − mean |v − mirror(v)|` with the mirror across the middle of `axis`, clamped to `[0, 1]`.

Example: a left–right symmetric brain gives close to `1` along x; a tumour on
one side lowers it.
"""
function _symmetry(v, axis)
    mirrored = reverse(v; dims = axis)      # the volume flipped along `axis`
    return clamp(1.0 - sum(abs.(v .- mirrored)) / length(v), 0.0, 1.0)
end

"""
Intensity-weighted centre along `axis`, normalised to `[0, 1]` (`spread =
false`; `0.5` when the volume is black), or the weighted standard deviation
over the axis length (`spread = true`; `0` when black). Negative values
weigh nothing.

Example along z (28 slices): all the intensity in slice 1 gives centre `0`
and spread `0`; intensity spread evenly gives centre `0.5`.
"""
function _com(v, axis, spread::Bool)
    n = size(v, axis)
    mass = 0.0                                              # Σ weight
    s1 = 0.0                                                # Σ weight · position
    s2 = 0.0                                                # Σ weight · position²
    @inbounds for idx in CartesianIndices(v)
        x = max(v[idx], 0.0)                # the voxel's weight
        p = idx[axis]                       # its position along the axis
        mass += x
        s1 += x * p
        s2 += x * p * p
    end
    mass <= 0 && return spread ? 0.0 : 0.5
    m = s1 / mass                           # weighted mean position
    n <= 1 && return spread ? 0.0 : 0.5
    # spread: sqrt(E[p²] − E[p]²) over the axis length; centre: mean mapped from 1…n to 0…1.
    return spread ? clamp(sqrt(max(s2 / mass - m^2, 0.0)) / (n - 1), 0.0, 1.0) : (m - 1) / (n - 1)
end

# ---------------------------------------------------------------------------
# Registration
# ---------------------------------------------------------------------------

"""
    @_mask_methods name compute

Define the mask-input methods of `name`, each calling `compute(fg)` on a
foreground `Bool` array:

- `name(mask)`: the binary voxels;
- `name(vol)`: an intensity volume at or above `0.5`;
- `name(vol, threshold)`: at or above `threshold`;
- `name(mask, roi)`: the mask restricted to a region (binary, or intensity at `0.5`).

Example: `@_mask_methods vshape_fill (fg -> count(fg) / length(fg))` makes
`vshape_fill(mask)`, `vshape_fill(vol)`, `vshape_fill(vol, 0.3)` and
`vshape_fill(mask, roi)`.
"""
macro _mask_methods(name, compute)
    name, compute = esc(name), esc(compute)             # use the caller's names, not this module's
    return quote
        $name(mask::_BinaryVolume, args...) = $compute(voxel_foreground(:vn_fg, mask.img, IsSet()))
        $name(vol::_IntensityVolume, args...) = $compute(voxel_foreground(:vn_fg, vol.img, AtLeast(0.5)))
        $name(vol::_IntensityVolume, threshold::Number, args...) =
            $compute(voxel_foreground(:vn_fg, vol.img, AtLeast(clamp_unit(threshold))))
        $name(mask::_BinaryVolume, roi::Union{_BinaryVolume,_IntensityVolume}, args...) =
            $compute(_intersect!(voxel_foreground(:vn_fg, mask.img, IsSet()), roi.img))
    end
end

"Attach `doc` to the function `name` and register it in `bundle`."
function _register!(bundle, name::Symbol, description::String, doc::String)
    @eval @doc $doc $name
    append_method!(bundle, getfield(@__MODULE__, name), name; description = description)
end

"Docstring of an operator defined by `@_mask_methods`."
_mask_doc(name, what) = """
    $name(mask, args...)
    $name(vol, [threshold], args...)
    $name(mask, roi, args...)

$what Intensity volumes are thresholded at `threshold` (default `0.5`); with
`roi`, only the foreground inside it counts. Empty → `0.0`.
"""

# --- Shape of the whole foreground.
#
# Each entry is (operator name, compute(fg) -> Float64, description); every
# entry becomes the four methods of `@_mask_methods`.
const _SHAPE = bundle_number_volumeShapeFromImg
for (name, compute, what) in (
        (:vshape_fill, fg -> count(fg) / length(fg), "Fraction of voxels in the foreground."),
        (:vshape_sphericity, fg -> _sphericity(count(fg), _surface(fg)), "Sphericity π^(1/3)(6V)^(2/3)/A of the foreground (voxel-face surface)."),
        (:vshape_elongation, fg -> _elongation(_principal_axes(fg)), "1 − sqrt(λ2/λ1) of the foreground's principal axes."),
        (:vshape_flatness, fg -> _flatness(_principal_axes(fg)), "1 − sqrt(λ3/λ2) of the foreground's principal axes."),
        (:vshape_extent, fg -> _extent(fg), "Foreground voxels over bounding-box voxels."),
        (:vshape_components, fg -> Float64(volume_table(fg, identity).n), "Number of 26-connected components."),
        # largest component's voxels / all foreground voxels
        (:vshape_largest_fraction, fg -> (t = volume_table(fg, identity); t.n == 0 ? 0.0 : maximum(t.area) / sum(t.area)), "Share of the foreground in its largest component."),
        # volume_holes!(nothing, fg) only counts: it returns (number of cavities, cavity voxels)
        (:vshape_cavities, fg -> Float64(volume_holes!(nothing, fg)[1]), "Number of enclosed cavities."),
        (:vshape_cavity_fraction, fg -> (n = count(fg); n == 0 ? 0.0 : (c = volume_holes!(nothing, fg)[2]; c / (n + c))), "Cavity voxels over filled foreground voxels."),
        (:vshape_centroid_y, fg -> _centroid_unit(fg, 1), "Normalised y of the foreground's centroid (0.5 when empty)."),
        (:vshape_centroid_x, fg -> _centroid_unit(fg, 2), "Normalised x of the foreground's centroid (0.5 when empty)."),
        (:vshape_centroid_z, fg -> _centroid_unit(fg, 3), "Normalised z of the foreground's centroid (0.5 when empty)."),
    )
    @eval @_mask_methods $name $compute
    _register!(_SHAPE, name, what, _mask_doc(name, what))
end
# --- Per-component descriptors, aggregated: every (descriptor, aggregate) pair,
# e.g. vobjs_volume_mean, vobjs_volume_std, …, vobjs_extent_cv (4 × 6 operators).
for descriptor in (:volume, :sphericity, :elongation, :extent), (aggregate, reducer) in _AGGREGATES
    name = Symbol(:vobjs_, descriptor, :_, aggregate)
    # One value per component, then reduced to a number; 0 when there is no component.
    compute = fg -> (values = _component_values(fg, descriptor); isempty(values) ? 0.0 : Float64(reducer(values)))
    @eval @_mask_methods $name $compute
    what = "The $aggregate of the components' $descriptor."
    _register!(_SHAPE, name, what, _mask_doc(name, what))
end

# --- Granulometry.
const _GRAN = bundle_number_volumeGranulometryFromImg
# Binary openings by a ball of each radius, of the foreground (vgran_open_r<k>)
# and of the background (vgran_open_bg_r<k>).
for radius in (1, 2, 3, 4)
    name = Symbol(:vgran_open_r, radius)
    compute = fg -> _open_fraction(fg, radius, false)
    @eval @_mask_methods $name $compute
    what = "Fraction of the foreground surviving an opening by a ball of radius $radius."
    _register!(_GRAN, name, what, _mask_doc(name, what))
    name = Symbol(:vgran_open_bg_r, radius)
    compute = fg -> _open_fraction(fg, radius, true)
    @eval @_mask_methods $name $compute
    what = "Fraction of the background surviving an opening by a ball of radius $radius."
    _register!(_GRAN, name, what, _mask_doc(name, what))
end
# Thickness: (operator name, statistic passed to _thickness, description).
for (name, statistic, what) in ((:vgran_thickness_mean, :mean, "Mean distance from foreground voxels to the background, over half the shortest side."),
                                (:vgran_thickness_max, :max, "Largest distance from a foreground voxel to the background, over half the shortest side."))
    compute = fg -> _thickness(fg, statistic)
    @eval @_mask_methods $name $compute
    _register!(_GRAN, name, what, _mask_doc(name, what))
end
# Grey openings / closings: for each cube radius, (name stem, closing?, wording),
# e.g. vgran_grey_open_r1 and vgran_grey_close_r1. These take an intensity volume
# (and optionally a region), not a mask, so they are defined by hand.
for radius in (1, 2), (stem, closing, what) in ((:vgran_grey_open_r, false, "intensity surviving a grey opening"),
                                               (:vgran_grey_close_r, true, "darkness surviving a grey closing"))
    name = Symbol(stem, radius)
    @eval begin
        $name(vol::_IntensityVolume, args...) = _grey_fraction(vol.img, $radius, $closing, nothing)
        function $name(vol::_IntensityVolume, roi::Union{_BinaryVolume,_IntensityVolume}, args...)
            size(vol) == size(roi) || throw(DimensionMismatch("volume and region must have the same size"))
            return _grey_fraction(vol.img, $radius, $closing, roi.img)
        end
    end
    side = 2radius + 1                      # cube side: 3 or 5 voxels
    _register!(_GRAN, name, "Share of the $what with a $(side)³ cube.", """
        $name(vol, [roi], args...)

    Share of the total $what with a $(side)×$(side)×$(side) cube (only inside
    `roi` when given).
    """)
end

# --- Profiles (intensity volumes only).
const _PROF = bundle_number_volumeProfileFromImg
# Shells: (index of the shell in _shells' result, operator name, wording).
for (k, name, what) in ((1, :vprof_shell_inner, "inner"), (2, :vprof_shell_middle, "middle"), (3, :vprof_shell_outer, "outer"))
    @eval begin
        # Around the volume centre ((n + 1) / 2 along each axis).
        $name(vol::_IntensityVolume, args...) = (v = voxel_values(:vp_values, vol.img); _shells(v, (size(v) .+ 1) ./ 2)[$k])
        # Around the centroid of a mask.
        function $name(vol::_IntensityVolume, mask::Union{_BinaryVolume,_IntensityVolume}, args...)
            size(vol) == size(mask) || throw(DimensionMismatch("volume and mask must have the same size"))
            return _shells(voxel_values(:vp_values, vol.img), _mask_centre(mask.img))[$k]
        end
    end
    _register!(_PROF, name, "Mean intensity in the $what third of the radius around the centre.", """
        $name(vol, [mask], args...)

    Mean intensity in the $what third of the radius around the volume centre,
    or around the centroid of `mask`.
    """)
end
# Inner shell minus outer shell: positive when the centre is brighter than the rim.
vprof_center_contrast(vol::_IntensityVolume, args...) = (s = _shells(voxel_values(:vp_values, vol.img), (size(vol) .+ 1) ./ 2); s[1] - s[3])
function vprof_center_contrast(vol::_IntensityVolume, mask::Union{_BinaryVolume,_IntensityVolume}, args...)
    size(vol) == size(mask) || throw(DimensionMismatch("volume and mask must have the same size"))
    s = _shells(voxel_values(:vp_values, vol.img), _mask_centre(mask.img))
    return s[1] - s[3]
end
_register!(_PROF, :vprof_center_contrast, "Inner-shell minus outer-shell mean intensity.", """
    vprof_center_contrast(vol, [mask], args...)

`vprof_shell_inner − vprof_shell_outer`.
""")
# Per axis: slabs (vprof_slab_<a>_low|mid|high), symmetry (vprof_symmetry_<a>),
# weighted centre and spread (vprof_com_<a>, vprof_spread_<a>).
for (axis, letter) in ((1, :y), (2, :x), (3, :z))
    for part in (:low, :mid, :high)
        name = Symbol(:vprof_slab_, letter, :_, part)
        # QuoteNode keeps `part` a Symbol inside the generated code (not a variable name).
        @eval $name(vol::_IntensityVolume, args...) = _slab(voxel_values(:vp_values, vol.img), $axis, $(QuoteNode(part)))
        _register!(_PROF, name, "Mean intensity in the $part third along $letter.", """
            $name(vol, args...)

        Mean intensity in the $part third of the volume along $letter.
        """)
    end
    name = Symbol(:vprof_symmetry_, letter)
    @eval $name(vol::_IntensityVolume, args...) = _symmetry(voxel_values(:vp_values, vol.img), $axis)
    _register!(_PROF, name, "Mirror symmetry across the middle of $letter.", """
        $name(vol, args...)

    `1 − mean |v − mirror(v)|` with the mirror across the middle of $letter:
    `1` for a perfectly symmetric volume.
    """)
    # (name stem, spread? passed to _com, wording)
    for (stem, spread, what) in ((:vprof_com_, false, "intensity-weighted centre"), (:vprof_spread_, true, "intensity-weighted spread"))
        name = Symbol(stem, letter)
        @eval $name(vol::_IntensityVolume, args...) = _com(voxel_values(:vp_values, vol.img), $axis, $spread)
        _register!(_PROF, name, "Normalised $what along $letter.", """
            $name(vol, args...)

        Normalised $what along $letter.
        """)
    end
end

end
