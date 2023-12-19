# # -*- coding: utf-8 -*-

""" Paste Operations

Exports :

- **bundle\\_string\\_paste** :
    - `paste`
    - `paste_0`
    - `paste_with_space `
- **bundle\\_string\\_concat\\_list\\_string** :
    - `paste_space_list_string`
    - `paste_list_string_sep`
    - `paste_list_string`

"""
module str_paste

using ..UTCGP: FunctionBundle, append_method!

# ########### #
# String Paste #
# ########### #

fallback(args...) = return ""

bundle_string_paste = FunctionBundle(fallback)
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

append_method!(bundle_string_paste, paste)
append_method!(bundle_string_paste, paste0)
append_method!(bundle_string_paste, paste_with_space)

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

append_method!(bundle_string_concat_list_string, paste_space_list_string)
append_method!(bundle_string_concat_list_string, paste_list_string_sep)
append_method!(bundle_string_concat_list_string, paste_list_string)

end
