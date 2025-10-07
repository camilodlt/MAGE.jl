# -*- coding: utf-8 -*-
""" Basic IMAGE 2D functions

Exports :

- **bundle\\image2D\\_basic** :
    - `identity_image2D`
    - `ones_2D`
    - `zeros_2D`

"""
module image2D_basic

using ImageCore: clamp01nan!, Normed, float64
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
using Statistics: mean, std
using ..UTCGP:
    SizedImage, SizedImage2D, SImageND, _get_image_tuple_size, _get_image_type, _validate_factory_type, _get_image_pixel_type,
    IntensityPixel, BinaryPixel, SegmentPixel

fallback(args...) = return nothing
bundle_image2DIntensity_basic_factory = FunctionBundle(fallback)
bundle_image2DSegment_basic_factory = FunctionBundle(fallback)
bundle_image2DBinary_basic_factory = FunctionBundle(fallback)

# ################### #
# IDENTITY            #
# ################### #
"""
    identity_image2D_factory(I::Type{<:SI}) where {SI<:SizedImage{S, T}} where {S,T} 

    Works for all types of pixels.
    Returns the identity of the img.   
"""
function identity_image2D_factory(I::Type{<:SI}) where {SI <: SizedImage{S, T}} where {S, T}
    return @eval function (img::$I, args::Vararg{Any})
        return identity(img)
    end
end

# ################### #
# ONES                #
# ################### #

"""
    ones_2D_factory(T::Type{<:Normed})
      
"""
function ones_2D_factory(i::Type{I}) where {I <: SizedImage2D{SIZE}} where {SIZE}
    IT, PT, S = _get_image_type(I), _get_image_pixel_type(I), _get_image_tuple_size(I)
    S1, S2 = S.parameters[1], S.parameters[2]
    _validate_factory_type(IT)

    """
    Returns a matrix of ones.
    """
    m1 = @eval (args::Vararg{Any},) -> begin
        return SImageND($PT.(ones($IT, $S1, $S2)))
    end
    return m1
end

# ################### #
# ZEROS               #
# ################### #

function zeros_2D_factory(i::Type{I}) where {I <: SizedImage2D}
    IT, PT, S = _get_image_type(I), _get_image_pixel_type(I), _get_image_tuple_size(I)
    S1, S2 = S.parameters[1], S.parameters[2]
    _validate_factory_type(IT)

    """
        zeros_(img::Array{T,2}, args...)::Array{T,2}

    Returns a matrix of zeros in the type needed.
    """
    return @eval ((img::CONCT, args::Vararg{Any}) where {CONCT <: $I}) -> begin
        return SImageND($PT.(zeros($IT, $S1, $S2)))
    end
end

# ################### #
# INVERT #
# ################### #
"""
    experimental_invert_image2D(img::Array{T,2}, args...)::Array{T,2} where {T<:Number}

"""
function experimental_invert_image2D_factory(i::Type{I}) where {I <: SizedImage}
    IT, PT, S = _get_image_type(I), _get_image_pixel_type(I), _get_image_tuple_size(I)
    # S1, S2 = S.parameters[1], S.parameters[2]
    _validate_factory_type(IT)
    return @eval function (img::CONCT, args::Vararg{Any}) where {CONCT <: $I}
        inv_ = abs.(1.0 .- float64.(img))
        clamp01nan!(inv_)
        return SImageND($PT.(inv_), $S)
    end
end

# ################### #
# Normalize           #
# ################### #

function _sanitize_img!(img::AbstractArray)
    replace!(img, NaN => 0.0)
    replace!(img, Inf => 0.0)
    return replace!(img, -Inf => 0.0)
end

function _standardise_img(img::AbstractArray)
    img_f = float.(img)
    _sanitize_img!(img_f)
    μ = mean(img_f)
    σ = std(img_f)
    img_f .= (img_f .- μ) ./ σ
    return img_f
end
function _normalize_img(img::AbstractArray)
    img_f = float.(img)
    _sanitize_img!(img_f)
    min_, max_ = minimum(img_f), maximum(img_f)
    img_f .= (img_f .- min_) ./ (max_ - min_)
    return img_f
end

"""
    experimental_normalize_image2D(img::Array{T,2}, args...)::Array{T,2} where {T<:Number}

"""
function experimental_normalize_image2D_factory(i::Type{I}) where {I <: SizedImage}
    IT, PT, S = _get_image_type(I), _get_image_pixel_type(I), _get_image_tuple_size(I)
    _validate_factory_type(IT)
    return @eval function (img::CONCT, args::Vararg{Any}) where {CONCT <: $I}
        normalized_img = _normalize_img(img)
        clamp01nan!(normalized_img)
        return SImageND($PT.(normalized_img), $S)
    end
end

function experimental_standardize_image2D_factory(i::Type{I}) where {I <: SizedImage}
    IT, PT, S = _get_image_type(I), _get_image_pixel_type(I), _get_image_tuple_size(I)
    _validate_factory_type(IT)
    return @eval function (img::CONCT, args::Vararg{Any}) where {CONCT <: $I}
        normalized_img = _standardise_img(img)
        clamp01nan!(normalized_img)
        return SImageND($PT.(normalized_img), $S)
    end
end

# Easy access to other pixels

# intensity => binary
# segment => binary
function _to_binary(img::SizedImage{S, IntensityPixel{T}}, th::Float64 = 0.0) where {S, T}
    return BinaryPixel.(reinterpret(img.img) .> th)
