"""
Deterministic continuous foreground extraction for intensity images.

# Bundles

- bundle_image2DIntensity_foreground_extraction_factory

The exhaustive operator list is on the Bundle Catalogue page.
"""
module image2D_foreground_extraction_continuous

using ..UTCGP: _factory_type_symbol, @serialized_factory

using ..UTCGP: scratch, output_pixels, image_result

using LinearAlgebra: Symmetric, cholesky, cholesky!
using ..image2D_foreground_extraction_discrete: _foreground_apply!
using SparseArrays: sparse, sparse!, CHOLMOD
using ..image2D_saliency_fixation: _spectral_residual_grayscale
using ..image2D_foreground_extraction_discrete: _automatic_graphcut_seeds, _mask_band_seeds, _seed_band
using ..UTCGP: FunctionBundle, append_method!
using ..UTCGP:
    BinaryPixel,
    IntensityPixel,
    SImageND,
    SizedImage,
    SizedImage2D,
    _get_image_pixel_type,
    _get_image_tuple_size,
    _get_image_type,
    _validate_factory_type

"A typed, single-factor task slot; e.g. changing patterns replaces its one retained factor."
mutable struct _SymbolicCache
    column_pointers::Vector{Int}
    row_indices::Vector{Int}
    factor::Union{Nothing,CHOLMOD.Factor{Float64,Int}}
end

"""Get this task's bounded symbolic cache; repeated calls return the same typed slot."""
function _symbolic_cache()
    cache = get!(task_local_storage(), :foreground_symbolic_cache) do
        _SymbolicCache(Int[], Int[], nothing)
    end
    return cache::_SymbolicCache
end

"""Reuse analysis on exactly matching patterns, recomputing all numerical values.
For example, changing `[2]` to `[3]` with right-hand side `[1]` gives `[1/3]`.
Pattern arrays are copied because callers reuse sparse assembly storage.
"""
function _symbolic_solve(matrix, rhs)::Vector{Float64}
    cache = _symbolic_cache()
    factor = cache.factor
    same_pattern = cache.column_pointers == matrix.colptr && cache.row_indices == matrix.rowval
    if factor !== nothing && same_pattern
        factor = cholesky!(factor, Symmetric(matrix))
    else
        factor = cholesky(Symmetric(matrix))
        cache.column_pointers = copy(matrix.colptr)
        cache.row_indices = copy(matrix.rowval)
        cache.factor = factor
    end
    return factor \ rhs
end

fallback(args...) = return nothing

"""
    bundle_image2DIntensity_foreground_extraction_factory

Seeded, deterministic foreground extraction operators whose output is a
same-size intensity image of soft foreground membership values in [0, 1].
Images above 32 on either axis
are box pooled to a grid with longer axis 32 and preserved aspect ratio
(224×100 → 32×14). Walker rough masks use majority; matting masks use guarded 1/8 occupancy.
Trimap conflicts become unknown; soft outputs use bilinear lifting.
Images at most 32×32 use their input grid. Existing third arguments retain
their parameter meanings; maximum graph-node arity is three.

Factories are specialized with the concrete intensity output type before
insertion into a MAGE library.

The bundle contains Random Walker segmentation and closed-form matting. Their
seeds come from spectral-residual saliency computed internally, a same-size
saliency map (Random Walker) or trimap (matting) from another MAGE image
chromosome, or a rough binary mask with an uncertainty band
(`(img, mask, band)`), which they refine to the image's edges.
"""
bundle_image2DIntensity_foreground_extraction_factory = FunctionBundle(fallback)

# Call tree: factory → _foreground_apply! → plain matrix kernels → seed helpers
# → solve → triplet assembly → _continuous_sparse
# → sparse! duplicate reduction → CHOLMOD Cholesky solve.

"""
Build a temporary sparse system using reusable assembly storage.

Uses precisely the sparse! implementation called by sparse, preserving duplicate
addition order. Storage is valid only until the next assembly in this task.
Example: triplets ([1, 1], [1, 1], [2.0, 3.0]) produce the entry 5.0.
"""
function _continuous_sparse(rows, columns, coefficients, n::Int)
    return sparse!(rows, columns, coefficients, n, n, +,
        resize!(scratch(:continuous_last_touch, Int, 0), n),
        resize!(scratch(:continuous_csr_ptr, Int, 0), n + 1),
        resize!(scratch(:continuous_csr_col, Int, 0), length(rows)),
        resize!(scratch(:continuous_csr_val, Float64, 0), length(rows)),
        resize!(scratch(:continuous_csc_ptr, Int, 0), n + 1),
        scratch(:continuous_csc_row, Int, 0),
        scratch(:continuous_csc_val, Float64, 0))
