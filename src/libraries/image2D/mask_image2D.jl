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

using ..UTCGP: _factory_type_symbol, @serialized_factory

using ..UTCGP: output_pixels, image_result

using ..UTCGP: FunctionBundle, append_method!
using ..image2D_basic: storage_boundary
import UTCGP:
    CONSTRAINED,
    MIN_INT,
    MAX_INT,
    MIN_FLOAT,
    MAX_FLOAT,
    _positive_params,
    _ceil_positive_params
using ImageCore: N0f8, Normed, clamp01nan!
using FixedPointNumbers: rawtype
using ..UTCGP:
    IntensityPixel, SizedImage, SImageND, _get_image_tuple_size, _get_image_type, _validate_factory_type

fallback(args...) = return nothing
experimental_bundle_image2D_mask_factory = FunctionBundle(fallback)
experimental_bundle_image2D_maskregion_factory = FunctionBundle(fallback)
experimental_bundle_image2D_maskregion_relative_factory = FunctionBundle(fallback)

# ################### #
# MASK                #
# ################### #

"""


"""
# Find the storage interval with binary search once per call. Comparing the
# old floating conversion at the boundary preserves its threshold rounding.
function mask_threshold!(destination, source, mask::AbstractArray{P}, threshold, compare::F) where {T<:Normed,P<:IntensityPixel{T},F}
    isnan(threshold) && return fill!(destination, zero(eltype(destination)))
    raw_mask = reinterpret(rawtype(T), mask)
    lower = storage_boundary(T, threshold, float, false)
    upper = storage_boundary(T, threshold, float, true)
    @inbounds for index in eachindex(destination, source, raw_mask)
        value = UInt128(raw_mask[index])
        if compare === (>)
            selected = value >= upper
        elseif compare === (<)
            selected = value < lower
        else
            selected = lower <= value < upper
        end
        destination[index] = selected ? source[index] : zero(eltype(destination))
    end
    return destination
end

function mask_threshold!(destination, source, mask, threshold, compare::F) where {F}
    storage = reinterpret(fieldtype(eltype(mask), 1), mask)
    for index in eachindex(destination, source, storage)
        if compare(storage[index], threshold)
            destination[index] = source[index]
        else
            destination[index] = zero(eltype(destination))
        end
    end
    return destination
end

@serialized_factory function maskgt_image2D_factory(i::Type{I}) where {I<:SizedImage}
    TT = Base.unwrap_unionall(I).parameters[2] # Image type
    _validate_factory_type(TT)
    FUNCTION_NAME = Symbol(:maskgt_image2D, :_, _factory_type_symbol(I))
    isdefined(@__MODULE__, FUNCTION_NAME) && return Base.invokelatest(getfield, @__MODULE__, FUNCTION_NAME)
    @eval function $FUNCTION_NAME(img::CONCT, mask::CONCT, by::Number, args::Vararg{Any}; out = nothing) where {CONCT<:$I}
        by_f = convert(Float64, by)
        t_f = clamp(by_f, 0.0, 1.0) # new th
        pixels = output_pixels(out, img)
        mask_threshold!(pixels, img.img, mask.img, t_f, >)
        return image_result(out, pixels, $(_get_image_tuple_size(I)))
    end

    @eval function $FUNCTION_NAME(img::CONCT, mask::CONCT, args::Vararg{Any}; out = nothing) where {CONCT<:$I}
        t_f = 0.5
        pixels = output_pixels(out, img)
        mask_threshold!(pixels, img.img, mask.img, t_f, >)
        return image_result(out, pixels, $(_get_image_tuple_size(I)))
    end
    return Base.invokelatest(getfield, @__MODULE__, FUNCTION_NAME)
end

