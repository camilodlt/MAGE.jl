# -*- coding: utf-8 -*-
""" Morphological functions

Exports :

- **bundle\\image2D\\_basic** :
    - `erosion`
    - `dilation` # TODO
    - `opening` # TODO
    - `closing` # TODO

"""

# We use the Array View for images

module image2D_morph

using ImageMorphology
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
using ImageCore: N0f8, Normed
using ..UTCGP:
    SizedImage, SImageND, _get_image_tuple_size, _get_image_type, _validate_factory_type
fallback(args...) = return nothing
bundle_image2D_morph = FunctionBundle(fallback)
bundle_image2D_morph_factory = FunctionBundle(fallback)

# ################### #
# Erosion             #
# ################### #

"""
    erosion_image2D(img::Array{T,2}, args...)::Array{T,2} where {T<:Number}

Erodes the image

Using Diamond Structural Element
"""
function erosion_image2D_factory(i::Type{I}) where {I<:SizedImage}

    TT = Base.unwrap_unionall(I).parameters[2]
    _validate_factory_type(TT)

    m1 = @eval ((img::CONCT, k::Int, args::Vararg{Any}) where {CONCT<:$I}) -> begin
        k = k % 2 == 0 ? k + 1 : k
        k = clamp(k, 3, 13)
        se = strel_diamond((k, k))
        return SImageND(erode(img.img, se))
    end

    # TODO k,k
    # TODO Box SE

    m2 = @eval ((img::CONCT, args::Vararg{Any}) where {CONCT<:$I}) -> begin
        return SImageND(erode(img.img))
    end
    ManualDispatcher((m1, m2), :erosion_2D)
end

# Factory Methods
append_method!(bundle_image2D_morph_factory, erosion_image2D_factory)

# Default
erosion_N0f8 = erosion_image2D_factory(SImageND{<:Tuple,N0f8,2})
append_method!(bundle_image2D_morph, erosion_N0f8)
end
