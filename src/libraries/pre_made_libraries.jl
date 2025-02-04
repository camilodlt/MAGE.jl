#######################
# PRE MADE LIBRARIES   #
#######################

# VECTOS ----

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
                FunctionWrapper(fn, wrapper.name, wrapper.caster, wrapper.fallback)
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
                FunctionWrapper(fn, wrapper.name, wrapper.caster, wrapper.fallback)
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
                FunctionWrapper(fn, wrapper.name, wrapper.caster, wrapper.fallback)
        end
    end

    liststring_bundles = [
        factories...,
        bundle_listgeneric_basic,
        bundle_listgeneric_subset,
        bundle_listgeneric_makelist,
        bundle_listgeneric_concat,
        bundle_listgeneric_set,
        bundle_listgeneric_where,
        bundle_listgeneric_utils,
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
                FunctionWrapper(fn, wrapper.name, wrapper.caster, wrapper.fallback)
        end
    end

    listtuples_bundles = [factories...]
    listtuples_bundles = [deepcopy(b) for b in listtuples_bundles]
    # Update Casters && Fallbacks
    for b in listtuples_bundles
        update_caster!(b, listtuple_identity)
        update_fallback!(b, () -> Tuple{Int,Int}[])
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
                FunctionWrapper(fn, wrapper.name, wrapper.caster, wrapper.fallback)
        end
    end

    listtuples_bundles = [factories...]
    listtuples_bundles = [deepcopy(b) for b in listtuples_bundles]
    # Update Casters && Fallbacks
    for b in listtuples_bundles
        update_caster!(b, listtuple_identity)
        update_fallback!(b, () -> Tuple{String,String}[])
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
                FunctionWrapper(fn, wrapper.name, wrapper.caster, wrapper.fallback)
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
                FunctionWrapper(fn, wrapper.name, wrapper.caster, wrapper.fallback)
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

    string_bundles = [
        bundle_string_basic,
        bundle_string_grep,
        bundle_string_paste,
        bundle_string_concat_list_string,
        bundle_string_conditional,
        bundle_string_caps,
        bundle_string_parse,
        bundle_element_pick,
        bundle_element_conditional,
    ]

    string_bundles = [deepcopy(b) for b in string_bundles]
    # Update Casters && Fallbacks
    for b in string_bundles
        update_caster!(b, string_caster)
        update_fallback!(b, () -> "")
    end
    return string_bundles
end

"""

Image Bundles
"""

function get_image2D_factory_bundles()
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
    ]

    # Update Casters && Fallbacks
    # for b in bundle_images
    # update_caster!(b, ())
    # update_fallback!(b, () -> SImageND)
    # end
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
                FunctionWrapper(fn, wrapper.name, wrapper.caster, wrapper.fallback)
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
    float_bundles
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