@serialized_factory function maskeqt_image2D_factory(i::Type{I}) where {I<:SizedImage}
    TT = Base.unwrap_unionall(I).parameters[2] # Image type
    _validate_factory_type(TT)
    FUNCTION_NAME = Symbol(:maskeqt_image2D, :_, _factory_type_symbol(I))
    isdefined(@__MODULE__, FUNCTION_NAME) && return Base.invokelatest(getfield, @__MODULE__, FUNCTION_NAME)
    @eval function $FUNCTION_NAME(img::CONCT, mask::CONCT, by::Number, args::Vararg{Any}; out = nothing) where {CONCT<:$I}
        by_f = convert(Float64, by)
        t_f = clamp(by_f, 0.0, 1.0) # new th
        pixels = output_pixels(out, img)
        mask_threshold!(pixels, img.img, mask.img, t_f, ==)
        return image_result(out, pixels, $(_get_image_tuple_size(I)))
    end

    @eval function $FUNCTION_NAME(img::CONCT, mask::CONCT, args::Vararg{Any}; out = nothing) where {CONCT<:$I}
        t_f = 0.5
        pixels = output_pixels(out, img)
        mask_threshold!(pixels, img.img, mask.img, t_f, ==)
        return image_result(out, pixels, $(_get_image_tuple_size(I)))
    end
    return Base.invokelatest(getfield, @__MODULE__, FUNCTION_NAME)
end

@serialized_factory function masklt_image2D_factory(i::Type{I}) where {I<:SizedImage}
    TT = Base.unwrap_unionall(I).parameters[2] # Image type
    _validate_factory_type(TT)
    FUNCTION_NAME = Symbol(:masklt_image2D, :_, _factory_type_symbol(I))
    isdefined(@__MODULE__, FUNCTION_NAME) && return Base.invokelatest(getfield, @__MODULE__, FUNCTION_NAME)
    @eval function $FUNCTION_NAME(img::CONCT, mask::CONCT, by::Number, args::Vararg{Any}; out = nothing) where {CONCT<:$I}
        by_f = convert(Float64, by)
        t_f = clamp(by_f, 0.0, 1.0) # new th
        pixels = output_pixels(out, img)
        mask_threshold!(pixels, img.img, mask.img, t_f, <)
        return image_result(out, pixels, $(_get_image_tuple_size(I)))
    end

    @eval function $FUNCTION_NAME(img::CONCT, mask::CONCT, args::Vararg{Any}; out = nothing) where {CONCT<:$I}
        t_f = 0.5
        pixels = output_pixels(out, img)
        mask_threshold!(pixels, img.img, mask.img, t_f, <)
        return image_result(out, pixels, $(_get_image_tuple_size(I)))
    end
    return Base.invokelatest(getfield, @__MODULE__, FUNCTION_NAME)
end

#####################
# MASK REGION       #
#####################
# Write every pixel once; equal bounds deliberately leave the source unchanged.
function _mask_band!(destination, source, axis::Int, lower, upper, outside::Bool)
    empty_band = lower == upper
    zero_pixel = eltype(destination)(0)
    @inbounds for column in axes(source, 2), row in axes(source, 1)
        position = axis == 1 ? row : column
        masked = outside ? (position < lower || position > upper) : (lower < position < upper)
        destination[row, column] = !empty_band && masked ? zero_pixel : source[row, column]
    end
    return destination
end

function _mask_cross!(destination, source, row_lower, row_upper, column_lower, column_upper)
    zero_pixel = eltype(destination)(0)
    @inbounds for column in axes(source, 2), row in axes(source, 1)
        masked = row_lower < row < row_upper || column_lower < column < column_upper
        destination[row, column] = masked ? zero_pixel : source[row, column]
    end
    return destination
end

@serialized_factory function notmaskfromtov_image2D_factory(i::Type{I}) where {I<:SizedImage}
    TT = Base.unwrap_unionall(I).parameters[2] # Image type
    _validate_factory_type(TT)

    function_name = Symbol(:notmaskfromtov_image2D_, _factory_type_symbol(I))
    isdefined(@__MODULE__, function_name) && return Base.invokelatest(getfield, @__MODULE__, function_name)
    m1 = @eval function $function_name(img_::CONCT, from::Number, to::Number, args::Vararg{Any}; out = nothing) where {CONCT<:$I}

        pixels = output_pixels(out, img_)
        from_ = round(Int, from)
        to_ = round(Int, to)
        S = _get_image_tuple_size(CONCT)
        w = S.parameters[1]
        h = S.parameters[2]
        to_ = clamp(to_, 0, h) # from 0 to all cols 
        from_ = clamp(from_, 0, to_) # from 0 to to_
        if to_ == from_
            copyto!(pixels, img_.img)
            return image_result(out, pixels, $(_get_image_tuple_size(I)))
        end
        _mask_band!(pixels, img_.img, 2, from_, to_, true)
        return image_result(out, pixels, $(_get_image_tuple_size(I)))
    end
    return m1
