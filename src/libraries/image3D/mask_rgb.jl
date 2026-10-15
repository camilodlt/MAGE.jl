"""
Shape-preserving arithmetic and masking for typed RGB images.

# Bundles

- [`bundle_image3DIntensity_rgb_factory`](@ref)
"""
module image3D_rgb

using ..UTCGP: FunctionBundle, append_method!
using ..UTCGP:
    BinaryPixel,
    IntensityPixel,
    SImageND,
    SizedImage3D,
    _get_image_pixel_type,
    _get_image_tuple_size,
    _get_image_type,
    _validate_factory_type

fallback(args...) = return nothing

"""
    bundle_image3DIntensity_rgb_factory

RGB-output arithmetic and masking operators. Specialize the bundle with a
concrete `SImage3D{height,width,3,IntensityPixel{T}}` output type.

Following the basic-library convention, the first two entries are
`identity_rgb` and the parameter-free constant constructor `return_rgb`.
The remaining entries provide pairwise channel arithmetic, unary color
transforms, bounded brightness/contrast/saturation/gamma adjustments, and
masking by a same-height, same-width 2D `BinaryPixel` image. Every operator
returns the exact specialized RGB type.

This bundle is opt-in through `get_extension_rgbimg`.
"""
bundle_image3DIntensity_rgb_factory = FunctionBundle(fallback)

"""
    identity_rgb_image3D_factory(::Type{I})

Specialize `identity_rgb(rgb) -> I`. This is the first entry of the RGB basic
bundle by convention and returns its RGB input unchanged. Trailing framework
`args...` are accepted and ignored.
"""
function identity_rgb_image3D_factory(
        ::Type{I},
    ) where {S1,S2,T,I<:SizedImage3D{S1,S2,3,IntensityPixel{T}}}
    function_name = Symbol(:identity_rgb_, Symbol(I))
    fn = @eval function $function_name(
            image::CONCT,
            args::Vararg{Any},
        ) where {CONCT<:$I}
        return identity(image)
    end
    return fn
end

"""
    return_rgb_image3D_factory(::Type{I})

Specialize the parameter-free constructor `return_rgb() -> I`. It returns an
RGB image filled with typed ones at the exact specialized dimensions. This is
the second entry of the RGB basic bundle, after `identity_rgb`, matching the
established basic-bundle convention. Framework-supplied `args...` are accepted
and ignored, so the function remains callable from ordinary MAGE nodes.
"""
function return_rgb_image3D_factory(
        ::Type{I},
    ) where {S1,S2,T,I<:SizedImage3D{S1,S2,3,IntensityPixel{T}}}
    IT = _get_image_type(I)
    PT = _get_image_pixel_type(I)
    S = _get_image_tuple_size(I)
    _validate_factory_type(IT)
    function_name = Symbol(:return_rgb_, Symbol(I))
    fn = @eval function $function_name(args::Vararg{Any})
        return SImageND($PT.(ones($IT, $S1, $S2, 3)), $S)
    end
    return fn
end

function _rgb_arithmetic_factory(
        ::Type{I},
        function_name_prefix::Symbol,
        operation::Symbol,
    ) where {S1,S2,T,I<:SizedImage3D{S1,S2,3,IntensityPixel{T}}}
    IT = _get_image_type(I)
    PT = _get_image_pixel_type(I)
    S = _get_image_tuple_size(I)
    _validate_factory_type(IT)
    function_name = Symbol(function_name_prefix, :_, Symbol(I))
    calculation = if operation === :add
        :(left .+ right)
    elseif operation === :subtract
        :(left .- right)
    elseif operation === :multiply
        :(left .* right)
    elseif operation === :maximum
        :(max.(left, right))
    elseif operation === :minimum
        :(min.(left, right))
    else
        throw(ArgumentError("Unsupported RGB arithmetic operation: $operation"))
    end

    fn = @eval function $function_name(
            image1::CONCT,
            image2::CONCT,
            args::Vararg{Any},
        ) where {CONCT<:$I}
        left = Float64.(reinterpret(image1.img))
        right = Float64.(reinterpret(image2.img))
        values = $calculation
        clamped = clamp.(values, 0.0, 1.0)
        return SImageND($PT.($IT.(clamped)), $S)
    end
    return fn
end

