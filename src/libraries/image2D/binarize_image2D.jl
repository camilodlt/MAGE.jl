# -*- coding: utf-8 -*-

""" Binarization functions

Exports :

- **bundle\\image2D\\_basic** :
    - `binarize\\_adaptive2D`
    - `binarize\\_niblack2D`
    - `binarize\\_polysegment2D`
    - `binarize\\_sauvola2D`
    - `binarize\\_otsu2D`
    - `binarize\\_minimumintermodes2D`
    - `binarize\\_intermodes2D`
    - `binarize\\_minimumerror2D`
    - `binarize\\_moments2D`
    - `binarize\\_unimodalrosin2D`
    - `binarize\\_entropy2D`
    - `binarize\\_balanced2D`
    - `binarize\\_yen2D`
    - `binarize\\_manual2D`
"""

module image2D_binarize

using ImageBinarization
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
using Statistics: mean
using Logging

cast = image2D_morph.cast
fallback(args...) = return nothing
bundle_image2DBinary_binarize_factory = FunctionBundle(fallback)

# ################### #
# Binarize            #
# ################### #

"""

The binarizers returns a 2D Image of 0,1

This Dispatcher holds the following functions: 

- binarize_adaptive2D(img, w, p)
- binarize_adaptive2D(img, w)
- binarize_adaptive2D(img)

`w` is the window size. `p` is the percentage. The higher `p`, the more conservative for considering pixels as background.

https://juliaimages.org/ImageBinarization.jl/stable/reference/#ImageBinarization.AdaptiveThreshold

### Constraints

- `p` between 0, 100
- `w` between 9 and `min(width,height)`
"""
function binarizeAdaptive_image2D_factory(i::Type{I}) where {I<:SizedImage{SIZE, <:BinaryPixel}} where SIZE
    IT, PT, S = _get_image_type(I), _get_image_pixel_type(I), _get_image_tuple_size(I)
    S1, S2 = S.parameters[1], S.parameters[2]
    _validate_factory_type(IT)

    SMALLER_AXIS = floor(Int, min(S1, S2))

    m1 = @eval ((img::CONCT, w_n::Number, p_n::Number, args::Vararg{Any}) where {T, CONCT<:SizedImage{$(SIZE), IntensityPixel{T}}}) -> begin
        w = round(Int, w_n)
        p = round(Int, p_n)
        max_w::Int = $SMALLER_AXIS
        p = clamp(p, 0, 100) # percentage diff of pixel t for calling it background
        w = clamp(w, 5, max_w)
        f = AdaptiveThreshold(window_size = w, percentage = p)
        res = binarize(reinterpret(img.img), f)
        clamp01nan!(res)
        return SImageND($PT.(cast($IT, res)), $S)
    end

    m2 = @eval ((img::CONCT, w_n::Number, args::Vararg{Any}) where {T, CONCT<:SizedImage{$(SIZE), IntensityPixel{T}}}) -> begin
        w = round(Int, w_n)
        max_w::Int = $SMALLER_AXIS
        w = clamp(w, 5, max_w)
        f = AdaptiveThreshold(window_size = w)
        res = binarize(reinterpret(img.img), f)
        clamp01nan!(res)
        return SImageND($PT.(cast($IT, res)), $S)
    end

    m3 = @eval ((img::CONCT, args::Vararg{Any}) where {T, CONCT<:SizedImage{$(SIZE), IntensityPixel{T}}}) -> begin
        img_ = reinterpret(img.img)
        f = AdaptiveThreshold(img_) # adaptive window size and percentage
        res = binarize(img_, f)
        clamp01nan!(res)
        return SImageND($PT.(cast($IT, res)), $S)
    end

    ManualDispatcher((m1, m2, m3), :binarize_adaptive2D)
end

