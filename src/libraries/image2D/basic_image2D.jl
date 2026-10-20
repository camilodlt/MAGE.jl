# -*- coding: utf-8 -*-
"""
Identity, constant images, inversion and casts between image types.

# Bundles

- [`bundle_image2DIntensity_basic_factory`](@ref)
- [`bundle_image2DBinary_basic_factory`](@ref)
- [`bundle_image2DSegment_basic_factory`](@ref)

The exhaustive, always-current list of operators in each bundle is on the
[Bundle Catalogue](@ref) page.
"""
module image2D_basic

using ..UTCGP: _factory_type_symbol, @serialized_factory

using ..UTCGP: @image_out, image_result, output_pixels, scratch, float_buffer

using ImageCore: clamp01nan!, clamp01nan, Normed, float64
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
using FixedPointNumbers: rawtype
using Statistics: mean, std
using ..UTCGP:
    SizedImage, SizedImage2D, SImageND, _get_image_tuple_size, _get_image_type, _validate_factory_type, _get_image_pixel_type,
    IntensityPixel, BinaryPixel, SegmentPixel

fallback(args...) = return nothing
"""
    bundle_image2DIntensity_basic_factory

Basic operators on intensity images: `identity_image2D`, the constant images
`ones_2D` and `zeros_2D`, `experimental_invert_2D`, the rescalings
`experimental_normalize_2D` and `experimental_standardize_2D`, and the cast
`experimental_tointensity_image2D`.

This is a *factory* bundle: each entry is a function of a type that returns the
method specialised for it, so the same operator can be instantiated for several
image or element types. See [Libraries](@ref) for how factories are specialised
into a library.
"""
bundle_image2DIntensity_basic_factory = FunctionBundle(fallback)
"""
    bundle_image2DSegment_basic_factory

Basic operators on segment images (label maps): `identity_image2D`, `ones_2D`,
`zeros_2D`, and the cast `experimental_tosegment_image2D`.

This is a *factory* bundle: each entry is a function of a type that returns the
method specialised for it, so the same operator can be instantiated for several
image or element types. See [Libraries](@ref) for how factories are specialised
into a library.
"""
bundle_image2DSegment_basic_factory = FunctionBundle(fallback)
"""
    bundle_image2DBinary_basic_factory

Basic operators on binary images (masks): `identity_image2D`, `ones_2D`,
`zeros_2D`, `experimental_invert_2D`, and the casts
`experimental_tobinary_image2D` and `experimental_tobinary_th_image2D_factory`.

This is a *factory* bundle: each entry is a function of a type that returns the
method specialised for it, so the same operator can be instantiated for several
image or element types. See [Libraries](@ref) for how factories are specialised
into a library.
"""
bundle_image2DBinary_basic_factory = FunctionBundle(fallback)

# ################### #
# IDENTITY            #
# ################### #
"""
    identity_image2D_factory(I::Type{<:SI}) where {SI<:SizedImage{S, T}} where {S,T} 

    Works for all types of pixels.
    Returns the identity of the img.   
"""
@serialized_factory function identity_image2D_factory(I::Type{<:SI}) where {SI <: SizedImage{S, T}} where {S, T}
    function_name = Symbol(:identity_image2D_, _factory_type_symbol(I))
    isdefined(@__MODULE__, function_name) && return Base.invokelatest(getfield, @__MODULE__, function_name)
    return @eval @image_out function $function_name(img::$I, args::Vararg{Any})
        return identity(img)
    end
end

# ################### #
# ONES                #
# ################### #

"""
    ones_2D_factory(T::Type{<:Normed})
      
"""
@serialized_factory function ones_2D_factory(i::Type{I}) where {I <: SizedImage2D{SIZE}} where {SIZE}
    IT, PT, S = _get_image_type(I), _get_image_pixel_type(I), _get_image_tuple_size(I)
    S1, S2 = S.parameters[1], S.parameters[2]
    _validate_factory_type(IT)

    """
    Returns a matrix of ones.
    """
    function_name = Symbol(:ones_2D_, _factory_type_symbol(I))
    isdefined(@__MODULE__, function_name) && return Base.invokelatest(getfield, @__MODULE__, function_name)
    m1 = @eval @image_out function $function_name(args::Vararg{Any},)

        if out !== nothing
            fill!(out.img,$PT(one($IT)))
            return out
        end
        return SImageND($PT.(ones($IT, $S1, $S2)), $S)
    end
    return m1
