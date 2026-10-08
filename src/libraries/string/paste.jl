# # -*- coding: utf-8 -*-

"""
Concatenate strings, and collapse a list of strings into one.

# Bundles

- [`bundle_string_paste`](@ref)
- [`bundle_string_concat_list_string`](@ref)

The exhaustive, always-current list of operators in each bundle is on the
[Bundle Catalogue](@ref) page.
"""
module str_paste

using ..UTCGP: FunctionBundle, append_method!

# ########### #
# String Paste #
# ########### #

fallback(args...) = return ""

"""
    bundle_string_paste

String concatenation: `paste` (comma-joined), `paste0` (no separator) and
`paste_with_space`.
"""
bundle_string_paste = FunctionBundle(fallback)
"""
    bundle_string_concat_list_string

Collapse a vector of strings into one: `paste_list_string`,
`paste_space_list_string`, and `paste_list_string_sep` with an explicit
separator.

The input type is a list of strings and the output a string, so this bundle
belongs to a `String` chromosome reading from a `Vector{String}` one.
"""
bundle_string_concat_list_string = FunctionBundle(fallback)

# FUNCTIONS ---
""" Concatenates `s1` and `s2` with `sep` in the middle
"""
function paste(s1::String, s2::String, sep::String, args...)::String
    return s1 * sep * s2
end

""" Concatenates `s1` and `s2`.
"""
function paste0(s1::String, s2::String, args...)::String
    return s1 * s2
end

""" Concatenates `s1` and `s2` with an space in the middle.
"""
function paste_with_space(s1::String, s2::String, args...)::String
    return paste(s1, s2, " ")
end

append_method!(
    bundle_string_paste,
    paste;
    description = "Concatenates two strings with a custom separator between them.",
)
append_method!(
    bundle_string_paste,
    paste0;
    description = "Concatenates two strings directly with no separator.",
)
append_method!(
    bundle_string_paste,
    paste_with_space;
    description = "Concatenates two strings with a single space between them.",
)

# WITH LISTS

""" Joins strings in a list with an space in the middle.
"""
function paste_space_list_string(ls::Vector{String}, args...)::String
    return join(ls, " ")
end

""" Joins strings in a list with a given `delim` in the middle.
"""
function paste_list_string_sep(ls::Vector{String}, delim::String, args...)::String
    return join(ls, delim)
end

""" Joins strings in a list with no delimeter.
"""
function paste_list_string(ls::Vector{String}, args...)::String
    return join(ls)
end

append_method!(
    bundle_string_concat_list_string,
    paste_space_list_string;
    description = "Joins a list of strings using a single space separator.",
)
append_method!(
    bundle_string_concat_list_string,
    paste_list_string_sep;
    description = "Joins a list of strings using the provided delimiter string.",
)
append_method!(
    bundle_string_concat_list_string,
    paste_list_string;
    description = "Joins a list of strings with no delimiter.",
)

end
