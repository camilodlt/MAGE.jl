```@meta
CurrentModule = UTCGP
```

# Bundle Catalogue

Every [`FunctionBundle`](@ref) MAGE exports, with the operators it holds.

This page is generated from the package at documentation build time, so it can
never drift from the code. The prose description of what each group is *for*
lives in the bundle's own docstring — follow the bundle name to reach it — and
the pages under **Function Libraries** carry the worked examples.

!!! note "Reading the table"
    A bundle whose name ends in `_factory` holds functions of a type: calling an
    entry with a concrete type returns the method specialised for it. See
    [Libraries](@ref).

```@eval
using UTCGP
using Markdown

# `@eval` output is inserted after Documenter's cross-reference pass, so `@ref`
# does not work here: build the links by hand instead.
const PRETTY = get(ENV, "CI", "false") == "true"
page_url(page) = PRETTY ? "../$(page)/" : "$(page).html"

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
for n in names(UTCGP, all = true)
    v = try getfield(UTCGP, n) catch; continue end
    v isa Module && v !== UTCGP && push!(submodules, v)
end

"Documenter anchors a docstring under the binding's defining module."
function anchor_for(name::String)
    sym = Symbol(name)
    value = getfield(UTCGP, sym)
    for m in submodules
        if isdefined(m, sym) && getfield(m, sym) === value
            return "UTCGP.$(nameof(m)).$(name)"
        end
    end
    return "UTCGP.$(name)"
end

esc(s) = replace(String(s), "|" => "\\|")

io = IOBuffer()
listed = String[]
for (title, pages) in groups
    println(io, "## ", title, "\n")
    for (page, names_) in pages
        for name in names_
            sym = Symbol(name)
            isdefined(UTCGP, sym) || continue
            bundle = getfield(UTCGP, sym)
            bundle isa UTCGP.FunctionBundle || continue
            push!(listed, name)
            url = string(page_url(page), "#", anchor_for(name))
            n = length(bundle)
            println(io, "### [`", name, "`](", url, ")\n")
            println(io, n, n == 1 ? " operator." : " operators.", "\n")
            println(io, "| Fn | Description |")
            println(io, "|:---|:------------|")
            for w in bundle
                println(io, "| `", esc(w.name), "` | ", esc(w.description), " |")
            end
            println(io)
        end
    end
end

# Anything exported but not placed above: never silently drop it.
all_bundles = String[]
for n in names(UTCGP)
    v = try getfield(UTCGP, n) catch; continue end
    v isa UTCGP.FunctionBundle && push!(all_bundles, String(n))
end
missing_ = sort(setdiff(all_bundles, listed))
if !isempty(missing_)
    println(io, "## Ungrouped\n")
    for name in missing_
        bundle = getfield(UTCGP, Symbol(name))
        println(io, "### `", name, "`\n")
        println(io, "| Fn | Description |")
        println(io, "|:---|:------------|")
        for w in bundle
            println(io, "| `", esc(w.name), "` | ", esc(w.description), " |")
        end
        println(io)
    end
end

Markdown.parse(String(take!(io)))
```
