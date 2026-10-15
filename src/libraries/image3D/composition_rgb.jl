"""
Cross-chromosome composition of typed 2D intensity images and RGB images.

# Bundles

- [`bundle_image3DIntensity_rgb_composition_factory`](@ref)
"""
module image3D_rgb_composition

using ..UTCGP: FunctionBundle, append_method!
using ..UTCGP:
    IntensityPixel,
    SImageND,
    SizedImage3D,
    _get_image_pixel_type,
    _get_image_tuple_size,
    _get_image_type,
    _validate_factory_type

fallback(args...) = return nothing

"""
    bundle_image3DIntensity_rgb_composition_factory

RGB-output bridge operators. Each factory is specialized with a concrete
`SImage3D{height,width,3,IntensityPixel{T}}` output type and accepts same-size
2D `IntensityPixel` images, RGB images of the specialized type, or both.

The bundle contains `compose_rgb`, `gray_to_rgb`, the three channel-replacement
operators, continuous intensity masking, spatial alpha blending, and luminance
replacement. Every callable has at most three effective MAGE inputs and always
returns the exact specialized RGB type with finite channel values in `[0,1]`.
Intensity control pixels are clamped to that interval and non-finite pixels are
treated as zero.

This is an opt-in extension through `get_extension_rgb_compositionimg`. It does
not repeat the basic RGB bundle's leading `identity_rgb` and `return_rgb`
functions, so place it after `get_extension_rgbimg()`.
"""
bundle_image3DIntensity_rgb_composition_factory = FunctionBundle(fallback)

@inline _finite01(value::Real) = isfinite(value) ? clamp(Float64(value), 0.0, 1.0) : 0.0

function _plane_values(image::SImageND)
    source = reinterpret(image.img)
    output = Matrix{Float64}(undef, size(source))
    @inbounds for index in eachindex(source)
        output[index] = _finite01(source[index])
    end
    return output
end

function _rgb_values(image::SImageND)
    source = reinterpret(image.img)
    output = Array{Float64}(undef, size(source))
    @inbounds for index in eachindex(source)
        output[index] = _finite01(source[index])
    end
    return output
end

function _compose_rgb_values(red::SImageND, green::SImageND, blue::SImageND)
    output = Array{Float64}(undef, size(red, 1), size(red, 2), 3)
    output[:, :, 1] .= _plane_values(red)
    output[:, :, 2] .= _plane_values(green)
    output[:, :, 3] .= _plane_values(blue)
    return output
end

function _gray_to_rgb_values(gray::SImageND)
    plane = _plane_values(gray)
    return cat(plane, plane, plane; dims = 3)
end

function _replace_channel_values(rgb::SImageND, plane::SImageND, channel::Int)
    output = _rgb_values(rgb)
    output[:, :, channel] .= _plane_values(plane)
    return output
end

function _multiply_rgb_intensity_values(rgb::SImageND, mask::SImageND)
    source = _rgb_values(rgb)
    weights = _plane_values(mask)
    @inbounds for channel in 1:3
        source[:, :, channel] .*= weights
    end
    return source
end

function _alpha_blend_rgb_values(
        foreground::SImageND,
        background::SImageND,
        alpha::SImageND,
    )
    foreground_values = _rgb_values(foreground)
    background_values = _rgb_values(background)
    weights = _plane_values(alpha)
    output = similar(foreground_values)
    @inbounds for channel in 1:3
        output[:, :, channel] .= weights .* foreground_values[:, :, channel] .+
            (1.0 .- weights) .* background_values[:, :, channel]
    end
    return output
end

function _set_luminance_rgb_values(rgb::SImageND, luminance::SImageND)
    source = _rgb_values(rgb)
    target = _plane_values(luminance)
    output = similar(source)
    @inbounds for col in axes(source, 2), row in axes(source, 1)
        current = 0.2126 * source[row, col, 1] +
            0.7152 * source[row, col, 2] +
            0.0722 * source[row, col, 3]
        difference = target[row, col] - current
        output[row, col, 1] = clamp(source[row, col, 1] + difference, 0.0, 1.0)
        output[row, col, 2] = clamp(source[row, col, 2] + difference, 0.0, 1.0)
        output[row, col, 3] = clamp(source[row, col, 3] + difference, 0.0, 1.0)
    end
    return output
