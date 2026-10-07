"""
Scalar summaries of an image's gradient orientations.

# Bundles

- [`bundle_float_orientation`](@ref)

The exhaustive, always-current list of operators in each bundle is on the
[Bundle Catalogue](@ref) page.
"""
module float_orientation

using ..UTCGP: FunctionBundle, append_method!
using ..UTCGP: SImageND, IntensityPixel
using ..UTCGP: image2D_orientation_common

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

function orientation_coherence(from::SImageND{S,T,2,C}, args...) where {S,T<:IntensityPixel,C}
    return image2D_orientation_common._orientation_coherence_value(from)
end

function dominant_orientation(from::SImageND{S,T,2,C}, args...) where {S,T<:IntensityPixel,C}
    return image2D_orientation_common._dominant_orientation_value(from)
end

function orientation_energy_0(from::SImageND{S,T,2,C}, args...) where {S,T<:IntensityPixel,C}
    return image2D_orientation_common._orientation_energy_proportions(from)[1]
end

function orientation_energy_45(from::SImageND{S,T,2,C}, args...) where {S,T<:IntensityPixel,C}
    return image2D_orientation_common._orientation_energy_proportions(from)[2]
end

function orientation_energy_90(from::SImageND{S,T,2,C}, args...) where {S,T<:IntensityPixel,C}
    return image2D_orientation_common._orientation_energy_proportions(from)[3]
end

function orientation_energy_135(from::SImageND{S,T,2,C}, args...) where {S,T<:IntensityPixel,C}
    return image2D_orientation_common._orientation_energy_proportions(from)[4]
end

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
