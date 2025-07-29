# -*- coding: utf-8 -*-

""" Image transcendental ops 

Exports :

- **bundle\\_image2D\\_arithmetic** :
    - exp\\_image2D\\_factory 
    - log\\_image2D\\_factory 
    - powerof\\_image2D\\_factory 
"""

module image2D_transcendental

using ..UTCGP: image2D_basic
using ..UTCGP:image2D_morph
using ..UTCGP: ManualDispatcher
using ..UTCGP: FunctionBundle, append_method!
import UTCGP:
    CONSTRAINED,
    MIN_INT,
    MAX_INT,
    MIN_FLOAT,
    MAX_FLOAT,
    _positive_params,
    _ceil_positive_params
using ImageCore: N0f8, Normed, clamp01nan!, clamp01nan, float64, Gray, FixedPoint
using ..UTCGP:
    SizedImage, SizedImage2D, SImageND, _get_image_tuple_size, _get_image_type, _validate_factory_type, _get_image_pixel_type, 
    IntensityPixel, BinaryPixel, SegmentPixel

cast = image2D_morph.cast
fallback(args...) = return nothing

bundle_image2DIntensity_transcendental_factory = FunctionBundle(fallback)

# ################### #
# EXP                 #
# ################### #

"""
    exp_image2D_factory(i::Type{I}) where {I<:InputType}

with InputType = SizedImage2D{S1,S2,T,IT} where {S1,S2,T<:Normed,IT}

Element wise `exp`.

**Exposes** : 

    exp_image2D(img1::CONCT, args::Vararg{Any})

"""
function exp_image2D_factory(i::Type{I}) where {I<:SizedImage{SIZE, IntensityPixel{T}}} where {SIZE,T}
    IT, PT, S = _get_image_type(I), _get_image_pixel_type(I), _get_image_tuple_size(I)
    S1, S2 = S.parameters[1], S.parameters[2]
    _validate_factory_type(IT)

    m1 = @eval ((img1::CONCT, args::Vararg{Any}) where {CONCT <: $I}) -> begin
        img3 = exp.(float(img1))
        img3 = image2D_basic._normalize_img(img3)
        clamp01nan!(img3)
        return SImageND($PT.(cast($IT, img3)), $S)
    end
    return m1
end

# ################### #
# LOG                 #
# ################### #

"""
    log_image2D_factory(i::Type{I}) where {I<:InputType}

with InputType = SizedImage2D{S1,S2,T,IT} where {S1,S2,T<:Normed,IT}

Element wise `log`.

**Exposes** : 

    log_image2D(img1::CONCT, args::Vararg{Any})

"""
function loginv_image2D_factory(i::Type{I}) where {I<:SizedImage{SIZE, IntensityPixel{T}}} where {SIZE,T}
    IT, PT, S = _get_image_type(I), _get_image_pixel_type(I), _get_image_tuple_size(I)
    S1, S2 = S.parameters[1], S.parameters[2]
    _validate_factory_type(IT)

    m1 = @eval ((img1::CONCT, args::Vararg{Any}) where {CONCT <: $I}) -> begin
        img3 = log.(float(img1)) .*- 1.
        clamp01nan!(img3)
        return SImageND($PT.(cast($IT, img3)), $S)
    end
    return m1
end
function log_image2D_factory(i::Type{I}) where {I<:SizedImage{SIZE, IntensityPixel{T}}} where {SIZE,T}
    IT, PT, S = _get_image_type(I), _get_image_pixel_type(I), _get_image_tuple_size(I)
    S1, S2 = S.parameters[1], S.parameters[2]
    _validate_factory_type(IT)
    TRUE_TYPE = IT.parameters[1]

    m1 = @eval ((img1::CONCT, args::Vararg{Any}) where {CONCT <: $I}) -> begin
        img3 = image2D_basic._normalize_img(log.(convert.(Float32,reinterpret($TRUE_TYPE,reinterpret(img1.img)))))
        clamp01nan!(img3)
        return SImageND($PT.(cast($IT, img3)), $S)
    end
    return m1
end

# ################### #
# Power of            #
# ################### #

"""
    powerof_image2D_factory(i::Type{I}) where {I<:InputType}

with InputType = SizedImage2D{S1,S2,T,IT} where {S1,S2,T<:Normed,IT}

Each element in `img1` is elevated to the power of `p`

**Exposes** : 

    powerof_image2D(img1::CONCT, p::Float64, args::Vararg{Any})

"""
function powerof_image2D_factory(i::Type{I}) where {I<:SizedImage{SIZE, IntensityPixel{T}}} where {SIZE,T}
    IT, PT, S = _get_image_type(I), _get_image_pixel_type(I), _get_image_tuple_size(I)
    S1, S2 = S.parameters[1], S.parameters[2]
    _validate_factory_type(IT)

    m1 = @eval ((img1::CONCT, p::Real, args::Vararg{Any}) where {CONCT <: $I}) -> begin
        img3 = (float(img1)) .^ p
        clamp01nan!(img3)
        return SImageND($PT.(cast($IT, img3)), $S)
    end
    return m1
end

# Factory Methods
append_method!(bundle_image2DIntensity_transcendental_factory, exp_image2D_factory, :exp_image2D)
append_method!(bundle_image2DIntensity_transcendental_factory, loginv_image2D_factory, :loginv_image2D)
append_method!(bundle_image2DIntensity_transcendental_factory, log_image2D_factory, :log_image2D)
append_method!(
    bundle_image2DIntensity_transcendental_factory,
    powerof_image2D_factory,
    :powerof_image2D,
)

end

