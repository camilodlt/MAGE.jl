"""
Deterministic continuous foreground extraction for intensity images.

# Bundles

- bundle_image2DIntensity_foreground_extraction_factory

The exhaustive operator list is on the Bundle Catalogue page.
"""
module image2D_foreground_extraction_continuous

using LinearAlgebra: Symmetric, cholesky
using SparseArrays: sparse
using ..image2D_saliency_fixation: _spectral_residual_grayscale
using ..image2D_foreground_extraction_discrete: _automatic_graphcut_seeds
using ..UTCGP: FunctionBundle, append_method!
using ..UTCGP:
    IntensityPixel,
    SImageND,
    SizedImage,
    SizedImage2D,
    _get_image_pixel_type,
    _get_image_tuple_size,
    _get_image_type,
    _validate_factory_type

fallback(args...) = return nothing

"""
    bundle_image2DIntensity_foreground_extraction_factory

Seeded, deterministic foreground extraction operators whose output is a
same-size intensity image of soft foreground membership values in [0, 1].
Factories are specialized with the concrete intensity output type before
insertion into a MAGE library.

The bundle currently contains Random Walker segmentation. It can derive seeds
from spectral-residual saliency internally or consume a same-size saliency map
from another MAGE image chromosome.
"""
bundle_image2DIntensity_foreground_extraction_factory = FunctionBundle(fallback)

const _RANDOM_WALKER_DEFAULT_CONTRAST = 90.0
const _RANDOM_WALKER_DEFAULT_FOREGROUND_QUANTILE = 0.95
const _RANDOM_WALKER_WEIGHT_FLOOR = 1.0e-6

@inline function _random_walker_squared_feature_distance(
        first_feature::Real,
        second_feature::Real,
    )
    difference = Float64(first_feature) - Float64(second_feature)
    return difference * difference
end

@inline function _random_walker_squared_feature_distance(
        first_feature::AbstractVector{<:Real},
        second_feature::AbstractVector{<:Real},
    )
    length(first_feature) == length(second_feature) ||
        throw(DimensionMismatch("feature vectors must have equal lengths"))
    distance = 0.0
    @inbounds for index in eachindex(first_feature, second_feature)
        difference = Float64(first_feature[index]) - Float64(second_feature[index])
        distance += difference * difference
    end
    return distance
end

@inline function _random_walker_edge_weight(
        first_feature,
        second_feature,
        contrast::Float64,
    )
    squared_distance = _random_walker_squared_feature_distance(
        first_feature,
        second_feature,
    )
    return exp(-contrast * squared_distance) + _RANDOM_WALKER_WEIGHT_FLOOR
end

"""
Solve the two-label Random Walker Dirichlet problem for explicit hard seeds.

The returned matrix is the probability that a walker first reaches a
foreground seed. Foreground seeds are exactly one, background seeds exactly
zero, and unknown pixels solve the weighted graph Laplacian.
"""
function _solve_random_walker(
        values::AbstractMatrix,
        foreground::AbstractMatrix{Bool},
        background::AbstractMatrix{Bool},
        contrast::Float64,
    )
    size(values) == size(foreground) == size(background) ||
        throw(DimensionMismatch("image and seed maps must have the same dimensions"))

    h, w = size(values)
    probabilities = zeros(Float64, h, w)
    isempty(values) && return probabilities

    foreground_seeds = BitMatrix(foreground)
    background_seeds = BitMatrix(background)
    background_seeds[foreground_seeds] .= false
    probabilities[foreground_seeds] .= 1.0
    any(foreground_seeds) || return probabilities
    any(background_seeds) || return fill(1.0, h, w)

    unknown_ids = zeros(Int, h, w)
    unknown_count = 0
    @inbounds for row in 1:h, col in 1:w
        if !foreground_seeds[row, col] && !background_seeds[row, col]
            unknown_count += 1
            unknown_ids[row, col] = unknown_count
        end
    end
    unknown_count == 0 && return probabilities

    rows = Int[]
    columns = Int[]
    coefficients = Float64[]
    right_hand_side = zeros(Float64, unknown_count)
    sizehint!(rows, 5unknown_count)
    sizehint!(columns, 5unknown_count)
    sizehint!(coefficients, 5unknown_count)

    @inbounds for row in 1:h, col in 1:w
        equation = unknown_ids[row, col]
        equation == 0 && continue
        center_feature = values[row, col]
        diagonal = 0.0

        for (neighbor_row, neighbor_col) in (
                (row - 1, col),
                (row + 1, col),
                (row, col - 1),
                (row, col + 1),
            )
            1 <= neighbor_row <= h && 1 <= neighbor_col <= w || continue
            weight = _random_walker_edge_weight(
                center_feature,
                values[neighbor_row, neighbor_col],
                contrast,
            )
            diagonal += weight
            neighbor_equation = unknown_ids[neighbor_row, neighbor_col]
            if neighbor_equation != 0
                push!(rows, equation)
                push!(columns, neighbor_equation)
                push!(coefficients, -weight)
            elseif foreground_seeds[neighbor_row, neighbor_col]
                right_hand_side[equation] += weight
            end
        end

        push!(rows, equation)
        push!(columns, equation)
        push!(coefficients, diagonal)
    end

    laplacian = sparse(rows, columns, coefficients, unknown_count, unknown_count)
    solution = cholesky(Symmetric(laplacian)) \ right_hand_side
    @inbounds for row in 1:h, col in 1:w
        equation = unknown_ids[row, col]
        equation == 0 && continue
        value = solution[equation]
        probabilities[row, col] = isfinite(value) ? clamp(value, 0.0, 1.0) : 0.0
    end
    return probabilities
