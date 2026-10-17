"""
Bottom-up fixation saliency maps for intensity images.

# Bundles

- [`bundle_image2DIntensity_saliency_fixation_factory`](@ref)

The exhaustive, always-current list of operators in each bundle is on the
[Bundle Catalogue](@ref) page.
"""
module image2D_saliency_fixation

using ..UTCGP: output_pixels, image_result, scratch, pixel_values!

using FFTW: plan_fft, plan_ifft
using LinearAlgebra: mul!
using ImageFiltering: Kernel, imfilter!
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

# ---------------------------------------------------------------------------
# Itti–Koch–Niebur saliency, computed in task scratch
#
# Call tree of `itti_koch_saliency(image, w, σ; out)`:
#
#   _itti_koch_niebur_into!(pixels, image, w, σ)
#   ├── _dyadic_gaussian_pyramid!(image)              9 levels, each half the previous size
#   ├── _intensity_conspicuity!(conspicuity, pyramid)
#   │   └── _add_feature!(…)                          centre–surround, normalise, resize, add
#   ├── _orientation_conspicuity!(conspicuity, pyramid)
#   │   ├── _oriented_levels!(pyramid, kernel)        |Gabor response| per level
#   │   └── _add_feature!(…)
#   ├── blend, _normalize01!, _resize_bilinear!, optional Gaussian smoothing
#   └── _store_values!(pixels, saliency)
#
# Every intermediate map lives in `scratch` (keyed per pyramid level), so a
# call allocates only ImageFiltering's internal padding. The arithmetic is the
# original one, step for step.
# ---------------------------------------------------------------------------

const _IKN_CENTER_SCALES = (2, 3, 4)
const _IKN_SCALE_DELTAS = (3, 4)
const _IKN_ORIENTATIONS = (0.0, pi / 4, pi / 2, 3pi / 4)
const _IKN_PYRAMID_BLUR = Kernel.gaussian(1.0)
"Scratch keys of the 9 pyramid levels and of the 9 oriented levels (built once, not per call)."
const _LEVEL_KEYS = ntuple(level -> Symbol(:ikn_level_, level), 9)
const _ORIENTED_KEYS = ntuple(level -> Symbol(:ikn_oriented_, level), 9)

"""
    _normalize01!(values) -> values

Rescale `values` min to max into `[0, 1]` in place; all `0` when empty,
constant or not finite. Example: `[2, 4, 6]` → `[0, 0.5, 1]`.
"""
function _normalize01!(values::AbstractMatrix{Float64})
    isempty(values) && return values
    lo, hi = extrema(values)
    (!isfinite(lo) || !isfinite(hi) || hi <= lo) && return fill!(values, 0.0)
    values .= (values .- lo) ./ (hi - lo)
    return values
end

"""
Mean of the strict local maxima (3 × 3 neighbourhood) other than the global
maximum; `0` when there are none.
"""
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

"""
    _itti_normalize!(values) -> values

Itti's map normalisation, in place: rescale to `[0, 1]`, then multiply by
`(1 − m)²`, `m` the mean of the local maxima other than the global one. A map
with one strong peak keeps it; a map with many similar peaks is damped.
"""
function _itti_normalize!(values::AbstractMatrix{Float64})
    _normalize01!(values)
    maximum(values) == 0.0 && return values
    mean_other_maxima = _mean_other_local_maxima(values)
    values .*= (1.0 - mean_other_maxima)^2
    return values
end

"""
    _resize_bilinear!(output, values) -> output

Bilinear resize of `values` to the size of `output`, corners aligned (output
pixel 1 reads input pixel 1, the last reads the last). Same size: a copy.

Example: a row `[0, 1]` resized to 3 columns gives `[0, 0.5, 1]`.
"""
function _resize_bilinear!(output::AbstractMatrix{Float64}, values::AbstractMatrix{<:Real})
    input_h, input_w = size(values)
    output_h, output_w = size(output)
    (input_h == output_h && input_w == output_w) && return copyto!(output, values)
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

"""
Smallest smoothing σ (pixels) that is applied. A Gaussian of σ < 0.1 already
leaves the map unchanged, and a vanishing σ (e.g. `1e-300`) gives a `NaN`
kernel, so smaller values mean no smoothing.
"""
const _MIN_SMOOTHING_SIGMA = 0.1

