"""
Grey-level co-occurrence matrix (GLCM) texture features.

See the [ImageFeatures.jl GLCM tutorial](https://juliaimages.org/ImageFeatures.jl/stable/tutorials/glcm/#GLCM-Properties).

# Bundles

- [`experimental_bundle_float_glcm_factory`](@ref)

The exhaustive, always-current list of operators in each bundle is on the
[Bundle Catalogue](@ref) page.
"""
module experimental_GLCM

using Statistics
using ImageCore: N0f8, Normed, clamp01nan!
using ..UTCGP: FunctionBundle, append_method!
import ..UTCGP:
    CONSTRAINED,
    MIN_INT,
    MAX_INT,
    MIN_FLOAT,
    MAX_FLOAT,
    _positive_params,
    _ceil_positive_params
using ..UTCGP:
    SImage2D, SImageND, _get_image_tuple_size, _get_image_type, _validate_factory_type, BinaryPixel, _get_image_pixel_type, IntensityPixel, SegmentPixel
using ImageFeatures
using DispatchDoctor

# ################### #
# IDENTITY            #
# ################### #
InputType = SImage2D{S1, S2, <:Union{IntensityPixel{T1}, SegmentPixel{T2}}} where {S1, S2, T1, T2} # 2D img
fallback(args...) = return -1.0
"""
    experimental_bundle_float_glcm_factory

Experimental grey-level co-occurrence matrix (GLCM) texture features.

Ten Haralick-style statistics — GLCM mean and variance, correlation, contrast,
inverse difference moment, angular second moment, entropy, maximum probability,
energy and dissimilarity — each aggregated over the co-occurrence directions
five ways (`mean`, `sum`, `std`, `minimum`, `maximum`).

Planar intensity and label inputs only. Co-occurrences use bounded levels
1–255, scaled by the image maximum; all-zero images occupy the first level.
These are symmetric raw count matrices, not probability-normalised matrices.
Distance is clamped to 1–10, matrix size to at most 255 (at least the smaller
of five and the number of distinct samples). Non-finite parameters use
`distance=1`, `matrix_size=16`. Experimental: the API may change.

This is a *factory* bundle: each entry is a function of a type that returns the
method specialised for it, so the same operator can be instantiated for several
image or element types. See [Libraries](@ref) for how factories are specialised
into a library.
"""
experimental_bundle_float_glcm_factory = FunctionBundle(fallback)

# Utils
# Work in Float64 before quantisation. For fixed-point inputs the previous
# i * bins / maximum calculation could round the maximum above `bins`, so
# ceil selected an out-of-bounds (bins + 1) row in ImageFeatures._glcm.
function prep_glcm(img::InputType, dis::Int, matrix_size::Int, angles)
    real_img = Float64.(img.img)
    distance_neighborhood = clamp(dis, 1, 10)
    min_matrix_size = length(unique(real_img))
    new_matrix_size = clamp(matrix_size, max(1, min(5, min_matrix_size)), 255)
    maximum_value = isempty(real_img) ? 0.0 : maximum(real_img)
    levels = map(real_img) do v
        maximum_value <= 0 && return 1
        clamp(ceil(Int, clamp(v / maximum_value, 0.0, 1.0) * new_matrix_size), 1, new_matrix_size)
    end
    # Use ImageFeatures' co-occurrence kernel on our bounded levels. Avoid
    # asking its public wrapper to quantise the image a second time.
    glcm_array = map(angles) do angle
        counts = ImageFeatures._glcm(levels, distance_neighborhood, angle, new_matrix_size)
        counts + counts'
    end
    return (glcm = glcm_array, img = real_img, ditance = dis, matrix_size = matrix_size)
end

"Finite, bounded integer parameters, with the documented default for NaN/Inf."
function _glcm_parameter(value::Number, default::Int, upper::Int)
    v = Float64(value)
    return isfinite(v) ? ceil(Int, clamp(v, 1.0, Float64(upper))) : default
end

# FUNCTIONS ---
const angles_all_directions = [pi, 3 / 4 * pi, pi / 2, pi / 4]

function glcm_dispatcher(property::Function, operation::Function, name) #
    global InputType
    fn = @eval function $name(img::CONCT, dis::Number, matrix_size::Number, args::Vararg{Any}) where {CONCT <: $InputType}
        global angles_all_directions
        res_tuple = prep_glcm(img, _glcm_parameter(dis, 1, 10), _glcm_parameter(matrix_size, 16, 255), angles_all_directions)
        return Float64($operation($property.(res_tuple.glcm)))::Float64
    end


    fn = @eval function $name(img::CONCT, matrix_size::Number, args::Vararg{Any}) where {CONCT <: $InputType}
        return $name(img, 1, matrix_size)
    end

    fn = @eval function $name(img::CONCT, args::Vararg{Any}) where {CONCT <: $InputType}
        return $name(img, 1, 16)
    end

    return fn