end

# ################### #
# ZEROS               #
# ################### #

@serialized_factory function zeros_2D_factory(i::Type{I}) where {I <: SizedImage2D}
    IT, PT, S = _get_image_type(I), _get_image_pixel_type(I), _get_image_tuple_size(I)
    S1, S2 = S.parameters[1], S.parameters[2]
    _validate_factory_type(IT)

    """
        zeros_(img::Array{T,2}, args...)::Array{T,2}

    Returns a matrix of zeros in the type needed.
    """
    function_name = Symbol(:zeros_2D_, _factory_type_symbol(I))
    isdefined(@__MODULE__, function_name) && return Base.invokelatest(getfield, @__MODULE__, function_name)
    return @eval @image_out function $function_name(img::CONCT, args::Vararg{Any}) where {CONCT <: $I}

        if out !== nothing
            fill!(out.img,$PT(zero($IT)))
            return out
        end
        return SImageND($PT.(zeros($IT, $S1, $S2)), $S)
    end
end

# ################### #
# INVERT #
# ################### #
"""
    experimental_invert_image2D(img::Array{T,2}, args...)::Array{T,2} where {T<:Number}

"""
@serialized_factory function experimental_invert_image2D_factory(i::Type{I}) where {I <: SizedImage}
    IT, PT, S = _get_image_type(I), _get_image_pixel_type(I), _get_image_tuple_size(I)
    # S1, S2 = S.parameters[1], S.parameters[2]
    _validate_factory_type(IT)
    function_name = Symbol(:experimental_invert_image2D_, _factory_type_symbol(I))
    isdefined(@__MODULE__, function_name) && return Base.invokelatest(getfield, @__MODULE__, function_name)
    return @eval function $function_name(img::CONCT, args::Vararg{Any}; out = nothing) where {CONCT <: $I}
        pixels = output_pixels(out, img)
        values = scratch(:experimental_invert, Float64, size(img.img)...)
        invert_into!(pixels, values, img.img)
        return image_result(out, pixels, $S)
    end
end

"`destination` = pixels of `clamp01nan(|1 − value|)`, as the original (two passes: they vectorise)."
function invert_into!(destination::AbstractArray{P}, values, pixels) where {P}
    values .= abs.(1.0 .- float64.(pixels))
    clamp01nan!(values)
    destination .= P.(values)
    return destination
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
"""
Min–max rescale to `[0, 1]`. A constant image gives all `0`. So does a range
of floating-point noise (≤ 1e-9 relative), e.g. a derivative filter on a flat
area (around 1e-17), which would otherwise be stretched into a full-range
random pattern.
"""
function _normalize_img(img::AbstractArray)
    img_f = float.(img)
    _sanitize_img!(img_f)
    min_, max_ = minimum(img_f), maximum(img_f)
    if max_ - min_ <= 1e-9 * max(1.0, abs(min_), abs(max_))
        return fill!(img_f, zero(eltype(img_f)))
    end
    img_f .= (img_f .- min_) ./ (max_ - min_)
    return img_f
end

"""
    experimental_normalize_image2D(img::Array{T,2}, args...)::Array{T,2} where {T<:Number}

"""
# Preserve the original floating element type and Statistics reduction order.
# Scratch is overwritten before either reduction reads it.
floating_work_buffer(::Type{Float32}, buffers, image, key) = float_buffer(buffers, 1, image, key)
floating_work_buffer(::Type{T}, buffers, image, key) where {T} = scratch(key, T, size(image)...)

