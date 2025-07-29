# -*- coding: utf-8 -*-
""" Morphological functions

Exports :

- **bundle\\image2D\\_morph** :
    - `erosion`
    - `dilation`
    - `opening` 
    - `closing` 
    - `tophat`
    - `bothat`
    - `mgradient`
    - `mlaplace`
"""

module image2D_morph

using ImageMorphology
using ..UTCGP: image2D_basic
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

fallback(args...) = return nothing
bundle_image2DIntensity_morph_factory = FunctionBundle(fallback)
bundle_image2DBinary_morph_factory = FunctionBundle(fallback)
# bundle_image2DSegment_morph_factory = FunctionBundle(fallback) # not applicable

# Bool => Intensity
function cast(to_type::Type{T}, img::Array{Bool}) where {T<: Real}
    to_type.(img) # 0. or 1. we can always promote
end
function cast(to_type::Type{T}, img::BitArray) where {T<: Real}
    to_type.(img) # 0. or 1. we can always promote
end

# do nothing img is already intensity => a Intensity image was eroded
function cast(to_type::Type{T}, img::Array{T}) where T
    return T.(img)    
end
function cast(to_type::Type{T1}, img::Array{T2}) where {T1<:FixedPoint, T2<:AbstractFloat}
    return T1.(img)    
end
function cast(to_type::Type{Bool}, img::BitArray)
    return img    
end
function cast(to_type::Type{Bool}, img::Matrix{Bool})
    return img    
end

# Intensity => Bool
function cast(to_type::Type{Bool}, img::Array{<:Real})
    img_ = clamp01nan.(img)
    img_ .= round.(Int, img_) # to 0 or 1
    to_type.(img_) # returns the boolean (rounded version) of the image
end

# ################### #
# EROSION             #
# ################### #

"""
    erosion_image2D(img::Array{T,2}, args...)::Array{T,2} where {T<:Number}

Erodes the image. Applies to IntensityPixel and BinaryPixel

Using Diamond Structural Element
"""
function erosion_image2D_factory(i::Type{I}) where {I<:SizedImage{SIZE, <:Union{BinaryPixel, IntensityPixel}}} where SIZE
    IT, PT, S = _get_image_type(I), _get_image_pixel_type(I), _get_image_tuple_size(I)
    S1, S2 = S.parameters[1], S.parameters[2]
    _validate_factory_type(IT)

    # the method accepts binary/intensity of the same size
    m1 = @eval ((img::CONCT, k_n::Number, args::Vararg{Any}) where {CONCT<:SizedImage{$(SIZE), <:Union{BinaryPixel, IntensityPixel}}}) -> begin
        k = round(Int, k_n)
        k = k % 2 == 0 ? k + 1 : k
        k = clamp(k, 3, 13)
        se = strel_diamond((k, k))
        res = erode(reinterpret(img.img), se)
        clamp01nan!(res)
        res_ = cast($IT, res)  
        return SImageND($PT.(res_), $S)
    end

    # TODO k,k
    # TODO Box SE

    # default structural element
    m2 = @eval ((img::CONCT, args::Vararg{Any}) where {CONCT<:SizedImage{$(SIZE), <:Union{BinaryPixel, IntensityPixel}}}) -> begin
        res = erode(reinterpret(img.img))
        clamp01nan!(res)
        res_ = cast($IT, res)  
        return SImageND($PT.(res_), $S)
    end
    ManualDispatcher((m1, m2), :erosion_2D)
end


# ################### #
# DILATION            #
# ################### #

"""
    experimental_dilation_image2D(img::Array{T,2}, args...)::Array{T,2} where {T<:Number}

Dilates the image

Using Diamond Structural Element
"""
function dilation_image2D_factory(i::Type{I}) where {I<:SizedImage{SIZE, <:Union{BinaryPixel, IntensityPixel}}} where SIZE
    IT, PT, S = _get_image_type(I), _get_image_pixel_type(I), _get_image_tuple_size(I)
    S1, S2 = S.parameters[1], S.parameters[2]
    _validate_factory_type(IT)

    m1 = @eval ((img::CONCT, k_n::Number, args::Vararg{Any}) where {CONCT<:SizedImage{$(SIZE), <:Union{BinaryPixel, IntensityPixel}}}) -> begin
        k = round(Int, k_n)
        k = k % 2 == 0 ? k + 1 : k
        k = clamp(k, 3, 13)
        se = strel_diamond((k, k))
        res = dilate(reinterpret(img.img), se)
        clamp01nan!(res)
        res_ = cast($IT, res)  
        return SImageND($PT.(res_), $S)
    end

    # TODO k,k
    # TODO Box SE

    m2 = @eval ((img::CONCT, args::Vararg{Any}) where {CONCT<:SizedImage{$(SIZE), <:Union{BinaryPixel, IntensityPixel}}}) -> begin
        res = dilate(reinterpret(img.img))
        clamp01nan!(res)
        res_ = cast($IT, res)  
        return SImageND($PT.(res_), $S)
    end
    ManualDispatcher((m1, m2), :dilation_2D)
