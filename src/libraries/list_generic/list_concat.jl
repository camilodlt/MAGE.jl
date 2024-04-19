# -*- coding: utf-8 -*-

""" Union of lists

Exports :

- **bundle\\_listgeneric\\_concat** :
    - `concat_two_lists`

"""
module listgeneric_concat
import ..UTCGP: FunctionBundle, append_method!, FunctionWrapper
import UTCGP: CONSTRAINED, SMALL_ARRAY, NANO_ARRAY, BIG_ARRAY

# ########### #
# CONCAT LIST #
# ########### #

fallback() = []
bundle_listgeneric_concat = FunctionBundle(fallback)
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
        if CONSTRAINED
            sm::Int = SMALL_ARRAY
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
append_method!(bundle_listgeneric_concat, concat_two_lists, :concat_two_lists)
append_method!(
    bundle_listgeneric_concat_factory,
    concat_two_lists_factory,
    :concat_two_lists,
)
end
