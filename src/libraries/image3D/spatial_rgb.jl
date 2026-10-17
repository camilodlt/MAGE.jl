"""
Fixed, training-free spatial feature transforms for typed RGB images.

# Bundles

- [`bundle_image3DIntensity_spatial_rgb_factory`](@ref)
"""
module image3D_spatial_rgb

using ..UTCGP: output_pixels, image_result, scratch, pixel_values!

using ImageFiltering: Kernel, centered, imfilter!, reflect
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

# ---------------------------------------------------------------------------
# How an operator runs
#
# Call tree of e.g. `gaussian_blur_rgb(rgb, σ; out)`:
#
#   output_pixels(out, image)                      where to write: out.img or a new array
#   _spatial_into!(pixels, image, kernel!, parameters...)
#   ├── pixel_values!(source, image.img)           pixels → Float64 (task scratch)
#   ├── kernel!(result, source, parameters...)     e.g. _gaussian_blur!: channel by channel
#   │   └── _filter_plane!(…)                      ImageFiltering's imfilter!, reflected border
#   └── _store_clamped!(pixels, result)            clamp to [0, 1], cast
#   image_result(out, pixels, size_type)
#
# Kernels write `result` (h × w × 3, task scratch) and never modify `source`;
# per-channel working planes come from `scratch`. The arithmetic is the
# original Float64 arithmetic, so results are unchanged.
# ---------------------------------------------------------------------------

"Channel `c` of an `h × w × 3` array as a matrix (a contiguous view)."
@inline _channel(values::Array{Float64,3}, c::Int) = view(values, :, :, c)

"A Float64 working plane of size `(h, w)` from task scratch, under `key`."
_plane(key::Symbol, values::Array{Float64,3}) = scratch(key, Float64, size(values, 1), size(values, 2))

"""
    _filter_plane!(destination, plane, kernel) -> destination

Convolve one channel with `kernel`, reflected border, into `destination`.
"""
function _filter_plane!(destination, plane, kernel)
    # TODO speed: imfilter! pads the plane into a new array on every call; a
    # padded working array kept across calls would remove that allocation.
    return imfilter!(destination, plane, kernel, "reflect")
end

"""
Divide by the maximum, so the strongest response is `1`; all `0` when the
maximum is not finite or below `1e-12`. Example: `[0, 2, 4]` → `[0, 0.5, 1]`.
"""
function _normalize_energy!(values::AbstractMatrix{Float64})
    maximum_value = maximum(values)
    if !isfinite(maximum_value) || maximum_value <= 1.0e-12
        fill!(values, 0.0)
    else
        values ./= maximum_value
    end
    return values
end

"Each channel of `source` convolved with `kernel`, into `result`."
function _filter_channels!(result, source, kernel)
    for c in 1:3
        _filter_plane!(_channel(result, c), _channel(source, c), kernel)
    end
    return result
end

"""
Per channel, the Sobel gradient magnitude `sqrt(dx² + dy²)`, divided by its maximum.

Example: a vertical step edge gives `1` along the edge, `0` on flat areas.
"""
function _sobel_magnitude!(result, source)
    dx = _plane(:rgb_dx, source)
    dy = _plane(:rgb_dy, source)
    for c in 1:3
        _filter_plane!(dx, _channel(source, c), _RGB_SOBEL_X)
        _filter_plane!(dy, _channel(source, c), _RGB_SOBEL_Y)
        magnitude = _channel(result, c)
        magnitude .= sqrt.(dx .^ 2 .+ dy .^ 2)
        _normalize_energy!(magnitude)
    end
    return result
end

"Per channel, the absolute Laplacian response, divided by its maximum."
function _laplacian_magnitude!(result, source)
    for c in 1:3
        response = _filter_plane!(_channel(result, c), _channel(source, c), _RGB_LAPLACIAN)
        response .= abs.(response)
        _normalize_energy!(response)
    end
    return result
end