end

const _RANDOM_WALKER_DEFAULT_CONTRAST = 90.0
const _RANDOM_WALKER_DEFAULT_FOREGROUND_QUANTILE = 0.95
const _RANDOM_WALKER_WEIGHT_FLOOR = 1.0e-6

@inline function _random_walker_edge_weight(first::Real, second::Real, contrast::Float64)
    difference = Float64(first) - Float64(second)
    squared_distance = difference * difference
    return exp(-contrast * squared_distance) + _RANDOM_WALKER_WEIGHT_FLOOR
end

"""
Solve the two-label Random Walker Dirichlet problem for explicit hard seeds.

Example: a row with foreground and background endpoints fixes them to 1 and 0.
The returned matrix is the probability that a walker first reaches a
foreground seed. Working probabilities live in task scratch until the next solve.
Foreground seeds are exactly one, background seeds exactly
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
    probabilities = fill!(scratch(:walker_probabilities, Float64, h, w), 0.0)
    isempty(values) && return probabilities

    foreground_seeds = BitMatrix(foreground)
    background_seeds = BitMatrix(background)
    background_seeds[foreground_seeds] .= false
    probabilities[foreground_seeds] .= 1.0
    any(foreground_seeds) || return probabilities
    any(background_seeds) || return fill!(probabilities, 1.0)

    unknown_ids = fill!(scratch(:walker_unknown_ids, Int, h, w), 0)
    unknown_count = 0
    @inbounds for row in 1:h, col in 1:w
        if !foreground_seeds[row, col] && !background_seeds[row, col]
            unknown_count += 1
            unknown_ids[row, col] = unknown_count
        end
    end
    unknown_count == 0 && return probabilities

    rows = empty!(scratch(:continuous_triplet_rows, Int, 0))
    columns = empty!(scratch(:continuous_triplet_cols, Int, 0))
    coefficients = empty!(scratch(:continuous_triplet_values, Float64, 0))
    right_hand_side = fill!(resize!(scratch(:walker_rhs, Float64, 0), unknown_count), 0.0)
    sizehint!(rows, 5unknown_count; shrink = false)
    sizehint!(columns, 5unknown_count; shrink = false)
    sizehint!(coefficients, 5unknown_count; shrink = false)

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

    laplacian = _continuous_sparse(rows, columns, coefficients, unknown_count)
    solution = _symbolic_solve(laplacian, right_hand_side)
    @inbounds for row in 1:h, col in 1:w
        equation = unknown_ids[row, col]
        equation == 0 && continue
        value = solution[equation]
        probabilities[row, col] = isfinite(value) ? clamp(value, 0.0, 1.0) : 0.0
    end
    return probabilities
end

"""
Contrast for the mask-seeded Random Walker: `10` divided by the mean squared
difference between 4-neighbours, so the conductance `exp(-contrast · d²)`
adapts to the image's dynamic range. A neighbour difference of typical size
conducts `e^-10`, an identical neighbour fully, so walkers stay inside regions
of similar intensity. A fixed contrast would give almost uniform weights on a
dim image (steps of `0.05` with `90`: `e^-0.2`). A flat image uses `90`.
"""
function _random_walker_adaptive_contrast(values::AbstractMatrix{<:Real})
    h, w = size(values)
    total = 0.0
    pairs = 0
    @inbounds for row in 1:h, col in 1:w
        v = Float64(values[row, col])
        if row < h
            total += (v - Float64(values[row + 1, col]))^2
            pairs += 1
        end
        if col < w
            total += (v - Float64(values[row, col + 1]))^2
            pairs += 1
        end
    end
    mean_squared = pairs == 0 ? 0.0 : total / pairs
    return mean_squared <= 1.0e-12 ? _RANDOM_WALKER_DEFAULT_CONTRAST : 10.0 / mean_squared
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

# CHOLMOD owns numerical factorization; task scratch reuses assembly storage.
"""Write Random Walker pixels from supplied saliency; e.g. 32×14 in fills 32×14 out."""
function _random_walker_foreground_supplied!(
        pixels::AbstractMatrix{P},
        image::AbstractMatrix, saliency::AbstractMatrix, contrast_input::Real,
    ) where {P}
    pixel_type = P
    storage_type = fieldtype(P, 1)
    contrast_value = Float64(contrast_input)
    contrast = isfinite(contrast_value) ?
               clamp(contrast_value, 0.0, 1000.0) :
               _RANDOM_WALKER_DEFAULT_CONTRAST
    probabilities = _random_walker_probabilities(
        reinterpret(image),
        reinterpret(saliency),
        contrast,
        _RANDOM_WALKER_DEFAULT_FOREGROUND_QUANTILE,
    )
    pixels .= pixel_type.(storage_type.(probabilities))
    return pixels
end

"""Write Random Walker pixels from automatic seeds; e.g. 32×14 in fills 32×14 out."""
function _random_walker_foreground_automatic!(
        pixels::AbstractMatrix{P},
        image::AbstractMatrix, ::Nothing, contrast_input::Real, foreground_quantile_input::Real,
    ) where {P}
    pixel_type = P
    storage_type = fieldtype(P, 1)
    contrast_value = Float64(contrast_input)
    quantile_value = Float64(foreground_quantile_input)
    contrast = isfinite(contrast_value) ?
               clamp(contrast_value, 0.0, 1000.0) :
               _RANDOM_WALKER_DEFAULT_CONTRAST
    foreground_quantile = isfinite(quantile_value) ?
                          clamp(quantile_value, 0.5, 0.99) :
                          _RANDOM_WALKER_DEFAULT_FOREGROUND_QUANTILE
    saliency = _spectral_residual_grayscale(image, 1, 2.0)
    probabilities = _random_walker_probabilities(
        reinterpret(image),
        saliency,
        contrast,
        foreground_quantile,
    )
    pixels .= pixel_type.(storage_type.(probabilities))
    return pixels
end

"""Write Random Walker pixels from a rough mask; e.g. 32×14 in fills 32×14 out."""
function _random_walker_foreground_mask!(
        pixels::AbstractMatrix{P},
        image::AbstractMatrix, mask::AbstractMatrix, band::Real,
    ) where {P}
    pixel_type = P
    storage_type = fieldtype(P, 1)
    guess = BitMatrix(Bool.(reinterpret(mask)))
    probabilities = if !any(guess)
        zeros(Float64, size(guess))
    else
        seed_band = _seed_band(band)
        if seed_band == 0
            pixels .= pixel_type.(storage_type.(Float64.(guess)))
            return pixels
        end
        foreground, background = _mask_band_seeds(guess, seed_band)
        values = reinterpret(image)
        _solve_random_walker(values, foreground, background, _random_walker_adaptive_contrast(values))
    end
    pixels .= pixel_type.(storage_type.(probabilities))
    return pixels
end

"""
    random_walker_foreground_image2D_factory(::Type{I})