function rescale!(destination, source, standardize::Bool, float_scratch)
    F = typeof(float(first(source)))
    values = floating_work_buffer(F, float_scratch, source, :basic_rescale)
    for index in eachindex(values, source)
        value = float(source[index])
        values[index] = isfinite(value) ? value : zero(F)
    end
    if standardize
        center = mean(values)
        scale = std(values)
    else
        center, largest = extrema(values)
        scale = largest - center
        if scale <= 1e-9 * max(1.0, abs(center), abs(largest))
            return fill!(destination, zero(eltype(destination)))
        end
    end
    for index in eachindex(destination, values)
        destination[index] = eltype(destination)(clamp01nan((values[index] - center) / scale))
    end
    return destination
end

# Count raw values below the threshold without doing arithmetic on Normed.
function storage_boundary(::Type{T}, threshold, convert_value::F, inclusive::Bool) where {T<:Normed,F}
    R = rawtype(T)
    low = UInt128(0)
    high = UInt128(typemax(R)) + 1
    while low < high
        middle = (low + high) ÷ 2
        value = convert_value(reinterpret(T, R(middle)))
        below = inclusive ? value <= threshold : value < threshold
        if below
            low = middle + 1
        else
            high = middle
        end
    end
    return low
end

function to_binary!(destination, img::SizedImage{S,IntensityPixel{T}}, threshold) where {S,T<:Normed}
    isnan(threshold) && return fill!(destination, zero(eltype(destination)))
    boundary = storage_boundary(T, threshold, Float64, true)
    source = reinterpret(rawtype(T), img.img)
    for index in eachindex(destination, source)
        destination[index] = eltype(destination)(UInt128(source[index]) >= boundary)
    end
    return destination
end

function to_binary!(destination, img::SizedImage{S,<:IntensityPixel}, threshold) where {S}
    source = reinterpret(fieldtype(eltype(img.img), 1), img.img)
    for index in eachindex(destination, source)
        destination[index] = eltype(destination)(source[index] > threshold)
    end
    return destination
end

function to_binary!(destination, img::SizedImage{S,<:SegmentPixel}, threshold) where {S}
    source = reinterpret(fieldtype(eltype(img.img), 1), img.img)
    background = minimum(source)
    for index in eachindex(destination, source)
        destination[index] = eltype(destination)(source[index] != background)
    end
    return destination
end

@serialized_factory function experimental_normalize_image2D_factory(i::Type{I}) where {I <: SizedImage}
    IT, PT, S = _get_image_type(I), _get_image_pixel_type(I), _get_image_tuple_size(I)
    _validate_factory_type(IT)
    function_name = Symbol(:experimental_normalize_image2D_, _factory_type_symbol(I))
    isdefined(@__MODULE__, function_name) && return Base.invokelatest(getfield, @__MODULE__, function_name)
    return @eval function $function_name(img::CONCT, args::Vararg{Any}; out = nothing, float_scratch = nothing) where {CONCT <: $I}
        pixels = output_pixels(out, img)
        rescale!(pixels, img, false, float_scratch)
        return image_result(out, pixels, $S)
    end
end

@serialized_factory function experimental_standardize_image2D_factory(i::Type{I}) where {I <: SizedImage}
    IT, PT, S = _get_image_type(I), _get_image_pixel_type(I), _get_image_tuple_size(I)
    _validate_factory_type(IT)
    function_name = Symbol(:experimental_standardize_image2D_, _factory_type_symbol(I))
    isdefined(@__MODULE__, function_name) && return Base.invokelatest(getfield, @__MODULE__, function_name)
    return @eval function $function_name(img::CONCT, args::Vararg{Any}; out = nothing, float_scratch = nothing) where {CONCT <: $I}
        pixels = output_pixels(out, img)
        rescale!(pixels, img, true, float_scratch)
        return image_result(out, pixels, $S)
    end
end

# Easy access to other pixels

# intensity => binary
# segment => binary
function _to_binary(img::SizedImage{S, IntensityPixel{T}}, th::Float64 = 0.0) where {S, T}
    return BinaryPixel.(reinterpret(fieldtype(eltype(img.img), 1), img.img) .> th)