"Size of the next pyramid level: every other row and column, starting at the first (`224 → 112`, `7 → 4`)."
_half_size(level::AbstractMatrix) = (cld(size(level, 1), 2), cld(size(level, 2), 2))

"""
    _dyadic_gaussian_pyramid!(image) -> levels

Nine levels in task scratch: level 1 is the image's values, each next level
the previous one blurred (σ = 1) and subsampled by 2 (e.g. 224², 112², …, 1²).
The returned vector is itself task scratch.
"""
function _dyadic_gaussian_pyramid!(image::SImageND)
    levels = resize!(scratch(:ikn_pyramid, Matrix{Float64}, 0), 9)
    levels[1] = pixel_values!(scratch(_LEVEL_KEYS[1], Float64, size(image.img)...), image.img)
    for level in 2:9
        previous = levels[level-1]
        blurred = imfilter!(scratch(:ikn_blurred, Float64, size(previous)...), previous, _IKN_PYRAMID_BLUR, "replicate")
        next = scratch(_LEVEL_KEYS[level], Float64, _half_size(previous)...)
        next .= view(blurred, 1:2:size(blurred, 1), 1:2:size(blurred, 2))
        levels[level] = next
    end
    return levels
end

"""
    _gabor_kernel(theta) -> Matrix{Float64}

9 × 9 zero-mean Gabor kernel (σ = 2, wavelength 4, aspect ratio 0.5) oriented
at `theta` radians, scaled so its absolute values sum to 1.
"""
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

"""
    _add_feature!(conspicuity, levels, center_scale, surround_scale) -> conspicuity

Add one centre–surround feature map to `conspicuity`: `|centre − surround|`
(the surround level resized to the centre's size), Itti-normalised, resized to
the size of `conspicuity`.

Example: centre scale 2, surround 5 compares level 3 (fine) with level 6
(coarse): small bright spots on a dark surround stand out.
"""
function _add_feature!(conspicuity, levels, center_scale::Int, surround_scale::Int)
    center = levels[center_scale+1]
    feature = _resize_bilinear!(scratch(:ikn_feature, Float64, size(center)...), levels[surround_scale+1])
    feature .= abs.(center .- feature)
    _itti_normalize!(feature)
    conspicuity .+= _resize_bilinear!(scratch(:ikn_feature_resized, Float64, size(conspicuity)...), feature)
    return conspicuity
end

"Sum over the six centre–surround pairs of the intensity pyramid, into `conspicuity`."
function _intensity_conspicuity!(conspicuity, pyramid)
    fill!(conspicuity, 0.0)
    for center_scale in _IKN_CENTER_SCALES, delta in _IKN_SCALE_DELTAS
        _add_feature!(conspicuity, pyramid, center_scale, center_scale + delta)
    end
    return conspicuity
end

"""
    _oriented_levels!(pyramid, kernel) -> levels

`|pyramid level ∗ kernel|` for levels 3 to 9 (the only ones the
centre–surround pairs read), in task scratch; levels 1 and 2 are left unset.
"""
function _oriented_levels!(pyramid, kernel)
    oriented = resize!(scratch(:ikn_oriented, Matrix{Float64}, 0), 9)
    for scale in 2:8
        level = pyramid[scale+1]
        response = imfilter!(scratch(_ORIENTED_KEYS[scale+1], Float64, size(level)...), level, kernel, "replicate")
        response .= abs.(response)
        oriented[scale+1] = response
    end
    return oriented
end

"""
Sum over the four Gabor orientations of the Itti-normalised orientation
conspicuity (six centre–surround pairs each), into `conspicuity`.
"""
function _orientation_conspicuity!(conspicuity, pyramid)
    fill!(conspicuity, 0.0)
    per_orientation = scratch(:ikn_per_orientation, Float64, size(conspicuity)...)
    for kernel in _IKN_GABOR_KERNELS
        oriented = _oriented_levels!(pyramid, kernel)
        fill!(per_orientation, 0.0)
        for center_scale in _IKN_CENTER_SCALES, delta in _IKN_SCALE_DELTAS
            _add_feature!(per_orientation, oriented, center_scale, center_scale + delta)
        end
        conspicuity .+= _itti_normalize!(per_orientation)
    end
    return conspicuity
end

