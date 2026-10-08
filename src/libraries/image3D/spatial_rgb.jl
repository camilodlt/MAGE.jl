"""
Fixed, training-free spatial feature transforms for typed RGB images.

# Bundles

- [`bundle_image3DIntensity_spatial_rgb_factory`](@ref)
"""
module image3D_spatial_rgb

using ImageFiltering: Kernel, centered, imfilter, reflect
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
    bundle_image3DIntensity_spatial_rgb_factory

Training-free spatial transforms specialized for a concrete
`SImage3D{height,width,3,IntensityPixel{T}}` output type. Every operator accepts
an RGB image of that exact type, processes its three channels independently,
uses reflected boundaries, and returns the exact specialized RGB type.

This is an extension bundle: it deliberately does not repeat the leading
`identity_rgb` and `return_rgb` functions supplied by the basic RGB bundle. Add
it explicitly with `get_extension_spatial_rgbimg`.
"""
bundle_image3DIntensity_spatial_rgb_factory = FunctionBundle(fallback)

const _RGB_SOBEL_Y, _RGB_SOBEL_X = reflect.(Kernel.sobel())
const _RGB_LAPLACIAN = reflect(convert(AbstractArray, Kernel.Laplacian((true, true))))

@inline function _finite_clamp(value::Real, lower::Float64, upper::Float64, default::Float64)
    converted = Float64(value)
    return isfinite(converted) ? clamp(converted, lower, upper) : default
end

@inline function _radius(value::Real)::Int
    converted = Float64(value)
    return isfinite(converted) ? round(Int, clamp(converted, 1.0, 5.0)) : 3
end

function _normalize_energy!(values::AbstractMatrix{Float64})
    maximum_value = maximum(values)
    if !isfinite(maximum_value) || maximum_value <= 1.0e-12
        fill!(values, 0.0)
    else
        values ./= maximum_value
    end
    return values
end

function _filter_channels(source::Array{Float64,3}, kernel)
    output = similar(source)
    for channel in 1:3
        output[:, :, channel] .= imfilter(
            @view(source[:, :, channel]), kernel, "reflect",
        )
    end
    return output
end

function _sobel_magnitude(source::Array{Float64,3})
    output = similar(source)
    for channel in 1:3
        plane = @view source[:, :, channel]
        dx = imfilter(plane, _RGB_SOBEL_X, "reflect")
        dy = imfilter(plane, _RGB_SOBEL_Y, "reflect")
        magnitude = sqrt.(dx .^ 2 .+ dy .^ 2)
        _normalize_energy!(magnitude)
        output[:, :, channel] .= magnitude
    end
    return output
end

function _laplacian_magnitude(source::Array{Float64,3})
    output = similar(source)
    for channel in 1:3
        response = abs.(imfilter(
            @view(source[:, :, channel]), _RGB_LAPLACIAN, "reflect",
        ))
        _normalize_energy!(response)
        output[:, :, channel] .= response
    end
    return output
end

function _gaussian_blur(source::Array{Float64,3}, sigma_input::Real)
    sigma = _finite_clamp(sigma_input, 0.3, 4.0, 1.0)
    return _filter_channels(source, Kernel.gaussian(sigma))
end

function _difference_of_gaussians(
        source::Array{Float64,3},
        sigma1_input::Real,
        sigma2_input::Real,
    )
    sigma1 = _finite_clamp(sigma1_input, 0.3, 4.0, 0.8)
    sigma2 = _finite_clamp(sigma2_input, 0.3, 4.0, 1.6)
    small_sigma, large_sigma = minmax(sigma1, sigma2)
    small = _filter_channels(source, Kernel.gaussian(small_sigma))
    large = _filter_channels(source, Kernel.gaussian(large_sigma))
    output = abs.(small .- large)
    for channel in 1:3
        _normalize_energy!(@view(output[:, :, channel]))
    end
    return output
end

function _unsharp_mask(
        source::Array{Float64,3},
        sigma_input::Real,
        amount_input::Real,
    )
    sigma = _finite_clamp(sigma_input, 0.3, 4.0, 1.0)
    amount = _finite_clamp(amount_input, 0.0, 3.0, 1.0)
    blurred = _filter_channels(source, Kernel.gaussian(sigma))
    return source .+ amount .* (source .- blurred)
end

function _local_moments(plane::AbstractMatrix{Float64}, radius::Int)
    width = 2radius + 1
    box = centered(fill(1.0 / width^2, width, width))
    local_mean = imfilter(plane, box, "reflect")
    local_square_mean = imfilter(plane .^ 2, box, "reflect")
    local_variance = max.(local_square_mean .- local_mean .^ 2, 0.0)
    local_variance[local_variance .<= 1.0e-12] .= 0.0
    return local_mean, local_variance
end

function _local_contrast_normalize(source::Array{Float64,3}, radius_input::Real)
    radius = _radius(radius_input)
    output = similar(source)
    for channel in 1:3
        plane = @view source[:, :, channel]
        local_mean, local_variance = _local_moments(plane, radius)
        standardized = (plane .- local_mean) ./ sqrt.(local_variance .+ 1.0e-6)
        output[:, :, channel] .= 0.5 .+ 0.2 .* standardized
    end
    return output
end

function _local_standard_deviation(source::Array{Float64,3}, radius_input::Real)
    radius = _radius(radius_input)
    output = similar(source)
    for channel in 1:3
        _, local_variance = _local_moments(@view(source[:, :, channel]), radius)
        energy = sqrt.(local_variance)
        _normalize_energy!(energy)
        output[:, :, channel] .= energy
    end
    return output
end

function _gabor_kernels(orientation_input::Real, wavelength_input::Real)
    raw_orientation = Float64(orientation_input)
    orientation = isfinite(raw_orientation) ? mod(raw_orientation, π) : 0.0
    wavelength = _finite_clamp(wavelength_input, 2.0, 8.0, 4.0)
    sigma = wavelength / 2
    radius = ceil(Int, 2sigma)
    real_kernel = Matrix{Float64}(undef, 2radius + 1, 2radius + 1)
    imaginary_kernel = similar(real_kernel)
    cosine = cos(orientation)
    sine = sin(orientation)
    for (row_index, y) in enumerate(-radius:radius)
        for (col_index, x) in enumerate(-radius:radius)
            rotated_x = x * cosine + y * sine
            rotated_y = -x * sine + y * cosine
            envelope = exp(-(rotated_x^2 + rotated_y^2) / (2sigma^2))
            phase = 2π * rotated_x / wavelength
            real_kernel[row_index, col_index] = envelope * cos(phase)
            imaginary_kernel[row_index, col_index] = envelope * sin(phase)
        end
    end
    real_kernel .-= sum(real_kernel) / length(real_kernel)
    imaginary_kernel .-= sum(imaginary_kernel) / length(imaginary_kernel)
    normalization = sqrt(sum(abs2, real_kernel) + sum(abs2, imaginary_kernel))
    real_kernel ./= normalization
    imaginary_kernel ./= normalization
    return centered(real_kernel), centered(imaginary_kernel)
end

function _gabor_energy(
        source::Array{Float64,3},
        orientation_input::Real,
        wavelength_input::Real,
    )
    real_kernel, imaginary_kernel = _gabor_kernels(orientation_input, wavelength_input)
    output = similar(source)
    for channel in 1:3
        plane = @view source[:, :, channel]
        real_response = imfilter(plane, real_kernel, "reflect")
        imaginary_response = imfilter(plane, imaginary_kernel, "reflect")
        energy = sqrt.(real_response .^ 2 .+ imaginary_response .^ 2)
        _normalize_energy!(energy)
        output[:, :, channel] .= energy
    end
    return output
end

function _spatial_factory(
        ::Type{I},
        function_name_prefix::Symbol,
        operation::Symbol,
    ) where {S1,S2,T,I<:SizedImage3D{S1,S2,3,IntensityPixel{T}}}
    IT = _get_image_type(I)
    PT = _get_image_pixel_type(I)
    S = _get_image_tuple_size(I)
    _validate_factory_type(IT)
    function_name = Symbol(function_name_prefix, :_, Symbol(I))
    call = if operation === :sobel
        :(_sobel_magnitude(source))
    elseif operation === :laplacian
        :(_laplacian_magnitude(source))
    elseif operation === :gaussian
        :(_gaussian_blur(source, parameter1))
    elseif operation === :dog
        :(_difference_of_gaussians(source, parameter1, parameter2))
    elseif operation === :unsharp
        :(_unsharp_mask(source, parameter1, parameter2))
    elseif operation === :local_contrast
        :(_local_contrast_normalize(source, parameter1))
    elseif operation === :local_std
        :(_local_standard_deviation(source, parameter1))
    elseif operation === :gabor
        :(_gabor_energy(source, parameter1, parameter2))
    else
        throw(ArgumentError("Unsupported spatial RGB operation: $operation"))
    end

    if operation in (:sobel, :laplacian)
        fn = @eval function $function_name(
                image::CONCT,
                args::Vararg{Any},
            ) where {CONCT<:$I}
            source = Float64.(reinterpret(image.img))
            output = $call
            clamped = clamp.(output, 0.0, 1.0)
            return SImageND($PT.($IT.(clamped)), $S)
        end
    elseif operation in (:gaussian, :local_contrast, :local_std)
        fn = @eval function $function_name(
                image::CONCT,
                parameter1::Real,
                args::Vararg{Any},
            ) where {CONCT<:$I}
            source = Float64.(reinterpret(image.img))
            output = $call
            clamped = clamp.(output, 0.0, 1.0)
            return SImageND($PT.($IT.(clamped)), $S)
        end
    else
        fn = @eval function $function_name(
                image::CONCT,
                parameter1::Real,
                parameter2::Real,
                args::Vararg{Any},
            ) where {CONCT<:$I}
            source = Float64.(reinterpret(image.img))
            output = $call
            clamped = clamp.(output, 0.0, 1.0)
            return SImageND($PT.($IT.(clamped)), $S)
        end
    end
    return fn
end

"""Specialize `sobel_magnitude_rgb(rgb) -> I`, the normalized channelwise Sobel gradient magnitude."""
sobel_magnitude_rgb_image3D_factory(::Type{I}) where {S1,S2,T,I<:SizedImage3D{S1,S2,3,IntensityPixel{T}}} =
    _spatial_factory(I, :sobel_magnitude_rgb, :sobel)

"""Specialize `laplacian_magnitude_rgb(rgb) -> I`, the normalized absolute channelwise Laplacian response."""
laplacian_magnitude_rgb_image3D_factory(::Type{I}) where {S1,S2,T,I<:SizedImage3D{S1,S2,3,IntensityPixel{T}}} =
    _spatial_factory(I, :laplacian_magnitude_rgb, :laplacian)

"""Specialize `gaussian_blur_rgb(rgb, sigma) -> I`; finite `sigma` is clamped to `[0.3,4]`."""
gaussian_blur_rgb_image3D_factory(::Type{I}) where {S1,S2,T,I<:SizedImage3D{S1,S2,3,IntensityPixel{T}}} =
    _spatial_factory(I, :gaussian_blur_rgb, :gaussian)

"""Specialize `difference_of_gaussians_rgb(rgb, sigma1, sigma2) -> I`; sigmas are clamped to `[0.3,4]`."""
difference_of_gaussians_rgb_image3D_factory(::Type{I}) where {S1,S2,T,I<:SizedImage3D{S1,S2,3,IntensityPixel{T}}} =
    _spatial_factory(I, :difference_of_gaussians_rgb, :dog)

"""Specialize `unsharp_mask_rgb(rgb, sigma, amount) -> I`; sigma is clamped to `[0.3,4]` and amount to `[0,3]`."""
unsharp_mask_rgb_image3D_factory(::Type{I}) where {S1,S2,T,I<:SizedImage3D{S1,S2,3,IntensityPixel{T}}} =
    _spatial_factory(I, :unsharp_mask_rgb, :unsharp)

"""Specialize `local_contrast_normalize_rgb(rgb, radius) -> I`; radius is rounded and clamped to `[1,5]`."""
local_contrast_normalize_rgb_image3D_factory(::Type{I}) where {S1,S2,T,I<:SizedImage3D{S1,S2,3,IntensityPixel{T}}} =
    _spatial_factory(I, :local_contrast_normalize_rgb, :local_contrast)

"""Specialize `local_std_rgb(rgb, radius) -> I`, normalized channelwise texture energy with radius in `[1,5]`."""
local_std_rgb_image3D_factory(::Type{I}) where {S1,S2,T,I<:SizedImage3D{S1,S2,3,IntensityPixel{T}}} =
    _spatial_factory(I, :local_std_rgb, :local_std)

"""Specialize `gabor_energy_rgb(rgb, orientation, wavelength) -> I`; orientation wraps modulo `π` and wavelength is clamped to `[2,8]`."""
gabor_energy_rgb_image3D_factory(::Type{I}) where {S1,S2,T,I<:SizedImage3D{S1,S2,3,IntensityPixel{T}}} =
    _spatial_factory(I, :gabor_energy_rgb, :gabor)

append_method!(
    bundle_image3DIntensity_spatial_rgb_factory,
    sobel_magnitude_rgb_image3D_factory,
    :sobel_magnitude_rgb;
    description = "Computes normalized Sobel edge magnitude independently in each RGB channel.",
)
append_method!(
    bundle_image3DIntensity_spatial_rgb_factory,
    laplacian_magnitude_rgb_image3D_factory,
    :laplacian_magnitude_rgb;
    description = "Computes the normalized absolute Laplacian response in each RGB channel.",
)
append_method!(
    bundle_image3DIntensity_spatial_rgb_factory,
    gaussian_blur_rgb_image3D_factory,
    :gaussian_blur_rgb;
    description = "Applies channelwise Gaussian smoothing with sigma clamped to [0.3,4].",
)
append_method!(
    bundle_image3DIntensity_spatial_rgb_factory,
    difference_of_gaussians_rgb_image3D_factory,
    :difference_of_gaussians_rgb;
    description = "Computes normalized channelwise Difference-of-Gaussians energy.",
)
append_method!(
    bundle_image3DIntensity_spatial_rgb_factory,
    unsharp_mask_rgb_image3D_factory,
    :unsharp_mask_rgb;
    description = "Sharpens each RGB channel with bounded Gaussian scale and amount.",
)
append_method!(
    bundle_image3DIntensity_spatial_rgb_factory,
    local_contrast_normalize_rgb_image3D_factory,
    :local_contrast_normalize_rgb;
    description = "Locally standardizes each RGB channel in a bounded reflected window.",
)
append_method!(
    bundle_image3DIntensity_spatial_rgb_factory,
    local_std_rgb_image3D_factory,
    :local_std_rgb;
    description = "Computes normalized local standard-deviation texture energy per RGB channel.",
)
append_method!(
    bundle_image3DIntensity_spatial_rgb_factory,
    gabor_energy_rgb_image3D_factory,
    :gabor_energy_rgb;
    description = "Computes channelwise Gabor energy with bounded orientation and wavelength.",
)

end
