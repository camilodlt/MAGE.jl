# -*- coding: utf-8 -*-

""" Binarization functions

Exports :

- **bundle\\image2D\\_basic** :
    - `binarize\\_adaptive2D`
    - `binarize\\_manual2D`
    - Others #TODO
"""

module image2D_binarize

using Base: error_if_canonical_getindex
using ImageBinarization
using ..UTCGP: ManualDispatcher
using ..UTCGP: FunctionBundle, append_method!
using Statistics: mean
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
bundle_image2D_binarize = FunctionBundle(fallback)
bundle_image2D_binarize_factory = FunctionBundle(fallback)

# ################### #
# Binarize            #
# ################### #
"""

CONCT is something like : UTCGP.SImageND{Tuple{512, 512}, FixedPointNumbers.N0f8, 2, Matrix{FixedPointNumbers.N0f8}}
"""
function _extract_image_size_from_image_type(CONCT::DataType)
    width::Int = CONCT.parameters[1].parameters[1]
    height::Int = CONCT.parameters[1].parameters[2]
    width, height
end

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
function binarizeAdaptive_image2D_factory(i::Type{I}) where {I<:SizedImage}

    TT = Base.unwrap_unionall(I).parameters[2] # Image type
    _validate_factory_type(TT)

    m1 = @eval ((img::CONCT, w::Int, p::Int, args::Vararg{Any}) where {CONCT<:$I}) -> begin
        # max window size
        img_w, img_h = _extract_image_size_from_image_type(CONCT)
        max_w::Int = floor(Int, min(img_w, img_h))

        p = clamp(p, 0, 100) # percentage diff of pixel t for calling it background
        w = clamp(w, 9, max_w)
        f = AdaptiveThreshold(window_size = w, percentage = p)
        return SImageND(binarize(img.img, f))
    end

    m2 = @eval ((img::CONCT, w::Int, args::Vararg{Any}) where {CONCT<:$I}) -> begin
        # max window size
        img_w, img_h = _extract_image_size_from_image_type(CONCT)
        max_w::Int = floor(Int, min(img_w, img_h))

        w = clamp(w, 9, max_w)
        f = AdaptiveThreshold(window_size = w)
        return SImageND(binarize(img.img, f))
    end

    m3 = @eval ((img::CONCT, args::Vararg{Any}) where {CONCT<:$I}) -> begin
        f = AdaptiveThreshold(img.img) # adaptive window size and percentage
        return SImageND(binarize(img.img, f))
    end

    ManualDispatcher((m1, m2, m3), :binarize_adaptive2D)
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
function binarizeManual_image2D_factory(i::Type{I}) where {I<:SizedImage}

    TT = Base.unwrap_unionall(I).parameters[2] # Image type
    _validate_factory_type(TT)

    m1 = @eval ((img::CONCT, t::Int, args::Vararg{Any}) where {CONCT<:$I}) -> begin
        t_f = t / 100
        t_f = clamp(t_f, 0.0, 1.0) # new th
        new_img = float(img.img) .> t_f
        return SImageND($TT.(new_img))
    end

    m2 = @eval ((img::CONCT, t::Float64, args::Vararg{Any}) where {CONCT<:$I}) -> begin
        t = clamp(t, 0.0, 1.0) # new th
        new_img = img .> t
        return SImageND($TT.(new_img))
    end

    m3 = @eval ((img1::CONCT, img2::CONCT, args::Vararg{Any}) where {CONCT<:$I}) -> begin
        new_img = img1 .> mean(img2)
        return SImageND($TT.(new_img))
    end

    m4 = @eval ((img::CONCT, args::Vararg{Any}) where {CONCT<:$I}) -> begin
        new_img = img .> 0.5
        return SImageND($TT.(new_img))
    end

    ManualDispatcher((m1, m2, m3, m4), :binarize_manual2D)
end


##############################
#   HISTOGRAM BINARIZERS      #
##############################

# OTSU

"""
"""
# function binarizeAdaptive_image2D_factory(i::Type{I}) where {I<:SizedImage}

#     TT = Base.unwrap_unionall(I).parameters[2] # Image type
#     _validate_factory_type(TT)

#     m1 = @eval ((img::CONCT, w::Int, p::Int, args::Vararg{Any}) where {CONCT<:$I}) -> begin
#         # max window size
#         img_w, img_h = _extract_image_size_from_image_type(CONCT)
#         max_w::Int = floor(Int, min(img_w, img_h))

#         p = clamp(p, 0, 100) # percentage diff of pixel t for calling it background
#         w = clamp(w, 9, max_w)
#         f = AdaptiveThreshold(window_size = w, percentage = p)
#         return SImageND(binarize(img.img, f))
#     end

#     ManualDispatcher((), :binarize_otsu2D)
# end



# Factory Methods
append_method!(
    bundle_image2D_binarize_factory,
    binarizeAdaptive_image2D_factory,
    :binarize_adaptive2D,
)
append_method!(
    bundle_image2D_binarize_factory,
    binarizeManual_image2D_factory,
    :binarize_manual2D,
)

# Default
bAdaptive_default = binarizeAdaptive_image2D_factory(SImageND{<:Tuple,N0f8,2})
append_method!(bundle_image2D_binarize, bAdaptive_default)

# Default Manual Binarizer
bManual_default = binarizeManual_image2D_factory(SImageND{<:Tuple,N0f8,2})
append_method!(bundle_image2D_binarize, bManual_default)
end