"Gaussian blur of each channel, `σ` clamped to `[0.3, 4]` (NaN → 1)."
function _gaussian_blur!(result, source, sigma_input::Real)
    sigma = _finite_clamp(sigma_input, 0.3, 4.0, 1.0)
    return _filter_channels!(result, source, Kernel.gaussian(sigma))
end

"""
Per channel, `|G(σ_small) − G(σ_large)|` divided by its maximum; σ1 and σ2
are clamped to `[0.3, 4]` (defaults 0.8 and 1.6) and sorted.
"""
function _difference_of_gaussians!(result, source, sigma1_input::Real, sigma2_input::Real)
    sigma1 = _finite_clamp(sigma1_input, 0.3, 4.0, 0.8)
    sigma2 = _finite_clamp(sigma2_input, 0.3, 4.0, 1.6)
    small_sigma, large_sigma = minmax(sigma1, sigma2)
    small = _filter_channels!(result, source, Kernel.gaussian(small_sigma))
    large = _filter_channels!(scratch(:rgb_large, Float64, size(source)...), source, Kernel.gaussian(large_sigma))
    small .= abs.(small .- large)
    for c in 1:3
        _normalize_energy!(_channel(result, c))
    end
    return result
end

"""
Unsharp masking `v + amount · (v − G(σ))`, σ clamped to `[0.3, 4]` (NaN → 1)
and amount to `[0, 3]` (NaN → 1).
"""
function _unsharp_mask!(result, source, sigma_input::Real, amount_input::Real)
    sigma = _finite_clamp(sigma_input, 0.3, 4.0, 1.0)
    amount = _finite_clamp(amount_input, 0.0, 3.0, 1.0)
    blurred = _filter_channels!(result, source, Kernel.gaussian(sigma))
    blurred .= source .+ amount .* (source .- blurred)
    return result
end

"""
    _local_moments!(local_mean, local_variance, plane, radius)

Mean and variance of `plane` over the `(2r+1)²` window around each pixel
(reflected border); variances at or below `1e-12` are set to `0`.
"""
function _local_moments!(local_mean, local_variance, plane, radius::Int)
    width = 2radius + 1
    box = centered(fill(1.0 / width^2, width, width))
    _filter_plane!(local_mean, plane, box)
    squares = _plane(:rgb_squares, local_mean)
    squares .= plane .^ 2
    _filter_plane!(local_variance, squares, box)          # local mean of the squares, for now
    local_variance .= max.(local_variance .- local_mean .^ 2, 0.0)
    local_variance .= ifelse.(local_variance .<= 1.0e-12, 0.0, local_variance)
    return local_mean, local_variance
end

"A Float64 working plane of the size of the matrix `like`."
_plane(key::Symbol, like::AbstractMatrix) = scratch(key, Float64, size(like)...)

"""
Local standardisation per channel: `0.5 + 0.2 · (v − mean) / sqrt(variance + 1e-6)`
over a `(2r+1)²` window, `r` rounded and clamped to `[1, 5]` (NaN → 3).
"""
function _local_contrast_normalize!(result, source, radius_input::Real)
    radius = _radius(radius_input)
    local_mean = _plane(:rgb_mean, source)
    local_variance = _plane(:rgb_variance, source)
    for c in 1:3
        plane = _channel(source, c)
        _local_moments!(local_mean, local_variance, plane, radius)
        _channel(result, c) .= 0.5 .+ 0.2 .* ((plane .- local_mean) ./ sqrt.(local_variance .+ 1.0e-6))
    end
    return result
end

"Per channel, the local standard deviation over a `(2r+1)²` window, divided by its maximum."
function _local_standard_deviation!(result, source, radius_input::Real)
    radius = _radius(radius_input)
    local_mean = _plane(:rgb_mean, source)
    local_variance = _plane(:rgb_variance, source)
    for c in 1:3
        _local_moments!(local_mean, local_variance, _channel(source, c), radius)
        energy = _channel(result, c)
        energy .= sqrt.(local_variance)
        _normalize_energy!(energy)
    end
    return result
