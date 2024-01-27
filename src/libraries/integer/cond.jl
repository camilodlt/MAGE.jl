# -*- coding: utf-8 -*-

""" Conditional assertions

Exports :

- **bundle\\_integer\\_cond** :
    - `is_eq_to`
    - `str_is_empty`

"""
module integer_cond

using ..UTCGP: FunctionBundle, append_method!

# ############# #
# CONDITIONS #
# ############# #

fallback(args...) = return 0

bundle_integer_cond = FunctionBundle(fallback)

# FUNCTIONS ---
"""
    is_eq_to(n::Number, to::Number, args...)

Returns 1 if `n==to`, 0 otherwise.
"""
function is_eq_to(n::Number, to::Number, args...)
    return Int(n == to)
end

# STRING 
"""
"""
function str_is_empty(s::String, args...)
    return Int(isempty(s))
end

append_method!(bundle_integer_cond, is_eq_to)
append_method!(bundle_integer_cond, str_is_empty)
end