end
function _to_binary(img::SizedImage{S, SegmentPixel{T}}, th::Float64 = 0.0) where {S, T}
    background_segment = minimum(unique(reinterpret(fieldtype(eltype(img.img), 1), img.img)))
    return BinaryPixel.(reinterpret(fieldtype(eltype(img.img), 1), img.img) .!= background_segment)
end

@serialized_factory function experimental_tobinary_image2D_factory(i::Type{I}) where {I <: SizedImage{SIZE}} where {SIZE}
    IT, PT, S = _get_image_type(I), _get_image_pixel_type(I), _get_image_tuple_size(I)
    _validate_factory_type(IT)
    function_name = Symbol(:experimental_tobinary_image2D_, _factory_type_symbol(I))
    isdefined(@__MODULE__, function_name) && return Base.invokelatest(getfield, @__MODULE__, function_name)
    return @eval function $function_name(img::CONCT, args::Vararg{Any}; out = nothing) where {CONCT <: SizedImage{$SIZE, <:Union{IntensityPixel{T1}, SegmentPixel{T2}}}} where {T1, T2}
        pixels = out === nothing ? similar(img.img, $PT) : out.img
        to_binary!(pixels, img, 0.0)
        return image_result(out, pixels, $S)
    end
end

@serialized_factory function experimental_tobinary_th_image2D_factory(i::Type{I}) where {I <: SizedImage{SIZE}} where {SIZE}
    IT, PT, S = _get_image_type(I), _get_image_pixel_type(I), _get_image_tuple_size(I)
    _validate_factory_type(IT)
    function_name = Symbol(:experimental_tobinary_th_image2D_, _factory_type_symbol(I))
    isdefined(@__MODULE__, function_name) && return Base.invokelatest(getfield, @__MODULE__, function_name)
    return @eval function $function_name(img::CONCT, th::Float64, args::Vararg{Any}; out = nothing) where {CONCT <: SizedImage{$SIZE, <:Union{IntensityPixel{T1}, SegmentPixel{T2}}}} where {T1, T2}
        pixels = out === nothing ? similar(img.img, $PT) : out.img
        to_binary!(pixels, img, th)
        return image_result(out, pixels, $S)
    end
end


# binary => intensity
# segment => intensity

function _to_intensity!(destination, img::SizedImage{S,BinaryPixel{T}}, ::Type{O}) where {S,T,O}
    for index in eachindex(destination, img.img)
        destination[index] = IntensityPixel{O}(O(Int(img[index])))
    end
    return destination
end

function _to_intensity!(destination, img::SizedImage{S,SegmentPixel{T}}, ::Type{O}) where {S,T,O}
    largest_label = maximum(float, img)
    if !(largest_label > 0)
        return fill!(destination, IntensityPixel{O}(zero(O)))
    end
    for index in eachindex(destination, img.img)
        destination[index] = IntensityPixel{O}(O(float(img[index]) / largest_label))
    end
    return destination
end

@serialized_factory function experimental_tointensity_image2D_factory(i::Type{I}) where {I <: SizedImage{SIZE}} where {SIZE}
    IT, PT, S = _get_image_type(I), _get_image_pixel_type(I), _get_image_tuple_size(I)
    _validate_factory_type(IT)
    function_name = Symbol(:experimental_tointensity_image2D_, _factory_type_symbol(I))
    isdefined(@__MODULE__, function_name) && return Base.invokelatest(getfield, @__MODULE__, function_name)
    return @eval function $function_name(img::CONCT, args::Vararg{Any}; out = nothing) where {CONCT <: SizedImage{$(SIZE), <:Union{BinaryPixel{T1}, SegmentPixel{T2}}}} where {T1, T2}
        pixels = out === nothing ? similar(img.img, $PT) : out.img
        _to_intensity!(pixels, img, $IT)
        return image_result(out, pixels, $S)
    end
end