end

function _random_walker_probabilities(
        values::AbstractMatrix,
        saliency::AbstractMatrix{<:Real},
        contrast::Float64,
        foreground_quantile::Float64,
    )
    size(values) == size(saliency) ||
        throw(DimensionMismatch("image and saliency must have the same dimensions"))
    foreground, background, normalized_saliency =
        _automatic_graphcut_seeds(saliency, foreground_quantile)
    maximum(normalized_saliency) == 0.0 &&
        return zeros(Float64, size(values))
    return _solve_random_walker(values, foreground, background, contrast)
end

"""
    random_walker_foreground_image2D_factory(::Type{I})

Specialize saliency-seeded Random Walker foreground extraction for a concrete
MAGE intensity output type I.

The returned callable supports these effective signatures:

    random_walker_foreground(image)
    random_walker_foreground(image, contrast::Real)
    random_walker_foreground(image, contrast::Real, foreground_quantile::Real)
    random_walker_foreground(image, saliency)
    random_walker_foreground(image, saliency, contrast::Real)

image is a same-size intensity image. The operator either computes
spectral-residual saliency internally or consumes a same-size intensity
saliency image. Saliency supplies deterministic hard foreground and background
seeds. Every other pixel receives the probability that a weighted four-neighbor
random walk reaches foreground before background.

contrast controls the conductance
exp(-contrast * (first - second)^2) + 1e-6; it is clamped to [0, 1000] and
defaults to 90. foreground_quantile is clamped to [0.5, 0.99] and defaults to
0.95. Non-finite values use the defaults. Supplied-saliency calls use the
default quantile to respect the MAGE three-input ceiling. Flat saliency returns
an all-zero probability map.

Every overload accepts and ignores trailing framework args... and returns
exactly the dimensions, IntensityPixel category, and storage type fixed by
specialization I.
"""
function random_walker_foreground_image2D_factory(
        ::Type{I},
    ) where {S1,S2,T,I<:SizedImage2D{S1,S2,IntensityPixel{T}}}
    IT = _get_image_type(I)
    PT = _get_image_pixel_type(I)
    S = _get_image_tuple_size(I)
    _validate_factory_type(IT)
    function_name = Symbol(:random_walker_foreground_image2D_, Symbol(I))

    fn = @eval function $function_name(
            image::SOURCE,
            saliency::SALIENCY,
            contrast_input::Real,
            args::Vararg{Any},
        ) where {
            ST,
            SOURCE<:SizedImage{$S,IntensityPixel{ST}},
            SAT,
            SALIENCY<:SizedImage{$S,IntensityPixel{SAT}},
        }
        contrast_value = Float64(contrast_input)
        contrast = isfinite(contrast_value) ?
                   clamp(contrast_value, 0.0, 1000.0) :
                   $_RANDOM_WALKER_DEFAULT_CONTRAST
        probabilities = _random_walker_probabilities(
            reinterpret(image.img),
            reinterpret(saliency.img),
            contrast,
            $_RANDOM_WALKER_DEFAULT_FOREGROUND_QUANTILE,
        )
        return SImageND($PT.($IT.(probabilities)), $S)
    end
    @eval function $function_name(
            image::SOURCE,
            saliency::SALIENCY,
            args::Vararg{Any},
        ) where {
            ST,
            SOURCE<:SizedImage{$S,IntensityPixel{ST}},
            SAT,
            SALIENCY<:SizedImage{$S,IntensityPixel{SAT}},
        }
        return $function_name(
            image,
            saliency,
            $_RANDOM_WALKER_DEFAULT_CONTRAST,
            args...,
        )
    end
    @eval function $function_name(
            image::SOURCE,
            contrast_input::Real,
            foreground_quantile_input::Real,
            args::Vararg{Any},
        ) where {ST,SOURCE<:SizedImage{$S,IntensityPixel{ST}}}
        contrast_value = Float64(contrast_input)
        quantile_value = Float64(foreground_quantile_input)
        contrast = isfinite(contrast_value) ?
                   clamp(contrast_value, 0.0, 1000.0) :
                   $_RANDOM_WALKER_DEFAULT_CONTRAST
        foreground_quantile = isfinite(quantile_value) ?
                              clamp(quantile_value, 0.5, 0.99) :
                              $_RANDOM_WALKER_DEFAULT_FOREGROUND_QUANTILE
        saliency = _spectral_residual_grayscale(image, 1, 2.0)
        probabilities = _random_walker_probabilities(
            reinterpret(image.img),
            saliency,
            contrast,
            foreground_quantile,
        )
        return SImageND($PT.($IT.(probabilities)), $S)
    end
    @eval function $function_name(
            image::SOURCE,
            contrast::Real,
            args::Vararg{Any},
        ) where {ST,SOURCE<:SizedImage{$S,IntensityPixel{ST}}}
        return $function_name(
            image,
            contrast,
            $_RANDOM_WALKER_DEFAULT_FOREGROUND_QUANTILE,
            args...,
        )
    end
    @eval function $function_name(
            image::SOURCE,
            args::Vararg{Any},
        ) where {ST,SOURCE<:SizedImage{$S,IntensityPixel{ST}}}
        return $function_name(
            image,
            $_RANDOM_WALKER_DEFAULT_CONTRAST,
            $_RANDOM_WALKER_DEFAULT_FOREGROUND_QUANTILE,
            args...,
        )
    end
    return fn
