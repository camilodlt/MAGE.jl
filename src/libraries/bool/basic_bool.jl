# -*- coding: utf-8 -*-

""" Basic Bool functions

Exports :

- **bundle\\_bool\\_basic** :
    - `ret_true`
    - `ret_false`
    - `parse_string`
"""
module bool_basic

using ..UTCGP: FunctionBundle, append_method!

fallback(args...) = return false

bundle_bool_basic = FunctionBundle(fallback)

baremodule BM_ end

# ################### #
# TRUE & FALSE        #
# ################### #
"""

    identity_bool(x::Bool, args...)

Returns the boolean
"""
function identity_bool(x::Bool, args...)
    return x
end

"""
    ret_true(args...)
"""
function ret_true(args...)
    return true
end

"""
    ret_false(args...)
"""
function ret_false(args...)
    return false
end

# ################### #
# EVAL STRING         #
# ################### #

"""
    parse_string(args...)
"""
function parse_string(s::String, args...)
    try
        e = Meta.parse(s)
        return Base.eval(BM_, e) == true
    catch
        return false
    end
end

append_method!(bundle_bool_basic, identity_bool)
append_method!(bundle_bool_basic, ret_true)
append_method!(bundle_bool_basic, ret_false)
append_method!(bundle_bool_basic, parse_string)
end