# Niblack
function binarizeNiblack_image2D_factory(i::Type{I}) where {I<:SizedImage{SIZE, <:BinaryPixel}} where SIZE
    IT, PT, S = _get_image_type(I), _get_image_pixel_type(I), _get_image_tuple_size(I)
    S1, S2 = S.parameters[1], S.parameters[2]
    _validate_factory_type(IT)

    SMALLER_AXIS = floor(Int, min(S1, S2))

    m1 = @eval ((img::CONCT, w_n::Number, p_n::Number, args::Vararg{Any}) where {T, CONCT<:SizedImage{$(SIZE), IntensityPixel{T}}}) -> begin
        w = round(Int, w_n)
        p = convert(Float64, p_n)
        max_w::Int = $SMALLER_AXIS
        w = clamp(w, 5, max_w)
        p = clamp(p, -1, +1) 
        f = Niblack(;window_size = w, bias= p)
        res = binarize(reinterpret(img.img), f)
        clamp01nan!(res)
        return SImageND($PT.(cast($IT, res)), $S)
    end

    m2 = @eval ((img::CONCT, w_n::Number, args::Vararg{Any}) where {T, CONCT<:SizedImage{$(SIZE), IntensityPixel{T}}}) -> begin
        w = round(Int, w_n)
        max_w::Int = $SMALLER_AXIS
        w = clamp(w, 5, max_w)
        f = Niblack(;window_size = w)
        res = binarize(reinterpret(img.img), f)
        clamp01nan!(res)
        return SImageND($PT.(cast($IT, res)), $S)
    end

    m3 = @eval ((img::CONCT, args::Vararg{Any}) where {T, CONCT<:SizedImage{$(SIZE), IntensityPixel{T}}}) -> begin
        f = Niblack()
        res = binarize(reinterpret(img.img), f)
        clamp01nan!(res)
        return SImageND($PT.(cast($IT, res)), $S)
    end

    ManualDispatcher((m1, m2, m3), :binarize_niblack2D)
end

# Polysegment
function binarizePolysegment_image2D_factory(i::Type{I}) where {I<:SizedImage{SIZE, <:BinaryPixel}} where SIZE
    IT, PT, S = _get_image_type(I), _get_image_pixel_type(I), _get_image_tuple_size(I)
    S1, S2 = S.parameters[1], S.parameters[2]
    _validate_factory_type(IT)
    SMALLER_AXIS = floor(Int, min(S1, S2))

    m1 = @eval ((img::CONCT, args::Vararg{Any}) where {T, CONCT<:SizedImage{$(SIZE), IntensityPixel{T}}}) -> begin
        f = Polysegment()
        res = binarize(float(img.img), f)
        clamp01nan!(res)
        return SImageND($PT.(cast($IT, res)), $S)
    end
    m1
end

# Sauvola
function binarizeSauvola_image2D_factory(i::Type{I}) where {I<:SizedImage{SIZE, <:BinaryPixel}} where SIZE
    IT, PT, S = _get_image_type(I), _get_image_pixel_type(I), _get_image_tuple_size(I)
    S1, S2 = S.parameters[1], S.parameters[2]
    _validate_factory_type(IT)
    SMALLER_AXIS = floor(Int, min(S1, S2))

    m1 = @eval ((img::CONCT, w_n::Number, p_n::Number, args::Vararg{Any}) where {T, CONCT<:SizedImage{$(SIZE), IntensityPixel{T}}}) -> begin
        w = round(Int, w_n)
        p = convert(Float64, p_n)
        max_w::Int = $SMALLER_AXIS
        w = clamp(w, 5, max_w)
        p = clamp(p, -1, +1) 
        f = Sauvola(;window_size = w, bias= p)
        res = binarize(reinterpret(img.img), f)
        clamp01nan!(res)
        return SImageND($PT.(cast($IT, res)), $S)
    end

    m2 = @eval ((img::CONCT, w_n::Number, args::Vararg{Any}) where {T, CONCT<:SizedImage{$(SIZE), IntensityPixel{T}}}) -> begin
        w = round(Int, w_n)
        max_w::Int = $SMALLER_AXIS
        w = clamp(w, 5, max_w)
        f = Sauvola(;window_size = w)
        res = binarize(reinterpret(img.img), f)
        clamp01nan!(res)
        return SImageND($PT.(cast($IT, res)), $S)
    end

    m3 = @eval ((img::CONCT, args::Vararg{Any}) where {T, CONCT<:SizedImage{$(SIZE), IntensityPixel{T}}}) -> begin
        f = Sauvola()
        res = binarize(reinterpret(img.img), f)
        clamp01nan!(res)
        return SImageND($PT.(cast($IT, res)), $S)
    end

    ManualDispatcher((m1, m2, m3), :binarize_sauvola2D)
end


