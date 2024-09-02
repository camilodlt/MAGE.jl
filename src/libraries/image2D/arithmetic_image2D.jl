# -*- coding: utf-8 -*-

""" Arithmetic ops between 2D images

Exports :

- **bundle\\_image2D\\_arithmetic** :
    - subtract\\_image2D\\_factory 
    - add\\_image2D\\_factory 
    - mult\\_image2D\\_factory
"""

module image2D_arithmetic

using ..UTCGP: FunctionBundle, append_method!
using ImageCore: clamp01nan!, Normed
using ..UTCGP: SizedImage2D, SImageND, _validate_factory_type

fallback(args...) = return nothing
bundle_image2D_arithmetic_factory = FunctionBundle(fallback)
InputType = SizedImage2D{S1,S2,T,IT} where {S1,S2,T<:Normed,IT}

# ################### #
# Subtract            #
# ################### #

"""
    subtract_image2D_factory(i::Type{I}) where {I<:InputType}

with InputType = SizedImage2D{S1,S2,T,IT} where {S1,S2,T<:Normed,IT}

**Exposes** : 

    m1 = @eval ((img1::CONCT, img2::CONCT, args::Vararg{Any}) where {CONCT<:\$I})

Which subtracts `img1` from `img2` (as floats) and then clamps the result between [0,1].

**Returns**:

The subtracted image as a `SImageND` with the same shape.
"""
function subtract_image2D_factory(i::Type{I}) where {I<:InputType}
    TT = Base.unwrap_unionall(I).parameters[2] # Image type
    _validate_factory_type(TT)

    m1 = @eval ((img1::CONCT, img2::CONCT, args::Vararg{Any}) where {CONCT<:$I}) -> begin
        S = CONCT.parameters[1] # Tuple{X,Y}
        img3 = float(img1) - float(img2)
        clamp01nan!(img3)
        return SImageND($TT.(img3), S)
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
function add_image2D_factory(i::Type{I}) where {I<:InputType}
    TT = Base.unwrap_unionall(I).parameters[2] # Image type
    _validate_factory_type(TT)

    m1 = @eval ((img1::CONCT, img2::CONCT, args::Vararg{Any}) where {CONCT<:$I}) -> begin
        S = CONCT.parameters[1] # Tuple{X,Y}
        img3 = float(img1) + float(img2)
        clamp01nan!(img3)
        return SImageND($TT.(img3), S)
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
function mult_image2D_factory(i::Type{I}) where {I<:InputType}
    TT = Base.unwrap_unionall(I).parameters[2] # Image type
    _validate_factory_type(TT)

    m1 = @eval ((img1::CONCT, img2::CONCT, args::Vararg{Any}) where {CONCT<:$I}) -> begin
        S = CONCT.parameters[1] # Tuple{X,Y}
        img3 = float(img1) * float(img2)
        clamp01nan!(img3)
        return SImageND($TT.(img3), S)
    end
    return m1
end


# Factory Methods
append_method!(bundle_image2D_arithmetic_factory, subtract_image2D_factory, :subtract_img2D)
append_method!(bundle_image2D_arithmetic_factory, add_image2D_factory, :add_img2D)
append_method!(bundle_image2D_arithmetic_factory, mult_image2D_factory, :mult_img2D)

end