Example: `op(image, mask, 0)` fixes mask pixels to one and other pixels to zero.

Images above 32 pixels on either axis use a 32-pixel working grid.
All third inputs retain their existing parameter meanings.
"""
@serialized_factory function random_walker_foreground_image2D_factory(
        ::Type{I},
    ) where {S1,S2,T,I<:SizedImage2D{S1,S2,IntensityPixel{T}}}
    IT = _get_image_type(I)
    PT = _get_image_pixel_type(I)
    S = _get_image_tuple_size(I)
    _validate_factory_type(IT)
    function_name = Symbol(:random_walker_foreground_image2D_, _factory_type_symbol(I))
    isdefined(@__MODULE__, function_name) && return Base.invokelatest(getfield, @__MODULE__, function_name)

    fn = @eval function $function_name(
            image::SOURCE,
            saliency::SALIENCY,
            contrast_input::Real,
            args::Vararg{Any}; out = nothing,
        ) where {
            ST,
            SOURCE<:SizedImage{$S,IntensityPixel{ST}},
            SAT,
            SALIENCY<:SizedImage{$S,IntensityPixel{SAT}},
        }
        pixels = output_pixels(out, image, $PT)
        _foreground_apply!(
            _random_walker_foreground_supplied!, pixels, image.img, saliency.img,
            (contrast_input,), Val(:mean), Val(true),
        )
        return image_result(out, pixels, $S)
    end
    @eval function $function_name(
            image::SOURCE,
            saliency::SALIENCY,
            args::Vararg{Any}; out = nothing,
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
            args...; out,
        )
    end
    @eval function $function_name(
            image::SOURCE,
            contrast_input::Real,
            foreground_quantile_input::Real,
            args::Vararg{Any}; out = nothing,
        ) where {ST,SOURCE<:SizedImage{$S,IntensityPixel{ST}}}
        pixels = output_pixels(out, image, $PT)
        _foreground_apply!(
            _random_walker_foreground_automatic!, pixels, image.img, nothing,
            (contrast_input, foreground_quantile_input), Val(:mean), Val(true),
        )
        return image_result(out, pixels, $S)
    end
    @eval function $function_name(
            image::SOURCE,
            contrast::Real,
            args::Vararg{Any}; out = nothing,
        ) where {ST,SOURCE<:SizedImage{$S,IntensityPixel{ST}}}
        return $function_name(
            image,
            contrast,
            $_RANDOM_WALKER_DEFAULT_FOREGROUND_QUANTILE,
            args...; out,
        )
    end
    @eval function $function_name(
            image::SOURCE,
            args::Vararg{Any}; out = nothing,
        ) where {ST,SOURCE<:SizedImage{$S,IntensityPixel{ST}}}
        return $function_name(
            image,
            $_RANDOM_WALKER_DEFAULT_CONTRAST,
            $_RANDOM_WALKER_DEFAULT_FOREGROUND_QUANTILE,
            args...; out,
        )
    end
    # Seeds from a rough mask and an uncertainty band.
    @eval function $function_name(
            image::SOURCE,
            mask::MASK,
            band::Real,
            args::Vararg{Any}; out = nothing,
        ) where {ST,SOURCE<:SizedImage{$S,IntensityPixel{ST}},MT,MASK<:SizedImage{$S,BinaryPixel{MT}}}
        pixels = output_pixels(out, image, $PT)
        _foreground_apply!(
            _random_walker_foreground_mask!, pixels, image.img, mask.img,
            (band,), Val(:majority), Val(true),
        )
        return image_result(out, pixels, $S)
    end
    @eval function $function_name(
            image::SOURCE,
            mask::MASK,
            args::Vararg{Any}; out = nothing,
        ) where {ST,SOURCE<:SizedImage{$S,IntensityPixel{ST}},MT,MASK<:SizedImage{$S,BinaryPixel{MT}}}
        return $function_name(image, mask, 4.0, args...; out)
    end
    return fn
end

append_method!(
    bundle_image2DIntensity_foreground_extraction_factory,
    random_walker_foreground_image2D_factory,
    :random_walker_foreground;
    description = "Soft foreground probabilities from a Random Walker: (img, [contrast], [quantile]) with saliency-derived seeds, (img, saliency) or (img, mask, [band]) refining a rough mask.",
)


const _CLOSED_FORM_DEFAULT_EDGE_SENSITIVITY = 7.0
const _CLOSED_FORM_DEFAULT_FOREGROUND_QUANTILE = 0.95
const _CLOSED_FORM_CONSTRAINT_STRENGTH = 100.0

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

"""
Assemble the grayscale matting Laplacian in window/triplet order.
Example: a constant 1×1 image contributes a zero Laplacian entry.
The temporary sparse storage is consumed before another assembly can overwrite it.
"""
function _closed_form_matting_laplacian(
        values::AbstractMatrix{<:Real},
        epsilon::Float64,
    )
    h, w = size(values)
    pixel_count = h * w
    rows = empty!(scratch(:continuous_triplet_rows, Int, 0))
    columns = empty!(scratch(:continuous_triplet_cols, Int, 0))
    coefficients = empty!(scratch(:continuous_triplet_values, Float64, 0))
    # Each window emits every ordered pair, including duplicates. Reserve the
    # exact count; emission order determines floating-point duplicate sums.
    row_pairs = h == 1 ? 1 : max(0, 9h - 10)
    col_pairs = w == 1 ? 1 : max(0, 9w - 10)
    triplet_count = row_pairs * col_pairs
    resize!(rows, triplet_count)
    resize!(columns, triplet_count)
    resize!(coefficients, triplet_count)
    triplet = 0
    window_indices = scratch(:matting_window_indices, Int, 9)
    deviations = scratch(:matting_deviations, Float64, 9)

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
                triplet += 1
                rows[triplet] = first_index
                columns[triplet] = second_index
                coefficients[triplet] = coefficient
            end
        end
    end
    return _continuous_sparse(rows, columns, coefficients, pixel_count)
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
    solution = _symbolic_solve(system, right_hand_side)
    alpha = reshape(solution, h, w)
    @inbounds for index in eachindex(alpha)
        value = alpha[index]
        alpha[index] = isfinite(value) ? clamp(value, 0.0, 1.0) : 0.0
    end
    alpha[background] .= 0.0
    alpha[foreground] .= 1.0
    return alpha
end

"""Solve pooled matting with sensitivity `7` giving regularization `1e-7`."""
_closed_form_alpha(values, trimap, edge_sensitivity::Float64) =
    _solve_closed_form_matting(values, trimap, 10.0^(-edge_sensitivity))

# Sparse addition and CHOLMOD own the final system and numerical factorization.
"""Write matting pixels from a trimap; e.g. 32×14 in fills 32×14 out."""
function _closed_form_matting_supplied!(
        pixels::AbstractMatrix{P},
        image::AbstractMatrix, trimap::AbstractMatrix, edge_sensitivity_input::Real,
    ) where {P}
    pixel_type = P
    storage_type = fieldtype(P, 1)
    raw_sensitivity = Float64(edge_sensitivity_input)
    edge_sensitivity = isfinite(raw_sensitivity) ?
        clamp(raw_sensitivity, 2.0, 12.0) :
        _CLOSED_FORM_DEFAULT_EDGE_SENSITIVITY
    alpha = _closed_form_alpha(
        reinterpret(image),
        reinterpret(trimap),
        edge_sensitivity,
    )
    pixels .= pixel_type.(storage_type.(alpha))
    return pixels
end

"""Write matting pixels from automatic seeds; e.g. 32×14 in fills 32×14 out."""
function _closed_form_matting_automatic!(
        pixels::AbstractMatrix{P},
        image::AbstractMatrix, ::Nothing, edge_sensitivity_input::Real, foreground_quantile_input::Real,
    ) where {P}
    pixel_type = P
    storage_type = fieldtype(P, 1)
    raw_sensitivity = Float64(edge_sensitivity_input)
    raw_quantile = Float64(foreground_quantile_input)
    edge_sensitivity = isfinite(raw_sensitivity) ?
        clamp(raw_sensitivity, 2.0, 12.0) :
        _CLOSED_FORM_DEFAULT_EDGE_SENSITIVITY
    foreground_quantile = isfinite(raw_quantile) ?
        clamp(raw_quantile, 0.5, 0.99) :
        _CLOSED_FORM_DEFAULT_FOREGROUND_QUANTILE
    saliency = _spectral_residual_grayscale(image, 1, 2.0)
    trimap, normalized =
        _automatic_closed_form_trimap(saliency, foreground_quantile)
    alpha = maximum(normalized) == 0.0 ?
        zeros(Float64, size(image)) :
        _closed_form_alpha(reinterpret(image), trimap, edge_sensitivity)
    pixels .= pixel_type.(storage_type.(alpha))
    return pixels
end

"""Write matting pixels from a rough mask; e.g. 32×14 in fills 32×14 out."""
function _closed_form_matting_mask!(
        pixels::AbstractMatrix{P},
        image::AbstractMatrix, mask::AbstractMatrix, band::Real,
    ) where {P}
    pixel_type = P
    storage_type = fieldtype(P, 1)
    guess = BitMatrix(Bool.(reinterpret(mask)))
    alpha = if !any(guess)
        zeros(Float64, size(guess))
    else
        seed_band = _seed_band(band)
        if seed_band == 0
            pixels .= pixel_type.(storage_type.(Float64.(guess)))
            return pixels
        end
        foreground, background = _mask_band_seeds(guess, seed_band)
        trimap = fill(0.5, size(guess))
        trimap[background] .= 0.0
        trimap[foreground] .= 1.0
        _closed_form_alpha(reinterpret(image), trimap, _CLOSED_FORM_DEFAULT_EDGE_SENSITIVITY)
    end
    pixels .= pixel_type.(storage_type.(alpha))
    return pixels
end

"""
    closed_form_matting_image2D_factory(::Type{I})

