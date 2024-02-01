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
import UTCGP: CONSTRAINED, SMALL_ARRAY, NANO_ARRAY, BIG_ARRAY

# Identity
function identity_list_factory(T::DataType)
    return @eval ((l::Vector{V}, args...) where {V<:$T}) -> begin
        if CONSTRAINED
            bound = min(length(l), BIG_ARRAY)
            return l[begin:bound]
        end
        return l
    end
end

"""
Just return the list.

Generic function
"""
identity_list = identity_list_factory(Any)

# New List
function new_list_factory(T::DataType)
    return @eval (args...) -> begin
        return []
    end
end

"""
    new_list(args...)

Generates a new vector, the type will be `Any` so a caster should be used.
"""
new_list = new_list_factory(Any)

# Reverse List
function reverse_list_factory(T::DataType)
    return @eval ((l::Vector{V}, args...) where {V<:$T}) -> begin
        if CONSTRAINED
            bound = min(length(l), BIG_ARRAY)
            return reverse(l[begin:bound])
        end
        return reverse(l)
    end
end

"""
    reverse_list(l::Vector{<:Any}, args...) 

Reverse the list without affecting the original list.
"""
reverse_list = reverse_list_factory(Any)


# BUNDLES 

bundle_listgeneric_basic = FunctionBundle(identity_list, new_list, new_list)
append_method!(bundle_listgeneric_basic, identity_list, :identity_list)
append_method!(bundle_listgeneric_basic, new_list, :new_list)
append_method!(bundle_listgeneric_basic, reverse_list, :reverse_list)

bundle_listgeneric_basic_factory = FunctionBundle(identity_list, new_list, new_list)
append_method!(bundle_listgeneric_basic_factory, identity_list_factory, :identity_list)
append_method!(bundle_listgeneric_basic_factory, new_list_factory, :new_list)
append_method!(bundle_listgeneric_basic_factory, reverse_list_factory, :reverse_list)
end
