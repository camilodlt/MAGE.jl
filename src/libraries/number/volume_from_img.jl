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
        fg[i] &= _roi_in(roi[i])
    end
    return fg
end

# ---------------------------------------------------------------------------
# Shape
# ---------------------------------------------------------------------------

"Exposed voxel faces of the foreground (faces next to background or the border)."
function _surface(fg::AbstractArray{Bool,3})
    h, w, d = size(fg)
    faces = 0
    @inbounds for s in 1:d, c in 1:w, r in 1:h
        fg[r, c, s] || continue
        faces += (r == 1 || !fg[r-1, c, s]) + (r == h || !fg[r+1, c, s]) +
                 (c == 1 || !fg[r, c-1, s]) + (c == w || !fg[r, c+1, s]) +
                 (s == 1 || !fg[r, c, s-1]) + (s == d || !fg[r, c, s+1])
    end
    return faces
end

"""
Sphericity `π^(1/3) (6V)^(2/3) / A`: `1` for a perfect sphere, lower for
less compact shapes (`V` voxels, `A` exposed faces; `0` when `A = 0`).
"""
_sphericity(volume, area) = area == 0 ? 0.0 : clamp(π^(1 / 3) * (6volume)^(2 / 3) / area, 0.0, 1.0)

"""
    _principal_axes(fg) -> (λ, n, mean) or nothing

Principal variances `λ = [λ1 ≥ λ2 ≥ λ3]` (eigenvalues of the covariance
matrix, each variance `+1/12` for the voxel width), voxel count `n` and mean
position `mean = [y, x, z]` of the whole foreground; `nothing` when empty.
"""
function _principal_axes(fg)
    n = 0
    sums = zeros(3)                  # Σ position along each axis
    cross_sums = zeros(3, 3)         # Σ position_a · position_b (upper triangle)
    @inbounds for idx in CartesianIndices(fg)
        fg[idx] || continue
        p = Tuple(idx)
        n += 1
        for a in 1:3
            sums[a] += p[a]
            for b in a:3
                cross_sums[a, b] += p[a] * p[b]
            end
        end
    end
    n == 0 && return nothing
    mean = sums ./ n
    C = [(a <= b ? cross_sums[a, b] : cross_sums[b, a]) / n - mean[a] * mean[b] + (a == b ? 1 / 12 : 0.0) for a in 1:3, b in 1:3]
    return (λ = sort(max.(eigvals(Symmetric(C)), 0.0); rev = true), n = n, mean = mean)
end

"`1 − sqrt(λ2/λ1)`: `0` when the two longest axes are equal, towards `1` for a needle."
function _elongation(axes)
    axes === nothing && return 0.0
    λ = axes.λ
    return λ[1] <= 0 ? 0.0 : clamp(1 - sqrt(λ[2] / λ[1]), 0.0, 1.0)
end
"`1 − sqrt(λ3/λ2)`: `0` when the two shortest axes are equal, towards `1` for a plate."
function _flatness(axes)
    axes === nothing && return 0.0
    λ = axes.λ
    return λ[2] <= 0 ? 0.0 : clamp(1 - sqrt(λ[3] / λ[2]), 0.0, 1.0)
end

"Foreground voxels over the voxels of its bounding box (`0` when empty)."
function _extent(fg)
    n = count(fg)
    n == 0 && return 0.0
    lo = [typemax(Int), typemax(Int), typemax(Int)]
    hi = [0, 0, 0]
    @inbounds for idx in CartesianIndices(fg)
        fg[idx] || continue
        for a in 1:3
            lo[a] = min(lo[a], idx[a]); hi[a] = max(hi[a], idx[a])
        end
    end
    return n / prod(hi .- lo .+ 1)
end

"Normalised position (`0` first, `1` last voxel) of the foreground's centroid along `axis`; `0.5` when empty."
function _centroid_unit(fg, axis)
    axes = _principal_axes(fg)
    axes === nothing && return 0.5
    n_axis = size(fg, axis)
    return n_axis <= 1 ? 0.5 : (axes.mean[axis] - 1) / (n_axis - 1)
end

"""
One value of `descriptor` per 26-connected component: `:volume` (share of
all voxels), `:extent`, `:elongation` or `:sphericity`. Empty when there is
no component.
"""
function _component_values(fg, descriptor::Symbol)
    t = volume_table(fg, identity)
    t.n == 0 && return Float64[]
    if descriptor === :volume
        return t.area ./ length(fg)
    elseif descriptor === :extent
        return [t.area[i] / prod(t.hi[i, k] - t.lo[i, k] + 1 for k in 1:3) for i in 1:t.n]
    elseif descriptor === :elongation
        return [begin
            λ = sort(max.(eigvals(Symmetric(covariance3(t, i))), 0.0); rev = true)
            λ[1] <= 0 ? 0.0 : clamp(1 - sqrt(λ[2] / λ[1]), 0.0, 1.0)
        end for i in 1:t.n]
    else                                                    # sphericity: exposed faces per component
        faces = zeros(Int, t.n)
        L = t.labels                                        # a face is exposed when the neighbour has another label
        h, w, d = size(L)
        @inbounds for s in 1:d, c in 1:w, r in 1:h
            l = L[r, c, s]
            l == 0 && continue
            faces[l] += (r == 1 || L[r-1, c, s] != l) + (r == h || L[r+1, c, s] != l) +
                        (c == 1 || L[r, c-1, s] != l) + (c == w || L[r, c+1, s] != l) +
                        (s == 1 || L[r, c, s-1] != l) + (s == d || L[r, c, s+1] != l)
        end
        return [_sphericity(t.area[i], faces[i]) for i in 1:t.n]
    end