# HISTOGRAM BASED
# Otsu
function binarizeOtsu_image2D_factory(i::Type{I}) where {I<:SizedImage{SIZE, <:BinaryPixel}} where SIZE
    IT, PT, S = _get_image_type(I), _get_image_pixel_type(I), _get_image_tuple_size(I)
    S1, S2 = S.parameters[1], S.parameters[2]
    _validate_factory_type(IT)
    SMALLER_AXIS = floor(Int, min(S1, S2))

    m1 = @eval ((img::CONCT, n_bins::Number, args::Vararg{Any}) where {T, CONCT<:SizedImage{$(SIZE), IntensityPixel{T}}}) -> begin
        n_bins = round(Int, n_bins)
        n_bins = clamp(n_bins, 30, 500)
        f = Otsu()
        res = binarize(reinterpret(img.img), f; nbins = n_bins)
        clamp01nan!(res)
        return SImageND($PT.(cast($IT, res)), $S)
    end

    m2 = @eval ((img::CONCT, args::Vararg{Any}) where {T, CONCT<:SizedImage{$(SIZE), IntensityPixel{T}}}) -> begin
        f = Otsu()
        res = binarize(reinterpret(img.img), f; nbins = 256)
        clamp01nan!(res)
        return SImageND($PT.(cast($IT, res)), $S)
    end

    ManualDispatcher((m1, m2), :binarize_otsu2D)
end

# MinimumIntermodes
function binarizeMinimumintermodes_image2D_factory(i::Type{I}) where {I<:SizedImage{SIZE, <:BinaryPixel}} where SIZE
    IT, PT, S = _get_image_type(I), _get_image_pixel_type(I), _get_image_tuple_size(I)
    S1, S2 = S.parameters[1], S.parameters[2]
    _validate_factory_type(IT)
    SMALLER_AXIS = floor(Int, min(S1, S2))

    m1 = @eval ((img::CONCT, n_bins::Number, args::Vararg{Any}) where {T, CONCT<:SizedImage{$(SIZE), IntensityPixel{T}}}) -> begin
        n_bins = round(Int, n_bins)
        n_bins = clamp(n_bins, 30, 500)
        f = MinimumIntermodes()
        res = with_logger(NullLogger()) do 
            binarize(reinterpret(img.img), f; nbins = n_bins)
        end
        clamp01nan!(res)
        return SImageND($PT.(cast($IT, res)), $S)
    end

    m2 = @eval ((img::CONCT, args::Vararg{Any}) where {T, CONCT<:SizedImage{$(SIZE), IntensityPixel{T}}}) -> begin
        f = MinimumIntermodes()
        res = with_logger(NullLogger()) do 
            binarize(reinterpret(img.img), f; nbins = 256)
        end
        clamp01nan!(res)
        return SImageND($PT.(cast($IT, res)), $S)
    end

    ManualDispatcher((m1, m2), :binarize_minimumintermodes2D)
end

# Intermodes
function binarizeIntermodes_image2D_factory(i::Type{I}) where {I<:SizedImage{SIZE, <:BinaryPixel}} where SIZE
    IT, PT, S = _get_image_type(I), _get_image_pixel_type(I), _get_image_tuple_size(I)
    S1, S2 = S.parameters[1], S.parameters[2]
    _validate_factory_type(IT)
    SMALLER_AXIS = floor(Int, min(S1, S2))

    m1 = @eval ((img::CONCT, n_bins::Number, args::Vararg{Any}) where {T, CONCT<:SizedImage{$(SIZE), IntensityPixel{T}}}) -> begin
        n_bins = round(Int, n_bins)
        n_bins = clamp(n_bins, 30, 500)
        f = Intermodes()
        res = with_logger(NullLogger()) do 
            binarize(reinterpret(img.img), f; nbins = n_bins)
        end
        clamp01nan!(res)
        return SImageND($PT.(cast($IT, res)), $S)
    end

    m2 = @eval ((img::CONCT, args::Vararg{Any}) where {T, CONCT<:SizedImage{$(SIZE), IntensityPixel{T}}}) -> begin
        f = Intermodes()
        res = with_logger(NullLogger()) do 
            binarize(reinterpret(img.img), f; nbins = 256)
        end
        clamp01nan!(res)
        return SImageND($PT.(cast($IT, res)), $S)
    end

    ManualDispatcher((m1, m2), :binarize_intermodes2D)
end

