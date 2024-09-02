# -*- coding: utf-8 -*-

""" Broadcasted Arithmetic ops between 2D images

Exports :

- **bundle\\_image2D\\_barithmetic** :
    - bsubtract\\_image2D\\_factory 
    - badd\\_image2D\\_factory 
    - bmult\\_image2D\\_factory
"""

module image2D_barithmetic

using ..UTCGP: FunctionBundle, append_method!
using ImageCore: clamp01nan!, Normed, float64
using ..UTCGP: SizedImage2D, SImageND, _validate_factory_type

fallback(args...) = return nothing
bundle_image2D_barithmetic_factory = FunctionBundle(fallback)
InputType = SizedImage2D{S1,S2,T,IT} where {S1,S2,T<:Normed,IT}

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
function bsubtract_image2D_factory(i::Type{I}) where {I<:InputType}
    TT = Base.unwrap_unionall(I).parameters[2] # Image type
    _validate_factory_type(TT)

    m1 = @eval ((img1::CONCT, p::Float64, args::Vararg{Any}) where {CONCT<:$I}) -> begin
        S = CONCT.parameters[1] # Tuple{X,Y}
        img2 = float64.(img1) .- p
        clamp01nan!(img2)
        return SImageND($TT.(img2), S)
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
function badd_image2D_factory(i::Type{I}) where {I<:InputType}
    TT = Base.unwrap_unionall(I).parameters[2] # Image type
    _validate_factory_type(TT)

    m1 = @eval ((img1::CONCT, p::Float64, args::Vararg{Any}) where {CONCT<:$I}) -> begin
        S = CONCT.parameters[1] # Tuple{X,Y}
        img2 = float64.(img1) .+ p
        clamp01nan!(img2)
        return SImageND($TT.(img2), S)
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
function bmult_image2D_factory(i::Type{I}) where {I<:InputType}
    TT = Base.unwrap_unionall(I).parameters[2] # Image type
    _validate_factory_type(TT)

    m1 = @eval ((img1::CONCT, p::Float64, args::Vararg{Any}) where {CONCT<:$I}) -> begin
        S = CONCT.parameters[1] # Tuple{X,Y}
        img2 = float64.(img1) .* p
        clamp01nan!(img2)
        return SImageND($TT.(img2), S)
    end
    return m1
end


# Factory Methods
append_method!(
    bundle_image2D_barithmetic_factory,
    bsubtract_image2D_factory,
    :bsubtract_image2D,
)
append_method!(bundle_image2D_barithmetic_factory, badd_image2D_factory, :badd_image2D)
append_method!(bundle_image2D_barithmetic_factory, bmult_image2D_factory, :bmult_image2D)

end