end

"""
    _gabor_kernels(orientation, wavelength) -> (real, imaginary)

Zero-mean Gabor kernel pair (cosine and sine phase) for an orientation
(radians, wrapped modulo π; NaN → 0) and a wavelength clamped to `[2, 8]`
pixels (NaN → 4), with σ = wavelength / 2, jointly normalised to unit energy.
"""
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

"Per channel, the Gabor energy `sqrt(real² + imaginary²)`, divided by its maximum."
function _gabor_energy!(result, source, orientation_input::Real, wavelength_input::Real)
    real_kernel, imaginary_kernel = _gabor_kernels(orientation_input, wavelength_input)
    real_response = _plane(:rgb_dx, source)
    imaginary_response = _plane(:rgb_dy, source)
    for c in 1:3
        _filter_plane!(real_response, _channel(source, c), real_kernel)
        _filter_plane!(imaginary_response, _channel(source, c), imaginary_kernel)
        energy = _channel(result, c)
        energy .= sqrt.(real_response .^ 2 .+ imaginary_response .^ 2)
        _normalize_energy!(energy)
    end
    return result
end

"""
    _spatial_into!(pixels, image, kernel!, parameters...) -> pixels

Run `kernel!(result, source, parameters...)` on the image's values and store
the result, clamped to `[0, 1]`, into `pixels`.
"""
function _spatial_into!(pixels, image, kernel!::K, parameters::Vararg{Any,N}) where {K,N}
    dims = size(image.img)
    source = pixel_values!(scratch(:rgb_source, Float64, dims...), image.img)
    result = scratch(:rgb_result, Float64, dims...)
    kernel!(result, source, parameters...)
    return _store_clamped!(pixels, result)
end

"`pixels .= P.(T.(clamp.(result, 0, 1)))`: one broadcast into the output."
function _store_clamped!(pixels::AbstractArray{IntensityPixel{T}}, result) where {T}
    pixels .= IntensityPixel{T}.(T.(clamp.(result, 0.0, 1.0)))
    return pixels
end

"The kernel of each operation and how many parameters it takes."
const _SPATIAL_KERNELS = Dict(
    :sobel => (_sobel_magnitude!, 0),
    :laplacian => (_laplacian_magnitude!, 0),
    :gaussian => (_gaussian_blur!, 1),
    :local_contrast => (_local_contrast_normalize!, 1),
    :local_std => (_local_standard_deviation!, 1),
    :dog => (_difference_of_gaussians!, 2),
    :unsharp => (_unsharp_mask!, 2),
    :gabor => (_gabor_energy!, 2),
)

"""
    _spatial_factory(I, function_name_prefix, operation) -> Function

Define the operator for RGB images of type `I`: `op(rgb[, p1[, p2]]; out)`
with as many numbers as the operation's kernel takes (see `_SPATIAL_KERNELS`).
"""
function _spatial_factory(
        ::Type{I},
        function_name_prefix::Symbol,
        operation::Symbol,
    ) where {S1,S2,T,I<:SizedImage3D{S1,S2,3,IntensityPixel{T}}}
    _validate_factory_type(_get_image_type(I))
    S = _get_image_tuple_size(I)
    function_name = Symbol(function_name_prefix, :_, Symbol(I))
    haskey(_SPATIAL_KERNELS, operation) || throw(ArgumentError("Unsupported spatial RGB operation: $operation"))
    kernel!, parameter_count = _SPATIAL_KERNELS[operation]
    parameters = [Symbol(:parameter, k) for k in 1:parameter_count]
    signature = [:(image::CONCT); [:($p::Real) for p in parameters]; :(args::Vararg{Any})]
    return @eval function $function_name($(signature...); out = nothing) where {CONCT<:$I}
        pixels = output_pixels(out, image)
        _spatial_into!(pixels, image, $kernel!, $(parameters...))
        return image_result(out, pixels, $S)
    end
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