end

# ################### #
# OPENING            #
# ################### #

"""
    experimental_opening_image2D(img::Array{T,2}, args...)::Array{T,2} where {T<:Number}

Opens the image : dilate(erode(img))

Using Diamond Structural Element
"""
function opening_image2D_factory(i::Type{I}) where {I<:SizedImage{SIZE, <:Union{BinaryPixel, IntensityPixel}}} where SIZE
    IT, PT, S = _get_image_type(I), _get_image_pixel_type(I), _get_image_tuple_size(I)
    S1, S2 = S.parameters[1], S.parameters[2]
    _validate_factory_type(IT)

    m1 = @eval ((img::CONCT, k_n::Number, args::Vararg{Any}) where {CONCT<:SizedImage{$(SIZE), <:Union{BinaryPixel, IntensityPixel}}}) -> begin
        k = round(Int, k_n)
        k = k % 2 == 0 ? k + 1 : k
        k = clamp(k, 3, 13)
        se = strel_diamond((k, k))
        res = opening(reinterpret(img.img), se)
        clamp01nan!(res)
        res_ = cast($IT, res)  
        return SImageND($PT.(res_), $S)
    end

    # TODO k,k
    # TODO Box SE

    m2 = @eval ((img::CONCT, args::Vararg{Any}) where {CONCT<:SizedImage{$(SIZE), <:Union{BinaryPixel, IntensityPixel}}}) -> begin
        res = opening(reinterpret(img.img))
        clamp01nan!(res)
        res_ = cast($IT, res)  
        return SImageND($PT.(res_), $S)
    end
    ManualDispatcher((m1, m2), :opening_2D)
end


# ################### #
# CLOSING             #
# ################### #

"""
    experimental_closing_image2D(img::Array{T,2}, args...)::Array{T,2} where {T<:Number}

Closes the image : erode(dilate(img))

Using Diamond Structural Element
"""
function closing_image2D_factory(i::Type{I}) where {I<:SizedImage{SIZE, <:Union{BinaryPixel, IntensityPixel}}} where SIZE
    IT, PT, S = _get_image_type(I), _get_image_pixel_type(I), _get_image_tuple_size(I)
    S1, S2 = S.parameters[1], S.parameters[2]
    _validate_factory_type(IT)

    m1 = @eval ((img::CONCT, k_n::Number, args::Vararg{Any}) where {CONCT<:SizedImage{$(SIZE), <:Union{BinaryPixel, IntensityPixel}}}) -> begin
        k = round(Int, k_n)
        k = k % 2 == 0 ? k + 1 : k
        k = clamp(k, 3, 13)
        se = strel_diamond((k, k))
        res = closing(reinterpret(img.img), se)
        clamp01nan!(res)
        res_ = cast($IT, res)  
        return SImageND($PT.(res_), $S)
    end

    # TODO k,k
    # TODO Box SE

    m2 = @eval ((img::CONCT, args::Vararg{Any}) where {CONCT<:SizedImage{$(SIZE), <:Union{BinaryPixel, IntensityPixel}}}) -> begin
        res = closing(reinterpret(img.img))
        clamp01nan!(res)
        res_ = cast($IT, res)  
        return SImageND($PT.(res_), $S)
    end
    ManualDispatcher((m1, m2), :closing_2D)
end