# MinimumError
function binarizeMinimumError_image2D_factory(i::Type{I}) where {I<:SizedImage{SIZE, <:BinaryPixel}} where SIZE
    IT, PT, S = _get_image_type(I), _get_image_pixel_type(I), _get_image_tuple_size(I)
    S1, S2 = S.parameters[1], S.parameters[2]
    _validate_factory_type(IT)
    SMALLER_AXIS = floor(Int, min(S1, S2))

    m1 = @eval ((img::CONCT, n_bins::Number, args::Vararg{Any}) where {T, CONCT<:SizedImage{$(SIZE), IntensityPixel{T}}}) -> begin
        n_bins = round(Int, n_bins)
        n_bins = clamp(n_bins, 30, 500)
        f = MinimumError()
        res = binarize(reinterpret(img.img), f; nbins = n_bins)
        clamp01nan!(res)
        return SImageND($PT.(cast($IT, res)), $S)
    end

    m2 = @eval ((img::CONCT, args::Vararg{Any}) where {T, CONCT<:SizedImage{$(SIZE), IntensityPixel{T}}}) -> begin
        f = MinimumError()
        res = binarize(reinterpret(img.img), f; nbins = 256)
        clamp01nan!(res)
        return SImageND($PT.(cast($IT, res)), $S)
    end

    ManualDispatcher((m1, m2), :binarize_minimumerror2D)
end

# Moments
function binarizeMoments_image2D_factory(i::Type{I}) where {I<:SizedImage{SIZE, <:BinaryPixel}} where SIZE
    IT, PT, S = _get_image_type(I), _get_image_pixel_type(I), _get_image_tuple_size(I)
    S1, S2 = S.parameters[1], S.parameters[2]
    _validate_factory_type(IT)
    SMALLER_AXIS = floor(Int, min(S1, S2))

    m1 = @eval ((img::CONCT, n_bins::Number, args::Vararg{Any}) where {T, CONCT<:SizedImage{$(SIZE), IntensityPixel{T}}}) -> begin
        n_bins = round(Int, n_bins)
        n_bins = clamp(n_bins, 30, 500)
        f = Moments()
        res = binarize(reinterpret(img.img), f; nbins = n_bins)
        clamp01nan!(res)
        return SImageND($PT.(cast($IT, res)), $S)
    end

    m2 = @eval ((img::CONCT, args::Vararg{Any}) where {T, CONCT<:SizedImage{$(SIZE), IntensityPixel{T}}}) -> begin
        f = Moments()
        res = binarize(reinterpret(img.img), f; nbins = 256)
        clamp01nan!(res)
        return SImageND($PT.(cast($IT, res)), $S)
    end

    ManualDispatcher((m1, m2), :binarize_moments2D)
end
 
# UnimodalRosin
function binarizeUnimodalRosin_image2D_factory(i::Type{I}) where {I<:SizedImage{SIZE, <:BinaryPixel}} where SIZE
    IT, PT, S = _get_image_type(I), _get_image_pixel_type(I), _get_image_tuple_size(I)
    S1, S2 = S.parameters[1], S.parameters[2]
    _validate_factory_type(IT)
    SMALLER_AXIS = floor(Int, min(S1, S2))

    m1 = @eval ((img::CONCT, n_bins::Number, args::Vararg{Any}) where {T, CONCT<:SizedImage{$(SIZE), IntensityPixel{T}}}) -> begin
        n_bins = round(Int, n_bins)
        n_bins = clamp(n_bins, 30, 500)
        f = UnimodalRosin()
        res = binarize(reinterpret(img.img), f; nbins = n_bins)
        clamp01nan!(res)
        return SImageND($PT.(cast($IT, res)), $S)
    end

    m2 = @eval ((img::CONCT, args::Vararg{Any}) where {T, CONCT<:SizedImage{$(SIZE), IntensityPixel{T}}}) -> begin
        f = UnimodalRosin()
        res = binarize(reinterpret(img.img), f; nbins = 256)
        clamp01nan!(res)
        return SImageND($PT.(cast($IT, res)), $S)
    end

    ManualDispatcher((m1, m2), :binarize_unimodalrosin2D)
end