end

@serialized_factory function notmaskfromtoh_image2D_factory(i::Type{I}) where {I<:SizedImage}
    TT = Base.unwrap_unionall(I).parameters[2] # Image type
    _validate_factory_type(TT)

    function_name = Symbol(:notmaskfromtoh_image2D_, _factory_type_symbol(I))
    isdefined(@__MODULE__, function_name) && return Base.invokelatest(getfield, @__MODULE__, function_name)
    m1 = @eval function $function_name(img_::CONCT, from::Number, to::Number, args::Vararg{Any}; out = nothing) where {CONCT<:$I}

        pixels = output_pixels(out, img_)
        from_ = round(Int, from)
        to_ = round(Int, to)
        S = _get_image_tuple_size(CONCT)
        w = S.parameters[1]
        h = S.parameters[2]
        to_ = clamp(to_, 0, w) # from 0 to all cols 
        from_ = clamp(from_, 0, to_) # from 0 to to_
        if to_ == from_
            copyto!(pixels, img_.img)
            return image_result(out, pixels, $(_get_image_tuple_size(I)))
        end
        _mask_band!(pixels, img_.img, 1, from_, to_, true)
        return image_result(out, pixels, $(_get_image_tuple_size(I)))
    end
    return m1
end

@serialized_factory function maskfromtov_image2D_factory(i::Type{I}) where {I<:SizedImage}
    TT = Base.unwrap_unionall(I).parameters[2] # Image type
    _validate_factory_type(TT)

    function_name = Symbol(:maskfromtov_image2D_, _factory_type_symbol(I))
    isdefined(@__MODULE__, function_name) && return Base.invokelatest(getfield, @__MODULE__, function_name)
    m1 = @eval function $function_name(img_::CONCT, from::Number, to::Number, args::Vararg{Any}; out = nothing) where {CONCT<:$I}

        pixels = output_pixels(out, img_)
        from_ = round(Int, from)
        to_ = round(Int, to)
        S = _get_image_tuple_size(CONCT)
        w = S.parameters[1]
        h = S.parameters[2]
        to_ = clamp(to_, 0, h) # from 0 to all cols 
        from_ = clamp(from_, 0, to_) # from 0 to to_
        if to_ == from_
            copyto!(pixels, img_.img)
            return image_result(out, pixels, $(_get_image_tuple_size(I)))
        end
        _mask_band!(pixels, img_.img, 2, from_, to_, false)
        return image_result(out, pixels, $(_get_image_tuple_size(I)))
    end
    return m1
end

@serialized_factory function maskfromtoh_image2D_factory(i::Type{I}) where {I<:SizedImage}
    TT = Base.unwrap_unionall(I).parameters[2] # Image type
    _validate_factory_type(TT)

    function_name = Symbol(:maskfromtoh_image2D_, _factory_type_symbol(I))
    isdefined(@__MODULE__, function_name) && return Base.invokelatest(getfield, @__MODULE__, function_name)
    m1 = @eval function $function_name(img_::CONCT, from::Number, to::Number, args::Vararg{Any}; out = nothing) where {CONCT<:$I}

        pixels = output_pixels(out, img_)
        from_ = round(Int, from)
        to_ = round(Int, to)
        S = _get_image_tuple_size(CONCT)
        w = S.parameters[1]
        h = S.parameters[2]
        to_ = clamp(to_, 0, w) # from 0 to all cols 
        from_ = clamp(from_, 0, to_) # from 0 to to_
        if to_ == from_
            copyto!(pixels, img_.img)
            return image_result(out, pixels, $(_get_image_tuple_size(I)))
        end
        _mask_band!(pixels, img_.img, 1, from_, to_, false)
        return image_result(out, pixels, $(_get_image_tuple_size(I)))
    end
    return m1
end

