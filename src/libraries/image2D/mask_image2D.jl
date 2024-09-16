# -*- coding: utf-8 -*-

""" EXPERIMENTAL mask image 2D

Exports :

- **bundle\\image2D\\_mask** :
    - `maskgt\\_image2D`
    - `maskeqt\\_image2D`
    - `masklt\\_image2D`
    - `mask_from_to\\_image2D`
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
experimental_bundle_image2D_maskregion_factory = FunctionBundle(fallback)
experimental_bundle_image2D_maskregion_relative_factory = FunctionBundle(fallback)

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

#####################
# MASK REGION       #
#####################
function notmaskfromtov_image2D_factory(i::Type{I}) where {I<:SizedImage}
    TT = Base.unwrap_unionall(I).parameters[2] # Image type
    _validate_factory_type(TT)
    m1 = @eval (
        (img_::CONCT, from::Number, to::Number, args::Vararg{Any}) where {CONCT<:$I}
    ) -> begin
        img = deepcopy(img_)
        from_ = round(Int, from)
        to_ = round(Int, to)
        S = _get_image_tuple_size(CONCT)
        w = S.parameters[1]
        h = S.parameters[2]
        to_ = clamp(to_, 0, h) # from 0 to all cols 
        from_ = clamp(from_, 0, to_) # from 0 to to_
        if to_ == from_
            return img
        end
        for i = 1:h
            if i < from_ || i > to_
                img.img[:, i] .= $TT(0)
            end
        end
        return SImageND($TT.(img))
    end
    return m1
end

function notmaskfromtoh_image2D_factory(i::Type{I}) where {I<:SizedImage}
    TT = Base.unwrap_unionall(I).parameters[2] # Image type
    _validate_factory_type(TT)
    m1 = @eval (
        (img_::CONCT, from::Number, to::Number, args::Vararg{Any}) where {CONCT<:$I}
    ) -> begin
        img = deepcopy(img_)
        from_ = round(Int, from)
        to_ = round(Int, to)
        S = _get_image_tuple_size(CONCT)
        w = S.parameters[1]
        h = S.parameters[2]
        to_ = clamp(to_, 0, w) # from 0 to all cols 
        from_ = clamp(from_, 0, to_) # from 0 to to_
        if to_ == from_
            return img
        end
        for i = 1:w
            if i < from_ || i > to_
                img.img[i, :] .= $TT(0)
            end
        end
        return SImageND($TT.(img))
    end
    return m1
end

function maskfromtov_image2D_factory(i::Type{I}) where {I<:SizedImage}
    TT = Base.unwrap_unionall(I).parameters[2] # Image type
    _validate_factory_type(TT)
    m1 = @eval (
        (img_::CONCT, from::Number, to::Number, args::Vararg{Any}) where {CONCT<:$I}
    ) -> begin
        img = deepcopy(img_)
        from_ = round(Int, from)
        to_ = round(Int, to)
        S = _get_image_tuple_size(CONCT)
        w = S.parameters[1]
        h = S.parameters[2]
        to_ = clamp(to_, 0, h) # from 0 to all cols 
        from_ = clamp(from_, 0, to_) # from 0 to to_
        if to_ == from_
            return img
        end
        for i = 1:h
            if i > from_ && i < to_
                img.img[:, i] .= $TT(0)
            end
        end
        return SImageND($TT.(img))
    end
    return m1
end

function maskfromtoh_image2D_factory(i::Type{I}) where {I<:SizedImage}
    TT = Base.unwrap_unionall(I).parameters[2] # Image type
    _validate_factory_type(TT)
    m1 = @eval (
        (img_::CONCT, from::Number, to::Number, args::Vararg{Any}) where {CONCT<:$I}
    ) -> begin
        img = deepcopy(img_)
        from_ = round(Int, from)
        to_ = round(Int, to)
        S = _get_image_tuple_size(CONCT)
        w = S.parameters[1]
        h = S.parameters[2]
        to_ = clamp(to_, 0, w) # from 0 to all cols 
        from_ = clamp(from_, 0, to_) # from 0 to to_
        if to_ == from_
            return img
        end
        for i = 1:w
            if i > from_ && i < to_
                img.img[i, :] .= $TT(0)
            end
        end
        return SImageND($TT.(img))
    end
    return m1
end

#############################
# MASK REGION RELATIVE      #
############################
function notmaskfromtov_relative_image2D_factory(i::Type{I}) where {I<:SizedImage}
    TT = Base.unwrap_unionall(I).parameters[2] # Image type
    _validate_factory_type(TT)
    m1 = @eval (
        (img_::CONCT, from::Number, to::Number, args::Vararg{Any}) where {CONCT<:$I}
    ) -> begin
        img = deepcopy(img_)
        from_ = round(Int, from)
        to_ = round(Int, to)
        S = _get_image_tuple_size(CONCT)
        w = S.parameters[1]
        h = S.parameters[2]
        # soft rescales in [0,1] and then rescales in [0,h] 
        to_ = h * (tanh(2 to_- 1) + 1) / 2
        from_ = h * (tanh(2 from_- 1) + 1) / 2
        # these two rows are technically unnecessary
        to_ = clamp(to_, 0, h) # from 0 to all cols 
        from_ = clamp(from_, 0, to_) # from 0 to to_
        if to_ == from_
            return img
        end
        for i = 1:h
            if i < from_ || i > to_
                img.img[:, i] .= $TT(0)
            end
        end
        return SImageND($TT.(img))
    end
    return m1
end

function notmaskfromtoh_relative_image2D_factory(i::Type{I}) where {I<:SizedImage}
    TT = Base.unwrap_unionall(I).parameters[2] # Image type
    _validate_factory_type(TT)
    m1 = @eval (
        (img_::CONCT, from::Number, to::Number, args::Vararg{Any}) where {CONCT<:$I}
    ) -> begin
        img = deepcopy(img_)
        from_ = round(Int, from)
        to_ = round(Int, to)
        S = _get_image_tuple_size(CONCT)
        w = S.parameters[1]
        h = S.parameters[2]
        # soft rescales in [0,1] and then rescales in [0,w] 
        to_ = w * (tanh(2 to_- 1) + 1) / 2
        from_ = w * (tanh(2 from_- 1) + 1) / 2
        # these two rows are technically unnecessary
        to_ = clamp(to_, 0, w) # from 0 to all cols 
        from_ = clamp(from_, 0, to_) # from 0 to to_
        if to_ == from_
            return img
        end
        for i = 1:w
            if i < from_ || i > to_
                img.img[i, :] .= $TT(0)
            end
        end
        return SImageND($TT.(img))
    end
    return m1
end

function maskfromtov_relative_image2D_factory(i::Type{I}) where {I<:SizedImage}
    TT = Base.unwrap_unionall(I).parameters[2] # Image type
    _validate_factory_type(TT)
    m1 = @eval (
        (img_::CONCT, from::Number, to::Number, args::Vararg{Any}) where {CONCT<:$I}
    ) -> begin
        img = deepcopy(img_)
        from_ = round(Int, from)
        to_ = round(Int, to)
        S = _get_image_tuple_size(CONCT)
        w = S.parameters[1]
        h = S.parameters[2]
        # soft rescales in [0,1] and then rescales in [0,h] 
        to_ = h * (tanh(2 to_- 1) + 1) / 2
        from_ = h * (tanh(2 from_- 1) + 1) / 2
        # these two rows are technically unnecessary
        to_ = clamp(to_, 0, h) # from 0 to all cols 
        from_ = clamp(from_, 0, to_) # from 0 to to_
        if to_ == from_
            return img
        end
        for i = 1:h
            if i > from_ && i < to_
                img.img[:, i] .= $TT(0)
            end
        end
        return SImageND($TT.(img))
    end
    return m1
end

function maskfromtoh_relative_image2D_factory(i::Type{I}) where {I<:SizedImage}
    TT = Base.unwrap_unionall(I).parameters[2] # Image type
    _validate_factory_type(TT)
    m1 = @eval (
        (img_::CONCT, from::Number, to::Number, args::Vararg{Any}) where {CONCT<:$I}
    ) -> begin
        img = deepcopy(img_)
        from_ = round(Int, from)
        to_ = round(Int, to)
        S = _get_image_tuple_size(CONCT)
        w = S.parameters[1]
        h = S.parameters[2]
        # soft rescales in [0,1] and then rescales in [0,w] 
        to_ = w * (tanh(2 to_- 1) + 1) / 2
        from_ = w * (tanh(2 from_- 1) + 1) / 2
        # these two rows are technically unnecessary
        to_ = clamp(to_, 0, w) # from 0 to all cols 
        from_ = clamp(from_, 0, to_) # from 0 to to_
        if to_ == from_
            return img
        end
        for i = 1:w
            if i > from_ && i < to_
                img.img[i, :] .= $TT(0)
            end
        end
        return SImageND($TT.(img))
    end
    return m1
end

# TODO outside a and b

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

# MASK REGION #
append_method!(
    experimental_bundle_image2D_maskregion_factory,
    notmaskfromtov_image2D_factory,
    :experimental_notmaskfromtov_image2D,
)
append_method!(
    experimental_bundle_image2D_maskregion_factory,
    notmaskfromtoh_image2D_factory,
    :experimental_notmaskfromtoh_image2D,
)
append_method!(
    experimental_bundle_image2D_maskregion_factory,
    maskfromtov_image2D_factory,
    :experimental_maskfromtov_image2D,
)
append_method!(
    experimental_bundle_image2D_maskregion_factory,
    maskfromtoh_image2D_factory,
    :experimental_maskfromtoh_image2D,
)

# MASK REGION RELATIVE #
append_method!(
    experimental_bundle_image2D_maskregion_relative_factory,
    notmaskfromtov_relative_image2D_factory,
    :experimental_notmaskfromtov_relative_image2D,
)
append_method!(
    experimental_bundle_image2D_maskregion_relative_factory,
    notmaskfromtoh_relative_image2D_factory,
    :experimental_notmaskfromtoh_relative_image2D,
)
append_method!(
    experimental_bundle_image2D_maskregion_relative_factory,
    maskfromtov_relative_image2D_factory,
    :experimental_maskfromtov_relative_image2D,
)
append_method!(
    experimental_bundle_image2D_maskregion_relative_factory,
    maskfromtoh_relative_image2D_factory,
    :experimental_maskfromtoh_relative_image2D,
)

end