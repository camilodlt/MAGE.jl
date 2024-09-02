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
using ImageCore: N0f8, Normed, clamp01nan!, float64, Gray
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

    m1 = @eval ((img::CONCT, k_n::Number, args::Vararg{Any}) where {CONCT<:$I}) -> begin
        k = round(Int, k_n)
        S = CONCT.parameters[1] # Tuple{X,Y}
        k = k % 2 == 0 ? k + 1 : k
        k = clamp(k, 3, 13)
        se = strel_diamond((k, k))
        res = erode(img.img, se)
        clamp01nan!(res)
        res = $TT.(res)
        return SImageND(res)
    end

    # TODO k,k
    # TODO Box SE

    m2 = @eval ((img::CONCT, args::Vararg{Any}) where {CONCT<:$I}) -> begin
        S = CONCT.parameters[1] # Tuple{X,Y}
        # TTT = CONCT.parameters[2]
        s = (S.parameters[1], S.parameters[2])
        res_fixed = Matrix{$TT}(undef, s)
        # res_float = Matrix{Float64}(undef, s)
        # res_float .= float64.(img.img)
        # res_float = erode(res_float)
        erode!(res_fixed, Gray.(img.img))
        # res_fixed = $TT.(res_float)
        return SImageND(res_fixed, S)
        # return SImageND(res_fixed, S)
    end
    ManualDispatcher((m1, m2), :erosion_2D)
end

"""
    experimental_dilation_image2D(img::Array{T,2}, args...)::Array{T,2} where {T<:Number}

Dilates the image

Using Diamond Structural Element
"""
function experimental_dilation_image2D_factory(i::Type{I}) where {I<:SizedImage}

    TT = Base.unwrap_unionall(I).parameters[2]
    _validate_factory_type(TT)

    m1 = @eval ((img::CONCT, k_n::Number, args::Vararg{Any}) where {CONCT<:$I}) -> begin
        k = round(Int, k_n)
        S = CONCT.parameters[1] # Tuple{X,Y}
        k = k % 2 == 0 ? k + 1 : k
        k = clamp(k, 3, 13)
        se = strel_diamond((k, k))
        res = dilate(img.img, se)
        clamp01nan!(res)
        res = $TT.(res)
        return SImageND(res)
    end

    # TODO k,k
    # TODO Box SE

    m2 = @eval ((img::CONCT, args::Vararg{Any}) where {CONCT<:$I}) -> begin
        S = CONCT.parameters[1] # Tuple{X,Y}
        # TTT = CONCT.parameters[2]
        s = (S.parameters[1], S.parameters[2])
        res_fixed = Matrix{$TT}(undef, s)
        # res_float = Matrix{Float64}(undef, s)
        # res_float .= float64.(img.img)
        # res_float = erode(res_float)
        dilate!(res_fixed, Gray.(img.img))
        # res_fixed = $TT.(res_float)
        return SImageND(res_fixed, S)
        # return SImageND(res_fixed, S)
    end
    ManualDispatcher((m1, m2), :experimental_dilation_2D)
end

"""
    experimental_opening_image2D(img::Array{T,2}, args...)::Array{T,2} where {T<:Number}

Opens the image : dilate(erode(img))

Using Diamond Structural Element
"""
function experimental_opening_image2D_factory(i::Type{I}) where {I<:SizedImage}

    TT = Base.unwrap_unionall(I).parameters[2]
    _validate_factory_type(TT)

    m1 = @eval ((img::CONCT, k_n::Number, args::Vararg{Any}) where {CONCT<:$I}) -> begin
        k = round(Int, k_n)
        S = CONCT.parameters[1] # Tuple{X,Y}
        k = k % 2 == 0 ? k + 1 : k
        k = clamp(k, 3, 13)
        se = strel_diamond((k, k))
        res = opening(img.img, se)
        clamp01nan!(res)
        res = $TT.(res)
        return SImageND(res)
    end

    # TODO k,k
    # TODO Box SE

    m2 = @eval ((img::CONCT, args::Vararg{Any}) where {CONCT<:$I}) -> begin
        S = CONCT.parameters[1] # Tuple{X,Y}
        # TTT = CONCT.parameters[2]
        s = (S.parameters[1], S.parameters[2])
        res_fixed = Matrix{$TT}(undef, s)
        res_tmp = Matrix{$TT}(undef, s)
        # res_float = Matrix{Float64}(undef, s)
        # res_float .= float64.(img.img)
        # res_float = erode(res_float)
        opening!(res_fixed, Gray.(img.img), res_tmp)
        # res_fixed = $TT.(res_float)
        return SImageND(res_fixed, S)
    end
    ManualDispatcher((m1, m2), :experimental_opening_2D)