end

append_method!(
    bundle_image2DIntensity_foreground_extraction_factory,
    random_walker_foreground_image2D_factory,
    :random_walker_foreground;
    description = "Returns soft foreground probabilities from a saliency-seeded Random Walker solve.",
)


const _CLOSED_FORM_DEFAULT_EDGE_SENSITIVITY = 7.0
const _CLOSED_FORM_DEFAULT_FOREGROUND_QUANTILE = 0.95
const _CLOSED_FORM_CONSTRAINT_STRENGTH = 100.0
const _CLOSED_FORM_MAX_SOLVE_PIXELS = 96 * 96

function _closed_form_trimap_masks(trimap::AbstractMatrix{<:Real})
    foreground = falses(size(trimap))
    background = falses(size(trimap))
    @inbounds for index in eachindex(trimap)
        value = Float64(trimap[index])
        if isfinite(value)
            foreground[index] = value >= 0.9
            background[index] = value <= 0.1
        end
    end
    background[foreground] .= false
    return foreground, background
end

function _automatic_closed_form_trimap(
        saliency::AbstractMatrix{<:Real},
        foreground_quantile::Float64,
    )
    foreground, background, normalized =
        _automatic_graphcut_seeds(saliency, foreground_quantile)
    trimap = fill(0.5, size(saliency))
    trimap[background] .= 0.0
    trimap[foreground] .= 1.0
    return trimap, normalized
end

function _closed_form_working_size(h::Int, w::Int)
    h * w <= _CLOSED_FORM_MAX_SOLVE_PIXELS && return h, w
    scale = sqrt(_CLOSED_FORM_MAX_SOLVE_PIXELS / (h * w))
    return max(1, floor(Int, h * scale)), max(1, floor(Int, w * scale))
