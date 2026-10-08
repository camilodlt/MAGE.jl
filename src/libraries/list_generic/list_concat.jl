# -*- coding: utf-8 -*-

"""
Concatenation of lists.

# Bundles

- [`bundle_listgeneric_concat`](@ref)
- [`bundle_listgeneric_concat_factory`](@ref)

The exhaustive, always-current list of operators in each bundle is on the
[Bundle Catalogue](@ref) page.
"""
module listgeneric_concat
import ..UTCGP: FunctionBundle, append_method!, FunctionWrapper
import UTCGP: CONSTRAINED, SMALL_ARRAY, NANO_ARRAY, BIG_ARRAY

# ########### #
# CONCAT LIST #
# ########### #

fallback() = []
"""
    bundle_listgeneric_concat

`concat_two_lists`: append one list to another.
"""
bundle_listgeneric_concat = FunctionBundle(fallback)
"""
    bundle_listgeneric_concat_factory

Factory form of [`bundle_listgeneric_concat`](@ref).

This is a *factory* bundle: each entry is a function of a type that returns the
method specialised for it, so the same operator can be instantiated for several
image or element types. See [Libraries](@ref) for how factories are specialised
into a library.
"""
bundle_listgeneric_concat_factory = FunctionBundle(fallback)

#############
# Functions #
#############

# Concat Two lists Of The Same Type

function concat_two_lists_factory(T::DataType)
    return @eval ((list_a::Vector{V}, list_b::Vector{V}, args...) where {V<:$T}) -> begin
        a_c = deepcopy(list_a)::Vector{V}
        b_c = deepcopy(list_b)::Vector{V}
        list_c = V[]
        push!(list_c, a_c...)
        push!(list_c, b_c...)
        bound::Int = 0
        if CONSTRAINED[]
            sm::Int = SMALL_ARRAY[]
            l::Int = length(list_c)
            bound += min(l, sm)
            return list_c[begin:bound]
        end
        return identity.(list_c)
    end
end

"""
    list_concat(list_a::Vector{T}, list_b::Vector{T}, args...)

Concats two lists, should be of the same type.

Although the types of the lists elements are not enforced.

T is a generic type.
"""
concat_two_lists = concat_two_lists_factory(Any)

##########
# Append #
##########
append_method!(
    bundle_listgeneric_concat,
    concat_two_lists,
    :concat_two_lists;
    description = "Concatenates two input lists of compatible element type.",
)
append_method!(
    bundle_listgeneric_concat_factory,
    concat_two_lists_factory,
    :concat_two_lists,
    ;
    description = "Concatenates two input lists of compatible element type.",
)
end
