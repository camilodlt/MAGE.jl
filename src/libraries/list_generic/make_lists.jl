# -*- coding: utf-8 -*-

"""
Build lists out of loose elements of the same type.

# Bundles

- [`bundle_listgeneric_makelist`](@ref)
- [`bundle_listgeneric_makelist_factory`](@ref)

The exhaustive, always-current list of operators in each bundle is on the
[Bundle Catalogue](@ref) page.
"""
module listgeneric_makelist

import ..UTCGP: FunctionBundle, append_method!, FunctionWrapper
import UTCGP: CONSTRAINED, SMALL_ARRAY, NANO_ARRAY, BIG_ARRAY


# FALLBACK
fallback() = []
"""
    bundle_listgeneric_makelist

Build a list out of loose elements: `make_list_from_one_element`,
`make_list_from_two_elements`, `make_list_from_three_elements`.

This is the bridge in the other direction from `bundle_element_pick`: a
scalar chromosome feeding a list one.
"""
bundle_listgeneric_makelist = FunctionBundle(fallback)
"""
    bundle_listgeneric_makelist_factory

Factory form of [`bundle_listgeneric_makelist`](@ref).

This is a *factory* bundle: each entry is a function of a type that returns the
method specialised for it, so the same operator can be instantiated for several
image or element types. See [Libraries](@ref) for how factories are specialised
into a library.
"""
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
    ;
    description = "Builds a one-element list from a single input value.",
)
append_method!(
    bundle_listgeneric_makelist,
    make_list_from_two_elements,
    :make_list_from_two_elements,
    ;
    description = "Builds a two-element list from two input values.",
)
append_method!(
    bundle_listgeneric_makelist,
    make_list_from_three_elements,
    :make_list_from_three_elements,
    ;
    description = "Builds a three-element list from three input values.",
)

append_method!(
    bundle_listgeneric_makelist_factory,
    make_list_from_one_element_factory,
    :make_list_from_one_element,
    ;
    description = "Builds a one-element list from a single input value.",
)
append_method!(
    bundle_listgeneric_makelist_factory,
    make_list_from_two_elements_factory,
    :make_list_from_two_elements,
    ;
    description = "Builds a two-element list from two input values.",
)
append_method!(
    bundle_listgeneric_makelist_factory,
    make_list_from_three_elements_factory,
    :make_list_from_three_elements,
    ;
    description = "Builds a three-element list from three input values.",
)
end