"""
    experimental_tophat_image2D(img::Array{T,2}, args...)::Array{T,2} where {T<:Number}

Tophat the image 

Using Diamond Structural Element
"""
function tophat_image2D_factory(i::Type{I}) where {I<:SizedImage{SIZE, <:Union{BinaryPixel, IntensityPixel}}} where SIZE
    IT, PT, S = _get_image_type(I), _get_image_pixel_type(I), _get_image_tuple_size(I)
    S1, S2 = S.parameters[1], S.parameters[2]
    _validate_factory_type(IT)

    m1 = @eval ((img::CONCT, k_n::Number, args::Vararg{Any}) where {CONCT<:SizedImage{$(SIZE), <:Union{BinaryPixel, IntensityPixel}}}) -> begin
        k = round(Int, k_n)
        k = k % 2 == 0 ? k + 1 : k
        k = clamp(k, 3, 13)
        se = strel_diamond((k, k))
        res = tophat(reinterpret(img.img), se)
        clamp01nan!(res)
        res_ = cast($IT, res)  
        return SImageND($PT.(res_), $S)
    end

    # TODO k,k
    # TODO Box SE

    m2 = @eval ((img::CONCT, args::Vararg{Any}) where {CONCT<:SizedImage{$(SIZE), <:Union{BinaryPixel, IntensityPixel}}}) -> begin
        res = tophat(reinterpret(img.img))
        clamp01nan!(res)
        res_ = cast($IT, res)  
        return SImageND($PT.(res_), $S)
    end
    ManualDispatcher((m1, m2), :tophat_2D)
end

"""
    bothat_image2D(img::Array{T,2}, args...)::Array{T,2} where {T<:Number}

bothat the image 

Using Diamond Structural Element
"""
function bothat_image2D_factory(i::Type{I}) where {I<:SizedImage{SIZE, <:Union{BinaryPixel, IntensityPixel}}} where SIZE
    IT, PT, S = _get_image_type(I), _get_image_pixel_type(I), _get_image_tuple_size(I)
    S1, S2 = S.parameters[1], S.parameters[2]
    _validate_factory_type(IT)

    m1 = @eval ((img::CONCT, k_n::Number, args::Vararg{Any}) where {CONCT<:SizedImage{$(SIZE), <:Union{BinaryPixel, IntensityPixel}}}) -> begin
        k = round(Int, k_n)
        k = k % 2 == 0 ? k + 1 : k
        k = clamp(k, 3, 13)
        se = strel_diamond((k, k))
        res = bothat(reinterpret(img.img), se)
        clamp01nan!(res)
        res_ = cast($IT, res)  
        return SImageND($PT.(res_), $S)
    end

    # TODO k,k
    # TODO Box SE

    m2 = @eval ((img::CONCT, args::Vararg{Any}) where {CONCT<:SizedImage{$(SIZE), <:Union{BinaryPixel, IntensityPixel}}}) -> begin
        res = bothat(reinterpret(img.img))
        clamp01nan!(res)
        res_ = cast($IT, res)  
        return SImageND($PT.(res_), $S)
    end
    ManualDispatcher((m1, m2), :bothat_2D)
end


"""
    morphogradient_image2D(img::Array{T,2}, args...)::Array{T,2} where {T<:Number}

morphogradient

Using Diamond Structural Element
"""
function morphogradient_image2D_factory(i::Type{I}) where {I<:SizedImage{SIZE, <:Union{BinaryPixel, IntensityPixel}}} where SIZE
    IT, PT, S = _get_image_type(I), _get_image_pixel_type(I), _get_image_tuple_size(I)
    S1, S2 = S.parameters[1], S.parameters[2]
    _validate_factory_type(IT)

    m1 = @eval ((img::CONCT, k_n::Number, mode_int::Number,args::Vararg{Any}) where {CONCT<:SizedImage{$(SIZE), <:Union{BinaryPixel, IntensityPixel}}}) -> begin
        if mode_int< 0
            mode_ = :beucher
        elseif mode_int== 0
            mode_ = :internal
        else
            mode_ = :external
        end
        k = round(Int, k_n)
        k = k % 2 == 0 ? k + 1 : k
        k = clamp(k, 3, 13)
        se = strel_diamond((k, k))
        res = mgradient(reinterpret(img.img), se; mode = mode_)
        clamp01nan!(res)
        res_ = cast($IT, res)  
        return SImageND($PT.(res_), $S)
    end

    m2 = @eval ((img::CONCT, k_n::Number, args::Vararg{Any}) where {CONCT<:SizedImage{$(SIZE), <:Union{BinaryPixel, IntensityPixel}}}) -> begin
        k = round(Int, k_n)
        k = k % 2 == 0 ? k + 1 : k
        k = clamp(k, 3, 13)
        se = strel_diamond((k, k))
        res = mgradient(reinterpret(img.img), se; mode = :beucher)
        clamp01nan!(res)
        res_ = cast($IT, res)  
        return SImageND($PT.(res_), $S)
    end

    # TODO k,k
    # TODO Box SE

    m3 = @eval ((img::CONCT, args::Vararg{Any}) where {CONCT<:SizedImage{$(SIZE), <:Union{BinaryPixel, IntensityPixel}}}) -> begin
        res = mgradient(reinterpret(img.img); mode = :beucher)
        clamp01nan!(res)
        res_ = cast($IT, res)  
        return SImageND($PT.(res_), $S)
    end

    ManualDispatcher((m1, m2, m3), :morphogradient_2D)
