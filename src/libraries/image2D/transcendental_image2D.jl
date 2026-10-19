# -*- coding: utf-8 -*-

"""
Pixel-wise transcendental transforms of an intensity image.

# Bundles

- [`bundle_image2DIntensity_transcendental_factory`](@ref)

The exhaustive, always-current list of operators in each bundle is on the
[Bundle Catalogue](@ref) page.
"""
module image2D_transcendental

using ..UTCGP: _factory_type_symbol, @serialized_factory

using ..UTCGP: @image_out, output_pixels, image_result

using ..UTCGP: image2D_basic
using ..UTCGP:image2D_morph
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

const cast = image2D_morph.cast
fallback(args...) = return nothing

"""
    bundle_image2DIntensity_transcendental_factory

Pixel-wise transcendental transforms of an intensity image: `exp_image2D`,
`log_image2D`, `loginv_image2D`, `powerof_image2D`.

This is a *factory* bundle: each entry is a function of a type that returns the
method specialised for it, so the same operator can be instantiated for several
image or element types. See [Libraries](@ref) for how factories are specialised
into a library.
"""
bundle_image2DIntensity_transcendental_factory = FunctionBundle(fallback)

# The pixel loops are separate functions (barriers): they run several times faster
# when their working array arrives as an argument than when fetched from scratch in
# the same function.

"`values[i] = exp(pixel i)`, in the floating type of the original `exp.(float(img))`."
function exp_values!(values, pixels)
    values .= exp.(float.(pixels))      # a broadcast, as the original: it vectorises
    return values
end

"`values[i] = log(Float32(raw storage value i))`, as the original."
function log_values!(values, raw)
    @inbounds for index in eachindex(values, raw)
        values[index] = log(Float32(raw[index]))
    end
    return values
end

"""
`destination` = `values` rescaled to `[0, 1]` and stored as pixels of storage `T`,
exactly as the original `_normalize_img` then `PT.(cast(T, ...))`. Broadcasts,
not a scalar loop: the conversions to `T` vectorise (much faster).
"""
function normalize_transform!(destination, values, ::Type{T}) where {T}
    image2D_basic._sanitize_img!(values)
    low, high = extrema(values)
    if high - low <= 1e-9 * max(1.0, abs(low), abs(high))
        return fill!(destination, zero(eltype(destination)))
    end
    values .= (values .- low) ./ (high - low)
    clamp01nan!(values)
    destination .= eltype(destination).(T.(values))
    return destination
end

"`destination` = pixels of `clamp01nan(float(image) ^ p)`, as the original `powerof`."
function power_into!(destination, values, image, p, ::Type{T}) where {T}
    values .= float(image) .^ p
    clamp01nan!(values)
    destination .= eltype(destination).(T.(values))
    return destination
end

# ################### #
# EXP                 #
# ################### #

"""
    exp_image2D_factory(i::Type{I}) where {I<:InputType}

with InputType = SizedImage2D{S1,S2,T,IT} where {S1,S2,T<:Normed,IT}

Element wise `exp`.

**Exposes** : 

    exp_image2D(img1::CONCT, args::Vararg{Any})

"""
@serialized_factory function exp_image2D_factory(i::Type{I}) where {I<:SizedImage{SIZE, IntensityPixel{T}}} where {SIZE,T}
    IT, PT, S = _get_image_type(I), _get_image_pixel_type(I), _get_image_tuple_size(I)
    S1, S2 = S.parameters[1], S.parameters[2]
    _validate_factory_type(IT)

    function_name = Symbol(:exp_image2D_, _factory_type_symbol(I))
    isdefined(@__MODULE__, function_name) && return getfield(@__MODULE__, function_name)
    m1 = @eval function $function_name(img1::CONCT, args::Vararg{Any}; out = nothing, float_scratch = nothing) where {CONCT <: $I}
        pixels = output_pixels(out, img1)
        F = typeof(exp(float(img1.img[firstindex(img1.img)])))
        values = image2D_basic.floating_work_buffer(F, float_scratch, img1, :transcendental_exp)
        exp_values!(values, img1.img)
        normalize_transform!(pixels, values, $IT)
        return image_result(out, pixels, $S)
    end
    return m1
end

# ################### #
# LOG                 #
# ################### #

