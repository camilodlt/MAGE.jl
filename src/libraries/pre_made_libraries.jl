#######################
# PRE MADE LIBRARIES   #
#######################

# VECTOS ----

const extension_nb = [
    bundle_number_regionFromImg,
    bundle_number_haarFromImg,
    bundle_float_orientation,
]

const extension_intensityimg = [
    bundle_image2DIntensity_pool_factory,
    bundle_image2DIntensity_pooler_factory,
    bundle_image2DIntensity_orientation_factory,
]

const extension_binaryimg = [
    bundle_image2DBinary_pool_factory,
    bundle_image2DBinary_pooler_factory,
]

const extension_saliency_intensityimg = [
    bundle_image2DIntensity_saliency_fixation_factory,
]

const extension_foreground_intensityimg = [
    bundle_image2DIntensity_foreground_extraction_factory,
]

const extension_foreground_binaryimg = [
    bundle_image2DBinary_foreground_extraction_factory,
]

const extension_blob_intensityimg = [
    bundle_image2DIntensity_blob_extraction_factory,
]

const extension_blob_binaryimg = [
    bundle_image2DBinary_blob_extraction_factory,
]

const extension_locate_nb = [
    bundle_number_locateFromImg,
    bundle_number_objectLocateFromImg,
    bundle_number_objectDescribeFromImg,
]

const extension_zoom_intensityimg = [
    bundle_image2DIntensity_zoom_factory,
]

const extension_zoom_binaryimg = [
    bundle_image2DBinary_zoom_factory,
]

const extension_zoom_segmentimg = [
    bundle_image2DSegment_zoom_factory,
]

const extension_decision_nb = [bundle_number_decision, bundle_number_motion]
const extension_similarity_nb = [bundle_number_similarityFromImg, bundle_number_templateFromImg]
const extension_descriptors_nb = [
    bundle_number_intensityStatsFromImg,
    bundle_number_shapeFromImg,
    bundle_number_objectStatsFromImg,
    bundle_number_granulometryFromImg,
]
# The basic bundles come first: identity at index 1 and the input-free constant
# at index 2, which node correction and mutation fall back to.
const extension_volume_intensityimg = [bundle_image3DIntensity_volume_basic_factory, bundle_image3DIntensity_volume_factory]
const extension_volume_binaryimg = [bundle_image3DBinary_volume_basic_factory, bundle_image3DBinary_volume_factory]
const extension_volume_to_intensityimg = [bundle_image2DIntensity_fromVolume_factory]
const extension_volume_to_binaryimg = [bundle_image2DBinary_fromVolume_factory]
const extension_volume_nb = [
    bundle_number_intensityStatsFromImg,
    bundle_number_volumeShapeFromImg,
    bundle_number_volumeGranulometryFromImg,
    bundle_number_volumeProfileFromImg,
]
const extension_maskshape_binaryimg = [bundle_image2DBinary_maskshape_factory]
const extension_maskshape_intensityimg = [bundle_image2DIntensity_maskshape_factory]
const extension_transform_intensityimg = [bundle_image2DIntensity_transform_factory]
const extension_transform_binaryimg = [bundle_image2DBinary_transform_factory]
const extension_transform_segmentimg = [bundle_image2DSegment_transform_factory]

const extension_color_statistics_rgb_intensityimg = [
    bundle_image2DIntensity_color_statistics_rgb_factory,
]

const extension_rgbimg = [
    bundle_image3DIntensity_rgb_factory,
]

const extension_spatial_rgbimg = [
    bundle_image3DIntensity_spatial_rgb_factory,
]

const extension_rgb_compositionimg = [
    bundle_image3DIntensity_rgb_composition_factory,
]

const extension_segmentimg = [
    bundle_image2DSegment_pool_factory,
    bundle_image2DSegment_pooler_factory,
]

"""
    get_extension_nb()

Fresh copies of the image-to-number bundles: region statistics, Haar features
and orientation summaries.

These are "extensions" in the sense that they extend a *number* library with
operators that read an image and return a scalar — the bridge that lets a float
chromosome consume the image chromosome.

Bundles are deep-copied on every call, so the returned ones can be re-cast with
update_caster! without touching the originals.
"""
function get_extension_nb()
    return [deepcopy(b) for b in extension_nb]
end