end


"""
    morpholaplace_image2D(img::Array{T,2}, args...)::Array{T,2} where {T<:Number}

morpholaplace + normalization to make it fit in 0-1

Using Diamond Structural Element
"""
function morpholaplace_image2D_factory(i::Type{I}) where {I<:SizedImage{SIZE, <:Union{BinaryPixel, IntensityPixel}}} where SIZE
    IT, PT, S = _get_image_type(I), _get_image_pixel_type(I), _get_image_tuple_size(I)
    S1, S2 = S.parameters[1], S.parameters[2]
    _validate_factory_type(IT)

    m1 = @eval ((img::CONCT, k_n::Number, args::Vararg{Any}) where {CONCT<:SizedImage{$(SIZE), <:Union{BinaryPixel, IntensityPixel}}}) -> begin
        k = round(Int, k_n)
        k = k % 2 == 0 ? k + 1 : k
        k = clamp(k, 3, 13)
        se = strel_diamond((k, k))
        res = mlaplacian(reinterpret(img.img), se)
        res = image2D_basic._normalize_img(res)
        clamp01nan!(res)
        res_ = cast($IT, res)  
        return SImageND($PT.(res_), $S)
    end

    # TODO k,k
    # TODO Box SE

    m2 = @eval ((img::CONCT, args::Vararg{Any}) where {CONCT<:SizedImage{$(SIZE), <:Union{BinaryPixel, IntensityPixel}}}) -> begin
        res = mlaplacian(reinterpret(img.img))
        res = image2D_basic._normalize_img(res)
        clamp01nan!(res)
        res_ = cast($IT, res)  
        return SImageND($PT.(res_), $S)
    end

    ManualDispatcher((m1, m2), :morpholaplace_2D)
end


# Factory Methods
append_method!(bundle_image2DIntensity_morph_factory, erosion_image2D_factory, :erosion_2D)
append_method!(bundle_image2DIntensity_morph_factory, dilation_image2D_factory, :dilation_2D)
append_method!(bundle_image2DIntensity_morph_factory, opening_image2D_factory, :opening_2D)
append_method!(bundle_image2DIntensity_morph_factory, closing_image2D_factory, :closing_2D)
append_method!(bundle_image2DIntensity_morph_factory, tophat_image2D_factory, :tophat_2D)
append_method!(bundle_image2DIntensity_morph_factory, bothat_image2D_factory, :bothat_2D)
append_method!(bundle_image2DIntensity_morph_factory, morphogradient_image2D_factory, :morphogradient_2D)
append_method!(bundle_image2DIntensity_morph_factory, morpholaplace_image2D_factory, :morpholaplace_2D)
# 


append_method!(bundle_image2DBinary_morph_factory, erosion_image2D_factory, :erosion_2D)
append_method!(bundle_image2DBinary_morph_factory, dilation_image2D_factory, :dilation_2D)
append_method!(bundle_image2DBinary_morph_factory, opening_image2D_factory, :opening_2D)
append_method!(bundle_image2DBinary_morph_factory, closing_image2D_factory, :closing_2D)
append_method!(bundle_image2DBinary_morph_factory, tophat_image2D_factory, :tophat_2D)
append_method!(bundle_image2DBinary_morph_factory, bothat_image2D_factory, :bothat_2D)
append_method!(bundle_image2DBinary_morph_factory, morphogradient_image2D_factory, :morphogradient_2D)
append_method!(bundle_image2DBinary_morph_factory, morpholaplace_image2D_factory, :morpholaplace_2D)

end