"""
    add_image3D_factory(::Type{I})

Specialize `add_img3D(rgb1, rgb2) -> I`. The two RGB images must have the exact
specialized type and their channels are added elementwise, with saturation at
one. Trailing framework `args...` are accepted and ignored.
"""
function add_image3D_factory(
        ::Type{I},
    ) where {S1,S2,T,I<:SizedImage3D{S1,S2,3,IntensityPixel{T}}}
    return _rgb_arithmetic_factory(I, :add_img3D, :add)
end

"""
    subtract_image3D_factory(::Type{I})

Specialize `subtract_img3D(rgb1, rgb2) -> I`. The second RGB image is
subtracted channelwise from the first and negative results are clamped to zero.
Trailing framework `args...` are accepted and ignored.
"""
function subtract_image3D_factory(
        ::Type{I},
    ) where {S1,S2,T,I<:SizedImage3D{S1,S2,3,IntensityPixel{T}}}
    return _rgb_arithmetic_factory(I, :subtract_img3D, :subtract)
end

"""
    mult_rgb_image3D_factory(::Type{I})

Specialize `mult_img3D(rgb1, rgb2) -> I`. Corresponding RGB channels are
multiplied elementwise. This differs from `mult_image3D`, whose second input is
a 2D binary mask. Trailing framework `args...` are accepted and ignored.
"""
function mult_rgb_image3D_factory(
        ::Type{I},
    ) where {S1,S2,T,I<:SizedImage3D{S1,S2,3,IntensityPixel{T}}}
    return _rgb_arithmetic_factory(I, :mult_img3D, :multiply)
end

"""
    max_image3D_factory(::Type{I})

Specialize `max_img3D(rgb1, rgb2) -> I`, selecting the larger value at every
pixel and channel. Trailing framework `args...` are accepted and ignored.
"""
function max_image3D_factory(
        ::Type{I},
    ) where {S1,S2,T,I<:SizedImage3D{S1,S2,3,IntensityPixel{T}}}
    return _rgb_arithmetic_factory(I, :max_img3D, :maximum)
end

"""
    min_image3D_factory(::Type{I})

Specialize `min_img3D(rgb1, rgb2) -> I`, selecting the smaller value at every
pixel and channel. Trailing framework `args...` are accepted and ignored.
"""
function min_image3D_factory(
        ::Type{I},
    ) where {S1,S2,T,I<:SizedImage3D{S1,S2,3,IntensityPixel{T}}}
    return _rgb_arithmetic_factory(I, :min_img3D, :minimum)
end

function _unary_rgb_factory(
        ::Type{I},
        function_name_prefix::Symbol,
        operation::Symbol,
    ) where {S1,S2,T,I<:SizedImage3D{S1,S2,3,IntensityPixel{T}}}
    IT = _get_image_type(I)
    PT = _get_image_pixel_type(I)
    S = _get_image_tuple_size(I)
    _validate_factory_type(IT)
    function_name = Symbol(function_name_prefix, :_, Symbol(I))
    calculation = if operation === :invert
        :(output = 1.0 .- source)
    elseif operation === :grayscale
        quote
            output = similar(source)
            @inbounds for col in axes(source, 2), row in axes(source, 1)
                luminance = 0.2126 * source[row, col, 1] +
                    0.7152 * source[row, col, 2] +
                    0.0722 * source[row, col, 3]
                output[row, col, 1] = luminance
                output[row, col, 2] = luminance
                output[row, col, 3] = luminance
            end
        end
    elseif operation === :keep_red
        quote
            output = zeros(Float64, size(source))
            output[:, :, 1] .= source[:, :, 1]
        end
    elseif operation === :keep_green
        quote
            output = zeros(Float64, size(source))
            output[:, :, 2] .= source[:, :, 2]
        end
    elseif operation === :keep_blue
        quote
            output = zeros(Float64, size(source))
            output[:, :, 3] .= source[:, :, 3]
        end
    elseif operation === :rotate_left
        quote
            output = similar(source)
            output[:, :, 1] .= source[:, :, 2]
            output[:, :, 2] .= source[:, :, 3]
            output[:, :, 3] .= source[:, :, 1]
        end
    elseif operation === :rotate_right
        quote
            output = similar(source)
            output[:, :, 1] .= source[:, :, 3]
            output[:, :, 2] .= source[:, :, 1]
            output[:, :, 3] .= source[:, :, 2]
        end
    else
        throw(ArgumentError("Unsupported unary RGB operation: $operation"))
    end

    fn = @eval function $function_name(
            image::CONCT,
            args::Vararg{Any},
        ) where {CONCT<:$I}
        source = Float64.(reinterpret(image.img))
        $calculation
        clamped = clamp.(output, 0.0, 1.0)
        return SImageND($PT.($IT.(clamped)), $S)
    end
    return fn