end

function _rgb_composition_factory(
        ::Type{I},
        operator_name::Symbol,
        operation::Symbol,
    ) where {S1,S2,T,I<:SizedImage3D{S1,S2,3,IntensityPixel{T}}}
    IT = _get_image_type(I)
    PT = _get_image_pixel_type(I)
    S = _get_image_tuple_size(I)
    _validate_factory_type(IT)
    function_name = Symbol(operator_name, :_, Symbol(I))

    if operation === :compose
        fn = @eval function $function_name(
                red::SImageND{Tuple{$S1,$S2},IntensityPixel{RT},2,RC},
                green::SImageND{Tuple{$S1,$S2},IntensityPixel{GT},2,GC},
                blue::SImageND{Tuple{$S1,$S2},IntensityPixel{BT},2,BC},
                args::Vararg{Any},
            ) where {RT,RC,GT,GC,BT,BC}
            output = _compose_rgb_values(red, green, blue)
            return SImageND($PT.($IT.(output)), $S)
        end
    elseif operation === :gray
        fn = @eval function $function_name(
                gray::SImageND{Tuple{$S1,$S2},IntensityPixel{MT},2,MC},
                args::Vararg{Any},
            ) where {MT,MC}
            output = _gray_to_rgb_values(gray)
            return SImageND($PT.($IT.(output)), $S)
        end
    elseif operation in (:replace_red, :replace_green, :replace_blue, :multiply, :luminance)
        channel = operation === :replace_red ? 1 : operation === :replace_green ? 2 : 3
        calculation = if operation in (:replace_red, :replace_green, :replace_blue)
            :(_replace_channel_values(rgb, plane, $channel))
        elseif operation === :multiply
            :(_multiply_rgb_intensity_values(rgb, plane))
        else
            :(_set_luminance_rgb_values(rgb, plane))
        end
        fn = @eval function $function_name(
                rgb::CONCT,
                plane::SImageND{Tuple{$S1,$S2},IntensityPixel{MT},2,MC},
                args::Vararg{Any},
            ) where {CONCT<:$I,MT,MC}
            output = $calculation
            return SImageND($PT.($IT.(output)), $S)
        end
    elseif operation === :blend
        fn = @eval function $function_name(
                foreground::CONCT,
                background::CONCT,
                alpha::SImageND{Tuple{$S1,$S2},IntensityPixel{MT},2,MC},
                args::Vararg{Any},
            ) where {CONCT<:$I,MT,MC}
            output = _alpha_blend_rgb_values(foreground, background, alpha)
            return SImageND($PT.($IT.(output)), $S)
        end
    else
        throw(ArgumentError("Unsupported RGB composition operation: $operation"))
    end
    return fn
end

"""
    compose_rgb_image3D_factory(::Type{I})

Specialize `compose_rgb(red, green, blue) -> I`. The inputs are three same-size
2D intensity images representing the red, green, and blue output planes. They
may use different underlying numeric types; each pixel is sanitized to `[0,1]`.
"""
compose_rgb_image3D_factory(::Type{I}) where {S1,S2,T,I<:SizedImage3D{S1,S2,3,IntensityPixel{T}}} =
    _rgb_composition_factory(I, :compose_rgb, :compose)

"""
    gray_to_rgb_image3D_factory(::Type{I})

Specialize `gray_to_rgb(gray) -> I`, replicating one same-size intensity image
into all three RGB channels.
"""
gray_to_rgb_image3D_factory(::Type{I}) where {S1,S2,T,I<:SizedImage3D{S1,S2,3,IntensityPixel{T}}} =
    _rgb_composition_factory(I, :gray_to_rgb, :gray)

