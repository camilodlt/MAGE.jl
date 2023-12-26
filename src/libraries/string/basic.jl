# # -*- coding: utf-8 -*-

""" 

Some basic operations.

Exports :

- **bundle\\_string\\_basic** :
    - `number_to_string`

"""
module str_basic

using ..UTCGP: FunctionBundle, append_method!

# ################### #
# String Conditional  #
# ################### #

fallback(args...) = return ""

bundle_string_basic = FunctionBundle(fallback)

# FUNCTIONS ---
"""
    identity_str(s::String, args...)

Returns the same string.
"""
function identity_str(s::String, args...)
    return s
end

"""
    number_to_string(num::Number, args...)

Returns the number as a string.
"""
function number_to_string(num::Number, args...)
    return string(num)
end

append_method!(bundle_string_basic, identity_str)
append_method!(bundle_string_basic, number_to_string)
end