"""
    get_extension_intensityimg()

Fresh copies of the historical extra intensity-image bundles: block pooling,
sliding-window pooling and orientation maps. New vision operators use dedicated
getters so existing training configurations do not acquire them implicitly.
"""
function get_extension_intensityimg()
    return [deepcopy(b) for b in extension_intensityimg]
end

"""
    get_extension_binaryimg()

Fresh copies of the historical extra binary-image bundles: block and
sliding-window pooling. New vision operators use dedicated getters so existing
training configurations do not acquire them implicitly.
"""
function get_extension_binaryimg()
    return [deepcopy(b) for b in extension_binaryimg]
end

"""
    get_extension_saliency_intensityimg()

Fresh copies of the new intensity-output fixation-saliency bundles.
"""
function get_extension_saliency_intensityimg()
    return [deepcopy(b) for b in extension_saliency_intensityimg]
end

"""
    get_extension_foreground_intensityimg()

Fresh copies of the new continuous foreground-extraction bundles.
"""
function get_extension_foreground_intensityimg()
    return [deepcopy(b) for b in extension_foreground_intensityimg]
end

"""
    get_extension_foreground_binaryimg()

Fresh copies of the new discrete foreground-extraction bundles.
"""
function get_extension_foreground_binaryimg()
    return [deepcopy(b) for b in extension_foreground_binaryimg]
end

"""
    get_extension_blob_intensityimg()

Fresh copies of the new intensity-output blob-extraction bundles.
"""
function get_extension_blob_intensityimg()
    return [deepcopy(b) for b in extension_blob_intensityimg]
end

"""
    get_extension_blob_binaryimg()

Fresh copies of the new binary-output blob-extraction bundles.
"""
function get_extension_blob_binaryimg()
    return [deepcopy(b) for b in extension_blob_binaryimg]
end

"""
    get_extension_locate_nb()

Fresh copies of the image-to-number localisation bundles: mask-free locators,
object locators and object descriptors. Their coordinates use the same
normalised convention as `region_*`, so a locator output can drive a region
statistic or a zoom operator.
"""
function get_extension_locate_nb()
    return [deepcopy(b) for b in extension_locate_nb]
end

"""
    get_extension_zoom_intensityimg()

Fresh copies of the intensity-output zoom (crop, resize and recenter) bundles.
"""
function get_extension_zoom_intensityimg()
    return [deepcopy(b) for b in extension_zoom_intensityimg]
end

"""
    get_extension_zoom_binaryimg()

Fresh copies of the binary-output zoom (crop, resize and recenter) bundles.
"""
function get_extension_zoom_binaryimg()
    return [deepcopy(b) for b in extension_zoom_binaryimg]
end

"""
    get_extension_zoom_segmentimg()

Fresh copies of the segment-output zoom (crop, resize and recenter) bundles.
"""
function get_extension_zoom_segmentimg()
    return [deepcopy(b) for b in extension_zoom_segmentimg]
end

"""
    get_extension_decision_nb()

Fresh copies of the scalar decision and motion bundles: shaping, comparing and
choosing between numbers, and geometry on normalised coordinates.
"""
get_extension_decision_nb() = [deepcopy(b) for b in extension_decision_nb]

"""
    get_extension_similarity_nb()

Fresh copies of the image-comparison bundles: pairwise similarity scores,
shift estimation and template matching.
"""
get_extension_similarity_nb() = [deepcopy(b) for b in extension_similarity_nb]

"""
    get_extension_descriptors_nb()

Fresh copies of the classification descriptor bundles: intensity-distribution
statistics (whole image, inside, outside and inside − outside a region), shape
descriptors and Hu invariants, statistics aggregated over objects, and
granulometry.
"""
get_extension_descriptors_nb() = [deepcopy(b) for b in extension_descriptors_nb]

"""
    get_extension_volume_intensityimg()

Fresh copies of the 3D → 3D intensity-volume bundles: the basic bundle first
(identity, then the input-free `vol_ones`, `vol_zeros`, `vol_from_mask`), then
filters, intensity transforms, grey morphology, masking, distance maps,
geometry and 2D extrusion.
"""
get_extension_volume_intensityimg() = [deepcopy(b) for b in extension_volume_intensityimg]

