# # -*- coding: utf-8 -*-

"""
Pattern matching and replacement.

# Bundles

- [`bundle_string_grep`](@ref)

The exhaustive, always-current list of operators in each bundle is on the
[Bundle Catalogue](@ref) page.
"""
module str_grep

using ..UTCGP: FunctionBundle, append_method!

# ########### #
# String Grep #
# ########### #
fallback(args...) = return ""

"""
    bundle_string_grep

Pattern rewriting: `replace_pattern` (all matches), `replace_first_pattern`, and
`remove_pattern`.
"""
bundle_string_grep = FunctionBundle(fallback)

# # FUNCTIONS ---
""" Replaces a pattern `from` by another string `to` in the strign `s`.
"""
function replace_pattern(s::String, from::String, to::String, args...)::String
    return replace(s, from => to)
end

""" Replaces a pattern `from` by another string `to` in the strign `s` only 1 time.
"""
function replace_first_pattern(s::String, from::String, to::String, args...)::String
    return replace(s, from => to, count = 1)
end # CANDIDATE FOR PARAMETRIZATION 


""" Removes the `pattern`  from the strign `s`. 
"""
function remove_pattern(s::String, pattern::String, args...)::String
    return replace(s, pattern => "")
end

append_method!(
    bundle_string_grep,
    replace_pattern;
    description = "Replaces all occurrences of a pattern string with a replacement string.",
)
append_method!(
    bundle_string_grep,
    replace_first_pattern;
    description = "Replaces only the first occurrence of a pattern string.",
)
append_method!(
    bundle_string_grep,
    remove_pattern;
    description = "Removes all occurrences of a pattern string from the input text.",
)

end