"""
    log_image2D_factory(i::Type{I}) where {I<:InputType}

with InputType = SizedImage2D{S1,S2,T,IT} where {S1,S2,T<:Normed,IT}

Element wise `log`.

**Exposes** : 

    log_image2D(img1::CONCT, args::Vararg{Any})

"""
@serialized_factory function loginv_image2D_factory(i::Type{I}) where {I<:SizedImage{SIZE, IntensityPixel{T}}} where {SIZE,T}
    IT, PT, S = _get_image_type(I), _get_image_pixel_type(I), _get_image_tuple_size(I)
    S1, S2 = S.parameters[1], S.parameters[2]
    _validate_factory_type(IT)

    function_name = Symbol(:loginv_image2D_, _factory_type_symbol(I))
    isdefined(@__MODULE__, function_name) && return getfield(@__MODULE__, function_name)
    m1 = @eval @image_out function $function_name(img1::CONCT, args::Vararg{Any}) where {CONCT <: $I}

        if out !== nothing
            for i in eachindex(out.img,img1.img)
                out.img[i] = $PT($IT(clamp01nan(log(float(img1.img[i])) * -1.0)))
            end
            return out
        end
        img3 = log.(float(img1)) .*- 1.
        clamp01nan!(img3)
        return SImageND($PT.(cast($IT, img3)), $S)
    end
    return m1
end
@serialized_factory function log_image2D_factory(i::Type{I}) where {I<:SizedImage{SIZE, IntensityPixel{T}}} where {SIZE,T}
    IT, PT, S = _get_image_type(I), _get_image_pixel_type(I), _get_image_tuple_size(I)
    S1, S2 = S.parameters[1], S.parameters[2]
    _validate_factory_type(IT)
    TRUE_TYPE = IT.parameters[1]

    function_name = Symbol(:log_image2D_, _factory_type_symbol(I))
    isdefined(@__MODULE__, function_name) && return getfield(@__MODULE__, function_name)
    m1 = @eval function $function_name(img1::CONCT, args::Vararg{Any}; out = nothing, float_scratch = nothing) where {CONCT <: $I}
        pixels = output_pixels(out, img1)
        raw = reinterpret($TRUE_TYPE, img1.img)
        F = typeof(log(Float32(raw[firstindex(img1.img)])))
        values = image2D_basic.floating_work_buffer(F, float_scratch, img1, :transcendental_log)
        log_values!(values, raw)
        normalize_transform!(pixels, values, $IT)
        return image_result(out, pixels, $S)
    end
    return m1
end

# ################### #
# Power of            #
# ################### #

"""
    powerof_image2D_factory(i::Type{I}) where {I<:InputType}

with InputType = SizedImage2D{S1,S2,T,IT} where {S1,S2,T<:Normed,IT}

Each element in `img1` is elevated to the power of `p`

**Exposes** : 

    powerof_image2D(img1::CONCT, p::Float64, args::Vararg{Any})

"""
@serialized_factory function powerof_image2D_factory(i::Type{I}) where {I<:SizedImage{SIZE, IntensityPixel{T}}} where {SIZE,T}
    IT, PT, S = _get_image_type(I), _get_image_pixel_type(I), _get_image_tuple_size(I)
    S1, S2 = S.parameters[1], S.parameters[2]
    _validate_factory_type(IT)

    function_name = Symbol(:powerof_image2D_, _factory_type_symbol(I))
    isdefined(@__MODULE__, function_name) && return getfield(@__MODULE__, function_name)
    m1 = @eval function $function_name(img1::CONCT, p::Real, args::Vararg{Any}; out = nothing) where {CONCT <: $I}
        pixels = output_pixels(out, img1)
        F = typeof(float(img1.img[firstindex(img1.img)]) ^ p)   # Float32 ^ p, as the original `float(img) .^ p`
        values = image2D_basic.floating_work_buffer(F, nothing, img1, :transcendental_power)
        power_into!(pixels, values, img1, p, $IT)
        return image_result(out, pixels, $S)
    end
    return m1
end

# Factory Methods
append_method!(
    bundle_image2DIntensity_transcendental_factory,
    exp_image2D_factory,
    :exp_image2D;
    description = "Applies exp to each pixel, then rescales to [0, 1].",
)
append_method!(
    bundle_image2DIntensity_transcendental_factory,
    loginv_image2D_factory,
    :loginv_image2D;
    description = "Computes -log(v) per pixel, clamped to [0, 1]: dark pixels (v <= 1/e) become 1, v = 1 becomes 0.",
)
append_method!(
    bundle_image2DIntensity_transcendental_factory,
    log_image2D_factory,
    :log_image2D;
    description = "Applies log to each pixel's raw stored value (zeros treated as the smallest), then rescales to [0, 1].",
)
append_method!(
    bundle_image2DIntensity_transcendental_factory,
    powerof_image2D_factory,
    :powerof_image2D,
    ;
    description = "Raises each pixel value to a provided exponent.",
)

end