"""
    _itti_koch_niebur_into!(pixels, image, orientation_weight, smoothing_sigma) -> pixels

The saliency map of `image`, normalised to `[0, 1]`, written into `pixels`:
the intensity and orientation conspicuities (at pyramid level 5) blended by
`orientation_weight`, resized to full resolution and optionally smoothed.
"""
function _itti_koch_niebur_into!(pixels, image::SImageND, orientation_weight::Float64, smoothing_sigma::Float64)
    pyramid = _dyadic_gaussian_pyramid!(image)
    saliency_size = size(pyramid[5])
    intensity = _itti_normalize!(_intensity_conspicuity!(scratch(:ikn_intensity, Float64, saliency_size...), pyramid))
    orientation = _itti_normalize!(_orientation_conspicuity!(scratch(:ikn_orientation, Float64, saliency_size...), pyramid))
    intensity .= (1.0 - orientation_weight) .* intensity .+ orientation_weight .* orientation   # the blend, in place
    saliency = _normalize01!(intensity)
    full_resolution = _resize_bilinear!(scratch(:ikn_full, Float64, size(image.img)...), saliency)
    if smoothing_sigma >= _MIN_SMOOTHING_SIGMA
        full_resolution = imfilter!(scratch(:ikn_smoothed, Float64, size(image.img)...), full_resolution,
            Kernel.gaussian(smoothing_sigma), "replicate")
    end
    return _store_values!(pixels, _normalize01!(full_resolution))
end

"`pixels .= P.(T.(values))` for values in `[0, 1]`: one broadcast into the output."
function _store_values!(pixels::AbstractArray{IntensityPixel{T}}, values) where {T}
    pixels .= IntensityPixel{T}.(T.(values))
    return pixels
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
Gaussian smoothing standard deviation in pixels and is clamped to `[0, 5]`
(below `0.1` there is no smoothing); its default is `0`. Non-finite parameter values use their respective defaults.
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
    _validate_factory_type(_get_image_type(I))
    S = _get_image_tuple_size(I)
    function_name = Symbol(:itti_koch_saliency_image2D_, Symbol(I))

    fn = @eval function $function_name(
            image::CONCT,
            orientation_weight_input::Real,
            smoothing_sigma_input::Real,
            args::Vararg{Any};
            out = nothing,
        ) where {CONCT<:$I}
        orientation_weight_value = Float64(orientation_weight_input)
        smoothing_sigma_value = Float64(smoothing_sigma_input)
        orientation_weight = isfinite(orientation_weight_value) ?
                             clamp(orientation_weight_value, 0.0, 1.0) : 0.5
        smoothing_sigma = isfinite(smoothing_sigma_value) ?
                          clamp(smoothing_sigma_value, 0.0, 5.0) : 0.0
        pixels = output_pixels(out, image)
        _itti_koch_niebur_into!(pixels, image, orientation_weight, smoothing_sigma)
        return image_result(out, pixels, $S)
    end
    @eval function $function_name(
            image::CONCT,
            orientation_weight::Real,
            args::Vararg{Any};
            out = nothing,
        ) where {CONCT<:$I}
        return $function_name(image, orientation_weight, 0.0; out)
    end
    @eval function $function_name(
            image::CONCT,
            args::Vararg{Any};
            out = nothing,
        ) where {CONCT<:$I}
        return $function_name(image, 0.5, 0.0; out)
    end
    return fn
end

append_method!(
    bundle_image2DIntensity_saliency_fixation_factory,
    itti_koch_saliency_image2D_factory,
    :itti_koch_saliency;
    description = "Computes grayscale Itti-Koch-Niebur bottom-up fixation saliency.",
)

"""
    _circular_box_mean!(output, values, radius) -> output

Mean over the `(2r+1)²` window around each pixel, wrapping around the borders
(the spectrum is periodic), by running sums along rows then columns.

Example (one row, `r = 1`): `[3, 0, 0, 0]` → `[1, 1, 0, 1]` (the first and
last pixels see the 3 through the wrap).
"""
function _circular_box_mean!(output::AbstractMatrix{Float64}, values::AbstractMatrix{<:Real}, radius::Int)
    h, w = size(values)
    width = 2radius + 1
    horizontal = scratch(:sr_horizontal, Float64, h, w)

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