"""
    get_extension_volume_binaryimg()

Fresh copies of the 3D → 3D binary-volume bundles: the basic bundle first
(identity, then the input-free `vol_ones`, `vol_zeros`), then binarisation,
binary morphology, 3D mask clean-up, logic, geometry and 2D extrusion.
"""
get_extension_volume_binaryimg() = [deepcopy(b) for b in extension_volume_binaryimg]

"""
    get_extension_volume_to_intensityimg()

Fresh copies of the 3D → 2D intensity bundle: projections and slices of
volumes, specialised on a 2D intensity image type.
"""
get_extension_volume_to_intensityimg() = [deepcopy(b) for b in extension_volume_to_intensityimg]

"""
    get_extension_volume_to_binaryimg()

Fresh copies of the 3D → 2D binary bundle: silhouettes and slices of masks.
"""
get_extension_volume_to_binaryimg() = [deepcopy(b) for b in extension_volume_to_binaryimg]

"""
    get_extension_volume_nb()

Fresh copies of the 3D → scalar bundles: intensity statistics (2D and 3D,
with ROI forms), 3D shape, 3D granulometry and intensity profiles.
"""
get_extension_volume_nb() = [deepcopy(b) for b in extension_volume_nb]

"""
    get_extension_maskshape_binaryimg()

Fresh copies of the binary mask clean-up bundles (fill holes, hulls,
skeletons, size and border filters).
"""
get_extension_maskshape_binaryimg() = [deepcopy(b) for b in extension_maskshape_binaryimg]

"""
    get_extension_maskshape_intensityimg()

Fresh copies of the mask distance-map bundles (intensity output).
"""
get_extension_maskshape_intensityimg() = [deepcopy(b) for b in extension_maskshape_intensityimg]

"""
    get_extension_transform_intensityimg()

Fresh copies of the intensity geometric-transform bundles.
"""
get_extension_transform_intensityimg() = [deepcopy(b) for b in extension_transform_intensityimg]

"""
    get_extension_transform_binaryimg()

Fresh copies of the binary geometric-transform bundles.
"""
get_extension_transform_binaryimg() = [deepcopy(b) for b in extension_transform_binaryimg]

"""
    get_extension_transform_segmentimg()

Fresh copies of the segment geometric-transform bundles.
"""
get_extension_transform_segmentimg() = [deepcopy(b) for b in extension_transform_segmentimg]

"""
    get_extension_color_statistics_rgb_intensityimg()

Fresh copies of the RGB-to-intensity color-statistics bundles. These factories
consume a same-size, three-channel `SImage3D` and produce the specialized 2D
intensity image type. They are not included by historical image getters.
"""
function get_extension_color_statistics_rgb_intensityimg()
    return [deepcopy(b) for b in extension_color_statistics_rgb_intensityimg]
end

"""
    get_extension_rgbimg()

Fresh copies of the RGB-output bundles. Their factories specialize on a
concrete three-channel RGB `SImage3D` type. The leading functions are
`identity_rgb` and the parameter-free constructor `return_rgb`, followed by
pairwise arithmetic, unary color transforms, bounded color adjustments, and
masking by a same-size 2D binary image.
"""
function get_extension_rgbimg()
    return [deepcopy(b) for b in extension_rgbimg]
end

"""
    get_extension_spatial_rgbimg()

Fresh copies of the opt-in RGB-to-RGB spatial-feature bundle. Its factories
specialize on a concrete three-channel RGB `SImage3D` output type and provide
fixed, training-free edge, scale, sharpening, local-statistics, and oriented
texture transforms. Combine this after `get_extension_rgbimg()` so the RGB
library retains its leading `identity_rgb` and `return_rgb` functions.
"""
function get_extension_spatial_rgbimg()
    return [deepcopy(b) for b in extension_spatial_rgbimg]
end

"""
    get_extension_rgb_compositionimg()

Fresh copies of the opt-in 2D-intensity-to-RGB composition bundle. Its
factories specialize on a concrete three-channel RGB `SImage3D` output type and
provide channel composition and replacement, continuous intensity masking,
spatial alpha blending, and luminance replacement. Combine this after
`get_extension_rgbimg()` so the RGB library retains its leading `identity_rgb`
and `return_rgb` functions.
"""
function get_extension_rgb_compositionimg()
    return [deepcopy(b) for b in extension_rgb_compositionimg]
