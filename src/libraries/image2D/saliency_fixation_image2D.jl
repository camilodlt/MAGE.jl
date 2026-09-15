"""
Bottom-up fixation saliency maps for intensity images.

# Bundles

- [`bundle_image2DIntensity_saliency_fixation_factory`](@ref)

The exhaustive, always-current list of operators in each bundle is on the
[Bundle Catalogue](@ref) page.
"""
module image2D_saliency_fixation

using FFTW: fft, ifft
using ImageFiltering: Kernel, imfilter
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
    bundle_image2DIntensity_saliency_fixation_factory

Classical bottom-up fixation-prediction maps. Each operator maps an intensity
image to an intensity image of the same size, with saliency normalized to
`[0, 1]`.

The bundle is opt-in through `get_extension_saliency_intensityimg` because fixation
saliency is more specialized than basic pixel arithmetic. It is a factory
bundle: specialize an entry with the concrete image type before adding it to a
MAGE library.
"""
bundle_image2DIntensity_saliency_fixation_factory = FunctionBundle(fallback)

const _IKN_CENTER_SCALES = (2, 3, 4)
const _IKN_SCALE_DELTAS = (3, 4)
const _IKN_ORIENTATIONS = (0.0, pi / 4, pi / 2, 3pi / 4)
const _IKN_PYRAMID_BLUR = Kernel.gaussian(1.0)

function _normalize01(values::AbstractMatrix{<:Real})
    isempty(values) && return zeros(Float64, size(values))
    lo, hi = extrema(values)
    (!isfinite(lo) || !isfinite(hi) || hi <= lo) && return zeros(Float64, size(values))
    return (Float64.(values) .- lo) ./ (hi - lo)
end

function _mean_other_local_maxima(values::AbstractMatrix{<:Real})
    h, w = size(values)
    global_maximum = argmax(values)
    maxima_sum = 0.0
    maxima_count = 0

    @inbounds for row in 1:h, col in 1:w
        current = Float64(values[row, col])
        is_local_maximum = true
        is_strict = false
        for neighbor_row in max(1, row - 1):min(h, row + 1)
            for neighbor_col in max(1, col - 1):min(w, col + 1)
                (neighbor_row == row && neighbor_col == col) && continue
                neighbor = Float64(values[neighbor_row, neighbor_col])
                if neighbor > current
                    is_local_maximum = false
                    break
                end
                is_strict |= current > neighbor
            end
            is_local_maximum || break
        end

        if is_local_maximum && is_strict && CartesianIndex(row, col) != global_maximum
            maxima_sum += current
            maxima_count += 1
        end
    end

    return maxima_count == 0 ? 0.0 : maxima_sum / maxima_count
end

function _itti_normalize(values::AbstractMatrix{<:Real})
    normalized = _normalize01(values)
    maximum(normalized) == 0.0 && return normalized
    mean_other_maxima = _mean_other_local_maxima(normalized)
    normalized .*= (1.0 - mean_other_maxima)^2
    return normalized
end

function _resize_bilinear(values::AbstractMatrix{<:Real}, output_size::Tuple{Int,Int})
    input_h, input_w = size(values)
    output_h, output_w = output_size
    (input_h == output_h && input_w == output_w) && return Float64.(values)

    output = Matrix{Float64}(undef, output_h, output_w)
    row_scale = output_h == 1 ? 0.0 : (input_h - 1) / (output_h - 1)
    col_scale = output_w == 1 ? 0.0 : (input_w - 1) / (output_w - 1)

    @inbounds for output_row in 1:output_h
        input_row = output_h == 1 ? (input_h + 1) / 2 : 1 + (output_row - 1) * row_scale
        row_lo = clamp(floor(Int, input_row), 1, input_h)
        row_hi = min(row_lo + 1, input_h)
        row_weight = input_row - row_lo
        for output_col in 1:output_w
            input_col = output_w == 1 ? (input_w + 1) / 2 : 1 + (output_col - 1) * col_scale
            col_lo = clamp(floor(Int, input_col), 1, input_w)
            col_hi = min(col_lo + 1, input_w)
            col_weight = input_col - col_lo

            top = (1 - col_weight) * values[row_lo, col_lo] + col_weight * values[row_lo, col_hi]
            bottom = (1 - col_weight) * values[row_hi, col_lo] + col_weight * values[row_hi, col_hi]
            output[output_row, output_col] =
                (1 - row_weight) * top + row_weight * bottom
        end
    end
    return output
end

function _dyadic_gaussian_pyramid(channel::AbstractMatrix{<:Real})
    pyramid = Vector{Matrix{Float64}}(undef, 9)
    pyramid[1] = Float64.(channel)
    for level in 2:9
        blurred = imfilter(pyramid[level - 1], _IKN_PYRAMID_BLUR, "replicate")
        pyramid[level] = Matrix{Float64}(blurred[1:2:end, 1:2:end])
    end
    return pyramid
end

function _gabor_kernel(theta::Float64)
    sigma = 2.0
    wavelength = 4.0
    aspect_ratio = 0.5
    radius = 4
    kernel = Matrix{Float64}(undef, 2radius + 1, 2radius + 1)

    @inbounds for row in -radius:radius, col in -radius:radius
        x_theta = col * cos(theta) + row * sin(theta)
        y_theta = -col * sin(theta) + row * cos(theta)
        envelope = exp(-(x_theta^2 + aspect_ratio^2 * y_theta^2) / (2sigma^2))
        kernel[row + radius + 1, col + radius + 1] =
            envelope * cos(2pi * x_theta / wavelength)
    end
    kernel .-= sum(kernel) / length(kernel)
    kernel ./= sum(abs, kernel)
    return kernel
end

const _IKN_GABOR_KERNELS = map(_gabor_kernel, _IKN_ORIENTATIONS)

function _center_surround(center::AbstractMatrix{<:Real}, surround::AbstractMatrix{<:Real})
    resized_surround = _resize_bilinear(surround, size(center))
    return abs.(center .- resized_surround)
end

function _intensity_conspicuity(
        pyramid::Vector{Matrix{Float64}},
        saliency_size::Tuple{Int,Int},
    )
    conspicuity = zeros(Float64, saliency_size)
    for center_scale in _IKN_CENTER_SCALES, delta in _IKN_SCALE_DELTAS
        surround_scale = center_scale + delta
        feature = _center_surround(
            pyramid[center_scale + 1],
            pyramid[surround_scale + 1],
        )
        conspicuity .+= _resize_bilinear(_itti_normalize(feature), saliency_size)
    end
    return conspicuity
end

function _orientation_conspicuity(
        pyramid::Vector{Matrix{Float64}},
        saliency_size::Tuple{Int,Int},
    )
    conspicuity = zeros(Float64, saliency_size)
    oriented = Vector{Matrix{Float64}}(undef, 9)

    for kernel in _IKN_GABOR_KERNELS
        orientation_conspicuity = zeros(Float64, saliency_size)
        for scale in 2:8
            response = imfilter(pyramid[scale + 1], kernel, "replicate")
            oriented[scale + 1] = abs.(response)
        end
        for center_scale in _IKN_CENTER_SCALES, delta in _IKN_SCALE_DELTAS
            surround_scale = center_scale + delta
            feature = _center_surround(
                oriented[center_scale + 1],
                oriented[surround_scale + 1],
            )
            orientation_conspicuity .+=
                _resize_bilinear(_itti_normalize(feature), saliency_size)
        end
        conspicuity .+= _itti_normalize(orientation_conspicuity)
    end
    return conspicuity
end

function _grayscale_feature_channels(image::SImageND)
    return (; intensity = Float64.(reinterpret(image.img)))
end

function _itti_koch_niebur_grayscale(
        image::SImageND,
        orientation_weight::Float64,
        smoothing_sigma::Float64,
    )
    channels = _grayscale_feature_channels(image)
    pyramid = _dyadic_gaussian_pyramid(channels.intensity)
    saliency_size = size(pyramid[5])
    intensity = _itti_normalize(_intensity_conspicuity(pyramid, saliency_size))
    orientation = _itti_normalize(_orientation_conspicuity(pyramid, saliency_size))
    saliency = _normalize01(
        (1.0 - orientation_weight) .* intensity .+ orientation_weight .* orientation,
    )
    full_resolution = _resize_bilinear(saliency, size(channels.intensity))
    if smoothing_sigma > 0.0
        full_resolution = imfilter(
            full_resolution,
            Kernel.gaussian(smoothing_sigma),
            "replicate",
        )
    end
    return _normalize01(full_resolution)
end

"""
    itti_koch_saliency_image2D_factory(::Type{I})