end

# Aggregates of per-component values (population standard deviation).
_mean(v) = sum(v) / length(v)
_std(v) = (m = _mean(v); sqrt(sum(x -> (x - m)^2, v) / length(v)))
_median(v) = (s = sort(v); n = length(s); isodd(n) ? s[(n + 1) ÷ 2] : (s[n ÷ 2] + s[n ÷ 2 + 1]) / 2)
"`(name, reducer)` pairs: each descriptor gets one `vobjs_<descriptor>_<name>` operator per pair; `cv` is std / mean."
const _AGGREGATES = (
    (:mean, _mean), (:std, _std), (:min, minimum), (:max, maximum), (:median, _median),
    (:cv, v -> (m = _mean(v); m == 0 ? 0.0 : _std(v) / m)),
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
"""
function _open_fraction(fg, radius::Int, invert::Bool)
    phase = scratch(:vg_phase, Bool, size(fg)...)       # the set being opened
    other = scratch(:vg_other, Bool, size(fg)...)       # its complement, then reused for the eroded set
    @inbounds for i in eachindex(fg)
        phase[i] = fg[i] != invert
        other[i] = !phase[i]
    end
    n = count(phase)
    n == 0 && return 0.0
    any(other) || return 1.0
    r2 = Float64(radius^2)
    D = scratch(:vg_distance, Float64, size(fg)...)
    volume_distance_map_upto!(D, other, radius)
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
"""
function _thickness(fg, statistic::Symbol)
    n = count(fg)
    n == 0 && return 0.0
    background = map(!, fg)                                   # Array{Bool}, not a BitArray
    any(background) || return 1.0
    D = volume_distance_map!(scratch(:vg_distance, Float64, size(fg)...), background)
    total = 0.0
    largest = 0.0
    @inbounds for i in eachindex(D)
        fg[i] || continue
        v = sqrt(D[i])
        total += v
        largest = max(largest, v)
    end
    return clamp((statistic === :mean ? total / n : largest) * 2 / minimum(size(fg)), 0.0, 1.0)
end

"""
Share of the total intensity surviving a grey opening by a `(2r+1)³` cube
(`closing = false`), or of the total darkness `1 − v` surviving a closing
(`closing = true`). Only voxels inside `roi` count when it is not `nothing`.
"""
function _grey_fraction(voxels, radius::Int, closing::Bool, roi)
    v = voxel_values(:vg_values, voxels)
    clamp!(v, 0.0, 1.0)
    first_pass = box_extremum!(scratch(:vg_first, Float64, size(v)...), v, radius, closing ? fmax : fmin)
    result = box_extremum!(scratch(:vg_result, Float64, size(v)...), first_pass, radius, closing ? fmin : fmax)
    before = 0.0
    after = 0.0
    @inbounds for i in eachindex(v)
        roi === nothing || _roi_in(roi[i]) || continue
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
"""
function _shells(v, centre)
    dims = size(v)
    radius = sqrt(sum(abs2, max.(centre .- 1, dims .- centre)))
    sums = zeros(3)
    counts = zeros(Int, 3)
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
    s = (0.0, 0.0, 0.0)
    @inbounds for idx in CartesianIndices(mask)
        _roi_in(mask[idx]) || continue
        n += 1
        s = s .+ Tuple(idx)
    end
    return n == 0 ? (size(mask) .+ 1) ./ 2 : s ./ n
end

"Mean intensity in the first (`part = :low`), middle (`:mid`) or last (`:high`) third along `axis`."
function _slab(v, axis, part)
    n = size(v, axis)
    third = max(1, n ÷ 3)
    range = part === :low ? (1:third) : part === :high ? (n-third+1:n) : (third+1:max(third + 1, n - third))
    total = 0.0
    count = 0
    @inbounds for idx in CartesianIndices(v)
        idx[axis] in range || continue
        total += v[idx]
        count += 1
    end
    return count == 0 ? 0.0 : total / count
end

"`1 − mean |v − mirror(v)|` with the mirror across the middle of `axis`, clamped to `[0, 1]`."
function _symmetry(v, axis)
    mirrored = reverse(v; dims = axis)
    return clamp(1.0 - sum(abs.(v .- mirrored)) / length(v), 0.0, 1.0)
end

"""
Intensity-weighted centre along `axis`, normalised to `[0, 1]` (`spread =
false`; `0.5` when the volume is black), or the weighted standard deviation
over the axis length (`spread = true`; `0` when black). Negative values
weigh nothing.
"""
function _com(v, axis, spread::Bool)
    n = size(v, axis)
    mass = 0.0
    s1 = 0.0                                                # Σ weight · position
    s2 = 0.0                                                # Σ weight · position²
    @inbounds for idx in CartesianIndices(v)
        x = max(v[idx], 0.0)
        p = idx[axis]
        mass += x
        s1 += x * p
        s2 += x * p * p
    end
    mass <= 0 && return spread ? 0.0 : 0.5
    m = s1 / mass
    n <= 1 && return spread ? 0.0 : 0.5
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
"""
macro _mask_methods(name, compute)
    name, compute = esc(name), esc(compute)
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

const _SHAPE = bundle_number_volumeShapeFromImg
for (name, compute, what) in (
        (:vshape_fill, fg -> count(fg) / length(fg), "Fraction of voxels in the foreground."),
        (:vshape_sphericity, fg -> _sphericity(count(fg), _surface(fg)), "Sphericity π^(1/3)(6V)^(2/3)/A of the foreground (voxel-face surface)."),
        (:vshape_elongation, fg -> _elongation(_principal_axes(fg)), "1 − sqrt(λ2/λ1) of the foreground's principal axes."),
        (:vshape_flatness, fg -> _flatness(_principal_axes(fg)), "1 − sqrt(λ3/λ2) of the foreground's principal axes."),
        (:vshape_extent, fg -> _extent(fg), "Foreground voxels over bounding-box voxels."),
        (:vshape_components, fg -> Float64(volume_table(fg, identity).n), "Number of 26-connected components."),
        (:vshape_largest_fraction, fg -> (t = volume_table(fg, identity); t.n == 0 ? 0.0 : maximum(t.area) / sum(t.area)), "Share of the foreground in its largest component."),
        (:vshape_cavities, fg -> Float64(volume_holes!(nothing, fg)[1]), "Number of enclosed cavities."),
        (:vshape_cavity_fraction, fg -> (n = count(fg); n == 0 ? 0.0 : (c = volume_holes!(nothing, fg)[2]; c / (n + c))), "Cavity voxels over filled foreground voxels."),
        (:vshape_centroid_y, fg -> _centroid_unit(fg, 1), "Normalised y of the foreground's centroid (0.5 when empty)."),
        (:vshape_centroid_x, fg -> _centroid_unit(fg, 2), "Normalised x of the foreground's centroid (0.5 when empty)."),
        (:vshape_centroid_z, fg -> _centroid_unit(fg, 3), "Normalised z of the foreground's centroid (0.5 when empty)."),
    )
    @eval @_mask_methods $name $compute
    _register!(_SHAPE, name, what, _mask_doc(name, what))
end
for descriptor in (:volume, :sphericity, :elongation, :extent), (aggregate, reducer) in _AGGREGATES
    name = Symbol(:vobjs_, descriptor, :_, aggregate)
    compute = fg -> (values = _component_values(fg, descriptor); isempty(values) ? 0.0 : Float64(reducer(values)))
    @eval @_mask_methods $name $compute
    what = "The $aggregate of the components' $descriptor."
    _register!(_SHAPE, name, what, _mask_doc(name, what))
end

const _GRAN = bundle_number_volumeGranulometryFromImg
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
for (name, statistic, what) in ((:vgran_thickness_mean, :mean, "Mean distance from foreground voxels to the background, over half the shortest side."),
                                (:vgran_thickness_max, :max, "Largest distance from a foreground voxel to the background, over half the shortest side."))
    compute = fg -> _thickness(fg, statistic)
    @eval @_mask_methods $name $compute
    _register!(_GRAN, name, what, _mask_doc(name, what))
end
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
    side = 2radius + 1
    _register!(_GRAN, name, "Share of the $what with a $(side)³ cube.", """
        $name(vol, [roi], args...)

    Share of the total $what with a $(side)×$(side)×$(side) cube (only inside
    `roi` when given).
    """)
end

const _PROF = bundle_number_volumeProfileFromImg
for (k, name, what) in ((1, :vprof_shell_inner, "inner"), (2, :vprof_shell_middle, "middle"), (3, :vprof_shell_outer, "outer"))
    @eval begin
        $name(vol::_IntensityVolume, args...) = (v = voxel_values(:vp_values, vol.img); _shells(v, (size(v) .+ 1) ./ 2)[$k])
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
for (axis, letter) in ((1, :y), (2, :x), (3, :z))
    for part in (:low, :mid, :high)
        name = Symbol(:vprof_slab_, letter, :_, part)
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
