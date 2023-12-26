# # -*- coding: utf-8 -*-

""" Grep Operations

Exports :

- **bundle\\_string\\_grep** :
    - replace_pattern
    - replace\\_first\\_pattern`
    - remove_pattern

"""
module str_grep



using ..UTCGP: FunctionBundle, append_method!

# ########### #
# String Grep #
# ########### #
fallback(args...) = return ""

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


append_method!(bundle_string_grep, replace_pattern)
append_method!(bundle_string_grep, replace_first_pattern)
append_method!(bundle_string_grep, remove_pattern)

end