Specialize the grayscale Itti-Koch-Niebur fixation-saliency operator for a
concrete MAGE intensity-image type `I`.

Returns a callable with these effective signatures (at most three MAGE inputs):

```julia
itti_koch_saliency(image::I) -> I
itti_koch_saliency(image::I, orientation_weight::Real) -> I
itti_koch_saliency(image::I, orientation_weight::Real, smoothing_sigma::Real) -> I
```

`image` is the intensity image to process. `orientation_weight` controls the
blend between intensity contrast (`0`) and oriented contrast (`1`) and is
clamped to `[0, 1]`; its default is `0.5`. `smoothing_sigma` is the final
Gaussian smoothing standard deviation in pixels and is clamped to `[0, 5]`;
its default is `0`. Non-finite parameter values use their respective defaults.
Any trailing `args` are accepted and ignored so the callable follows the MAGE
node-function convention. The returned image has the same dimensions and
`IntensityPixel` storage type as `image`.

The implementation follows the 1998 model's dyadic Gaussian pyramid, six
center-surround scale pairs, four Gabor orientations, and local-maximum
normalization. It returns a same-size `IntensityPixel` map in `[0, 1]`. Because
the current MAGE image type is grayscale, it deliberately omits the red-green
and blue-yellow opponency maps. It also stops at the static saliency map rather
than simulating winner-take-all dynamics or inhibition of return.