end

function _closed_form_downsample(
        values::AbstractMatrix,
        trimap::AbstractMatrix{<:Real},
        output_h::Int,
        output_w::Int,
    )
    h, w = size(values)
    output_values = Matrix{Float64}(undef, output_h, output_w)
    output_trimap = fill(0.5, output_h, output_w)
    @inbounds for output_row in 1:output_h, output_col in 1:output_w
        first_row = floor(Int, (output_row - 1) * h / output_h) + 1
        last_row = max(first_row, floor(Int, output_row * h / output_h))
        first_col = floor(Int, (output_col - 1) * w / output_w) + 1
        last_col = max(first_col, floor(Int, output_col * w / output_w))
        value_sum = 0.0
        foreground_count = 0
        background_count = 0
        sample_count = 0
        for row in first_row:last_row, col in first_col:last_col
            value_sum += Float64(values[row, col])
            trimap_value = Float64(trimap[row, col])
            foreground_count += isfinite(trimap_value) && trimap_value >= 0.9
            background_count += isfinite(trimap_value) && trimap_value <= 0.1
            sample_count += 1
        end
        output_values[output_row, output_col] = value_sum / sample_count
        if foreground_count > 0 && background_count == 0
            output_trimap[output_row, output_col] = 1.0
        elseif background_count > 0 && foreground_count == 0
            output_trimap[output_row, output_col] = 0.0
        elseif foreground_count != background_count
            output_trimap[output_row, output_col] =
                foreground_count > background_count ? 1.0 : 0.0
        end
    end
    return output_values, output_trimap
end

function _closed_form_resize_bilinear(
        values::AbstractMatrix{<:Real},
        output_h::Int,
        output_w::Int,
    )
    input_h, input_w = size(values)
    (input_h, input_w) == (output_h, output_w) && return Float64.(values)
    output = Matrix{Float64}(undef, output_h, output_w)
    row_scale = output_h == 1 ? 0.0 : (input_h - 1) / (output_h - 1)
    col_scale = output_w == 1 ? 0.0 : (input_w - 1) / (output_w - 1)
    @inbounds for row in 1:output_h, col in 1:output_w
        source_row = 1 + (row - 1) * row_scale
        source_col = 1 + (col - 1) * col_scale
        row0 = clamp(floor(Int, source_row), 1, input_h)
        col0 = clamp(floor(Int, source_col), 1, input_w)
        row1 = min(row0 + 1, input_h)
        col1 = min(col0 + 1, input_w)
        row_fraction = source_row - row0
        col_fraction = source_col - col0
        top = (1 - col_fraction) * Float64(values[row0, col0]) +
              col_fraction * Float64(values[row0, col1])
        bottom = (1 - col_fraction) * Float64(values[row1, col0]) +
                 col_fraction * Float64(values[row1, col1])
        output[row, col] =
            (1 - row_fraction) * top + row_fraction * bottom
    end
    return output
end

function _closed_form_matting_laplacian(
        values::AbstractMatrix{<:Real},
        epsilon::Float64,
    )
    h, w = size(values)
    pixel_count = h * w
    rows = Int[]
    columns = Int[]
    coefficients = Float64[]
    sizehint!(rows, 81pixel_count)
    sizehint!(columns, 81pixel_count)
    sizehint!(coefficients, 81pixel_count)
    window_indices = Vector{Int}(undef, 9)
    deviations = Vector{Float64}(undef, 9)

    @inbounds for center_row in 1:h, center_col in 1:w
        first_row = max(1, center_row - 1)
        last_row = min(h, center_row + 1)
        first_col = max(1, center_col - 1)
        last_col = min(w, center_col + 1)
        window_size = (last_row - first_row + 1) * (last_col - first_col + 1)
        mean_value = 0.0
        position = 0
        for row in first_row:last_row, col in first_col:last_col
            position += 1
            window_indices[position] = row + (col - 1) * h
            mean_value += Float64(values[row, col])
        end
        mean_value /= window_size
        variance_sum = 0.0
        position = 0
        for row in first_row:last_row, col in first_col:last_col
            position += 1
            deviation = Float64(values[row, col]) - mean_value
            deviations[position] = deviation
            variance_sum += deviation * deviation
        end
        denominator = variance_sum / window_size + epsilon / window_size
        inverse_window_size = 1.0 / window_size
        for first_position in 1:window_size
            first_index = window_indices[first_position]
            first_deviation = deviations[first_position]
            for second_position in 1:window_size
                second_index = window_indices[second_position]
                coefficient =
                    (first_position == second_position ? 1.0 : 0.0) -
                    inverse_window_size *
                    (1.0 + first_deviation * deviations[second_position] / denominator)
                push!(rows, first_index)
                push!(columns, second_index)
                push!(coefficients, coefficient)
            end
        end
    end
    return sparse(rows, columns, coefficients, pixel_count, pixel_count)