# Entropy
function binarizeEntropy_image2D_factory(i::Type{I}) where {I<:SizedImage{SIZE, <:BinaryPixel}} where SIZE
    IT, PT, S = _get_image_type(I), _get_image_pixel_type(I), _get_image_tuple_size(I)
    S1, S2 = S.parameters[1], S.parameters[2]
    _validate_factory_type(IT)
    SMALLER_AXIS = floor(Int, min(S1, S2))

    m1 = @eval ((img::CONCT, n_bins::Number, args::Vararg{Any}) where {T, CONCT<:SizedImage{$(SIZE), IntensityPixel{T}}}) -> begin
        n_bins = round(Int, n_bins)
        n_bins = clamp(n_bins, 30, 500)
        f = Entropy()
        res = with_logger(NullLogger()) do 
            binarize(reinterpret(img.img), f; nbins = n_bins)
        end
        clamp01nan!(res)
        return SImageND($PT.(cast($IT, res)), $S)
    end

    m2 = @eval ((img::CONCT, args::Vararg{Any}) where {T, CONCT<:SizedImage{$(SIZE), IntensityPixel{T}}}) -> begin
        f = Entropy()
        res = with_logger(NullLogger()) do 
            binarize(reinterpret(img.img), f; nbins = 256)
        end
        clamp01nan!(res)
        return SImageND($PT.(cast($IT, res)), $S)
    end

    ManualDispatcher((m1, m2), :binarize_entropy2D)
end

# Balanced
function binarizeBalanced_image2D_factory(i::Type{I}) where {I<:SizedImage{SIZE, <:BinaryPixel}} where SIZE
    IT, PT, S = _get_image_type(I), _get_image_pixel_type(I), _get_image_tuple_size(I)
    S1, S2 = S.parameters[1], S.parameters[2]
    _validate_factory_type(IT)
    SMALLER_AXIS = floor(Int, min(S1, S2))

    m1 = @eval ((img::CONCT, n_bins::Number, args::Vararg{Any}) where {T, CONCT<:SizedImage{$(SIZE), IntensityPixel{T}}}) -> begin
        n_bins = round(Int, n_bins)
        n_bins = clamp(n_bins, 30, 500)
        f = Balanced()
        res = with_logger(NullLogger()) do 
            binarize(reinterpret(img.img), f; nbins = n_bins)
        end
        clamp01nan!(res)
        return SImageND($PT.(cast($IT, res)), $S)
    end

    m2 = @eval ((img::CONCT, args::Vararg{Any}) where {T, CONCT<:SizedImage{$(SIZE), IntensityPixel{T}}}) -> begin
        f = Balanced()
        res = with_logger(NullLogger()) do 
            binarize(reinterpret(img.img), f; nbins = 256)
        end
        clamp01nan!(res)
        return SImageND($PT.(cast($IT, res)), $S)
    end

    ManualDispatcher((m1, m2), :binarize_balanced2D)
end

# Yen
function binarizeYen_image2D_factory(i::Type{I}) where {I<:SizedImage{SIZE, <:BinaryPixel}} where SIZE
    IT, PT, S = _get_image_type(I), _get_image_pixel_type(I), _get_image_tuple_size(I)
    S1, S2 = S.parameters[1], S.parameters[2]
    _validate_factory_type(IT)
    SMALLER_AXIS = floor(Int, min(S1, S2))

    m1 = @eval ((img::CONCT, n_bins::Number, args::Vararg{Any}) where {T, CONCT<:SizedImage{$(SIZE), IntensityPixel{T}}}) -> begin
        n_bins = round(Int, n_bins)
        n_bins = clamp(n_bins, 30, 500)
        f = Yen()
        res = binarize(reinterpret(img.img), f; nbins = n_bins)
        clamp01nan!(res)
        return SImageND($PT.(cast($IT, res)), $S)
    end

    m2 = @eval ((img::CONCT, args::Vararg{Any}) where {T, CONCT<:SizedImage{$(SIZE), IntensityPixel{T}}}) -> begin
        f = Yen()
        res = binarize(reinterpret(img.img), f; nbins = 256)
        clamp01nan!(res)
        return SImageND($PT.(cast($IT, res)), $S)
    end

    ManualDispatcher((m1, m2), :binarize_yen2D)
end

# Manual Binarizer 