Reference: L. Itti, C. Koch, and E. Niebur, IEEE TPAMI 20(11), 1998,
doi:10.1109/34.730558.
"""
function itti_koch_saliency_image2D_factory(
        ::Type{I},
    ) where {S1,S2,T,I<:SizedImage2D{S1,S2,IntensityPixel{T}}}
    IT = _get_image_type(I)
    PT = _get_image_pixel_type(I)
    S = _get_image_tuple_size(I)
    _validate_factory_type(IT)
    function_name = Symbol(:itti_koch_saliency_image2D_, Symbol(I))

    fn = @eval function $function_name(
            image::CONCT,
            orientation_weight_input::Real,
            smoothing_sigma_input::Real,
            args::Vararg{Any},
        ) where {CONCT<:$I}
        orientation_weight_value = Float64(orientation_weight_input)
        smoothing_sigma_value = Float64(smoothing_sigma_input)
        orientation_weight = isfinite(orientation_weight_value) ?
                             clamp(orientation_weight_value, 0.0, 1.0) : 0.5
        smoothing_sigma = isfinite(smoothing_sigma_value) ?
                          clamp(smoothing_sigma_value, 0.0, 5.0) : 0.0
        saliency = _itti_koch_niebur_grayscale(
            image,
            orientation_weight,
            smoothing_sigma,
        )
        return SImageND($PT.($IT.(saliency)), $S)
    end
    @eval function $function_name(
            image::CONCT,
            orientation_weight::Real,
            args::Vararg{Any},
        ) where {CONCT<:$I}
        return $function_name(image, orientation_weight, 0.0, args...)
    end
    @eval function $function_name(
            image::CONCT,
            args::Vararg{Any},
        ) where {CONCT<:$I}
        return $function_name(image, 0.5, 0.0, args...)
    end
    return fn
end

append_method!(
    bundle_image2DIntensity_saliency_fixation_factory,
    itti_koch_saliency_image2D_factory,
    :itti_koch_saliency;
    description = "Computes grayscale Itti-Koch-Niebur bottom-up fixation saliency.",
)

function _circular_box_mean(values::AbstractMatrix{<:Real}, radius::Int)
    h, w = size(values)
    width = 2radius + 1
    horizontal = Matrix{Float64}(undef, h, w)
    output = Matrix{Float64}(undef, h, w)

    @inbounds for row in 1:h
        window_sum = sum(
            Float64(values[row, mod1(col, w)]) for col in (1 - radius):(1 + radius)
        )
        horizontal[row, 1] = window_sum / width
        for col in 2:w
            window_sum += Float64(values[row, mod1(col + radius, w)])
            window_sum -= Float64(values[row, mod1(col - radius - 1, w)])
            horizontal[row, col] = window_sum / width
        end
    end

    @inbounds for col in 1:w
        window_sum = sum(
            horizontal[mod1(row, h), col] for row in (1 - radius):(1 + radius)
        )
        output[1, col] = window_sum / width
        for row in 2:h
            window_sum += horizontal[mod1(row + radius, h), col]
            window_sum -= horizontal[mod1(row - radius - 1, h), col]
            output[row, col] = window_sum / width
        end
    end
    return output
end

function _spectral_residual_grayscale(
        image::SImageND,
        spectral_average_radius::Int,
        smoothing_sigma::Float64,
    )
    values = Float64.(reinterpret(image.img))
    lo, hi = extrema(values)
    (!isfinite(lo) || !isfinite(hi) || hi <= lo) && return zeros(Float64, size(values))
    spectrum = fft(values)
    log_amplitude = log.(abs.(spectrum) .+ eps(Float64))
    average_log_amplitude = _circular_box_mean(log_amplitude, spectral_average_radius)
    spectral_residual = log_amplitude .- average_log_amplitude
    reconstructed = ifft(exp.(spectral_residual .+ im .* angle.(spectrum)))
    saliency = abs2.(reconstructed)
    if smoothing_sigma > 0.0
        saliency = imfilter(saliency, Kernel.gaussian(smoothing_sigma), "replicate")
    end
    return _normalize01(saliency)
end

"""
    spectral_residual_saliency_image2D_factory(::Type{I})