end

function _solve_closed_form_matting(
        values::AbstractMatrix{<:Real},
        trimap::AbstractMatrix{<:Real},
        epsilon::Float64,
    )
    size(values) == size(trimap) ||
        throw(DimensionMismatch("image and trimap must have the same dimensions"))
    h, w = size(values)
    isempty(values) && return zeros(Float64, h, w)
    foreground, background = _closed_form_trimap_masks(trimap)
    any(foreground) || return zeros(Float64, h, w)
    any(background) || return ones(Float64, h, w)
    known = foreground .| background

    laplacian = _closed_form_matting_laplacian(values, epsilon)
    diagonal = Float64.(vec(known)) .* _CLOSED_FORM_CONSTRAINT_STRENGTH .+ 1.0e-10
    system = laplacian + sparse(1:(h * w), 1:(h * w), diagonal, h * w, h * w)
    right_hand_side = Float64.(vec(foreground)) .* _CLOSED_FORM_CONSTRAINT_STRENGTH
    solution = cholesky(Symmetric(system)) \ right_hand_side
    alpha = reshape(solution, h, w)
    @inbounds for index in eachindex(alpha)
        value = alpha[index]
        alpha[index] = isfinite(value) ? clamp(value, 0.0, 1.0) : 0.0
    end
    alpha[background] .= 0.0
    alpha[foreground] .= 1.0
    return alpha
end

function _closed_form_alpha(
        values::AbstractMatrix{<:Real},
        trimap::AbstractMatrix{<:Real},
        edge_sensitivity::Float64,
    )
    size(values) == size(trimap) ||
        throw(DimensionMismatch("image and trimap must have the same dimensions"))
    h, w = size(values)
    foreground, background = _closed_form_trimap_masks(trimap)
    any(foreground) || return zeros(Float64, h, w)
    any(background) || return ones(Float64, h, w)
    epsilon = 10.0^(-edge_sensitivity)
    working_h, working_w = _closed_form_working_size(h, w)
    if (working_h, working_w) == (h, w)
        return _solve_closed_form_matting(values, trimap, epsilon)
    end
    working_values, working_trimap =
        _closed_form_downsample(values, trimap, working_h, working_w)
    working_alpha =
        _solve_closed_form_matting(working_values, working_trimap, epsilon)
    alpha = _closed_form_resize_bilinear(working_alpha, h, w)
    alpha[background] .= 0.0
    alpha[foreground] .= 1.0
    return alpha
end

