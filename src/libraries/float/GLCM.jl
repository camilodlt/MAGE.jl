""" Gray level co occurence matrix

https://juliaimages.org/ImageFeatures.jl/stable/tutorials/glcm/#GLCM-Properties

Exports :

- **experimental_bundle\\_float\\_glcm** :
    - `glcm_mean`
    - `glcm_variance`
    - `glcm_correlation`
    - `glcm_contrast`
    - `glcm_idm`
    - `glcm_asm`
    - `glcm_entropy`
    - `glcm_maxprob`
    - `glcm_energy`
    - `glcm_dissimilarity`
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
experimental_bundle_float_glcm_factory = FunctionBundle(fallback)

# Utils
function prep_glcm(img::SImageND, dis::Int, matrix_size::Int, angles)
    real_img = reinterpret(img.img)

    # Neighborhood extension
    distance_neighborhood = clamp(dis, 1, 10)

    # GLCM granularity
    min_matrix_size = length(unique(real_img))
    new_matrix_size = clamp(matrix_size, min(5, min_matrix_size), 255)

    glcm_array = glcm_symmetric(real_img, distance_neighborhood, angles, new_matrix_size)
    return (glcm = glcm_array, img = real_img, ditance = dis, matrix_size = matrix_size)
end

# FUNCTIONS ---
const angles_all_directions = [pi, 3 / 4 * pi, pi / 2, pi / 4]

function glcm_dispatcher(property::Function, operation::Function, name) #
    global InputType
    fn = @eval function $name(img::CONCT, dis::Number, matrix_size::Number, args::Vararg{Any}) where {CONCT <: $InputType}
        global angles_all_directions
        res_tuple = prep_glcm(img, Base.ceil(Int, dis), Base.ceil(Int, matrix_size), angles_all_directions)
        return $operation($property.(res_tuple.glcm))
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

# ADD Mean
glcm_mean_ref_functions, glcm_mean_ref_names = make_functions_with_op(ImageFeatures.glcm_mean_ref)
append_method!.(
    Ref(experimental_bundle_float_glcm_factory),
    glcm_mean_ref_functions,
    glcm_mean_ref_names,
)

# ADD Var
glcm_var_ref_functions, glcm_var_ref_names = make_functions_with_op(ImageFeatures.glcm_var_ref)
append_method!.(
    Ref(experimental_bundle_float_glcm_factory),
    glcm_var_ref_functions,
    glcm_var_ref_names,
)

# ADD corr
glcm_corr_ref_functions, glcm_corr_ref_names = make_functions_with_op(ImageFeatures.correlation)
append_method!.(
    Ref(experimental_bundle_float_glcm_factory),
    glcm_corr_ref_functions,
    glcm_corr_ref_names,
)

# ADD contrast
glcm_contrast_ref_functions, glcm_contrast_ref_names = make_functions_with_op(ImageFeatures.contrast)
append_method!.(
    Ref(experimental_bundle_float_glcm_factory),
    glcm_contrast_ref_functions,
    glcm_contrast_ref_names,
)

# ADD IDM
glcm_idm_ref_functions, glcm_idm_ref_names = make_functions_with_op(ImageFeatures.IDM)
append_method!.(
    Ref(experimental_bundle_float_glcm_factory),
    glcm_idm_ref_functions,
    glcm_idm_ref_names,
)

# ADD ASM
glcm_asm_ref_functions, glcm_asm_ref_names = make_functions_with_op(ImageFeatures.ASM)
append_method!.(
    Ref(experimental_bundle_float_glcm_factory),
    glcm_asm_ref_functions,
    glcm_asm_ref_names,
)

# ADD Entropy
glcm_entropy_ref_functions, glcm_entropy_ref_names = make_functions_with_op(ImageFeatures.glcm_entropy)
append_method!.(
    Ref(experimental_bundle_float_glcm_factory),
    glcm_entropy_ref_functions,
    glcm_entropy_ref_names,
)

# ADD MAXPROB
glcm_maxprob_ref_functions, glcm_maxprob_ref_names = make_functions_with_op(ImageFeatures.max_prob)
append_method!.(
    Ref(experimental_bundle_float_glcm_factory),
    glcm_maxprob_ref_functions,
    glcm_maxprob_ref_names,
)

# ADD Energy
glcm_energy_ref_functions, glcm_energy_ref_names = make_functions_with_op(ImageFeatures.energy)
append_method!.(
    Ref(experimental_bundle_float_glcm_factory),
    glcm_energy_ref_functions,
    glcm_energy_ref_names,
)

# ADD DISSIMILARITY
glcm_dissimilarity_ref_functions, glcm_dissimilarity_ref_names = make_functions_with_op(ImageFeatures.dissimilarity)
append_method!.(
    Ref(experimental_bundle_float_glcm_factory),
    glcm_dissimilarity_ref_functions,
    glcm_dissimilarity_ref_names,
)

end