end

"""
    experimental_closing_image2D(img::Array{T,2}, args...)::Array{T,2} where {T<:Number}

Closes the image : erode(dilate(img))

Using Diamond Structural Element
"""
function experimental_closing_image2D_factory(i::Type{I}) where {I<:SizedImage}

    TT = Base.unwrap_unionall(I).parameters[2]
    _validate_factory_type(TT)

    m1 = @eval ((img::CONCT, k_n::Number, args::Vararg{Any}) where {CONCT<:$I}) -> begin
        k = round(Int, k_n)
        S = CONCT.parameters[1] # Tuple{X,Y}
        k = k % 2 == 0 ? k + 1 : k
        k = clamp(k, 3, 13)
        se = strel_diamond((k, k))
        res = closing(img.img, se)
        clamp01nan!(res)
        res = $TT.(res)
        return SImageND(res)
    end

    # TODO k,k
    # TODO Box SE

    m2 = @eval ((img::CONCT, args::Vararg{Any}) where {CONCT<:$I}) -> begin
        S = CONCT.parameters[1] # Tuple{X,Y}
        # TTT = CONCT.parameters[2]
        s = (S.parameters[1], S.parameters[2])
        res_fixed = Matrix{$TT}(undef, s)
        res_tmp = Matrix{$TT}(undef, s)
        # res_float = Matrix{Float64}(undef, s)
        # res_float .= float64.(img.img)
        # res_float = erode(res_float)
        closing!(res_fixed, Gray.(img.img), res_tmp)
        # res_fixed = $TT.(res_float)
        return SImageND(res_fixed, S)
        # return SImageND(res_fixed, S)
    end
    ManualDispatcher((m1, m2), :experimental_closing_2D)
end


"""
    experimental_tophat_image2D(img::Array{T,2}, args...)::Array{T,2} where {T<:Number}

Tophat the image 

Using Diamond Structural Element
"""
function experimental_tophat_image2D_factory(i::Type{I}) where {I<:SizedImage}

    TT = Base.unwrap_unionall(I).parameters[2]
    _validate_factory_type(TT)

    m1 = @eval ((img::CONCT, k_n::Number, args::Vararg{Any}) where {CONCT<:$I}) -> begin
        k = round(Int, k_n)
        S = CONCT.parameters[1] # Tuple{X,Y}
        k = k % 2 == 0 ? k + 1 : k
        k = clamp(k, 3, 13)
        se = strel_diamond((k, k))
        res = tophat(img.img, se)
        clamp01nan!(res)
        res = $TT.(res)
        return SImageND(res)
    end

    # TODO k,k
    # TODO Box SE

    m2 = @eval ((img::CONCT, args::Vararg{Any}) where {CONCT<:$I}) -> begin
        S = CONCT.parameters[1] # Tuple{X,Y}
        # TTT = CONCT.parameters[2]
        s = (S.parameters[1], S.parameters[2])
        res_fixed = Matrix{$TT}(undef, s)
        res_tmp = Matrix{$TT}(undef, s)
        # res_float = Matrix{Float64}(undef, s)
        # res_float .= float64.(img.img)
        # res_float = erode(res_float)
        tophat!(res_fixed, Gray.(img.img), res_tmp)
        # res_fixed = $TT.(res_float)
        return SImageND(res_fixed, S)
    end
    ManualDispatcher((m1, m2), :experimental_tophat_2D)
end