Images above 32 pixels on either axis use a 32-pixel working grid.
All third inputs retain their existing parameter meanings.
"""
@serialized_factory function closed_form_matting_image2D_factory(
        ::Type{I},
    ) where {S1,S2,T,I<:SizedImage2D{S1,S2,IntensityPixel{T}}}
    IT = _get_image_type(I)
    PT = _get_image_pixel_type(I)
    S = _get_image_tuple_size(I)
    _validate_factory_type(IT)
    function_name = Symbol(:closed_form_matting_image2D_, _factory_type_symbol(I))
    isdefined(@__MODULE__, function_name) && return Base.invokelatest(getfield, @__MODULE__, function_name)

    fn = @eval function $function_name(
            image::SOURCE,
            trimap::TRIMAP,
            edge_sensitivity_input::Real,
            args::Vararg{Any}; out = nothing,
        ) where {
            ST,
            SOURCE<:SizedImage{$S,IntensityPixel{ST}},
            TT,
            TRIMAP<:SizedImage{$S,IntensityPixel{TT}},
        }
        pixels = output_pixels(out, image, $PT)
        _foreground_apply!(
            _closed_form_matting_supplied!, pixels, image.img, trimap.img,
            (edge_sensitivity_input,), Val(:trimap), Val(true),
        )
        return image_result(out, pixels, $S)
    end
    @eval function $function_name(
            image::SOURCE,
            trimap::TRIMAP,
            args::Vararg{Any}; out = nothing,
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
            args...; out,
        )
    end
    @eval function $function_name(
            image::SOURCE,
            edge_sensitivity_input::Real,
            foreground_quantile_input::Real,
            args::Vararg{Any}; out = nothing,
        ) where {ST,SOURCE<:SizedImage{$S,IntensityPixel{ST}}}
        pixels = output_pixels(out, image, $PT)
        _foreground_apply!(
            _closed_form_matting_automatic!, pixels, image.img, nothing,
            (edge_sensitivity_input, foreground_quantile_input), Val(:mean), Val(true),
        )
        return image_result(out, pixels, $S)
    end
    @eval function $function_name(
            image::SOURCE,
            edge_sensitivity::Real,
            args::Vararg{Any}; out = nothing,
        ) where {ST,SOURCE<:SizedImage{$S,IntensityPixel{ST}}}
        return $function_name(
            image,
            edge_sensitivity,
            $_CLOSED_FORM_DEFAULT_FOREGROUND_QUANTILE,
            args...; out,
        )
    end
    @eval function $function_name(
            image::SOURCE,
            args::Vararg{Any}; out = nothing,
        ) where {ST,SOURCE<:SizedImage{$S,IntensityPixel{ST}}}
        return $function_name(
            image,
            $_CLOSED_FORM_DEFAULT_EDGE_SENSITIVITY,
            $_CLOSED_FORM_DEFAULT_FOREGROUND_QUANTILE,
            args...; out,
        )
    end
    # A rough mask and an uncertainty band define the trimap: deep inside 1,
    # far outside 0, the band along the mask's edge unknown.
    @eval function $function_name(
            image::SOURCE,
            mask::MASK,
            band::Real,
            args::Vararg{Any}; out = nothing,
        ) where {ST,SOURCE<:SizedImage{$S,IntensityPixel{ST}},MT,MASK<:SizedImage{$S,BinaryPixel{MT}}}
        pixels = output_pixels(out, image, $PT)
        _foreground_apply!(
            _closed_form_matting_mask!, pixels, image.img, mask.img,
            (band,), Val(:sparse), Val(true),
        )
        return image_result(out, pixels, $S)
    end
    @eval function $function_name(
            image::SOURCE,
            mask::MASK,
            args::Vararg{Any}; out = nothing,
        ) where {ST,SOURCE<:SizedImage{$S,IntensityPixel{ST}},MT,MASK<:SizedImage{$S,BinaryPixel{MT}}}
        return $function_name(image, mask, 4.0, args...; out)
    end
    return fn
end

append_method!(
    bundle_image2DIntensity_foreground_extraction_factory,
    closed_form_matting_image2D_factory,
    :closed_form_matting;
    description = "Soft alpha matte: (img, [sensitivity], [quantile]) with saliency-derived constraints, (img, trimap) or (img, mask, [band]) refining a rough mask.",
)

end
