# -*- coding: utf-8 -*-

""" EXPERIMENTAL mask image 2D

Exports :

- **bundle\\image2D\\_mask** :
    - `maskgt\\_image2D`
    - `maskeqt\\_image2D`
    - `masklt\\_image2D`
"""

module experimental_image2D_mask

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
using ImageCore: N0f8, Normed, clamp01nan!
using ..UTCGP:
    SizedImage, SImageND, _get_image_tuple_size, _get_image_type, _validate_factory_type

fallback(args...) = return nothing
experimental_bundle_image2D_mask_factory = FunctionBundle(fallback)

# ################### #
# MASK                #
# ################### #

"""


"""
function maskgt_image2D_factory(i::Type{I}) where {I<:SizedImage}
    TT = Base.unwrap_unionall(I).parameters[2] # Image type
    _validate_factory_type(TT)
    m1 = @eval (
        (img::CONCT, mask::CONCT, by::Number, args::Vararg{Any}) where {CONCT<:$I}
    ) -> begin
        by_f = convert(Float64, by)
        t_f = clamp(by_f, 0.0, 1.0) # new th
        m = float(mask.img) .> t_f # boolean mask
        img_r = img.img .* m
        return SImageND($TT.(img_r))
    end

    m2 = @eval ((img::CONCT, mask::CONCT, args::Vararg{Any}) where {CONCT<:$I}) -> begin
        t_f = 0.5
        m = float(mask.img) .> t_f # boolean mask
        img_r = img.img .* m
        return SImageND($TT.(img_r))
    end
    ManualDispatcher((m1, m2), :maskgt_image2D)
end

function maskeqt_image2D_factory(i::Type{I}) where {I<:SizedImage}
    TT = Base.unwrap_unionall(I).parameters[2] # Image type
    _validate_factory_type(TT)
    m1 = @eval (
        (img::CONCT, mask::CONCT, by::Number, args::Vararg{Any}) where {CONCT<:$I}
    ) -> begin
        by_f = convert(Float64, by)
        t_f = clamp(by_f, 0.0, 1.0) # new th
        m = float(mask.img) .== t_f # boolean mask
        img_r = img.img .* m
        return SImageND($TT.(img_r))
    end

    m2 = @eval ((img::CONCT, mask::CONCT, args::Vararg{Any}) where {CONCT<:$I}) -> begin
        t_f = 0.5
        m = float(mask.img) .== t_f # boolean mask
        img_r = img.img .* m
        return SImageND($TT.(img_r))
    end
    ManualDispatcher((m1, m2), :maskeqt_image2D)
end

function masklt_image2D_factory(i::Type{I}) where {I<:SizedImage}
    TT = Base.unwrap_unionall(I).parameters[2] # Image type
    _validate_factory_type(TT)
    m1 = @eval (
        (img::CONCT, mask::CONCT, by::Number, args::Vararg{Any}) where {CONCT<:$I}
    ) -> begin
        by_f = convert(Float64, by)
        t_f = clamp(by_f, 0.0, 1.0) # new th
        m = float(mask.img) .< t_f # boolean mask
        img_r = img.img .* m
        return SImageND($TT.(img_r))
    end

    m2 = @eval ((img::CONCT, mask::CONCT, args::Vararg{Any}) where {CONCT<:$I}) -> begin
        t_f = 0.5
        m = float(mask.img) .< t_f # boolean mask
        img_r = img.img .* m
        return SImageND($TT.(img_r))
    end
    ManualDispatcher((m1, m2), :masklt_image2D)
end

# TODO between a and b
# TODO outside a and b
# TODO invert image

# Factory Methods
append_method!(
    experimental_bundle_image2D_mask_factory,
    maskgt_image2D_factory,
    :maskgt_image2D,
)
append_method!(
    experimental_bundle_image2D_mask_factory,
    masklt_image2D_factory,
    :masklt_image2D,
)
append_method!(
    experimental_bundle_image2D_mask_factory,
    maskeqt_image2D_factory,
    :maskeqt_image2D,
)

end