#############################
# MASK REGION RELATIVE      #
############################
@serialized_factory function notmaskfromtov_relative_image2D_factory(i::Type{I}) where {I<:SizedImage}
    TT = Base.unwrap_unionall(I).parameters[2] # Image type
    _validate_factory_type(TT)

    function_name = Symbol(:notmaskfromtov_relative_image2D_, _factory_type_symbol(I))
    isdefined(@__MODULE__, function_name) && return Base.invokelatest(getfield, @__MODULE__, function_name)
    m1 = @eval function $function_name(img_::CONCT, from::Number, to::Number, args::Vararg{Any}; out = nothing) where {CONCT<:$I}

        pixels = output_pixels(out, img_)
        from_ = round(Int, from)
        to_ = round(Int, to)
        S = _get_image_tuple_size(CONCT)
        w = S.parameters[1]
        h = S.parameters[2]
        # soft rescales in [0,1] and then rescales in [0,h] 
        to_ = h * (tanh(2to_ - 1) + 1) / 2
        from_ = h * (tanh(2from_ - 1) + 1) / 2
        # these two rows are technically unnecessary
        to_ = clamp(to_, 0, h) # from 0 to all cols 
        from_ = clamp(from_, 0, to_) # from 0 to to_
        if to_ == from_
            copyto!(pixels, img_.img)
            return image_result(out, pixels, $(_get_image_tuple_size(I)))
        end
        _mask_band!(pixels, img_.img, 2, from_, to_, true)
        return image_result(out, pixels, $(_get_image_tuple_size(I)))
    end
    return m1
end

@serialized_factory function notmaskfromtoh_relative_image2D_factory(i::Type{I}) where {I<:SizedImage}
    TT = Base.unwrap_unionall(I).parameters[2] # Image type
    _validate_factory_type(TT)

    function_name = Symbol(:notmaskfromtoh_relative_image2D_, _factory_type_symbol(I))
    isdefined(@__MODULE__, function_name) && return Base.invokelatest(getfield, @__MODULE__, function_name)
    m1 = @eval function $function_name(img_::CONCT, from::Number, to::Number, args::Vararg{Any}; out = nothing) where {CONCT<:$I}

        pixels = output_pixels(out, img_)
        from_ = round(Int, from)
        to_ = round(Int, to)
        S = _get_image_tuple_size(CONCT)
        w = S.parameters[1]
        h = S.parameters[2]
        # soft rescales in [0,1] and then rescales in [0,w] 
        to_ = w * (tanh(2to_ - 1) + 1) / 2
        from_ = w * (tanh(2from_ - 1) + 1) / 2
        # these two rows are technically unnecessary
        to_ = clamp(to_, 0, w) # from 0 to all cols 
        from_ = clamp(from_, 0, to_) # from 0 to to_
        if to_ == from_
            copyto!(pixels, img_.img)
            return image_result(out, pixels, $(_get_image_tuple_size(I)))
        end
        _mask_band!(pixels, img_.img, 1, from_, to_, true)
        return image_result(out, pixels, $(_get_image_tuple_size(I)))
    end
    return m1
end

@serialized_factory function maskfromtov_relative_image2D_factory(i::Type{I}) where {I<:SizedImage}
    TT = Base.unwrap_unionall(I).parameters[2] # Image type
    _validate_factory_type(TT)

    function_name = Symbol(:maskfromtov_relative_image2D_, _factory_type_symbol(I))
    isdefined(@__MODULE__, function_name) && return Base.invokelatest(getfield, @__MODULE__, function_name)
    m1 = @eval function $function_name(img_::CONCT, from::Number, to::Number, args::Vararg{Any}; out = nothing) where {CONCT<:$I}

        pixels = output_pixels(out, img_)
        from_ = round(Int, from)
        to_ = round(Int, to)
        S = _get_image_tuple_size(CONCT)
        w = S.parameters[1]
        h = S.parameters[2]
        # soft rescales in [0,1] and then rescales in [0,h] 
        to_ = h * (tanh(2to_ - 1) + 1) / 2
        from_ = h * (tanh(2from_ - 1) + 1) / 2
        # these two rows are technically unnecessary
        to_ = clamp(to_, 0, h) # from 0 to all cols 
        from_ = clamp(from_, 0, to_) # from 0 to to_
        if to_ == from_
            copyto!(pixels, img_.img)
            return image_result(out, pixels, $(_get_image_tuple_size(I)))
        end
        _mask_band!(pixels, img_.img, 2, from_, to_, false)
        return image_result(out, pixels, $(_get_image_tuple_size(I)))
    end
    return m1
