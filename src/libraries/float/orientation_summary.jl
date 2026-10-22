"""
Scalar summaries of an image's gradient orientations.

# Call tree

    orientation_energy_* / dominant_orientation      → _scalar_energy_proportions
    orientation_coherence / orientation_spread        → _orientation_coherence_value
    both (orientation_common.jl): Sobel derivatives into task scratch, one fused
    pass per pixel, then the same sums as before; no allocation per call.

# Bundles

- [`bundle_float_orientation`](@ref)

The exhaustive, always-current list of operators in each bundle is on the
[Bundle Catalogue](@ref) page.
"""
module float_orientation

using ..MAGE: FunctionBundle, append_method!
using ..MAGE: SImageND, IntensityPixel
using ..MAGE: image2D_orientation_common

fallback(args...) = return -1.0
"""
    bundle_float_orientation

Scalar summaries of the **edge** orientations of an intensity image (the
direction along each edge), computed from Sobel derivatives and weighted by
edge strength. Angles run clockwise on screen because rows grow downwards.

- `orientation_energy_0`, `_45`, `_90`, `_135`: share of the edge strength in
  each of four bins: horizontal edges, `\\` diagonals (down to the right),
  vertical edges, `/` diagonals. The four sum to `1` (`0` for a flat image).
- `dominant_orientation`: the strongest bin as `0`, `0.25`, `0.5` or `0.75`.
- `orientation_coherence`: `1` when all edges share one orientation, near `0`
  when they point every way; `orientation_spread = 1 − coherence`.

Example: vertical stripes give `orientation_energy_90 = 1`,
`dominant_orientation = 0.5`, `orientation_coherence = 1`.
"""
bundle_float_orientation = FunctionBundle(fallback)

"""
    orientation_coherence(img) -> Float64 in [0, 1]

How aligned the edges are: the length of the edge-strength-weighted mean of
the doubled edge angles, divided by the total edge strength (doubling makes
θ and θ + π the same orientation). `1` when every edge has the same
orientation, near `0` when orientations are spread evenly, `0` for a flat image.

Example: vertical stripes → `1.0`; a checkerboard (horizontal and vertical
edges in equal amounts) → about `0`.
"""
function orientation_coherence(from::SImageND{S,T,2,C}, args...) where {S,T<:IntensityPixel,C}
    return image2D_orientation_common._orientation_coherence_value(from)
end

"""
    dominant_orientation(img) -> 0.0, 0.25, 0.5 or 0.75

The orientation bin holding the most edge strength, as its centre over π:
`0` horizontal edges, `0.25` `\\` diagonals (down to the right), `0.5`
vertical edges, `0.75` `/` diagonals. Ties go to the first bin; a flat image gives `0`.

Example: vertical stripes → `0.5`.
"""
function dominant_orientation(from::SImageND{S,T,2,C}, args...) where {S,T<:IntensityPixel,C}
    return image2D_orientation_common._dominant_orientation_value(from)
end

"""
    orientation_energy_0(img) -> Float64 in [0, 1]

Share of the total edge strength on horizontal edges (edge orientation
nearest 0°). The four `orientation_energy_*` values sum to `1` (all `0` for a
flat image).

Example: horizontal stripes → `1.0`; vertical stripes → `0.0`.
"""
function orientation_energy_0(from::SImageND{S,T,2,C}, args...) where {S,T<:IntensityPixel,C}
    return image2D_orientation_common._scalar_energy_proportions(from)[1]
end

"""
    orientation_energy_45(img) -> Float64 in [0, 1]

Share of the total edge strength on `\\` diagonal edges (down to the right,
nearest 45° clockwise on screen).

Example: stripes running from top-left to bottom-right → `1.0`.
"""
function orientation_energy_45(from::SImageND{S,T,2,C}, args...) where {S,T<:IntensityPixel,C}
    return image2D_orientation_common._scalar_energy_proportions(from)[2]
end

"""
    orientation_energy_90(img) -> Float64 in [0, 1]

Share of the total edge strength on vertical edges (edge orientation nearest 90°).

Example: vertical stripes → `1.0`; a checkerboard → about `0.5`.
"""
function orientation_energy_90(from::SImageND{S,T,2,C}, args...) where {S,T<:IntensityPixel,C}
    return image2D_orientation_common._scalar_energy_proportions(from)[3]
end

"""
    orientation_energy_135(img) -> Float64 in [0, 1]

Share of the total edge strength on `/` diagonal edges (nearest 135°
clockwise on screen, i.e. rising to the right).

Example: stripes running from bottom-left to top-right → `1.0`.
"""
function orientation_energy_135(from::SImageND{S,T,2,C}, args...) where {S,T<:IntensityPixel,C}
    return image2D_orientation_common._scalar_energy_proportions(from)[4]
end

"""
    orientation_spread(img) -> Float64 in [0, 1]

`1 − orientation_coherence(img)`: near `0` when the edges are aligned, near
`1` when they point every way (and `1` for a flat image, whose coherence is `0`).

Example: vertical stripes → `0.0`.
"""
function orientation_spread(from::SImageND{S,T,2,C}, args...) where {S,T<:IntensityPixel,C}
    return image2D_orientation_common._orientation_spread_value(from)
end

append_method!(
    bundle_float_orientation,
    orientation_coherence;
    description = "How aligned the edges are: 1 when all edges share one orientation, near 0 when they point every way.",
)
append_method!(
    bundle_float_orientation,
    dominant_orientation;
    description = "Edge orientation bin with the most edge strength, over π: 0 horizontal, 0.25 \\ diagonal, 0.5 vertical, 0.75 / diagonal.",
)
append_method!(
    bundle_float_orientation,
    orientation_energy_0;
    description = "Share of the edge strength on horizontal edges (edge orientation nearest 0°).",
)
append_method!(
    bundle_float_orientation,
    orientation_energy_45;
    description = "Share of the edge strength on \\ diagonal edges (down to the right, nearest 45° clockwise).",
)
append_method!(
    bundle_float_orientation,
    orientation_energy_90;
    description = "Share of the edge strength on vertical edges (edge orientation nearest 90°).",
)
append_method!(
    bundle_float_orientation,
    orientation_energy_135;
    description = "Share of the edge strength on / diagonal edges (nearest 135° clockwise).",
)
append_method!(
    bundle_float_orientation,
    orientation_spread;
    description = "1 − orientation_coherence: near 0 when all edges are parallel, near 1 when they point every way.",
)

end
