""" Broadcasted Arithmetic ops between 2D images

Exports :

- **bundle\\_image2D\\_barithmetic** :
    - bsubtract\\_image2D\\_factory 
    - badd\\_image2D\\_factory 
    - bmult\\_image2D\\_factory
"""

module image2D_barithmetic

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

bundle_image2DIntensity_barithmetic_factory = FunctionBundle(fallback)

# ################### #
# Subtract            #
# ################### #

"""
    bsubtract_image2D_factory(i::Type{I}) where {I<:InputType}

with InputType = SizedImage2D{S1,S2,T,IT} where {S1,S2,T<:Normed,IT}

**Exposes** : 

    m1 = @eval ((img1::CONCT, p::Float64, args::Vararg{Any}) where {CONCT<:\$I})

Which broadcasts the subtraction of `p` from `img2` (as floats) and then clamps the result between [0,1].

**Returns**:

The subtracted image as a `SImageND` with the same shape.
"""
function bsubtract_image2D_factory(i::Type{I}) where {I<:SizedImage{SIZE, IntensityPixel{T}}} where {SIZE,T}
    IT, PT, S = _get_image_type(I), _get_image_pixel_type(I), _get_image_tuple_size(I)
    S1, S2 = S.parameters[1], S.parameters[2]
    _validate_factory_type(IT)

    m1 = @eval ((img1::CONCT, p::Float64, args::Vararg{Any}) where {CONCT <: $I}) -> begin
        img3 = float(img1) .- p
        clamp01nan!(img3)
        return SImageND($PT.(cast($IT, img3)), $S)
    end
    return m1
end

"""
    add_image2D_factory(i::Type{I}) where {I<:InputType}

with InputType = SizedImage2D{S1,S2,T,IT} where {S1,S2,T<:Normed,IT}

**Exposes** : 

    m1 = @eval ((img1::CONCT, img2::CONCT, args::Vararg{Any}) where {CONCT<:\$I})

Which adds `img1` and `img2` (as floats) and then clamps the result between [0,1].

**Returns**:

The added image as a `SImageND` with the same shape.
"""
function badd_image2D_factory(i::Type{I}) where {I<:SizedImage{SIZE, IntensityPixel{T}}} where {SIZE,T}
    IT, PT, S = _get_image_type(I), _get_image_pixel_type(I), _get_image_tuple_size(I)
    S1, S2 = S.parameters[1], S.parameters[2]
    _validate_factory_type(IT)

    m1 = @eval ((img1::CONCT, p::Float64, args::Vararg{Any}) where {CONCT <: $I}) -> begin
        img3 = float(img1) .+ p
        clamp01nan!(img3)
        return SImageND($PT.(cast($IT, img3)), $S)
    end
    return m1
end

"""
    mult_image2D_factory(i::Type{I}) where {I<:InputType}

with InputType = SizedImage2D{S1,S2,T,IT} where {S1,S2,T<:Normed,IT}

**Exposes** : 

    m1 = @eval ((img1::CONCT, img2::CONCT, args::Vararg{Any}) where {CONCT<:\$I})

Which multiplies `img1` and `img2` (as floats) and then clamps the result between [0,1].

**Returns**:

The multiplied image as a `SImageND` with the same shape.
"""
function bmult_image2D_factory(i::Type{I}) where {I<:SizedImage{SIZE, IntensityPixel{T}}} where {SIZE,T}
    IT, PT, S = _get_image_type(I), _get_image_pixel_type(I), _get_image_tuple_size(I)
    S1, S2 = S.parameters[1], S.parameters[2]
    _validate_factory_type(IT)

    m1 = @eval ((img1::CONCT, p::Float64, args::Vararg{Any}) where {CONCT <: $I}) -> begin
        img3 = float(img1) .* p
        clamp01nan!(img3)
        return SImageND($PT.(cast($IT, img3)), $S)
    end
    return m1
end


# Factory Methods
append_method!(
    bundle_image2DIntensity_barithmetic_factory,
    bsubtract_image2D_factory,
    :bsubtract_image2D,
)
append_method!(bundle_image2DIntensity_barithmetic_factory, badd_image2D_factory, :badd_image2D)
append_method!(bundle_image2DIntensity_barithmetic_factory, bmult_image2D_factory, :bmult_image2D)

end