"""

Manual Binarizer uses manual thresholds to filter the image. 

The functions in the dispatcher are : 
- manual_binarize(img), the threshold is 0.5 
- manual_binarize(img, t::Int) : the threshold is t/100 and then clamped ∈ [0,1]
- manual_binarize(img, t::Float) : the threshold is t if ∈ [0,1]
- manual_binarize(img1, img2) : the threshold is the mean of img2

"""
function binarizeManual_image2D_factory(i::Type{I}) where {I<:SizedImage{SIZE, <:BinaryPixel}} where SIZE
    IT, PT, S = _get_image_type(I), _get_image_pixel_type(I), _get_image_tuple_size(I)
    S1, S2 = S.parameters[1], S.parameters[2]
    _validate_factory_type(IT)
    SMALLER_AXIS = floor(Int, min(S1, S2))

    m1 = @eval ((img::CONCT, t::AbstractFloat, args::Vararg{Any}) where {T, CONCT<:SizedImage{$(SIZE), IntensityPixel{T}}}) -> begin
        t = clamp(t, 0.0, 1.0)
        new_img = float(img) .>= t
        return SImageND($PT.(cast($IT, new_img)), $S)
    end

    m2 = @eval ((img::CONCT, t_n::Number, args::Vararg{Any}) where {T, CONCT<:SizedImage{$(SIZE), IntensityPixel{T}}}) -> begin
        t = round(Int, t_n)
        t_f = t / 255
        t_f = clamp(t_f, 0.0, 1.0) # new th
        new_img = float(img.img) .>= t_f
        return SImageND($PT.(cast($IT, new_img)), $S)
    end

    m3 = @eval ((img1::CONCT, img2::CONCT, args::Vararg{Any}) where {T, CONCT<:SizedImage{$(SIZE), IntensityPixel{T}}}) -> begin
        new_img = float(img1) .>= mean(float(img2))
        return SImageND($PT.(cast($IT, new_img)), $S)
    end

    m4 = @eval ((img::CONCT, args::Vararg{Any}) where {T, CONCT<:SizedImage{$(SIZE), IntensityPixel{T}}}) -> begin
        new_img = float(img) .>= 0.5
        return SImageND($PT.(cast($IT, new_img)), $S)
    end

    ManualDispatcher((m1, m2, m3, m4), :binarize_manual2D)
end



# Factory Methods
append_method!(
    bundle_image2DBinary_binarize_factory,
    binarizeAdaptive_image2D_factory,
    :binarize_adaptive2D,
)
append_method!(
    bundle_image2DBinary_binarize_factory,
    binarizeNiblack_image2D_factory,
    :binarize_niblack2D,
)
append_method!(
    bundle_image2DBinary_binarize_factory,
    binarizePolysegment_image2D_factory,
    :binarize_polysegment2D,
)
append_method!(
    bundle_image2DBinary_binarize_factory,
    binarizeSauvola_image2D_factory,
    :binarize_sauvola2D,
)

# HISTOGRAM
append_method!(
    bundle_image2DBinary_binarize_factory,
    binarizeOtsu_image2D_factory,
    :binarize_otsu2D,
)
append_method!(
    bundle_image2DBinary_binarize_factory,
    binarizeMinimumintermodes_image2D_factory,
    :binarize_minimumintermodes2D,
)
append_method!(
    bundle_image2DBinary_binarize_factory,
    binarizeIntermodes_image2D_factory,
    :binarize_intermodes2D,
)
append_method!(
    bundle_image2DBinary_binarize_factory,
    binarizeMinimumError_image2D_factory,
    :binarize_minimumerror2D,
)
append_method!(
    bundle_image2DBinary_binarize_factory,
    binarizeMoments_image2D_factory,
    :binarize_moments2D,
)
append_method!(
    bundle_image2DBinary_binarize_factory,
    binarizeUnimodalRosin_image2D_factory,
    :binarize_unimodalrosin2D,
)
append_method!(
    bundle_image2DBinary_binarize_factory,
    binarizeEntropy_image2D_factory,
    :binarize_entropy2D,
)
append_method!(
    bundle_image2DBinary_binarize_factory,
    binarizeBalanced_image2D_factory,
    :binarize_balanced2D,
)
append_method!(
    bundle_image2DBinary_binarize_factory,
    binarizeYen_image2D_factory,
    :binarize_yen2D,
)
append_method!(
    bundle_image2DBinary_binarize_factory,
    binarizeManual_image2D_factory,
    :binarize_manual2D,
)
end
