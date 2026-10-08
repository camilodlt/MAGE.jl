"""
Color statistics and opponent channels for typed RGB image inputs.

# Bundles

- [`bundle_image2DIntensity_color_statistics_rgb_factory`](@ref)

The exhaustive, always-current list of operators in the bundle is on the
[Bundle Catalogue](@ref) page.
"""
module image3D_color_statistics_rgb

using ..UTCGP: FunctionBundle, append_method!
using ..UTCGP:
    IntensityPixel,
    SImageND,
    SizedImage2D,
    _get_image_pixel_type,
    _get_image_tuple_size,
    _get_image_type,
    _validate_factory_type

fallback(args...) = return nothing

"""
    bundle_image2DIntensity_color_statistics_rgb_factory

Color-derived intensity maps for an RGB input stored as
`SImage3D{height,width,3,IntensityPixel{T}}`. The three slices on the last axis
are red, green, and blue respectively. Every operator has one effective MAGE
argument and returns the concrete same-size 2D intensity type used to
specialize the factory.

The bundle contains `rgb_luminance`, `red_green_opponency`,
`blue_yellow_opponency`, `rgb_saturation`, `normalized_red`,
`normalized_green`, and `normalized_blue`. It is opt-in through
`get_extension_color_statistics_rgb_intensityimg`; existing image library
getters do not include it implicitly.
"""
bundle_image2DIntensity_color_statistics_rgb_factory = FunctionBundle(fallback)

@inline _finite_channel(x::Real) = isfinite(x) ? clamp(Float64(x), 0.0, 1.0) : 0.0

@inline function _rgb_value(r::Float64, g::Float64, b::Float64, ::Val{:luminance})
    # Rec. 709 coefficients, applied directly to the stored (normally sRGB) channels.
    return muladd(0.2126, r, muladd(0.7152, g, 0.0722b))
end

@inline function _rgb_value(r::Float64, g::Float64, ::Float64, ::Val{:red_green})
    # Preserve both opponent directions in an unsigned image: 0.5 is neutral.
    return clamp(0.5 + 0.5 * (r - g), 0.0, 1.0)
end

@inline function _rgb_value(r::Float64, g::Float64, b::Float64, ::Val{:blue_yellow})
    # Blue versus the additive yellow axis (R + G) / 2; 0.5 is neutral.
    return clamp(0.5 + 0.5 * (b - 0.5 * (r + g)), 0.0, 1.0)
end

@inline function _rgb_value(r::Float64, g::Float64, b::Float64, ::Val{:saturation})
    return max(r, g, b) - min(r, g, b)
end

@inline function _rgb_value(r::Float64, g::Float64, b::Float64, ::Val{:normalized_red})
    total = r + g + b
    return total > 0.0 ? r / total : 0.0
end

@inline function _rgb_value(r::Float64, g::Float64, b::Float64, ::Val{:normalized_green})
    total = r + g + b
    return total > 0.0 ? g / total : 0.0
end

@inline function _rgb_value(r::Float64, g::Float64, b::Float64, ::Val{:normalized_blue})
    total = r + g + b
    return total > 0.0 ? b / total : 0.0
end

function _rgb_statistic(image::SImageND, statistic::Val)
    source = reinterpret(image.img)
    h, w, _ = size(source)
    output = Matrix{Float64}(undef, h, w)
    @inbounds for col in 1:w, row in 1:h
        r = _finite_channel(source[row, col, 1])
        g = _finite_channel(source[row, col, 2])
        b = _finite_channel(source[row, col, 3])
        output[row, col] = _rgb_value(r, g, b, statistic)
    end
    return output
end

function _rgb_statistic_factory(
        ::Type{I},
        operator_name::Symbol,
        ::Val{K},
    ) where {S1,S2,T,I<:SizedImage2D{S1,S2,IntensityPixel{T}},K}
    IT = _get_image_type(I)
    PT = _get_image_pixel_type(I)
    S = _get_image_tuple_size(I)
    _validate_factory_type(IT)
    function_name = Symbol(operator_name, :_image3D_, Symbol(I))

    fn = @eval function $function_name(
            image::SImageND{Tuple{$S1,$S2,3},IntensityPixel{ST},3,C},
            args::Vararg{Any},
        ) where {ST,C}
        values = _rgb_statistic(image, Val{$(QuoteNode(K))}())
        return SImageND($PT.($IT.(values)), $S)
    end
    return fn