end

function _adjust_rgb_factory(
        ::Type{I},
        function_name_prefix::Symbol,
        operation::Symbol,
    ) where {S1,S2,T,I<:SizedImage3D{S1,S2,3,IntensityPixel{T}}}
    IT = _get_image_type(I)
    PT = _get_image_pixel_type(I)
    S = _get_image_tuple_size(I)
    _validate_factory_type(IT)
    function_name = Symbol(function_name_prefix, :_, Symbol(I))
    calculation = if operation === :brightness
        quote
            parameter = isfinite(raw_parameter) ?
                        clamp(raw_parameter, -1.0, 1.0) : 0.0
            output = source .+ parameter
        end
    elseif operation === :contrast
        quote
            parameter = isfinite(raw_parameter) ?
                        clamp(raw_parameter, 0.0, 4.0) : 1.0
            output = 0.5 .+ parameter .* (source .- 0.5)
        end
    elseif operation === :saturation
        quote
            parameter = isfinite(raw_parameter) ?
                        clamp(raw_parameter, 0.0, 4.0) : 1.0
            output = similar(source)
            @inbounds for col in axes(source, 2), row in axes(source, 1)
                luminance = 0.2126 * source[row, col, 1] +
                    0.7152 * source[row, col, 2] +
                    0.0722 * source[row, col, 3]
                output[row, col, 1] = luminance +
                    parameter * (source[row, col, 1] - luminance)
                output[row, col, 2] = luminance +
                    parameter * (source[row, col, 2] - luminance)
                output[row, col, 3] = luminance +
                    parameter * (source[row, col, 3] - luminance)
            end
        end
    elseif operation === :gamma
        quote
            parameter = isfinite(raw_parameter) ?
                        clamp(raw_parameter, 0.1, 5.0) : 1.0
            output = source .^ parameter
        end
    else
        throw(ArgumentError("Unsupported RGB adjustment: $operation"))
    end

    fn = @eval function $function_name(
            image::CONCT,
            parameter_input::Real,
            args::Vararg{Any},
        ) where {CONCT<:$I}
        source = Float64.(reinterpret(image.img))
        raw_parameter = Float64(parameter_input)
        $calculation
        clamped = clamp.(output, 0.0, 1.0)
        return SImageND($PT.($IT.(clamped)), $S)
    end
    return fn
end

"""Specialize `invert_rgb(rgb) -> I`, replacing every channel value `x` with `1-x`."""
function invert_rgb_image3D_factory(
        ::Type{I},
    ) where {S1,S2,T,I<:SizedImage3D{S1,S2,3,IntensityPixel{T}}}
    return _unary_rgb_factory(I, :invert_rgb, :invert)
end

"""Specialize `grayscale_rgb(rgb) -> I`, replicating Rec. 709 luminance into all three channels."""
function grayscale_rgb_image3D_factory(
        ::Type{I},
    ) where {S1,S2,T,I<:SizedImage3D{S1,S2,3,IntensityPixel{T}}}
    return _unary_rgb_factory(I, :grayscale_rgb, :grayscale)
end

"""Specialize `keep_red_rgb(rgb) -> I`, retaining red and setting green and blue to zero."""
function keep_red_rgb_image3D_factory(
        ::Type{I},
    ) where {S1,S2,T,I<:SizedImage3D{S1,S2,3,IntensityPixel{T}}}
    return _unary_rgb_factory(I, :keep_red_rgb, :keep_red)
end

"""Specialize `keep_green_rgb(rgb) -> I`, retaining green and setting red and blue to zero."""
function keep_green_rgb_image3D_factory(
        ::Type{I},
    ) where {S1,S2,T,I<:SizedImage3D{S1,S2,3,IntensityPixel{T}}}
    return _unary_rgb_factory(I, :keep_green_rgb, :keep_green)
end

"""Specialize `keep_blue_rgb(rgb) -> I`, retaining blue and setting red and green to zero."""
function keep_blue_rgb_image3D_factory(
        ::Type{I},
    ) where {S1,S2,T,I<:SizedImage3D{S1,S2,3,IntensityPixel{T}}}
    return _unary_rgb_factory(I, :keep_blue_rgb, :keep_blue)
