using MAGE
using Markdown

# Where each bundle's docstring is rendered.
groups = [
    ("Elements and booleans", [
        ("bool", ["bundle_bool_basic"]),
        ("element", ["bundle_element_pick", "bundle_element_conditional",
                     "bundle_element_conditional_factory"]),
    ]),
    ("Numbers", [
        ("number", ["bundle_number_arithmetic", "bundle_number_transcendental",
                    "bundle_number_reduce"]),
        ("float", ["bundle_float_basic"]),
        ("integer", ["bundle_integer_basic", "bundle_integer_cond",
                     "bundle_integer_find", "bundle_integer_modulo"]),
    ]),
    ("Strings", [
        ("string", ["bundle_string_basic", "bundle_string_caps",
                    "bundle_string_conditional", "bundle_string_grep",
                    "bundle_string_parse", "bundle_string_paste",
                    "bundle_string_concat_list_string"]),
    ]),
    ("Generic lists", [
        ("list_generic", ["bundle_listgeneric_basic", "bundle_listgeneric_basic_factory",
            "bundle_listgeneric_subset", "bundle_listgeneric_subset_factory",
            "bundle_listgeneric_makelist", "bundle_listgeneric_makelist_factory",
            "bundle_listgeneric_concat", "bundle_listgeneric_concat_factory",
            "bundle_listgeneric_set", "bundle_listgeneric_set_factory",
            "bundle_listgeneric_utils", "bundle_listgeneric_utils_factory",
            "bundle_listgeneric_where", "bundle_listgeneric_where_factory"]),
    ]),
    ("Numeric lists", [
        ("list_number", ["bundle_listnumber_basic", "bundle_listnumber_arithmetic",
            "bundle_listnumber_algebraic", "bundle_listnumber_recursive",
            "bundle_listnumber_vectuples"]),
    ]),
    ("Integer lists", [
        ("list_integer", ["bundle_listinteger_iscond", "bundle_listinteger_primes",
            "bundle_listinteger_string"]),
    ]),
    ("String lists", [
        ("list_string", ["bundle_liststring_split", "bundle_liststring_caps",
            "bundle_liststring_broadcast"]),
    ]),
    ("Tuple lists", [
        ("list_tuple", ["bundle_listtuple_combinatorics",
            "bundle_listtuple_combinatorics_factory", "bundle_listtuple_mappings",
            "bundle_listtuple_mappings_factory"]),
    ]),
    ("Images: basics and arithmetic", [
        ("image", ["bundle_image2DIntensity_basic_factory",
            "bundle_image2DBinary_basic_factory", "bundle_image2DSegment_basic_factory",
            "bundle_image2DIntensity_arithmetic_factory",
            "bundle_image2DBinary_arithmetic_factory",
            "bundle_image2DIntensity_barithmetic_factory",
            "bundle_image2DIntensity_transcendental_factory"]),
    ]),
    ("Images: filtering and morphology", [
        ("image", ["bundle_image2DIntensity_filtering_factory",
            "bundle_image2DBinary_filtering_factory",
            "bundle_image2DIntensity_morph_factory", "bundle_image2DBinary_morph_factory",
            "bundle_image2DIntensity_orientation_factory"]),
    ]),
    ("Images: saliency, foreground and blobs", [
        ("image", ["bundle_image2DIntensity_saliency_fixation_factory"]),
        ("foreground_extraction", ["bundle_image2DBinary_foreground_extraction_factory"]),
        ("foreground_extraction_continuous", ["bundle_image2DIntensity_foreground_extraction_factory"]),
        ("blob_extraction", ["bundle_image2DBinary_blob_extraction_factory",
            "bundle_image2DIntensity_blob_extraction_factory"]),
    ]),
    ("Images: object attention", [
        ("object_attention", ["bundle_number_locateFromImg",
            "bundle_number_objectLocateFromImg", "bundle_number_objectDescribeFromImg",
            "bundle_image2DIntensity_zoom_factory", "bundle_image2DBinary_zoom_factory",
            "bundle_image2DSegment_zoom_factory"]),
    ]),
    ("Images: mask shape and geometric transforms", [
        ("mask_shape", ["bundle_image2DBinary_maskshape_factory",
            "bundle_image2DIntensity_maskshape_factory"]),
        ("transform", ["bundle_image2DIntensity_transform_factory",
            "bundle_image2DBinary_transform_factory", "bundle_image2DSegment_transform_factory"]),
    ]),
    ("Image comparison and scalar decisions", [
        ("similarity", ["bundle_number_similarityFromImg", "bundle_number_templateFromImg"]),
        ("../image_scalar_contract", ["bundle_number_similarityNDFromImg", "bundle_number_similarity2DFromImg"]),
        ("decision", ["bundle_number_decision", "bundle_number_motion"]),
    ]),
    ("Classification descriptors", [
        ("descriptors", ["bundle_number_intensityStatsFromImg", "bundle_number_shapeFromImg",
            "bundle_number_objectStatsFromImg", "bundle_number_granulometryFromImg"]),
    ]),
    ("3D volumes", [
        ("volumes", ["bundle_image3DIntensity_volume_basic_factory", "bundle_image3DBinary_volume_basic_factory",
            "bundle_image3DIntensity_volume_factory", "bundle_image3DBinary_volume_factory"]),
        ("volumes_projections", ["bundle_image2DIntensity_fromVolume_factory", "bundle_image2DBinary_fromVolume_factory",
            "bundle_number_volumeShapeFromImg", "bundle_number_volumeGranulometryFromImg",
            "bundle_number_volumeProfileFromImg"]),
    ]),
    ("Images: RGB", [
        ("color_statistics_rgb", [
            "bundle_image2DIntensity_color_statistics_rgb_factory",
            "bundle_image3DIntensity_rgb_factory",
        ]),
        ("spatial_rgb", [
            "bundle_image3DIntensity_spatial_rgb_factory",
        ]),
        ("composition_rgb", [
            "bundle_image3DIntensity_rgb_composition_factory",
        ]),
    ]),
    ("Images: thresholding and segmentation", [
        ("image", ["bundle_image2DBinary_binarize_factory",
            "bundle_image2DSegment_segmentation_factory"]),
    ]),
    ("Images: pooling", [
        ("image", ["bundle_image2DIntensity_pool_factory", "bundle_image2DBinary_pool_factory",
            "bundle_image2DSegment_pool_factory", "bundle_image2DIntensity_pooler_factory",
            "bundle_image2DBinary_pooler_factory", "bundle_image2DSegment_pooler_factory"]),
    ]),
    ("Images to scalars", [
        ("number", ["bundle_number_reduceFromImg", "bundle_number_coordinatesFromImg",
            "bundle_number_relativeCoordinatesFromImg", "bundle_number_regionFromImg",
            "bundle_number_haarFromImg"]),
        ("float", ["bundle_float_orientation", "bundle_float_imagegraph",
            "experimental_bundle_float_glcm_factory"]),
    ]),
]