end

"""
    rgb_luminance_image2D_factory(::Type{I})

Specialize `rgb_luminance(rgb)` for the 2D intensity output type `I`. The input
must be a same-height, same-width, three-channel `SImage3D`; the output uses
Rec. 709 weights `0.2126R + 0.7152G + 0.0722B` and has exactly the dimensions
and pixel category of `I`.
"""
rgb_luminance_image2D_factory(::Type{I}) where {I<:SizedImage2D} =
    _rgb_statistic_factory(I, :rgb_luminance, Val(:luminance))

"""
    red_green_opponency_image2D_factory(::Type{I})

Specialize `red_green_opponency(rgb)` for output type `I`. It encodes signed
red-minus-green opponency as `0.5 + 0.5(R-G)`, so 0.5 is neutral, red tends to
1, and green tends to 0.
"""
red_green_opponency_image2D_factory(::Type{I}) where {I<:SizedImage2D} =
    _rgb_statistic_factory(I, :red_green_opponency, Val(:red_green))

"""
    blue_yellow_opponency_image2D_factory(::Type{I})

Specialize `blue_yellow_opponency(rgb)` for output type `I`. It encodes blue
against the additive-yellow axis `(R+G)/2`, with 0.5 representing neutrality.
"""
blue_yellow_opponency_image2D_factory(::Type{I}) where {I<:SizedImage2D} =
    _rgb_statistic_factory(I, :blue_yellow_opponency, Val(:blue_yellow))

"""
    rgb_saturation_image2D_factory(::Type{I})

Specialize `rgb_saturation(rgb)` for output type `I`. The map is HSV-style
chroma `max(R,G,B) - min(R,G,B)`, in `[0,1]`.
"""
rgb_saturation_image2D_factory(::Type{I}) where {I<:SizedImage2D} =
    _rgb_statistic_factory(I, :rgb_saturation, Val(:saturation))

"""
    normalized_red_image2D_factory(::Type{I})

Specialize `normalized_red(rgb)` for output type `I`. Each non-black pixel is
`R/(R+G+B)`; black maps to zero.
"""
normalized_red_image2D_factory(::Type{I}) where {I<:SizedImage2D} =
    _rgb_statistic_factory(I, :normalized_red, Val(:normalized_red))

"""
    normalized_green_image2D_factory(::Type{I})

Specialize `normalized_green(rgb)` for output type `I`. Each non-black pixel is
`G/(R+G+B)`; black maps to zero.
"""
normalized_green_image2D_factory(::Type{I}) where {I<:SizedImage2D} =
    _rgb_statistic_factory(I, :normalized_green, Val(:normalized_green))

"""
    normalized_blue_image2D_factory(::Type{I})

Specialize `normalized_blue(rgb)` for output type `I`. Each non-black pixel is
`B/(R+G+B)`; black maps to zero.
"""
normalized_blue_image2D_factory(::Type{I}) where {I<:SizedImage2D} =
    _rgb_statistic_factory(I, :normalized_blue, Val(:normalized_blue))

for (factory, name, description) in (
        (rgb_luminance_image2D_factory, :rgb_luminance,
            "Converts a same-size RGB SImage3D to Rec. 709 luminance."),
        (red_green_opponency_image2D_factory, :red_green_opponency,
            "Encodes signed red-minus-green opponency with neutral at 0.5."),
        (blue_yellow_opponency_image2D_factory, :blue_yellow_opponency,
            "Encodes signed blue-versus-yellow opponency with neutral at 0.5."),
        (rgb_saturation_image2D_factory, :rgb_saturation,
            "Returns per-pixel RGB chroma (maximum channel minus minimum channel)."),
        (normalized_red_image2D_factory, :normalized_red,
            "Returns red chromaticity R/(R+G+B), with black mapped to zero."),
        (normalized_green_image2D_factory, :normalized_green,
            "Returns green chromaticity G/(R+G+B), with black mapped to zero."),
        (normalized_blue_image2D_factory, :normalized_blue,
            "Returns blue chromaticity B/(R+G+B), with black mapped to zero."),
    )
    append_method!(
        bundle_image2DIntensity_color_statistics_rgb_factory,
        factory,
        name;
        description,
    )
end

end