end

"""
    get_extension_segmentimg()

Fresh copies of the extra segment-image (label map) bundles: block and
sliding-window pooling.
"""
function get_extension_segmentimg()
    return [deepcopy(b) for b in extension_segmentimg]
end

# INTEGER LIBRARY

"""
listinteger_bundles
"""
function get_listinteger_bundles()
    factories = [
        bundle_listgeneric_basic_factory,
        bundle_listgeneric_subset_factory,
        bundle_listgeneric_makelist_factory,
        bundle_listgeneric_concat_factory,
        bundle_listgeneric_set_factory,
        bundle_listgeneric_where_factory,
        bundle_listgeneric_utils_factory,
    ]
    factories = [deepcopy(b) for b in factories]
    for factory_bundle in factories
        for (i, wrapper) in enumerate(factory_bundle)
            fn = wrapper.fn(Int) # specialize
            # create a new wrapper in order to change the type
            factory_bundle.functions[i] =
                FunctionWrapper(
                    fn,
                    wrapper.name,
                    wrapper.caster,
                    wrapper.fallback;
                    description = wrapper.description,
                )
        end
    end

    listinteger_bundles = [
        factories...,
        bundle_listnumber_arithmetic,
        bundle_listnumber_algebraic,
        bundle_listnumber_recursive,
        bundle_listnumber_vectuples,
        bundle_listnumber_basic,
        bundle_listinteger_iscond,
        bundle_listinteger_string,
        bundle_listinteger_primes,
    ]
    listinteger_bundles = [deepcopy(b) for b in listinteger_bundles]
    # Update Casters && Fallbacks
    for b in listinteger_bundles
        update_caster!(b, listinteger_caster)
        update_fallback!(b, () -> Int[])
    end
    return listinteger_bundles
end


# LIST FLOAT LIBRARY

"""
listfloat_bundles
"""
function get_listfloat_bundles()
    factories = [
        bundle_listgeneric_basic_factory,
        bundle_listgeneric_subset_factory,
        bundle_listgeneric_makelist_factory,
        bundle_listgeneric_concat_factory,
        bundle_listgeneric_set_factory,
        bundle_listgeneric_where_factory,
        bundle_listgeneric_utils_factory,
    ]
    factories = [deepcopy(b) for b in factories]
    for factory_bundle in factories
        for (i, wrapper) in enumerate(factory_bundle)
            fn = wrapper.fn(Float64)
            @show wrapper.name
            # create a new wrapper in order to change the type
            factory_bundle.functions[i] =
                FunctionWrapper(
                    fn,
                    wrapper.name,
                    wrapper.caster,
                    wrapper.fallback;
                    description = wrapper.description,
                )
        end
    end
    listfloat_bundles = [
        factories...,
        bundle_listnumber_arithmetic,
        bundle_listnumber_algebraic,
        bundle_listnumber_recursive,
        bundle_listnumber_vectuples,
        bundle_listnumber_basic,
        bundle_listinteger_iscond,
        bundle_listinteger_string,
        bundle_listinteger_primes,
    ]
    listfloat_bundles = [deepcopy(b) for b in listfloat_bundles]
    # Update Casters && Fallbacks
    for b in listfloat_bundles
        update_caster!(b, listfloat_caster)
        update_fallback!(b, () -> Float64[])
    end
    return listfloat_bundles
end


# VEC STRING LIBRARY
"""
liststring_bundles
"""
function get_liststring_bundles()
    factories = [
        bundle_listgeneric_basic_factory,
        bundle_listgeneric_subset_factory,
        bundle_listgeneric_makelist_factory,
        bundle_listgeneric_concat_factory,
        bundle_listgeneric_set_factory,
        bundle_listgeneric_where_factory,
        bundle_listgeneric_utils_factory,
    ]
    factories = [deepcopy(b) for b in factories]
    for factory_bundle in factories
        for (i, wrapper) in enumerate(factory_bundle)
            fn = wrapper.fn(String)
            # create a new wrapper in order to change the type
            factory_bundle.functions[i] =
                FunctionWrapper(
                    fn,
                    wrapper.name,
                    wrapper.caster,
                    wrapper.fallback;
                    description = wrapper.description,
                )
        end
    end

    liststring_bundles = [
        factories...,
        bundle_liststring_split,
        bundle_liststring_caps,
        bundle_liststring_broadcast,
    ]
    liststring_bundles = [deepcopy(b) for b in liststring_bundles]
    # Update Casters && Fallbacks
    for b in liststring_bundles
        update_caster!(b, liststring_caster)
        update_fallback!(b, () -> String[])
    end
    return liststring_bundles
