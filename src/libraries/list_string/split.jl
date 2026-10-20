# -*- coding: utf-8 -*-


"""
Split a string into a list of strings.

# Bundles

- [`bundle_liststring_split`](@ref)

The exhaustive, always-current list of operators in each bundle is on the
[Bundle Catalogue](@ref) page.
"""
module liststring_split

using ..UTCGP: FunctionBundle, append_method!
import UTCGP: CONSTRAINED, SMALL_ARRAY, NANO_ARRAY, BIG_ARRAY

# ########### #
# String Grep #
# ########### #
fallback(args...) = return String[]

"""
    bundle_liststring_split

`split_string_to_vector`: split a string into a list of strings.
"""
bundle_liststring_split = FunctionBundle(fallback)

# FUNCTIONS ---
""" 
"""
function split_string_to_vector(s::String, by::String, args...)
    if CONSTRAINED[]
        bound = min(length(s), SMALL_ARRAY[])
        return String.(split(s[begin:bound], by))
    end
    return String.(split(s, by))
end


append_method!(
    bundle_liststring_split,
    split_string_to_vector;
    description = "Splits a string using the provided delimiter and returns a vector of substrings.",
)

end