end

"""Specialize `rotate_channels_left_rgb(rgb) -> I`, mapping `(R,G,B)` to `(G,B,R)`."""
function rotate_channels_left_rgb_image3D_factory(
        ::Type{I},
    ) where {S1,S2,T,I<:SizedImage3D{S1,S2,3,IntensityPixel{T}}}
    return _unary_rgb_factory(I, :rotate_channels_left_rgb, :rotate_left)
end

"""Specialize `rotate_channels_right_rgb(rgb) -> I`, mapping `(R,G,B)` to `(B,R,G)`."""
function rotate_channels_right_rgb_image3D_factory(
        ::Type{I},
    ) where {S1,S2,T,I<:SizedImage3D{S1,S2,3,IntensityPixel{T}}}
    return _unary_rgb_factory(I, :rotate_channels_right_rgb, :rotate_right)
end

"""
    adjust_brightness_rgb_image3D_factory(::Type{I})

Specialize `adjust_brightness_rgb(rgb, amount) -> I`. Finite `amount` is
clamped to `[-1,1]` and added to every channel; non-finite values mean zero.
"""
function adjust_brightness_rgb_image3D_factory(
        ::Type{I},
    ) where {S1,S2,T,I<:SizedImage3D{S1,S2,3,IntensityPixel{T}}}
    return _adjust_rgb_factory(I, :adjust_brightness_rgb, :brightness)
end

"""
    adjust_contrast_rgb_image3D_factory(::Type{I})

Specialize `adjust_contrast_rgb(rgb, factor) -> I` around midpoint `0.5`.
Finite `factor` is clamped to `[0,4]`; non-finite values mean identity (`1`).
"""
function adjust_contrast_rgb_image3D_factory(
        ::Type{I},
    ) where {S1,S2,T,I<:SizedImage3D{S1,S2,3,IntensityPixel{T}}}
    return _adjust_rgb_factory(I, :adjust_contrast_rgb, :contrast)
end

"""
    adjust_saturation_rgb_image3D_factory(::Type{I})

Specialize `adjust_saturation_rgb(rgb, factor) -> I` around Rec. 709 luminance.
Finite `factor` is clamped to `[0,4]`; `0` is grayscale, `1` is identity, and
non-finite values also mean identity.
"""
function adjust_saturation_rgb_image3D_factory(
        ::Type{I},
    ) where {S1,S2,T,I<:SizedImage3D{S1,S2,3,IntensityPixel{T}}}
    return _adjust_rgb_factory(I, :adjust_saturation_rgb, :saturation)
end

"""
    adjust_gamma_rgb_image3D_factory(::Type{I})

Specialize `adjust_gamma_rgb(rgb, gamma) -> I`, computing `channel^gamma`.
Finite `gamma` is clamped to `[0.1,5]`; non-finite values mean identity (`1`).
"""
function adjust_gamma_rgb_image3D_factory(
        ::Type{I},
    ) where {S1,S2,T,I<:SizedImage3D{S1,S2,3,IntensityPixel{T}}}
    return _adjust_rgb_factory(I, :adjust_gamma_rgb, :gamma)
end

"""
    mult_image3D_factory(::Type{I})

Specialize `mult_image3D(rgb, binary_mask) -> I` for the concrete RGB output type
`I`. The input RGB image must have exactly the specialized dimensions and
three channels; `binary_mask` must be a same-size 2D `BinaryPixel` image.

White mask pixels retain all three input channels and black mask pixels set all
three channels to zero. Consequently, an all-black mask returns an all-black
RGB image—not `nothing`—with the exact specialized size and pixel category.
Trailing framework `args...` are accepted and ignored.
"""
function mult_image3D_factory(
        ::Type{I},
    ) where {S1,S2,T,I<:SizedImage3D{S1,S2,3,IntensityPixel{T}}}
    IT = _get_image_type(I)
    PT = _get_image_pixel_type(I)
    S = _get_image_tuple_size(I)
    _validate_factory_type(IT)
    function_name = Symbol(:mult_image3D_, Symbol(I))

    fn = @eval function $function_name(
            image::CONCT,
            mask::SImageND{Tuple{$S1,$S2},BinaryPixel{MT},2,MC},
            args::Vararg{Any},
        ) where {CONCT<:$I,MT,MC}
        source = reinterpret(image.img)
        keep = reinterpret(mask.img)
        output = Array{$IT}(undef, $S1, $S2, 3)
        @inbounds for channel in 1:3, col in 1:$S2, row in 1:$S1
            output[row, col, channel] = keep[row, col] ?
                $IT(source[row, col, channel]) : zero($IT)
        end
        return SImageND($PT.(output), $S)
    end
    return fn
