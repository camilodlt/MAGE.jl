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

"""
    experimental_is_gt(n::Number, then::Number, args...)

Returns 1 if `n>then`, 0 otherwise.
"""
function experimental_is_gt(n::Number, then::Number, args...)
    return Int(n > then)
end

"""
    experimental_is_lt(n::Number, then::Number, args...)

Returns 1 if `n<then`, 0 otherwise.
"""
function experimental_is_lt(n::Number, then::Number, args...)
    return Int(n < then)
end

"""
    experimental_not(n::Number, args...)

Returns 1 if `n<=.5`, 0 otherwise. If applied in the boolean domain negates the argument.
"""
function experimental_not(n::Number, args...)
    # return Int(!Bool(round(Int, clamp(n, 0 ,1))))
    return Int(n <= .5)
end


# STRING 
"""
"""
function str_is_empty(s::String, args...)
    return Int(isempty(s))
end

append_method!(bundle_integer_cond, is_eq_to)
append_method!(bundle_integer_cond, str_is_empty)
append_method!(bundle_integer_cond, experimental_is_gt)
append_method!(bundle_integer_cond, experimental_is_lt)
append_method!(bundle_integer_cond, experimental_not)
end