"""
    experimental_bothat_image2D(img::Array{T,2}, args...)::Array{T,2} where {T<:Number}

bothat hat the image 

Using Diamond Structural Element
"""
function experimental_bothat_image2D_factory(i::Type{I}) where {I<:SizedImage}

    TT = Base.unwrap_unionall(I).parameters[2]
    _validate_factory_type(TT)

    m1 = @eval ((img::CONCT, k_n::Number, args::Vararg{Any}) where {CONCT<:$I}) -> begin
        k = round(Int, k_n)
        S = CONCT.parameters[1] # Tuple{X,Y}
        k = k % 2 == 0 ? k + 1 : k
        k = clamp(k, 3, 13)
        se = strel_diamond((k, k))
        res = bothat(img.img, se)
        clamp01nan!(res)
        res = $TT.(res)
        return SImageND(res)
    end

    # TODO k,k
    # TODO Box SE

    m2 = @eval ((img::CONCT, args::Vararg{Any}) where {CONCT<:$I}) -> begin
        S = CONCT.parameters[1] # Tuple{X,Y}
        # TTT = CONCT.parameters[2]
        s = (S.parameters[1], S.parameters[2])
        res_fixed = Matrix{$TT}(undef, s)
        res_tmp = Matrix{$TT}(undef, s)
        # res_float = Matrix{Float64}(undef, s)
        # res_float .= float64.(img.img)
        # res_float = erode(res_float)
        bothat!(res_fixed, Gray.(img.img), res_tmp)
        # res_fixed = $TT.(res_float)
        return SImageND(res_fixed, S)
        # return SImageND(res_fixed, S)
    end
    ManualDispatcher((m1, m2), :experimental_bothat_2D)
end


"""
    experimental_morphogradient_image2D(img::Array{T,2}, args...)::Array{T,2} where {T<:Number}

morphogradient

Using Diamond Structural Element
"""
function experimental_morphogradient_image2D_factory(i::Type{I}) where {I<:SizedImage}

    TT = Base.unwrap_unionall(I).parameters[2]
    _validate_factory_type(TT)

    m1 = @eval ((img::CONCT, k_n::Number, args::Vararg{Any}) where {CONCT<:$I}) -> begin
        k = round(Int, k_n)
        S = CONCT.parameters[1] # Tuple{X,Y}
        k = k % 2 == 0 ? k + 1 : k
        k = clamp(k, 3, 13)
        se = strel_diamond((k, k))
        res = ImageMorphology.morphogradient(img.img, se)
        clamp01nan!(res)
        res = $TT.(res)
        return SImageND(res)
    end

    m2 = @eval ((img::CONCT, args::Vararg{Any}) where {CONCT<:$I}) -> begin
        S = CONCT.parameters[1] # Tuple{X,Y}
        res = ImageMorphology.morphogradient(img.img)
        clamp01nan!(res)
        res = $TT.(res)
        return SImageND(res, S)
    end

    ManualDispatcher((m1, m2), :experimental_morphogradient_2D)
end


"""
    experimental_morpholaplace_image2D(img::Array{T,2}, args...)::Array{T,2} where {T<:Number}

morpholaplace

Using Diamond Structural Element
"""
function experimental_morpholaplace_image2D_factory(i::Type{I}) where {I<:SizedImage}

    TT = Base.unwrap_unionall(I).parameters[2]
    _validate_factory_type(TT)

    m1 = @eval ((img::CONCT, k_n::Number, args::Vararg{Any}) where {CONCT<:$I}) -> begin
        k = round(Int, k_n)
        S = CONCT.parameters[1] # Tuple{X,Y}
        k = k % 2 == 0 ? k + 1 : k
        k = clamp(k, 3, 13)
        se = strel_diamond((k, k))
        res = ImageMorphology.morpholaplace(img.img, se)
        clamp01nan!(res)
        res = $TT.(res)
        return SImageND(res)
    end

    m2 = @eval ((img::CONCT, args::Vararg{Any}) where {CONCT<:$I}) -> begin
        S = CONCT.parameters[1] # Tuple{X,Y}
        res = ImageMorphology.morpholaplace(img.img)
        clamp01nan!(res)
        res = $TT.(res)
        return SImageND(res)
    end

    ManualDispatcher((m1, m2), :experimental_morpholaplace_2D)
end

# Factory Methods
append_method!(bundle_image2D_morph_factory, erosion_image2D_factory)
append_method!(bundle_image2D_morph_factory, experimental_dilation_image2D_factory)
append_method!(bundle_image2D_morph_factory, experimental_opening_image2D_factory)
append_method!(bundle_image2D_morph_factory, experimental_closing_image2D_factory)
append_method!(bundle_image2D_morph_factory, experimental_tophat_image2D_factory)
append_method!(bundle_image2D_morph_factory, experimental_bothat_image2D_factory)
append_method!(bundle_image2D_morph_factory, experimental_morphogradient_image2D_factory)
append_method!(bundle_image2D_morph_factory, experimental_morpholaplace_image2D_factory)

# Default
erosion_N0f8 = erosion_image2D_factory(SImageND{<:Tuple,N0f8,2})
append_method!(bundle_image2D_morph, erosion_N0f8)
end