end

@serialized_factory function maskfromtoh_relative_image2D_factory(i::Type{I}) where {I<:SizedImage}
    TT = Base.unwrap_unionall(I).parameters[2] # Image type
    _validate_factory_type(TT)

    function_name = Symbol(:maskfromtoh_relative_image2D_, _factory_type_symbol(I))
    isdefined(@__MODULE__, function_name) && return Base.invokelatest(getfield, @__MODULE__, function_name)
    m1 = @eval function $function_name(img_::CONCT, from::Number, to::Number, args::Vararg{Any}; out = nothing) where {CONCT<:$I}

        pixels = output_pixels(out, img_)
        from_ = round(Int, from)
        to_ = round(Int, to)
        S = _get_image_tuple_size(CONCT)
        w = S.parameters[1]
        h = S.parameters[2]
        # soft rescales in [0,1] and then rescales in [0,w] 
        to_ = w * (tanh(2to_ - 1) + 1) / 2
        from_ = w * (tanh(2from_ - 1) + 1) / 2
        # these two rows are technically unnecessary
        to_ = clamp(to_, 0, w) # from 0 to all cols 
        from_ = clamp(from_, 0, to_) # from 0 to to_
        if to_ == from_
            copyto!(pixels, img_.img)
            return image_result(out, pixels, $(_get_image_tuple_size(I)))
        end
        _mask_band!(pixels, img_.img, 1, from_, to_, false)
        return image_result(out, pixels, $(_get_image_tuple_size(I)))
    end
    return m1
end

# idea of focusing the vision around a certain area
# TODO 1 range as parameter
# TODO 2 change focus shape to sphere
@serialized_factory function notmaskaround_relative_image2D_factory(i::Type{I}) where {I<:SizedImage}
    TT = Base.unwrap_unionall(I).parameters[2] # Image type
    _validate_factory_type(TT)

    function_name = Symbol(:notmaskaround_relative_image2D_, _factory_type_symbol(I))
    isdefined(@__MODULE__, function_name) && return Base.invokelatest(getfield, @__MODULE__, function_name)
    m1 = @eval function $function_name(img_::CONCT, x::Number, y::Number, args::Vararg{Any}; out = nothing) where {CONCT<:$I}

            pixels = output_pixels(out, img_)
            range = 0.25
            S = _get_image_tuple_size(CONCT)
            w = S.parameters[1]
            h = S.parameters[2]
            x_range = range * w
            y_range = range * h
            # Use the positional centre and initialise lower bounds before upper bounds.
            x_ = w * (tanh(2x - 1) + 1) / 2
            y_ = h * (tanh(2y - 1) + 1) / 2
            x_from_ = clamp(round(Int, x_ - x_range), 0, w)
            x_to_ = clamp(round(Int, x_ + x_range), x_from_, w)
            y_from_ = clamp(round(Int, y_ - y_range), 0, h)
            y_to_ = clamp(round(Int, y_ + y_range), y_from_, h)
            _mask_cross!(pixels, img_.img, x_from_, x_to_, y_from_, y_to_)
            return image_result(out, pixels, $(_get_image_tuple_size(I)))
        end
    return m1
end

# returns the binarized image: white where the color is the requested one, black elsewhere
function color_mask!(destination, source::AbstractArray{IntensityPixel{T}}, color) where {T<:Normed}
    raw = reinterpret(rawtype(T), source)
    lower = storage_boundary(T, color - 1.0 / 255.0, Float64, true)
    upper = storage_boundary(T, color + 1.0 / 255.0, Float64, false)
    @inbounds for index in eachindex(destination, raw)
        value = UInt128(raw[index])
        destination[index] = eltype(destination)(lower <= value < upper)
    end
    return destination
end

