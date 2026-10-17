"""
Shared orientation machinery: Sobel derivatives, gradient and edge
orientations, and the four-bin orientation energies.

# Angle conventions

Rows grow downwards, so angles are measured from the `+x` axis (pointing
right) **clockwise on screen**, in `[0, π)` (an orientation has no head or
tail). `0` is horizontal, `π/4` is a `\\` diagonal (going down to the right),
`π/2` vertical, `3π/4` a `/` diagonal.

Two different angles are used, 90° apart:

- the **gradient orientation** is the direction in which the intensity
  changes fastest, perpendicular to an edge: a vertical edge (dark left,
  bright right) has gradient orientation `0`. Used by `grad_orientation` and
  `orientation_select`.
- the **edge (structure) orientation** is the direction along the edge: the
  same vertical edge has edge orientation `π/2`. Used by the scalar summaries
  (`orientation_energy_*`, `dominant_orientation`, `orientation_coherence`).
"""
module image2D_orientation_common

using ImageFiltering: Kernel, reflect, imfilter!
using ImageCore: RGB
using ..UTCGP: SImageND, scratch, pixel_values!

const _YSOBEL, _XSOBEL = reflect.(Kernel.sobel())

"Derivatives smaller than this are floating-point noise from the filter on flat areas (around 1e-17), not edges."
const _FLAT = 1e-12

"""
Sobel derivatives `(gx, gy)` along columns (x) and rows (y). Their signs are
flipped by the kernel convention, which does not affect magnitudes or
orientations modulo π. Noise-level values (below `_FLAT`) are set to `0`, so
flat pixels have no magnitude and orientation `0` instead of a random angle.
"""
function _sobel_xy(from::SImageND)
    img = Float64.(reinterpret(from.img))
    return _sobel_xy!(similar(img), similar(img), img)
end

"""
    _sobel_xy!(gx, gy, values) -> (gx, gy)

As `_sobel_xy`, from the image's values (`Float64` matrix), writing the
derivatives into `gx` and `gy` (same size) instead of allocating them.
"""
function _sobel_xy!(gx, gy, values)
    imfilter!(gx, values, _XSOBEL, "replicate")
    imfilter!(gy, values, _YSOBEL, "replicate")
    _zero_flat!(gx)
    _zero_flat!(gy)
    return gx, gy
end

"Set the noise-level derivatives (`|x| < _FLAT`) to `0`."
_zero_flat!(derivative) = (derivative .= ifelse.(abs.(derivative) .< _FLAT, 0.0, derivative); derivative)

"Gradient magnitude `sqrt(gx² + gy²)` (and `gx`, `gy`)."
function _grad_magnitude_matrix(from::SImageND)
    gx, gy = _sobel_xy(from)
    return sqrt.(gx .^ 2 .+ gy .^ 2), gx, gy
end

"Gradient orientation in `[0, π)` per pixel (flat pixels get `0`), with `gx`, `gy`."
function _gradient_orientation_matrix(from::SImageND)
    _, gx, gy = _grad_magnitude_matrix(from)
    theta = atan.(gy, gx)
    return mod.(theta .+ π, π), gx, gy
end

"Edge (structure) orientation: the gradient orientation turned by 90°, in `[0, π)`."
function _structure_orientation_matrix(from::SImageND)
    grad_theta, gx, gy = _gradient_orientation_matrix(from)
    return mod.(grad_theta .+ (π / 2), π), gx, gy
end

function _normalize01(x::AbstractMatrix)
    minv = minimum(x)
    maxv = maximum(x)
    maxv == minv && return zeros(Float64, size(x))
    return (x .- minv) ./ (maxv - minv)
end

function _angle_distance(a::AbstractMatrix, theta::Real)
    d = abs.(a .- theta)
    return min.(d, π .- d)
end

"Centres of the four orientation bins: horizontal, `\\`, vertical, `/` (clockwise convention)."
const _ORIENTATION_CENTERS = (0.0, π / 4, π / 2, 3π / 4)

"""
Magnitude and edge orientation from a single Sobel pass (the same arithmetic
as `_grad_magnitude_matrix` and `_structure_orientation_matrix`).
"""
function _magnitude_and_edge_orientation(from::SImageND)
    gx, gy = _sobel_xy(from)
    mag = sqrt.(gx .^ 2 .+ gy .^ 2)
    grad_theta = mod.(atan.(gy, gx) .+ π, π)
    return mag, mod.(grad_theta .+ (π / 2), π)
end