submodules = Module[]
for n in names(MAGE, all = true)
    v = try getfield(MAGE, n) catch; continue end
    v isa Module && v !== MAGE && push!(submodules, v)
end

"Documenter anchors a docstring under the binding's defining module."
function anchor_for(name::String)
    sym = Symbol(name)
    value = getfield(MAGE, sym)
    for m in submodules
        if isdefined(m, sym) && getfield(m, sym) === value
            return "MAGE.$(nameof(m)).$(name)"
        end
    end
    return "MAGE.$(name)"
end


"All exported bundle bindings, including experimental bundles."
function exported_bundles()
    return sort([String(n) for n in names(MAGE) if getfield(MAGE, n) isa MAGE.FunctionBundle])
end

# Bundles are organised by their intended chromosome output. Numeric and
# generic operators can return different concrete types depending on inputs;
# a Library's caster determines the final chromosome type.
const BUNDLE_OUTPUT_GROUPS = [
    "Bool" => r"^bundle_bool_",
    "Element T" => r"^bundle_element_",
    "Number (generic arithmetic and mixed image reductions)" => r"^bundle_number_(arithmetic(_sr)?|transcendental(_sr)?|reduce|reduceFromImg)$",
    "Float64 (scalar descriptors, coordinates and decisions)" =>
        r"^(?:(experimental_)?bundle_float_|bundle_number_(coordinatesFromImg|relativeCoordinatesFromImg|regionFromImg|haarFromImg|locateFromImg|objectLocateFromImg|objectDescribeFromImg|decision|motion|similarityFromImg|similarityNDFromImg|similarity2DFromImg|templateFromImg|intensityStatsFromImg|shapeFromImg|objectStatsFromImg|granulometryFromImg|volumeShapeFromImg|volumeGranulometryFromImg|volumeProfileFromImg)$)",
    "Int" => r"^bundle_integer_",
    "String" => r"^bundle_string_",
    "Vector{T}" => r"^bundle_listgeneric_",
    "Vector{<:Number}" => r"^bundle_listnumber_",
    "Vector{Int}" => r"^bundle_listinteger_",
    "Vector{String}" => r"^bundle_liststring_",
    "Vector{Tuple{T,T}}" => r"^bundle_listtuple_",
    "2D intensity image" => r"^bundle_image2DIntensity_",
    "2D binary image" => r"^bundle_image2DBinary_",
    "2D segment image" => r"^bundle_image2DSegment_",
    "3D intensity image / RGB (H × W × 3)" => r"^bundle_image3DIntensity_",
    "3D binary volume" => r"^bundle_image3DBinary_",
]

"Generated home-page list; fail the build if a new bundle needs an output group."
function bundle_output_index()
    all_names = exported_bundles()
    listed = String[]
    io = IOBuffer()
    prefix = get(ENV, "CI", "false") == "true" ? "libraries/catalogue/" : "libraries/catalogue.html"
    for (output, pattern) in BUNDLE_OUTPUT_GROUPS
        matches = filter(n -> occursin(pattern, n), all_names)
        isempty(matches) && continue
        println(io, "### ", output, "\n")
        for name in matches
            # Catalogue headings are plain bundle names inside links. Explicit
            # anchors there make this independent of Documenter slug rules.
            println(io, "- [`", name, "`](", prefix, "#", name, ") (", length(getfield(MAGE, Symbol(name))), " operators)")
        end
        println(io)
        append!(listed, matches)
    end
    missing = setdiff(all_names, listed)
    isempty(missing) || error("Bundle output classification missing for: $(join(missing, ", "))")
    length(unique(listed)) == length(listed) || error("A bundle belongs to multiple output groups")
    return Markdown.parse(String(take!(io)))
end

"Render catalogue Markdown with stable HTML anchors for the home-page links."
function bundle_catalogue_html(text::AbstractString)
    html = sprint(show, MIME"text/html"(), Markdown.parse(text))
    for name in exported_bundles()
        html = replace(html, "<p><code>MAGEBUNDLEANCHOR$name</code></p>" => "<a id=\"$name\"></a>")
    end
    return html
end
