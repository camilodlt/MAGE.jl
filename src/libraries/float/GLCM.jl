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
using ..UTCGP: FunctionBundle, append_method!, ManualDispatcher
import ..UTCGP:
    CONSTRAINED,
    MIN_INT,
    MAX_INT,
    MIN_FLOAT,
    MAX_FLOAT,
    _positive_params,
    _ceil_positive_params
using ..UTCGP:
    SizedImage2D, SImageND, _get_image_tuple_size, _get_image_type, _validate_factory_type
using ImageFeatures

# ################### #
# IDENTITY            #
# ################### #
InputType = SizedImage2D{S1,S2,T,IT} where {S1,S2,T<:Normed,IT} # 2D img
fallback(args...) = return -1.0
experimental_bundle_float_glcm_factory = FunctionBundle(fallback)

# FUNCTIONS ---
const angles_all_directions = [pi, 3 / 4 * pi, pi / 2, pi / 4]

function glcm_dispatcher(property::Function)
    global InputType
    @show property
    # quote
    function glcm_factory(i::Type{I}) where {I<:InputType}
        TT = Base.unwrap_unionall(I).parameters[2] # Image type
        _validate_factory_type(TT)
        StorageType = TT.types[1] # UInt8, UInt16 ...
        fn_name = Symbol(property)

        m1 = @eval (
            (img::CONCT, d::Number, values::Number, args::Vararg{Any}) where {CONCT<:$I}
        ) -> begin
            global angles_all_directions
            real_img = reinterpret.($StorageType, img.img)
            n = ceil(Int, values)
            n = clamp(n, 2, 255) # to account for the 255 colors even if gray values should be less 
            dis = ceil(Int, d)
            dis = clamp(n, 1, 3) # allow farther pixels
            glcm_array = glcm_symmetric(real_img, dis, angles_all_directions, n)
            return mean($property.(glcm_array))
        end

        # dist of 1
        m2 = @eval ((img::CONCT, values::Number, args::Vararg{Any}) where {CONCT<:$I}) ->
            begin
                global angles_all_directions
                real_img = reinterpret.($StorageType, img.img)
                n = ceil(Int, values)
                n = clamp(n, 2, 255) # to account for the 255 colors even if gray values should be less 
                glcm_array = glcm_symmetric(real_img, 1, angles_all_directions, n)
                return mean($property.(glcm_array))
            end

        # defaults to 16 gray values & dist of 1
        m3 = @eval ((img::CONCT, args::Vararg{Any}) where {CONCT<:$I}) -> begin
            global angles_all_directions
            real_img = reinterpret.($StorageType, img.img)
            glcm_array = glcm_symmetric(real_img, 1, angles_all_directions, 16)
            # @show size(glcm_array)
            # @show $property.(glcm_array)
            return mean($property.(glcm_array))
        end
        ManualDispatcher((m1, m2, m3), fn_name)
    end
    # end |> eval
end

glcm_mean_ref_factory = glcm_dispatcher(ImageFeatures.glcm_mean_ref)
glcm_variance_ref_factory = glcm_dispatcher(ImageFeatures.glcm_var_ref)
glcm_correlation_factory = glcm_dispatcher(ImageFeatures.correlation)
glcm_contrast_factory = glcm_dispatcher(ImageFeatures.contrast)
glcm_idm_factory = glcm_dispatcher(ImageFeatures.IDM)
glcm_asm_factory = glcm_dispatcher(ImageFeatures.ASM)
glcm_entropy_factory = glcm_dispatcher(ImageFeatures.glcm_entropy)
glcm_maxprob_factory = glcm_dispatcher(ImageFeatures.max_prob)
glcm_energy_factory = glcm_dispatcher(ImageFeatures.energy)
glcm_dissimilarity_factory = glcm_dispatcher(ImageFeatures.dissimilarity)


append_method!(
    experimental_bundle_float_glcm_factory,
    glcm_mean_ref_factory,
    :glcm_mean_ref_factory,
)
append_method!(
    experimental_bundle_float_glcm_factory,
    glcm_variance_ref_factory,
    :glcm_variance_ref_factory,
)
append_method!(
    experimental_bundle_float_glcm_factory,
    glcm_correlation_factory,
    :glcm_correlation_factory,
)
append_method!(
    experimental_bundle_float_glcm_factory,
    glcm_contrast_factory,
    :glcm_contrast_factory,
)
append_method!(experimental_bundle_float_glcm_factory, glcm_idm_factory, :glcm_idm_factory)
append_method!(experimental_bundle_float_glcm_factory, glcm_asm_factory, :glcm_asm_factory)
append_method!(
    experimental_bundle_float_glcm_factory,
    glcm_entropy_factory,
    :glcm_entropy_factory,
)
append_method!(
    experimental_bundle_float_glcm_factory,
    glcm_maxprob_factory,
    :glcm_maxprob_factory,
)
append_method!(
    experimental_bundle_float_glcm_factory,
    glcm_energy_factory,
    :glcm_energy_factory,
)
append_method!(
    experimental_bundle_float_glcm_factory,
    glcm_dissimilarity_factory,
    :glcm_dissimilarity_factory,
)

end

