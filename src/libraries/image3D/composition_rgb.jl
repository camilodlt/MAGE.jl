"""
Cross-chromosome composition of typed 2D intensity images and RGB images.

# Bundles

- [`bundle_image3DIntensity_rgb_composition_factory`](@ref)
"""
module image3D_rgb_composition

using ..UTCGP: image_result

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

@inline function store_rgb!(destination, index, value)
    P = eltype(destination)
    T = fieldtype(P, 1)
    destination[index] = P(T(value))
end

function compose_rgb!(destination, red, green, blue)
    planes = (reinterpret(fieldtype(eltype(red.img), 1), red.img), reinterpret(fieldtype(eltype(green.img), 1), green.img), reinterpret(fieldtype(eltype(blue.img), 1), blue.img))
    @inbounds for channel in 1:3, col in axes(destination, 2), row in axes(destination, 1)
        store_rgb!(destination, CartesianIndex(row, col, channel), _finite01(planes[channel][row, col]))
    end
    return destination
end

function gray_to_rgb!(destination, gray)
    source = reinterpret(fieldtype(eltype(gray.img), 1), gray.img)
    @inbounds for channel in 1:3, col in axes(destination, 2), row in axes(destination, 1)
        store_rgb!(destination, CartesianIndex(row, col, channel), _finite01(source[row, col]))
    end
    return destination
end

function replace_channel!(destination, rgb, plane, selected_channel)
    source = reinterpret(fieldtype(eltype(rgb.img), 1), rgb.img)
    replacement = reinterpret(fieldtype(eltype(plane.img), 1), plane.img)
    @inbounds for channel in 1:3, col in axes(destination, 2), row in axes(destination, 1)
        value = source[row, col, channel]
        if channel == selected_channel
            value = replacement[row, col]
        end
        store_rgb!(destination, CartesianIndex(row, col, channel), _finite01(value))
    end
    return destination
end

function multiply_rgb_intensity!(destination, rgb, mask)
    source = reinterpret(fieldtype(eltype(rgb.img), 1), rgb.img)
    weights = reinterpret(fieldtype(eltype(mask.img), 1), mask.img)
    @inbounds for channel in 1:3, col in axes(destination, 2), row in axes(destination, 1)
        value = _finite01(source[row, col, channel]) * _finite01(weights[row, col])
        store_rgb!(destination, CartesianIndex(row, col, channel), value)
    end
    return destination
end

function alpha_blend_rgb!(destination, foreground, background, alpha)
    front = reinterpret(fieldtype(eltype(foreground.img), 1), foreground.img)
    back = reinterpret(fieldtype(eltype(background.img), 1), background.img)
    weights = reinterpret(fieldtype(eltype(alpha.img), 1), alpha.img)
    @inbounds for channel in 1:3, col in axes(destination, 2), row in axes(destination, 1)
        weight = _finite01(weights[row, col])
        value = weight * _finite01(front[row, col, channel]) +
            (1.0 - weight) * _finite01(back[row, col, channel])
        store_rgb!(destination, CartesianIndex(row, col, channel), value)
    end
    return destination
end

function set_luminance_rgb!(destination, rgb, luminance)
    source = reinterpret(fieldtype(eltype(rgb.img), 1), rgb.img)
    target = reinterpret(fieldtype(eltype(luminance.img), 1), luminance.img)
    @inbounds for col in axes(destination, 2), row in axes(destination, 1)
        red = _finite01(source[row, col, 1])
        green = _finite01(source[row, col, 2])
        blue = _finite01(source[row, col, 3])
        current = 0.2126 * red + 0.7152 * green + 0.0722 * blue
        difference = _finite01(target[row, col]) - current
        for (channel, value) in enumerate((red, green, blue))
            store_rgb!(destination, CartesianIndex(row, col, channel), clamp(value + difference, 0.0, 1.0))
        end
    end
    return destination
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
                args::Vararg{Any}; out = nothing,
            ) where {RT,RC,GT,GC,BT,BC}
            pixels = out === nothing ? Array{$PT}(undef, $S1, $S2, 3) : out.img
            compose_rgb!(pixels, red, green, blue)
            return image_result(out, pixels, $S)
        end
    elseif operation === :gray
        fn = @eval function $function_name(
                gray::SImageND{Tuple{$S1,$S2},IntensityPixel{MT},2,MC},
                args::Vararg{Any}; out = nothing,
            ) where {MT,MC}
            pixels = out === nothing ? Array{$PT}(undef, $S1, $S2, 3) : out.img
            gray_to_rgb!(pixels, gray)
            return image_result(out, pixels, $S)
        end
    elseif operation in (:replace_red, :replace_green, :replace_blue, :multiply, :luminance)
        channel = operation === :replace_red ? 1 : operation === :replace_green ? 2 : 3
        calculation = if operation in (:replace_red, :replace_green, :replace_blue)
            :(replace_channel!(pixels, rgb, plane, $channel))
        elseif operation === :multiply
            :(multiply_rgb_intensity!(pixels, rgb, plane))
        else
            :(set_luminance_rgb!(pixels, rgb, plane))
        end
        fn = @eval function $function_name(
                rgb::CONCT,
                plane::SImageND{Tuple{$S1,$S2},IntensityPixel{MT},2,MC},
                args::Vararg{Any}; out = nothing,
            ) where {CONCT<:$I,MT,MC}
            pixels = out === nothing ? Array{$PT}(undef, $S1, $S2, 3) : out.img
            $calculation
            return image_result(out, pixels, $S)
        end
    elseif operation === :blend
        fn = @eval function $function_name(
                foreground::CONCT,
                background::CONCT,
                alpha::SImageND{Tuple{$S1,$S2},IntensityPixel{MT},2,MC},
                args::Vararg{Any}; out = nothing,
            ) where {CONCT<:$I,MT,MC}
            pixels = out === nothing ? Array{$PT}(undef, $S1, $S2, 3) : out.img
            alpha_blend_rgb!(pixels, foreground, background, alpha)
            return image_result(out, pixels, $S)
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