# binary => segment
@serialized_factory function experimental_tosegment_image2D_factory(i::Type{I}) where {I <: SizedImage{SIZE, SegmentPixel{ST}}} where {SIZE, ST}
    IT, PT, S = _get_image_type(I), _get_image_pixel_type(I), _get_image_tuple_size(I)
    _validate_factory_type(IT)
    function_name = Symbol(:experimental_tosegment_image2D_, _factory_type_symbol(I))
    isdefined(@__MODULE__, function_name) && return Base.invokelatest(getfield, @__MODULE__, function_name)
    return @eval function $function_name(img::CONCT, args::Vararg{Any}; out = nothing) where {CONCT <: SizedImage{$(SIZE), BinaryPixel{T}}} where {T}
        pixels = out === nothing ? similar(img.img, $PT) : out.img
        for index in eachindex(pixels, img.img)
            pixels[index] = $PT($IT(Int(img[index])))
        end
        return image_result(out, pixels, $S)
    end
end

# Factory Intensity
append_method!(
    bundle_image2DIntensity_basic_factory,
    identity_image2D_factory,
    :identity_image2D;
    description = "Returns the input image unchanged.",
)
append_method!(
    bundle_image2DIntensity_basic_factory,
    ones_2D_factory,
    :ones_2D;
    description = "Creates an image filled with ones, matching input shape.",
)
append_method!(
    bundle_image2DIntensity_basic_factory,
    zeros_2D_factory,
    :zeros_2D;
    description = "Creates an image filled with zeros, matching input shape.",
)
append_method!(
    bundle_image2DIntensity_basic_factory,
    experimental_invert_image2D_factory,
    :experimental_invert_2D;
    description = "Inverts image intensities with respect to the [0, 1] range.",
)
append_method!(
    bundle_image2DIntensity_basic_factory,
    experimental_normalize_image2D_factory,
    :experimental_normalize_2D;
    description = "Normalizes image values to the [0, 1] range.",
)
append_method!(
    bundle_image2DIntensity_basic_factory,
    experimental_standardize_image2D_factory,
    :experimental_standardize_2D;
    description = "Standardizes image values using mean and standard deviation.",
)
append_method!(
    bundle_image2DIntensity_basic_factory,
    experimental_tointensity_image2D_factory,
    :experimental_tointensity_image2D;
    description = "Converts binary or segment images to intensity image representation.",
)

# Factory Binary
append_method!(
    bundle_image2DBinary_basic_factory,
    identity_image2D_factory,
    :identity_image2D;
    description = "Returns the input image unchanged.",
)
append_method!(
    bundle_image2DBinary_basic_factory,
    ones_2D_factory,
    :ones_2D;
    description = "Creates an image filled with ones, matching input shape.",
)
append_method!(
    bundle_image2DBinary_basic_factory,
    zeros_2D_factory,
    :zeros_2D;
    description = "Creates an image filled with zeros, matching input shape.",
)
append_method!(
    bundle_image2DBinary_basic_factory,
    experimental_invert_image2D_factory,
    :experimental_invert_2D;
    description = "Inverts image intensities with respect to the [0, 1] range.",
)
append_method!(
    bundle_image2DBinary_basic_factory,
    experimental_tobinary_image2D_factory,
    :experimental_tobinary_image2D;
    description = "Mask of the non-zero pixels of an intensity image (any value > 0), or of every segment except the smallest label.",
)
append_method!(
    bundle_image2DBinary_basic_factory,
    experimental_tobinary_th_image2D_factory,
    :experimental_tobinary_th_image2D_factory;
    description = "(img, th): mask of the pixels above th (th a Float64 in [0, 1]); for segments, every label except the smallest.",
)

# Factory Segment
append_method!(
    bundle_image2DSegment_basic_factory,
    identity_image2D_factory,
    :identity_image2D;
    description = "Returns the input image unchanged.",
)
append_method!(
    bundle_image2DSegment_basic_factory,
    ones_2D_factory,
    :ones_2D;
    description = "Creates an image filled with ones, matching input shape.",
)
append_method!(
    bundle_image2DSegment_basic_factory,
    zeros_2D_factory,
    :zeros_2D;
    description = "Creates an image filled with zeros, matching input shape.",
)
append_method!(
    bundle_image2DSegment_basic_factory,
    experimental_tosegment_image2D_factory,
    :experimental_tosegment_image2D;
    description = "Converts a binary image to segment image representation.",
)

end
