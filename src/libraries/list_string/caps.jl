# -*- coding: utf-8 -*-

"""
Case operators broadcast over a `Vector{String}`.

# Bundles

- [`bundle_liststring_caps`](@ref)

The exhaustive, always-current list of operators in each bundle is on the
[Bundle Catalogue](@ref) page.
"""
module liststring_caps

using ..UTCGP: FunctionBundle, append_method!
import UTCGP: CONSTRAINED, SMALL_ARRAY, NANO_ARRAY, BIG_ARRAY

# ################### #
# Broacast uppercase #
# ################### #

fallback(args...) = return String[""]

"""
    bundle_liststring_caps

Case operators broadcast over a list of strings: `capitalize_list_string` and
`uppercasefirst_list_string`.
"""
bundle_liststring_caps = FunctionBundle(fallback)


"""
    capitalize_list_string(strings::Vector{String}, args...)::Vector{String}

Broadcasts the `Base.titlecase` function to every element in the vector. 
"""
function capitalize_list_string(strings::Vector{String}, args...)::Vector{String}
    if CONSTRAINED[]
        bound = min(length(strings), SMALL_ARRAY[])
        return titlecase.(strings[begin:bound])
    end
    return titlecase.(strings)
end

"""
    uppercasefirst_list_string(strings::Vector{String}, args...)::Vector{String}

Broadcasts the `Base.uppercasefirst` function to every element in the vector. 
"""
function uppercasefirst_list_string(strings::Vector{String}, args...)::Vector{String}
    if CONSTRAINED[]
        bound = min(length(strings), SMALL_ARRAY[])
        return uppercasefirst.(strings[begin:bound])
    end
    return uppercasefirst.(strings)
end

append_method!(
    bundle_liststring_caps,
    capitalize_list_string;
    description = "Applies title case to each string in the input vector.",
)
append_method!(
    bundle_liststring_caps,
    uppercasefirst_list_string;
    description = "Uppercases the first character of each string in the input vector.",
)
end