end
function _to_binary(img::SizedImage{S, SegmentPixel{T}}, th::Float64 = 0.0) where {S, T}
    background_segment = minimum(unique(reinterpret(img.img)))
    return BinaryPixel.(reinterpret(img.img) .!= background_segment)
end

function experimental_tobinary_image2D_factory(i::Type{I}) where {I <: SizedImage{SIZE}} where {SIZE}
    IT, PT, S = _get_image_type(I), _get_image_pixel_type(I), _get_image_tuple_size(I)
    _validate_factory_type(IT)
    return @eval function (img::CONCT, args::Vararg{Any}) where {CONCT <: SizedImage{$(SIZE), <:Union{IntensityPixel{T1}, SegmentPixel{T2}}}} where {T1, T2}
        r = _to_binary(img)
        return SImageND(r, $S)
    end
end

function experimental_tobinary_th_image2D_factory(i::Type{I}) where {I <: SizedImage{SIZE}} where {SIZE}
    IT, PT, S = _get_image_type(I), _get_image_pixel_type(I), _get_image_tuple_size(I)
    _validate_factory_type(IT)
    return @eval function (img::CONCT, th::Float64, args::Vararg{Any}) where {CONCT <: SizedImage{$(SIZE), <:Union{IntensityPixel{T1}, SegmentPixel{T2}}}} where {T1, T2}
        r = _to_binary(img, th)
        return SImageND(r, $S)
    end
end


# binary => intensity
# segment => intensity

function _to_intensity(img::SizedImage{S, BinaryPixel{T}}, TOTYPE) where {S, T}
    return IntensityPixel.(TOTYPE.(Int.(img)))
end
function _to_intensity(img::SizedImage{S, SegmentPixel{T}}, TOTYPE) where {S, T}
    r = float.(img)
    max_ = maximum(r)
    r .= r ./ max_
    r_typed = TOTYPE.(r)
    return IntensityPixel.(r_typed)
end
function experimental_tointensity_image2D_factory(i::Type{I}) where {I <: SizedImage{SIZE}} where {SIZE}
    IT, PT, S = _get_image_type(I), _get_image_pixel_type(I), _get_image_tuple_size(I)
    _validate_factory_type(IT)
    return @eval function (img::CONCT, args::Vararg{Any}) where {CONCT <: SizedImage{$(SIZE), <:Union{BinaryPixel{T1}, SegmentPixel{T2}}}} where {T1, T2}
        r = _to_intensity(img, $(IT))
        return SImageND(r, $S)
    end
end

# binary => segment
function _to_segment(img::SizedImage{S, BinaryPixel{T}}, TOTYPE) where {S, T}
    return SegmentPixel.(TOTYPE.(Int.(img)))
end
function experimental_tosegment_image2D_factory(i::Type{I}) where {I <: SizedImage{SIZE, SegmentPixel{ST}}} where {SIZE, ST}
    IT, PT, S = _get_image_type(I), _get_image_pixel_type(I), _get_image_tuple_size(I)
    _validate_factory_type(IT)
    return @eval function (img::CONCT, args::Vararg{Any}) where {CONCT <: SizedImage{$(SIZE), BinaryPixel{T}}} where {T}
        r = _to_segment(img, $IT)
        return SImageND(r, $S)
    end
end

# Factory Intensity
append_method!(bundle_image2DIntensity_basic_factory, identity_image2D_factory, :identity_image2D)
append_method!(bundle_image2DIntensity_basic_factory, ones_2D_factory, :ones_2D)
append_method!(bundle_image2DIntensity_basic_factory, zeros_2D_factory, :zeros_2D)
append_method!(bundle_image2DIntensity_basic_factory, experimental_invert_image2D_factory, :experimental_invert_2D)
append_method!(bundle_image2DIntensity_basic_factory, experimental_normalize_image2D_factory, :experimental_normalize_2D)
append_method!(bundle_image2DIntensity_basic_factory, experimental_standardize_image2D_factory, :experimental_standardize_2D)
append_method!(bundle_image2DIntensity_basic_factory, experimental_tointensity_image2D_factory, :experimental_tointensity_image2D)

# Factory Binary
append_method!(bundle_image2DBinary_basic_factory, identity_image2D_factory, :identity_image2D)
append_method!(bundle_image2DBinary_basic_factory, ones_2D_factory, :ones_2D)
append_method!(bundle_image2DBinary_basic_factory, zeros_2D_factory, :zeros_2D)
append_method!(bundle_image2DBinary_basic_factory, experimental_invert_image2D_factory, :experimental_invert_2D)
append_method!(bundle_image2DBinary_basic_factory, experimental_tobinary_image2D_factory, :experimental_tobinary_image2D)
append_method!(bundle_image2DBinary_basic_factory, experimental_tobinary_th_image2D_factory, :experimental_tobinary_th_image2D_factory)

# Factory Segment
append_method!(bundle_image2DSegment_basic_factory, identity_image2D_factory, :identity_image2D)
append_method!(bundle_image2DSegment_basic_factory, ones_2D_factory, :ones_2D)
append_method!(bundle_image2DSegment_basic_factory, zeros_2D_factory, :zeros_2D)
append_method!(bundle_image2DSegment_basic_factory, experimental_tosegment_image2D_factory, :experimental_tosegment_image2D)

end
