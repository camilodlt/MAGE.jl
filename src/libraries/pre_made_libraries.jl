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