Specialize the grayscale spectral-residual fixation-saliency operator for a
concrete MAGE intensity-image type `I`.

Returns a callable with these effective signatures (at most three MAGE inputs):

```julia
spectral_residual_saliency(image::I) -> I
spectral_residual_saliency(image::I, spectral_average_radius::Real) -> I
spectral_residual_saliency(image::I, spectral_average_radius::Real, smoothing_sigma::Real) -> I
```

`spectral_average_radius` is rounded to an integer and clamped to `[1, 15]`;
radius `r` averages the log-amplitude spectrum in a `(2r + 1) × (2r + 1)`
window. Its default is `1`, the classical `3 × 3` neighborhood.
`smoothing_sigma` is the final Gaussian standard deviation in pixels, clamped
to `[0, 5]`, and defaults to `2`. Non-finite values use their respective
defaults. Any trailing `args` are accepted and ignored for the MAGE
node-function convention.

The implementation computes the Fourier log-amplitude residual, combines it
with the original phase, applies the inverse transform, squares the magnitude,
smooths it, and normalizes the result to `[0, 1]`. The output has exactly the
same dimensions and `IntensityPixel` storage type as the specialization `I`.
The spectral operations are channel-local, so a future RGB specialization can
compute per-channel residual maps before combining them without changing this
grayscale API.

Reference: X. Hou and L. Zhang, CVPR 2007,
doi:10.1109/CVPR.2007.383267.
"""
function spectral_residual_saliency_image2D_factory(
        ::Type{I},
    ) where {S1,S2,T,I<:SizedImage2D{S1,S2,IntensityPixel{T}}}
    IT = _get_image_type(I)
    PT = _get_image_pixel_type(I)
    S = _get_image_tuple_size(I)
    _validate_factory_type(IT)
    function_name = Symbol(:spectral_residual_saliency_image2D_, Symbol(I))

    fn = @eval function $function_name(
            image::CONCT,
            spectral_average_radius_input::Real,
            smoothing_sigma_input::Real,
            args::Vararg{Any},
        ) where {CONCT<:$I}
        radius_value = Float64(spectral_average_radius_input)
        sigma_value = Float64(smoothing_sigma_input)
        spectral_average_radius = isfinite(radius_value) ?
                                  clamp(round(Int, radius_value), 1, 15) : 1
        smoothing_sigma = isfinite(sigma_value) ? clamp(sigma_value, 0.0, 5.0) : 2.0
        saliency = _spectral_residual_grayscale(
            image,
            spectral_average_radius,
            smoothing_sigma,
        )
        return SImageND($PT.($IT.(saliency)), $S)
    end
    @eval function $function_name(
            image::CONCT,
            spectral_average_radius::Real,
            args::Vararg{Any},
        ) where {CONCT<:$I}
        return $function_name(image, spectral_average_radius, 2.0, args...)
    end
    @eval function $function_name(
            image::CONCT,
            args::Vararg{Any},
        ) where {CONCT<:$I}
        return $function_name(image, 1.0, 2.0, args...)
    end
    return fn
end

append_method!(
    bundle_image2DIntensity_saliency_fixation_factory,
    spectral_residual_saliency_image2D_factory,
    :spectral_residual_saliency;
    description = "Computes grayscale spectral-residual bottom-up fixation saliency.",
)

end
