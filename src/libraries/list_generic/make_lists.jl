# -*- coding: utf-8 -*-

"""
Make vectors from elements of the same type

Exports : **bundle\\_listgeneric\\_makelist**: 
- `make_list_from_one_element`
- `make_list_from_two_elements`
- `make_list_from_three_elements`

"""
module listgeneric_makelist

import ..UTCGP: FunctionBundle, append_method!, FunctionWrapper
import UTCGP: CONSTRAINED, SMALL_ARRAY, NANO_ARRAY, BIG_ARRAY


# FALLBACK
fallback() = []
bundle_listgeneric_makelist = FunctionBundle(fallback)
bundle_listgeneric_makelist_factory = FunctionBundle(fallback)

Ts = Union{Number,String}

#####################
# Make list from ... #
#####################

# Make List From One Element ---
function make_list_from_one_element_factory(T::DataType)
    return @eval ((e1::ET, args...) where {ET<:$T}) -> begin
        v = [e1]
        return identity.(v)
    end
end

"""
    make_list_from_one_element(e1::T, args...) 

Makes [e1]
"""
make_list_from_one_element = make_list_from_one_element_factory(Any)

# Make List From 2 Element ---

function make_list_from_two_elements_factory(T::DataType)
    return @eval ((e1::ET, e2::ET, args...) where {ET<:$T}) -> begin
        v = [e1, e2]
        return identity.(v)
    end
end

"""
    make_list_from_two_elements(e1::T, e2::T, args...) 

Makes [e1,e2]
"""
make_list_from_two_elements = make_list_from_two_elements_factory(Any)

# Make List From Three Elements --- 

function make_list_from_three_elements_factory(T::DataType)
    return @eval ((e1::ET, e2::ET, e3::ET, args...) where {ET<:$T}) -> begin
        v = [e1, e2, e3]
        return identity.(v)
    end
end

"""
    make_list_from_three_elements(e1::T, e2::T, e3::T, args...)

Makes [e1,e2,e3]
"""
make_list_from_three_elements = make_list_from_three_elements_factory(Any)


##########
# APPEND #
##########
append_method!(
    bundle_listgeneric_makelist,
    make_list_from_one_element,
    :make_list_from_one_element,
)
append_method!(
    bundle_listgeneric_makelist,
    make_list_from_two_elements,
    :make_list_from_two_elements,
)
append_method!(
    bundle_listgeneric_makelist,
    make_list_from_three_elements,
    :make_list_from_three_elements,
)

append_method!(
    bundle_listgeneric_makelist_factory,
    make_list_from_one_element_factory,
    :make_list_from_one_element,
)
append_method!(
    bundle_listgeneric_makelist_factory,
    make_list_from_two_elements_factory,
    :make_list_from_two_elements,
)
append_method!(
    bundle_listgeneric_makelist_factory,
    make_list_from_three_elements_factory,
    :make_list_from_three_elements,
)
end