end


function make_functions_with_op(property::Function)
    Dispatchers = Function[]
    Names = []
    for operation in [mean, sum, std, minimum, maximum]
        op_string = string(operation)
        name = Symbol("glcm_$(property)_$op_string")
        dispatcher = glcm_dispatcher(property, operation, name)
        push!(Dispatchers, dispatcher)
        push!(Names, name)
    end
    return Dispatchers, Names
end

function glcm_registration_description(name::Symbol)::String
    name_parts = split(String(name), "_")
    reducer_token = name_parts[end]
    metric_token = join(name_parts[1:end-1], "_")

    reducer_map = Dict(
        "mean" => "mean",
        "sum" => "sum",
        "std" => "standard deviation",
        "minimum" => "minimum",
        "maximum" => "maximum",
    )
    metric_map = Dict(
        "glcm_mean_ref" => "GLCM mean",
        "glcm_var_ref" => "GLCM variance",
        "glcm_correlation" => "GLCM correlation",
        "glcm_contrast" => "GLCM contrast",
        "glcm_IDM" => "GLCM inverse-difference-moment",
        "glcm_ASM" => "GLCM angular-second-moment",
        "glcm_glcm_entropy" => "GLCM entropy",
        "glcm_max_prob" => "GLCM max-probability",
        "glcm_energy" => "GLCM energy",
        "glcm_dissimilarity" => "GLCM dissimilarity",
    )

    reducer_label = get(reducer_map, reducer_token, reducer_token)
    metric_label = get(metric_map, metric_token, replace(metric_token, "_" => " "))
    return "Computes $(metric_label) across angles [pi, 3pi/4, pi/2, pi/4], then applies $(reducer_label) reducer. Supports signatures (img), (img, matrix_size), and (img, distance, matrix_size)."
end

function append_glcm_functions!(functions, names)
    for (fn, name) in zip(functions, names)
        append_method!(
            experimental_bundle_float_glcm_factory,
            fn,
            name;
            description = glcm_registration_description(name),
        )
    end
end

# ADD Mean
glcm_mean_ref_functions, glcm_mean_ref_names = make_functions_with_op(ImageFeatures.glcm_mean_ref)
append_glcm_functions!(glcm_mean_ref_functions, glcm_mean_ref_names)

# ADD Var
glcm_var_ref_functions, glcm_var_ref_names = make_functions_with_op(ImageFeatures.glcm_var_ref)
append_glcm_functions!(glcm_var_ref_functions, glcm_var_ref_names)

# ADD corr
glcm_corr_ref_functions, glcm_corr_ref_names = make_functions_with_op(ImageFeatures.correlation)
append_glcm_functions!(glcm_corr_ref_functions, glcm_corr_ref_names)

# ADD contrast
glcm_contrast_ref_functions, glcm_contrast_ref_names = make_functions_with_op(ImageFeatures.contrast)
append_glcm_functions!(glcm_contrast_ref_functions, glcm_contrast_ref_names)

# ADD IDM
glcm_idm_ref_functions, glcm_idm_ref_names = make_functions_with_op(ImageFeatures.IDM)
append_glcm_functions!(glcm_idm_ref_functions, glcm_idm_ref_names)

# ADD ASM
glcm_asm_ref_functions, glcm_asm_ref_names = make_functions_with_op(ImageFeatures.ASM)
append_glcm_functions!(glcm_asm_ref_functions, glcm_asm_ref_names)

# ADD Entropy
glcm_entropy_ref_functions, glcm_entropy_ref_names = make_functions_with_op(ImageFeatures.glcm_entropy)
append_glcm_functions!(glcm_entropy_ref_functions, glcm_entropy_ref_names)

# ADD MAXPROB
glcm_maxprob_ref_functions, glcm_maxprob_ref_names = make_functions_with_op(ImageFeatures.max_prob)
append_glcm_functions!(glcm_maxprob_ref_functions, glcm_maxprob_ref_names)

# ADD Energy
glcm_energy_ref_functions, glcm_energy_ref_names = make_functions_with_op(ImageFeatures.energy)
append_glcm_functions!(glcm_energy_ref_functions, glcm_energy_ref_names)

# ADD DISSIMILARITY
glcm_dissimilarity_ref_functions, glcm_dissimilarity_ref_names = make_functions_with_op(ImageFeatures.dissimilarity)
append_glcm_functions!(glcm_dissimilarity_ref_functions, glcm_dissimilarity_ref_names)

end