end

append_method!(
    bundle_image3DIntensity_rgb_factory,
    identity_rgb_image3D_factory,
    :identity_rgb;
    description = "Returns an RGB image unchanged.",
)
append_method!(
    bundle_image3DIntensity_rgb_factory,
    return_rgb_image3D_factory,
    :return_rgb;
    description = "Returns a parameter-free RGB image filled with typed ones.",
)
append_method!(
    bundle_image3DIntensity_rgb_factory,
    add_image3D_factory,
    :add_img3D;
    description = "Adds two RGB images channelwise and clamps the result to [0,1].",
)
append_method!(
    bundle_image3DIntensity_rgb_factory,
    subtract_image3D_factory,
    :subtract_img3D;
    description = "Subtracts the second RGB image channelwise and clamps the result to [0,1].",
)
append_method!(
    bundle_image3DIntensity_rgb_factory,
    mult_rgb_image3D_factory,
    :mult_img3D;
    description = "Multiplies two RGB images channelwise.",
)
append_method!(
    bundle_image3DIntensity_rgb_factory,
    max_image3D_factory,
    :max_img3D;
    description = "Computes the channelwise maximum of two RGB images.",
)
append_method!(
    bundle_image3DIntensity_rgb_factory,
    min_image3D_factory,
    :min_img3D;
    description = "Computes the channelwise minimum of two RGB images.",
)
append_method!(
    bundle_image3DIntensity_rgb_factory,
    invert_rgb_image3D_factory,
    :invert_rgb;
    description = "Inverts every RGB channel.",
)
append_method!(
    bundle_image3DIntensity_rgb_factory,
    grayscale_rgb_image3D_factory,
    :grayscale_rgb;
    description = "Replicates luminance into all three RGB channels.",
)
append_method!(
    bundle_image3DIntensity_rgb_factory,
    keep_red_rgb_image3D_factory,
    :keep_red_rgb;
    description = "Retains only the red channel.",
)
append_method!(
    bundle_image3DIntensity_rgb_factory,
    keep_green_rgb_image3D_factory,
    :keep_green_rgb;
    description = "Retains only the green channel.",
)
append_method!(
    bundle_image3DIntensity_rgb_factory,
    keep_blue_rgb_image3D_factory,
    :keep_blue_rgb;
    description = "Retains only the blue channel.",
)
append_method!(
    bundle_image3DIntensity_rgb_factory,
    rotate_channels_left_rgb_image3D_factory,
    :rotate_channels_left_rgb;
    description = "Rotates RGB channels from (R,G,B) to (G,B,R).",
)
append_method!(
    bundle_image3DIntensity_rgb_factory,
    rotate_channels_right_rgb_image3D_factory,
    :rotate_channels_right_rgb;
    description = "Rotates RGB channels from (R,G,B) to (B,R,G).",
)
append_method!(
    bundle_image3DIntensity_rgb_factory,
    adjust_brightness_rgb_image3D_factory,
    :adjust_brightness_rgb;
    description = "Adjusts RGB brightness with an amount clamped to [-1,1].",
)
append_method!(
    bundle_image3DIntensity_rgb_factory,
    adjust_contrast_rgb_image3D_factory,
    :adjust_contrast_rgb;
    description = "Adjusts RGB contrast with a factor clamped to [0,4].",
)
append_method!(
    bundle_image3DIntensity_rgb_factory,
    adjust_saturation_rgb_image3D_factory,
    :adjust_saturation_rgb;
    description = "Adjusts RGB saturation with a factor clamped to [0,4].",
)
append_method!(
    bundle_image3DIntensity_rgb_factory,
    adjust_gamma_rgb_image3D_factory,
    :adjust_gamma_rgb;
    description = "Applies gamma correction with gamma clamped to [0.1,5].",
)
append_method!(
    bundle_image3DIntensity_rgb_factory,
    mult_image3D_factory,
    :mult_image3D;
    description = "Keeps RGB pixels selected by a same-size binary mask and returns typed black elsewhere.",
)

end
