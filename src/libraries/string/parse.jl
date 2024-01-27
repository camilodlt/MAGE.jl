# # -*- coding: utf-8 -*-

""" 
Parse types to String. 

Exports :

- **bundle\\_string\\_parse** :
    - `parse_number`
"""
module str_parse

using ..UTCGP: FunctionBundle, append_method!

# ################### #
# PARSE FROM NUMBER   #
# ################### #

fallback(args...) = return ""

bundle_string_parse = FunctionBundle(fallback)

# FUNCTIONS ---
"""
    parse_number(n::Number, args...)

Parses the number to string.
"""
function parse_number(n::Number, args...)
    return string(n)
end

# APPEND ---
append_method!(bundle_string_parse, parse_number)

end
