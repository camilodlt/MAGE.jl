# -*- coding: utf-8 -*-

"""
BAD FN to test dispatch. 

DO not use
"""
function new_list()
    return ""
end

"""
Basic Functions that apply to all lists

Exports : **bundle_listgeneric_basic**: 
    - `identity_list`
    - `new_list`
    - `reverse_list`

"""
module listgeneric_basic

import ..UTCGP: FunctionBundle, append_method!, FunctionWrapper


# FALLBACK
"""

    new_list(args...)

Generates a new vector, the type will be `Any` so a caster should be used.
"""
function new_list(args...)
    return Vector()
end

# Casters
"""
Just return the list.

Generic function
"""
function identity_list(l::Vector{T}, args...)::Vector{T} where {T}
    return l
end

"""
    reverse_list(l::Vector{<:Any}, args...) 

Reverse the list without affecting the original list.
"""
reverse_list(l::Vector{<:Any}, args...) = reverse(l)


bundle_listgeneric_basic = FunctionBundle(identity_list, new_list, new_list)
append_method!(bundle_listgeneric_basic, identity_list)
append_method!(bundle_listgeneric_basic, new_list)
append_method!(bundle_listgeneric_basic, reverse_list)
end
