""" Orientation summary functions from image to Float64

Exports :

- **bundle\\_float\\_orientation** :
    - `orientation_coherence`
    - `dominant_orientation`
    - `orientation_energy_0`
    - `orientation_energy_45`
    - `orientation_energy_90`
    - `orientation_energy_135`
    - `orientation_spread`
"""
module float_orientation

using ..UTCGP: FunctionBundle, append_method!
using ..UTCGP: SImageND, IntensityPixel
using ..UTCGP: image2D_orientation_common

fallback(args...) = return -1.0
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

append_method!(bundle_float_orientation, orientation_coherence)
append_method!(bundle_float_orientation, dominant_orientation)
append_method!(bundle_float_orientation, orientation_energy_0)
append_method!(bundle_float_orientation, orientation_energy_45)
append_method!(bundle_float_orientation, orientation_energy_90)
append_method!(bundle_float_orientation, orientation_energy_135)
append_method!(bundle_float_orientation, orientation_spread)

end
