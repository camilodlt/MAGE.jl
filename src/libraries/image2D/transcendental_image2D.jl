# -*- coding: utf-8 -*-

""" Image transcendental ops 

Exports :

- **bundle\\_image2D\\_arithmetic** :
    - exp\\_image2D\\_factory 
    - log\\_image2D\\_factory 
    - powerof\\_image2D\\_factory 
"""

module image2D_transcendental

using ..UTCGP: FunctionBundle, append_method!
using ImageCore: clamp01nan!, Normed, float64
using ..UTCGP: SizedImage2D, SImageND, _validate_factory_type

fallback(args...) = return nothing
bundle_image2D_transcendental_factory = FunctionBundle(fallback)
InputType = SizedImage2D{S1,S2,T,IT} where {S1,S2,T<:Normed,IT}

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
function exp_image2D_factory(i::Type{I}) where {I<:InputType}
    TT = Base.unwrap_unionall(I).parameters[2] # Image type
    _validate_factory_type(TT)
    m1 = @eval ((img1::CONCT, args::Vararg{Any}) where {CONCT<:$I}) -> begin
        S = CONCT.parameters[1] # Tuple{X,Y}
        img2 = exp.(float64.(img1))
        clamp01nan!(img2)
        img_res = $TT.(img2)
        return SImageND(img_res, S)
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
function log_image2D_factory(i::Type{I}) where {I<:InputType}
    TT = Base.unwrap_unionall(I).parameters[2] # Image type
    _validate_factory_type(TT)
    m1 = @eval ((img1::CONCT, args::Vararg{Any}) where {CONCT<:$I}) -> begin
        S = CONCT.parameters[1] # Tuple{X,Y}
        img2 = log.(float64.(img1))
        clamp01nan!(img2)
        return SImageND($TT.(img2), S)
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
function powerof_image2D_factory(i::Type{I}) where {I<:InputType}
    TT = Base.unwrap_unionall(I).parameters[2] # Image type
    _validate_factory_type(TT)
    m1 = @eval ((img1::CONCT, p::Real, args::Vararg{Any}) where {CONCT<:$I}) -> begin
        S = CONCT.parameters[1] # Tuple{X,Y}
        img2 = float64.(img1) .^ p
        clamp01nan!(img2)
        return SImageND($TT.(img2), S)
    end
    return m1
end


# Factory Methods
append_method!(bundle_image2D_transcendental_factory, exp_image2D_factory, :exp_image2D)
append_method!(bundle_image2D_transcendental_factory, log_image2D_factory, :log_image2D)
append_method!(
    bundle_image2D_transcendental_factory,
    powerof_image2D_factory,
    :powerof_image2D,
)

end