"""
    closed_form_matting_image2D_factory(::Type{I})

Specialize grayscale closed-form alpha matting for a concrete MAGE intensity
output type I.

The returned callable supports these effective signatures:

    closed_form_matting(image)
    closed_form_matting(image, edge_sensitivity::Real)
    closed_form_matting(image, edge_sensitivity::Real, foreground_quantile::Real)
    closed_form_matting(image, trimap)
    closed_form_matting(image, trimap, edge_sensitivity::Real)

An explicit trimap uses values at most 0.1 as hard background, values at least
0.9 as hard foreground, and intermediate values as unknown. Without a trimap,
spectral-residual saliency supplies deterministic hard constraints and all
remaining pixels are unknown.

edge_sensitivity is clamped to [2, 12], defaults to 7, and maps to the matting
Laplacian epsilon as 10^(-edge_sensitivity). foreground_quantile is clamped to
[0.5, 0.99] and defaults to 0.95. Non-finite parameters use their defaults.
For bounded runtime, problems larger than 9216 pixels solve the same objective
on a deterministic reduced grid, lift the alpha matte bilinearly, and restore
the original hard constraints exactly.

Every overload accepts and ignores trailing framework args... and returns
exactly the dimensions, IntensityPixel category, and storage type fixed by
specialization I.
"""
function closed_form_matting_image2D_factory(
        ::Type{I},
    ) where {S1,S2,T,I<:SizedImage2D{S1,S2,IntensityPixel{T}}}
    IT = _get_image_type(I)
    PT = _get_image_pixel_type(I)
    S = _get_image_tuple_size(I)
    _validate_factory_type(IT)
    function_name = Symbol(:closed_form_matting_image2D_, Symbol(I))

    fn = @eval function $function_name(
            image::SOURCE,
            trimap::TRIMAP,
            edge_sensitivity_input::Real,
            args::Vararg{Any},
        ) where {
            ST,
            SOURCE<:SizedImage{$S,IntensityPixel{ST}},
            TT,
            TRIMAP<:SizedImage{$S,IntensityPixel{TT}},
        }
        raw_sensitivity = Float64(edge_sensitivity_input)
        edge_sensitivity = isfinite(raw_sensitivity) ?
            clamp(raw_sensitivity, 2.0, 12.0) :
            $_CLOSED_FORM_DEFAULT_EDGE_SENSITIVITY
        alpha = _closed_form_alpha(
            reinterpret(image.img),
            reinterpret(trimap.img),
            edge_sensitivity,
        )
        return SImageND($PT.($IT.(alpha)), $S)
    end
    @eval function $function_name(
            image::SOURCE,
            trimap::TRIMAP,
            args::Vararg{Any},
        ) where {
            ST,
            SOURCE<:SizedImage{$S,IntensityPixel{ST}},
            TT,
            TRIMAP<:SizedImage{$S,IntensityPixel{TT}},
        }
        return $function_name(
            image,
            trimap,
            $_CLOSED_FORM_DEFAULT_EDGE_SENSITIVITY,
            args...,
        )
    end
    @eval function $function_name(
            image::SOURCE,
            edge_sensitivity_input::Real,
            foreground_quantile_input::Real,
            args::Vararg{Any},
        ) where {ST,SOURCE<:SizedImage{$S,IntensityPixel{ST}}}
        raw_sensitivity = Float64(edge_sensitivity_input)
        raw_quantile = Float64(foreground_quantile_input)
        edge_sensitivity = isfinite(raw_sensitivity) ?
            clamp(raw_sensitivity, 2.0, 12.0) :
            $_CLOSED_FORM_DEFAULT_EDGE_SENSITIVITY
        foreground_quantile = isfinite(raw_quantile) ?
            clamp(raw_quantile, 0.5, 0.99) :
            $_CLOSED_FORM_DEFAULT_FOREGROUND_QUANTILE
        saliency = _spectral_residual_grayscale(image, 1, 2.0)
        trimap, normalized =
            _automatic_closed_form_trimap(saliency, foreground_quantile)
        alpha = maximum(normalized) == 0.0 ?
            zeros(Float64, $(S.parameters...)) :
            _closed_form_alpha(reinterpret(image.img), trimap, edge_sensitivity)
        return SImageND($PT.($IT.(alpha)), $S)
    end
    @eval function $function_name(
            image::SOURCE,
            edge_sensitivity::Real,
            args::Vararg{Any},
        ) where {ST,SOURCE<:SizedImage{$S,IntensityPixel{ST}}}
        return $function_name(
            image,
            edge_sensitivity,
            $_CLOSED_FORM_DEFAULT_FOREGROUND_QUANTILE,
            args...,
        )
    end
    @eval function $function_name(
            image::SOURCE,
            args::Vararg{Any},
        ) where {ST,SOURCE<:SizedImage{$S,IntensityPixel{ST}}}
        return $function_name(
            image,
            $_CLOSED_FORM_DEFAULT_EDGE_SENSITIVITY,
            $_CLOSED_FORM_DEFAULT_FOREGROUND_QUANTILE,
            args...,
        )
    end
    return fn
end

append_method!(
    bundle_image2DIntensity_foreground_extraction_factory,
    closed_form_matting_image2D_factory,
    :closed_form_matting;
    description = "Returns a soft alpha matte from explicit or automatically derived trimap constraints.",
)

end
