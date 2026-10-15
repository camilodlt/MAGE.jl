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

using ImageFiltering: Kernel, reflect, imfilter
using ImageCore: RGB
using ..UTCGP: SImageND

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
    gx = imfilter(img, _XSOBEL, "replicate")
    gy = imfilter(img, _YSOBEL, "replicate")
    gx[abs.(gx) .< _FLAT] .= 0.0
    gy[abs.(gy) .< _FLAT] .= 0.0
    return gx, gy
end

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

"Centre of the strongest bin over `π`: `0` horizontal, `0.25` `\\`, `0.5` vertical, `0.75` `/`."
function _dominant_orientation_value(from::SImageND)
    energies = _orientation_energy_proportions(from)
    return _ORIENTATION_CENTERS[argmax(energies)] / π
end

"""
Length of the magnitude-weighted mean of the doubled edge angles, over the
total magnitude: `1` when every edge has the same orientation, near `0` when
orientations are spread evenly. (Doubling makes `θ` and `θ + π` agree.)
"""
function _orientation_coherence_value(from::SImageND)
    mag, theta = _magnitude_and_edge_orientation(from)
    total = sum(mag)
    total == 0 && return 0.0
    c = sum(mag .* cos.(2 .* theta))
    s = sum(mag .* sin.(2 .* theta))
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