end

# VEV TUPLES LIBRARY

"""

listtuples_bundles Integer
"""
function get_list_int_tuples_bundles()
    factories = [
        bundle_listgeneric_basic_factory,
        # bundle_listgeneric_subset_factory,
        # bundle_listgeneric_makelist_factory,
        # bundle_listgeneric_concat_factory,
        # bundle_listgeneric_set_factory,
        # bundle_listgeneric_where_factory,
        # bundle_listgeneric_utils_factory,
        bundle_listtuple_combinatorics_factory,
        bundle_listtuple_mappings_factory,
    ]
    factories = [deepcopy(b) for b in factories]
    for factory_bundle in factories
        for (i, wrapper) in enumerate(factory_bundle)
            fn = wrapper.fn(Int)
            # create a new wrapper in order to change the type
            factory_bundle.functions[i] =
                FunctionWrapper(
                    fn,
                    wrapper.name,
                    wrapper.caster,
                    wrapper.fallback;
                    description = wrapper.description,
                )
        end
    end

    listtuples_bundles = [factories...]
    listtuples_bundles = [deepcopy(b) for b in listtuples_bundles]
    # Update Casters && Fallbacks
    for b in listtuples_bundles
        update_caster!(b, listtuple_identity)
        update_fallback!(b, () -> Tuple{Int, Int}[])
    end
    return listtuples_bundles
end
"""

listtuples_bundles String
"""
function get_list_string_tuples_bundles()
    factories = [
        bundle_listgeneric_basic_factory,
        # bundle_listgeneric_subset_factory,
        # bundle_listgeneric_makelist_factory,
        # bundle_listgeneric_concat_factory,
        # bundle_listgeneric_set_factory,
        # bundle_listgeneric_where_factory,
        # bundle_listgeneric_utils_factory,
        bundle_listtuple_combinatorics_factory,
        bundle_listtuple_mappings_factory,
    ]
    factories = [deepcopy(b) for b in factories]
    for factory_bundle in factories
        for (i, wrapper) in enumerate(factory_bundle)
            fn = wrapper.fn(String)
            # create a new wrapper in order to change the type
            factory_bundle.functions[i] =
                FunctionWrapper(
                    fn,
                    wrapper.name,
                    wrapper.caster,
                    wrapper.fallback;
                    description = wrapper.description,
                )
        end
    end

    listtuples_bundles = [factories...]
    listtuples_bundles = [deepcopy(b) for b in listtuples_bundles]
    # Update Casters && Fallbacks
    for b in listtuples_bundles
        update_caster!(b, listtuple_identity)
        update_fallback!(b, () -> Tuple{String, String}[])
    end
    return listtuples_bundles
end

# ELEMENTS ----

# INT LIBRARY
"""
integer_bundles
"""
function get_integer_bundles()
    factories = [bundle_element_conditional_factory]
    factories = [deepcopy(b) for b in factories]
    for factory_bundle in factories
        for (i, wrapper) in enumerate(factory_bundle)
            fn = wrapper.fn(Int)
            # create a new wrapper in order to change the type
            factory_bundle.functions[i] =
                FunctionWrapper(
                    fn,
                    wrapper.name,
                    wrapper.caster,
                    wrapper.fallback;
                    description = wrapper.description,
                )
        end
    end
    integer_bundles = [
        bundle_integer_basic,
        bundle_integer_find,
        bundle_integer_modulo,
        bundle_integer_cond,
        bundle_number_arithmetic,
        bundle_number_reduce,
        bundle_element_pick,
        # bundle_element_conditional,
        bundle_number_transcendental,
        factories...,
    ]
    integer_bundles = [deepcopy(b) for b in integer_bundles]
    # Update Casters && Fallbacks
    for b in integer_bundles
        update_caster!(b, integer_caster)
        update_fallback!(b, () -> 0)
    end
    return integer_bundles
end