"""
    _spectral_residual_map(image, spectral_average_radius, smoothing_sigma) -> Matrix{Float64}

Spectral-residual saliency of `image`, normalised to `[0, 1]` (all `0` for a
constant image), in task scratch (valid until the next call in the same task):

1. `spectrum = fft(values)`; `L = log(|spectrum| + eps)`;
2. residual `R = L − box mean of L` (radius `spectral_average_radius`, wrapped);
3. `saliency = |ifft(exp(R + i·angle(spectrum)))|²`, optionally smoothed.

The FFTs use the same FFTW plans as `fft` / `ifft`, applied with `mul!` into
task scratch, so the result is unchanged.
"""
function _spectral_residual_map(image::SImageND, spectral_average_radius::Int, smoothing_sigma::Float64)
    dims = size(image.img)
    values = pixel_values!(scratch(:sr_values, Float64, dims...), image.img)
    lo, hi = extrema(values)
    if !isfinite(lo) || !isfinite(hi) || hi <= lo
        return fill!(scratch(:sr_saliency, Float64, dims...), 0.0)
    end
    complex_values = scratch(:sr_complex_values, ComplexF64, dims...)
    complex_values .= values
    spectrum = mul!(scratch(:sr_spectrum, ComplexF64, dims...), plan_fft(complex_values), complex_values)
    log_amplitude = scratch(:sr_log_amplitude, Float64, dims...)
    log_amplitude .= log.(abs.(spectrum) .+ eps(Float64))
    average_log_amplitude = _circular_box_mean!(scratch(:sr_average, Float64, dims...), log_amplitude, spectral_average_radius)
    residual_spectrum = scratch(:sr_residual_spectrum, ComplexF64, dims...)
    residual_spectrum .= exp.((log_amplitude .- average_log_amplitude) .+ im .* angle.(spectrum))
    reconstructed = mul!(complex_values, plan_ifft(residual_spectrum), residual_spectrum)   # reuses the input buffer
    saliency = scratch(:sr_saliency, Float64, dims...)
    saliency .= abs2.(reconstructed)
    if smoothing_sigma >= _MIN_SMOOTHING_SIGMA
        saliency = imfilter!(scratch(:sr_smoothed, Float64, dims...), saliency, Kernel.gaussian(smoothing_sigma), "replicate")
    end
    return _normalize01!(saliency)
end

"""
    _spectral_residual_grayscale(image, spectral_average_radius, smoothing_sigma) -> Matrix{Float64}

As `_spectral_residual_map`, in a new array the caller may keep (used by the
foreground-extraction operators).
"""
_spectral_residual_grayscale(image::SImageND, spectral_average_radius::Int, smoothing_sigma::Float64) =
    copy(_spectral_residual_map(image, spectral_average_radius, smoothing_sigma))

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
to `[0, 5]` (below `0.1` there is no smoothing), and defaults to `2`. Non-finite values use their respective
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
    _validate_factory_type(_get_image_type(I))
    S = _get_image_tuple_size(I)
    function_name = Symbol(:spectral_residual_saliency_image2D_, Symbol(I))

    fn = @eval function $function_name(
            image::CONCT,
            spectral_average_radius_input::Real,
            smoothing_sigma_input::Real,
            args::Vararg{Any};
            out = nothing,
        ) where {CONCT<:$I}
        radius_value = Float64(spectral_average_radius_input)
        sigma_value = Float64(smoothing_sigma_input)
        spectral_average_radius = isfinite(radius_value) ?
                                  round(Int, clamp(radius_value, 1.0, 15.0)) : 1
        smoothing_sigma = isfinite(sigma_value) ? clamp(sigma_value, 0.0, 5.0) : 2.0
        pixels = output_pixels(out, image)
        _store_values!(pixels, _spectral_residual_map(image, spectral_average_radius, smoothing_sigma))
        return image_result(out, pixels, $S)
    end
    @eval function $function_name(
            image::CONCT,
            spectral_average_radius::Real,
            args::Vararg{Any};
            out = nothing,
        ) where {CONCT<:$I}
        return $function_name(image, spectral_average_radius, 2.0; out)
    end
    @eval function $function_name(
            image::CONCT,
            args::Vararg{Any};
            out = nothing,
        ) where {CONCT<:$I}
        return $function_name(image, 1.0, 2.0; out)
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