"""Specialize `replace_red_rgb(rgb, red) -> I`, replacing only the red channel with a same-size intensity image."""
replace_red_rgb_image3D_factory(::Type{I}) where {S1,S2,T,I<:SizedImage3D{S1,S2,3,IntensityPixel{T}}} =
    _rgb_composition_factory(I, :replace_red_rgb, :replace_red)

"""Specialize `replace_green_rgb(rgb, green) -> I`, replacing only the green channel with a same-size intensity image."""
replace_green_rgb_image3D_factory(::Type{I}) where {S1,S2,T,I<:SizedImage3D{S1,S2,3,IntensityPixel{T}}} =
    _rgb_composition_factory(I, :replace_green_rgb, :replace_green)

"""Specialize `replace_blue_rgb(rgb, blue) -> I`, replacing only the blue channel with a same-size intensity image."""
replace_blue_rgb_image3D_factory(::Type{I}) where {S1,S2,T,I<:SizedImage3D{S1,S2,3,IntensityPixel{T}}} =
    _rgb_composition_factory(I, :replace_blue_rgb, :replace_blue)

"""
    multiply_rgb_intensity_image3D_factory(::Type{I})

Specialize `multiply_rgb_intensity(rgb, mask) -> I`. A same-size intensity map
continuously scales all three channels per pixel. Zero produces typed RGB black
and one preserves the source pixel.
"""
multiply_rgb_intensity_image3D_factory(::Type{I}) where {S1,S2,T,I<:SizedImage3D{S1,S2,3,IntensityPixel{T}}} =
    _rgb_composition_factory(I, :multiply_rgb_intensity, :multiply)

"""
    alpha_blend_rgb_image3D_factory(::Type{I})

Specialize `alpha_blend_rgb(foreground, background, alpha) -> I`. The same-size
intensity alpha map computes `alpha*foreground + (1-alpha)*background` at every
pixel and channel.
"""
alpha_blend_rgb_image3D_factory(::Type{I}) where {S1,S2,T,I<:SizedImage3D{S1,S2,3,IntensityPixel{T}}} =
    _rgb_composition_factory(I, :alpha_blend_rgb, :blend)

"""
    set_luminance_rgb_image3D_factory(::Type{I})

Specialize `set_luminance_rgb(rgb, luminance) -> I`. The target intensity map
replaces Rec. 709 luminance by adding the same signed offset to all channels,
which preserves channel differences until output clipping is required.
"""
set_luminance_rgb_image3D_factory(::Type{I}) where {S1,S2,T,I<:SizedImage3D{S1,S2,3,IntensityPixel{T}}} =
    _rgb_composition_factory(I, :set_luminance_rgb, :luminance)

for (factory, name, description) in (
        (compose_rgb_image3D_factory, :compose_rgb,
            "Composes red, green, and blue intensity planes into one RGB image."),
        (gray_to_rgb_image3D_factory, :gray_to_rgb,
            "Replicates one intensity plane into all three RGB channels."),
        (replace_red_rgb_image3D_factory, :replace_red_rgb,
            "Replaces an RGB image's red channel with an intensity plane."),
        (replace_green_rgb_image3D_factory, :replace_green_rgb,
            "Replaces an RGB image's green channel with an intensity plane."),
        (replace_blue_rgb_image3D_factory, :replace_blue_rgb,
            "Replaces an RGB image's blue channel with an intensity plane."),
        (multiply_rgb_intensity_image3D_factory, :multiply_rgb_intensity,
            "Continuously masks all RGB channels with an intensity map."),
        (alpha_blend_rgb_image3D_factory, :alpha_blend_rgb,
            "Blends foreground and background RGB images under an intensity alpha map."),
        (set_luminance_rgb_image3D_factory, :set_luminance_rgb,
            "Replaces RGB luminance while preserving channel differences until clipping."),
    )
    append_method!(
        bundle_image3DIntensity_rgb_composition_factory,
        factory,
        name;
        description,
    )
end

end