"""
Share of the total gradient magnitude in each of the four edge-orientation
bins (nearest bin centre). Example: an image of vertical stripes puts all its
energy in bin 3 (`[0, 0, 1, 0]`).
"""
function _orientation_energy_proportions(from::SImageND)
    mag, theta = _magnitude_and_edge_orientation(from)
    total = sum(mag)
    total == 0 && return zeros(Float64, 4)

    energies = zeros(Float64, 4)
    @inbounds for idx in eachindex(theta)
        t = theta[idx]
        nearest = 1
        nearest_dist = min(abs(t - _ORIENTATION_CENTERS[1]), π - abs(t - _ORIENTATION_CENTERS[1]))
        for k in 2:4
            dist = min(abs(t - _ORIENTATION_CENTERS[k]), π - abs(t - _ORIENTATION_CENTERS[k]))
            if dist < nearest_dist
                nearest = k
                nearest_dist = dist
            end
        end
        energies[nearest] += mag[idx]
    end
    return energies ./ total
end

# Scalar summaries (orientation_energy_*, dominant_orientation, orientation_coherence/spread):
#
#   _scalar_energy_proportions(from) / _orientation_coherence_value(from)
#   ├── _scalar_gradients(from)            values, gx, gy in task scratch
#   │   ├── pixel_values!(values, from.img)
#   │   └── _sobel_xy!(gx, gy, values)      public imfilter!, as the image operators
#   └── _scalar_energies! / _scalar_coherence!   one fused pass per pixel, then Base.sum
#
# Results are identical to the original: the derivatives are the same imfilter!
# calls, per-bin sums run in the same linear order, and totals use the same
# pairwise `sum` over a matrix (a scratch matrix instead of a new one).
# Images whose pixels are not stored in a plain Matrix keep the original path.

"""
    _scalar_gradients(from) -> (gx, gy, work)

The Sobel derivatives of a 2D image in task scratch, plus a third scratch matrix
(`work`, holding the image values on return) that the reductions may overwrite.

Example: a constant image gives `gx` and `gy` all zero.
"""
function _scalar_gradients(from::SImageND)
    dims = size(from.img)
    values = pixel_values!(scratch(:scalar_orientation_values, Float64, dims...), from.img)
    gx = scratch(:scalar_orientation_gx, Float64, dims...)
    gy = scratch(:scalar_orientation_gy, Float64, dims...)
    # TODO speed: imfilter! pads its input into a new array on every call (about
    # 0.4 MB per derivative at 224×224); nothing public avoids it.
    _sobel_xy!(gx, gy, values)
    return gx, gy, values
end

"""
    _scalar_energy_proportions(from) -> NTuple{4,Float64}

Share of the total gradient magnitude in each edge-orientation bin
(horizontal, `\\`, vertical, `/`), as `_orientation_energy_proportions` but without
allocating. Example: vertical stripes give `(0.0, 0.0, 1.0, 0.0)`.
"""
_scalar_energy_proportions(from::SImageND{S,T,2,<:Matrix}) where {S,T} = _scalar_energies!(_scalar_gradients(from)...)
_scalar_energy_proportions(from::SImageND) = Tuple(_orientation_energy_proportions(from))

"""
    _scalar_energies!(gx, gy, work) -> four shares

Accumulate bins in the original linear order, and reduce the magnitude
matrix with the original sum. Zero derivatives give (0.0, 0.0, 0.0, 0.0).
"""
function _scalar_energies!(gx, gy, work)
    e1 = e2 = e3 = e4 = 0.0
    @inbounds for i in eachindex(gx, gy, work)
        magnitude = sqrt(gx[i]^2 + gy[i]^2)
        theta = mod(mod(atan(gy[i], gx[i]) + π, π) + (π / 2), π)
        bin = _nearest_orientation_bin(theta)
        work[i] = magnitude
        if bin == 1
            e1 += magnitude
        elseif bin == 2
            e2 += magnitude
        elseif bin == 3
            e3 += magnitude
        else
            e4 += magnitude
        end
    end
    total = sum(work)
    total == 0 && return (0.0, 0.0, 0.0, 0.0)
    return (e1 / total, e2 / total, e3 / total, e4 / total)
end

"Centre of the strongest bin (vertical stripes give 0.5) over `π`: `0` horizontal, `0.25` `\\`, `0.5` vertical, `0.75` `/`."
function _dominant_orientation_value(from::SImageND)
    energies = _scalar_energy_proportions(from)
    return _ORIENTATION_CENTERS[argmax(energies)] / π
end