function color_mask!(destination, source, color)
    lower = color - 1.0 / 255.0
    upper = color + 1.0 / 255.0
    for index in eachindex(destination, source)
        destination[index] = eltype(destination)(lower < source[index] < upper)
    end
    return destination
end

@serialized_factory function notmaskbycolor_image2D_factory(i::Type{I}) where {I<:SizedImage}
    TT = Base.unwrap_unionall(I).parameters[2] # Image type
    _validate_factory_type(TT)
    function_name = Symbol(:notmaskbycolor_image2D_, _factory_type_symbol(I))
    isdefined(@__MODULE__, function_name) && return Base.invokelatest(getfield, @__MODULE__, function_name)
    m1 = @eval function $function_name(img_::CONCT, color::Number, args::Vararg{Any}; out = nothing) where {CONCT<:$I}

        pixels = output_pixels(out, img_)
        color_mask!(pixels, img_.img, clamp(color, 0.0, 1.0))
        return image_result(out, pixels, $(_get_image_tuple_size(I)))
    end
    return m1
end

# TODO outside a and b

# Factory Methods
append_method!(
    experimental_bundle_image2D_mask_factory,
    maskgt_image2D_factory,
    :maskgt_image2D,
    ;
    description = "Masks pixels greater than a threshold with a provided replacement value.",
)
append_method!(
    experimental_bundle_image2D_mask_factory,
    masklt_image2D_factory,
    :masklt_image2D,
    ;
    description = "Masks pixels lower than a threshold with a provided replacement value.",
)
append_method!(
    experimental_bundle_image2D_mask_factory,
    maskeqt_image2D_factory,
    :maskeqt_image2D,
    ;
    description = "Masks pixels equal to a threshold with a provided replacement value.",
)
append_method!(
    experimental_bundle_image2D_mask_factory,
    notmaskbycolor_image2D_factory,
    :experimental_notmaskbycolor_image2D,
    ;
    description = "Keeps only pixels close to a target color and masks the rest.",
)

# MASK REGION #
append_method!(
    experimental_bundle_image2D_maskregion_factory,
    notmaskfromtov_image2D_factory,
    :experimental_notmaskfromtov_image2D,
    ;
    description = "Keeps a vertical interval region and masks values outside it.",
)
append_method!(
    experimental_bundle_image2D_maskregion_factory,
    notmaskfromtoh_image2D_factory,
    :experimental_notmaskfromtoh_image2D,
    ;
    description = "Keeps a horizontal interval region and masks values outside it.",
)
append_method!(
    experimental_bundle_image2D_maskregion_factory,
    maskfromtov_image2D_factory,
    :experimental_maskfromtov_image2D,
    ;
    description = "Masks values inside a vertical interval region.",
)
append_method!(
    experimental_bundle_image2D_maskregion_factory,
    maskfromtoh_image2D_factory,
    :experimental_maskfromtoh_image2D,
    ;
    description = "Masks values inside a horizontal interval region.",
)

# MASK REGION RELATIVE #
append_method!(
    experimental_bundle_image2D_maskregion_relative_factory,
    notmaskfromtov_relative_image2D_factory,
    :experimental_notmaskfromtov_relative_image2D,
    ;
    description = "Keeps a relative vertical region and masks outside values.",
)
append_method!(
    experimental_bundle_image2D_maskregion_relative_factory,
    notmaskfromtoh_relative_image2D_factory,
    :experimental_notmaskfromtoh_relative_image2D,
    ;
    description = "Keeps a relative horizontal region and masks outside values.",
)
append_method!(
    experimental_bundle_image2D_maskregion_relative_factory,
    maskfromtov_relative_image2D_factory,
    :experimental_maskfromtov_relative_image2D,
    ;
    description = "Masks values inside a relative vertical region.",
)
append_method!(
    experimental_bundle_image2D_maskregion_relative_factory,
    maskfromtoh_relative_image2D_factory,
    :experimental_maskfromtoh_relative_image2D,
    ;
    description = "Masks values inside a relative horizontal region.",
)
append_method!(
    experimental_bundle_image2D_maskregion_relative_factory,
    notmaskaround_relative_image2D_factory,
    :experimental_notmaskaround_relative_image2D,
    ;
    description = "Keeps values around a relative center window and masks the rest.",
)

end