# FLOAT LIBRARY
"""
floatinteger_bundles
"""
function get_float_bundles()
    factories = [bundle_element_conditional_factory]
    factories = [deepcopy(b) for b in factories]
    for factory_bundle in factories
        for (i, wrapper) in enumerate(factory_bundle)
            fn = wrapper.fn(Float64)
            # create a new wrapper in order to change the type
            factory_bundle.functions[i] =
                FunctionWrapper(
                    fn,
                    wrapper.name,
                    wrapper.caster,
                    wrapper.fallback;
                    description = wrapper.description,
                )
        end
    end

    float_bundles = [
        bundle_float_basic,
        bundle_integer_find,
        bundle_integer_modulo,
        bundle_integer_cond,
        bundle_number_arithmetic,
        bundle_number_reduce,
        # bundle_element_pick,
        bundle_number_transcendental,
        bundle_number_reduceFromImg,
        factories...,
    ]
    float_bundles = [deepcopy(b) for b in float_bundles]
    # Update Casters && Fallbacks
    for b in float_bundles
        update_caster!(b, float_caster)
        update_fallback!(b, () -> 0.0)
    end
    return float_bundles
end

"""
SR float lib
"""
function get_sr_float_bundles()
    float_bundles = [
        bundle_float_basic,
        bundle_integer_modulo,
        bundle_integer_cond,
        bundle_number_arithmetic,
        bundle_number_transcendental,
    ]
    float_bundles = [deepcopy(b) for b in float_bundles]
    # Update Casters && Fallbacks
    for b in float_bundles
        update_caster!(b, float_caster)
        update_fallback!(b, () -> 0.0)
    end
    return float_bundles
end

"""
Functions picked for scalar symbolic regression, as (source bundle, function name).

Each one is defined once in its own bundle; `get_scalar_sr_bundles` copies exactly these
wrappers into a single new bundle, so this list is the whole SR function set. Constants
are not functions here: pass them as program inputs.
"""
const SCALAR_SR_FUNCTIONS = [
    # First by MAGE convention: output nodes use the library's first function (make_genome.jl).
    (:bundle_float_basic, :identity_float),
    (:bundle_number_arithmetic, :number_sum),
    (:bundle_number_arithmetic, :number_minus),
    (:bundle_number_arithmetic, :number_mult),
    (:bundle_number_arithmetic, :safe_div),
    (:bundle_number_arithmetic_sr, :number_square),
    (:bundle_number_arithmetic_sr, :number_cube),
    (:bundle_number_arithmetic_sr, :number_negate),
    (:bundle_number_arithmetic_sr, :number_inverse),
    (:bundle_number_transcendental_sr, :sqrt_),
    (:bundle_number_transcendental, :exp_),
    (:bundle_number_transcendental, :log_),
    (:bundle_number_transcendental_sr, :sin_),
    (:bundle_number_transcendental_sr, :cos_),
    (:bundle_float_basic, :tanh),
    (:bundle_number_decision, :number_abs),
    (:bundle_number_decision, :number_min),
    (:bundle_number_decision, :number_max),
]

"""
    get_scalar_sr_bundles(selection = SCALAR_SR_FUNCTIONS)

One bundle holding exactly the `selection` functions, copied from the bundles that define
them, with the float caster and a `0.0` fallback. Unlike [`get_sr_float_bundles`](@ref),
which adds whole bundles, nothing outside the selection is included.
"""
function get_scalar_sr_bundles(selection = SCALAR_SR_FUNCTIONS)
    sr_bundle = FunctionBundle(float_caster, () -> 0.0)
    for (bundle_name, fn_name) in selection
        source = getfield(@__MODULE__, bundle_name)
        idx = findfirst(w -> w.name == fn_name, source.functions)
        isnothing(idx) && error("$(fn_name) is not in $(bundle_name)")
        push!(sr_bundle.functions, deepcopy(source.functions[idx]))
    end
    @assert _unique_names_in_bundle(sr_bundle) "Duplicate function names in the SR selection"
    update_caster!(sr_bundle, float_caster)
    update_fallback!(sr_bundle, () -> 0.0)
    return [sr_bundle]
end

# STRING LIBRARY