"""
Length of the magnitude-weighted mean of the doubled edge angles, over the
total magnitude: `1` when every edge has the same orientation, near `0` when
orientations are spread evenly. For example, vertical stripes give 1.0.
(Doubling makes `θ` and `θ + π` agree.)
"""
_orientation_coherence_value(from::SImageND{S,T,2,<:Matrix}) where {S,T} = _scalar_coherence!(_scalar_gradients(from)...)
_orientation_coherence_value(from::SImageND) = _orientation_coherence_from_arrays(_magnitude_and_edge_orientation(from)...)

"""
    _orientation_coherence_from_arrays(magnitude, theta) -> Float64

Original array reductions for storage outside the scratch path. Example:
a 2×2 matrix of unit magnitudes and zero angles has coherence 1.0.
"""
function _orientation_coherence_from_arrays(magnitude, theta)
    total = sum(magnitude)
    total == 0 && return 0.0
    c = sum(magnitude .* cos.(2 .* theta))
    s = sum(magnitude .* sin.(2 .* theta))
    return sqrt(c^2 + s^2) / total
end

"""
    _scalar_coherence!(gx, gy, work) -> Float64

Reuse derivatives for the magnitude and angle, then the reduction workspace
for each weighted trigonometric product. Parallel edges give 1.0.
"""
function _scalar_coherence!(gx, gy, work)
    @inbounds for i in eachindex(gx, gy, work)
        x, y = gx[i], gy[i]
        gx[i] = sqrt(x^2 + y^2)
        gy[i] = mod(mod(atan(y, x) + π, π) + (π / 2), π)
    end
    total = sum(gx)
    total == 0 && return 0.0
    @inbounds for i in eachindex(work, gx, gy)
        work[i] = gx[i] * cos(2 * gy[i])
    end
    c = sum(work)
    @inbounds for i in eachindex(work, gx, gy)
        work[i] = gx[i] * sin(2 * gy[i])
    end
    s = sum(work)
    return sqrt(c^2 + s^2) / total
end

_orientation_spread_value(from::SImageND) = 1.0 - _orientation_coherence_value(from)

function _draw_point!(canvas::AbstractMatrix{<:RGB}, r::Int, c::Int, color)
    if 1 <= r <= size(canvas, 1) && 1 <= c <= size(canvas, 2)
        canvas[r, c] = color
    end
    return canvas
end

function _orientation_stencil_coords(bin::Int)
    if bin == 1
        return ((2, 1), (2, 2), (2, 3)) # 0°
    elseif bin == 2
        return ((1, 1), (2, 2), (3, 3)) # 45° in image coordinates
    elseif bin == 3
        return ((1, 2), (2, 2), (3, 2)) # 90°
    else
        return ((3, 1), (2, 2), (1, 3)) # 135° in image coordinates
    end
end

function _nearest_orientation_bin(theta::Real)
    nearest = 1
    nearest_dist = min(abs(theta - _ORIENTATION_CENTERS[1]), π - abs(theta - _ORIENTATION_CENTERS[1]))
    for k in 2:4
        dist = min(abs(theta - _ORIENTATION_CENTERS[k]), π - abs(theta - _ORIENTATION_CENTERS[k]))
        if dist < nearest_dist
            nearest = k
            nearest_dist = dist
        end
    end
    return nearest
end

function _draw_stencil!(canvas::AbstractMatrix{<:RGB}, top::Int, left::Int, bin::Int, color)
    for (dr, dc) in _orientation_stencil_coords(bin)
        _draw_point!(canvas, top + dr - 1, left + dc - 1, color)
    end
    return canvas
end

function _orientation_glyph_canvas(
        struct_theta::AbstractMatrix{<:Real},
        weights::AbstractMatrix{<:Real};
        stride::Int = 1,
        cell::Int = 3,
        color = RGB(1.0, 0.2, 0.2)
    )
    h, w = size(struct_theta)
    cell_ = max(cell, 3)
    canvas = fill(RGB(0.0, 0.0, 0.0), h * cell_, w * cell_)
    weight01 = _normalize01(Float64.(weights))
    stride_ = max(stride, 1)

    @inbounds for r in 1:stride_:h, c in 1:stride_:w
        wt = weight01[r, c]
        wt <= 0 && continue
        θ = Float64(struct_theta[r, c])
        bin = _nearest_orientation_bin(θ)
        top = (r - 1) * cell_ + 1
        left = (c - 1) * cell_ + 1
        weighted_color = RGB(color.r * wt, color.g * wt, color.b * wt)
        _draw_stencil!(canvas, top, left, bin, weighted_color)
    end

    return canvas
end

end
