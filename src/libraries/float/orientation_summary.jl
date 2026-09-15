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

Scalar summaries of an image's gradient orientations, computed from Sobel
derivatives.

`dominant_orientation` and `orientation_coherence` describe the main direction
and how consistent it is; `orientation_energy_0`, `_45`, `_90` and `_135` give
the energy in four directional bands, and `orientation_spread` how dispersed the
orientations are.
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
    description = "Computes orientation coherence of the image gradient field.",
)
append_method!(
    bundle_float_orientation,
    dominant_orientation;
    description = "Returns the strongest coarse orientation bin center among {0, π/4, π/2, 3π/4}, normalized by π.",
)
append_method!(
    bundle_float_orientation,
    orientation_energy_0;
    description = "Returns orientation energy proportion near 0 degrees.",
)
append_method!(
    bundle_float_orientation,
    orientation_energy_45;
    description = "Returns orientation energy proportion near 45 degrees.",
)
append_method!(
    bundle_float_orientation,
    orientation_energy_90;
    description = "Returns orientation energy proportion near 90 degrees.",
)
append_method!(
    bundle_float_orientation,
    orientation_energy_135;
    description = "Returns orientation energy proportion near 135 degrees.",
)
append_method!(
    bundle_float_orientation,
    orientation_spread;
    description = "Measures how widely orientation energy is distributed across directions.",
)

end