"""
stringinteger_bundles
"""
function get_string_bundles()
    factories = [bundle_element_conditional_factory]
    factories = [deepcopy(b) for b in factories]
    for factory_bundle in factories
        for (i, wrapper) in enumerate(factory_bundle)
            fn = wrapper.fn(String)
            # create a new wrapper in order to change the type
            factory_bundle.functions[i] =
                FunctionWrapper(
                    fn,
                    wrapper.name,
                    wrapper.caster,
                    wrapper.fallback;
                    description = wrapper.description,
                )
        end
    end

    string_bundles = [
        bundle_string_basic,
        bundle_string_grep,
        bundle_string_paste,
        bundle_string_concat_list_string,
        bundle_string_conditional,
        bundle_string_caps,
        bundle_string_parse,
        bundle_element_pick, # TODO
        factories...,
    ]

    string_bundles = [deepcopy(b) for b in string_bundles]
    # Update Casters && Fallbacks
    for b in string_bundles
        update_caster!(b, string_caster)
        update_fallback!(b, () -> "")
    end
    return string_bundles
end

# IMAGES ---
function get_image2Dintensity_factory_bundles()
    bundle_images = [
        bundle_image2DIntensity_basic_factory,
        bundle_image2DIntensity_morph_factory,
        bundle_image2DIntensity_arithmetic_factory,
        bundle_image2DIntensity_barithmetic_factory,
        bundle_image2DIntensity_filtering_factory,
        bundle_image2DIntensity_transcendental_factory,
        bundle_element_conditional_factory,
    ]
    return deepcopy(bundle_images)
end

function get_image2Dbinary_factory_bundles()
    bundle_images = [
        bundle_image2DBinary_basic_factory,
        bundle_image2DBinary_arithmetic_factory,
        bundle_image2DBinary_binarize_factory,
        bundle_image2DBinary_filtering_factory,
        bundle_image2DBinary_morph_factory,
        bundle_element_conditional_factory,
    ]
    return deepcopy(bundle_images)
end

function get_image2Dsegment_factory_bundles()
    bundle_images = [
        bundle_image2DSegment_basic_factory,
        bundle_image2DSegment_segmentation_factory,
    ]
    return deepcopy(bundle_images)
end


# ATARI

function get_float_bundles_atari()
    factories = [bundle_element_conditional_factory]
    factories = [deepcopy(b) for b in factories]
    for factory_bundle in factories
        for (i, wrapper) in enumerate(factory_bundle)
            fn = wrapper.fn(Float64)
            # create a new wrapper in order to change the type
            factory_bundle.functions[i] =
                FunctionWrapper(
                    fn,
                    wrapper.name,
                    wrapper.caster,
                    wrapper.fallback;
                    description = wrapper.description,
                )
        end
    end

    float_bundles = [
        bundle_float_basic,
        bundle_integer_find,
        bundle_integer_modulo,
        bundle_integer_cond,
        bundle_number_arithmetic,
        # bundle_number_reduce,
        # bundle_element_pick,
        bundle_number_transcendental,
        bundle_number_reduceFromImg,
        bundle_number_coordinatesFromImg,     # to uncomment if not processing relative elements
        bundle_number_relativeCoordinatesFromImg,
        factories...,
    ]
    float_bundles = [deepcopy(b) for b in float_bundles]
    # Update Casters && Fallbacks
    for b in float_bundles
        println("Updating casters for bundle")
        update_caster!(b, float_caster)
        update_fallback!(b, () -> 0.0)
    end
    return float_bundles
end

function get_image2D_factory_bundles_atari()
    bundle_images = [
        bundle_image2D_basic_factory,
        bundle_image2D_morph_factory,
        bundle_image2D_binarize_factory,
        bundle_image2D_segmentation_factory,
        bundle_image2D_arithmetic_factory,
        bundle_image2D_barithmetic_factory,
        bundle_image2D_transcendental_factory,
        bundle_image2D_filtering_factory,
        bundle_element_conditional_factory,
        # experimental_bundle_float_glcm_factory, texture stuff
        experimental_bundle_image2D_mask_factory,
        experimental_bundle_image2D_maskregion_factory,
        experimental_bundle_image2D_maskregion_relative_factory,
    ]

    # Update Casters && Fallbacks
    # for b in bundle_images
    # update_caster!(b, ())
    # update_fallback!(b, () -> SImageND)
    # end
    return deepcopy(bundle_images)
end
