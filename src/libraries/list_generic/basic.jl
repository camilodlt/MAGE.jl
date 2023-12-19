
# -*- coding: utf-8 -*-

"""
BAD FN to test dispatch. 

DO not use
"""
function new_list()
    return ""
end

module list_generic_basic

import ..UTCGP: FunctionBundle, append_method!, FunctionWrapper

"""
Exports :

- ***bundle_basic_generic_list** : identity_list (generic, so can be used in other lists fns)

"""

# FALLBACK
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


bundle_basic_generic_list = FunctionBundle(identity_list, new_list, new_list)
append_method!(bundle_basic_generic_list, identity_list)
append_method!(bundle_basic_generic_list, new_list)

# export new_list
export identity_list
export bundle_basic_generic_list
end
