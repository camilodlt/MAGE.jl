# -*- coding: utf-8 -*-

""" Union of lists

Exports :

- **bundle\\_listgeneric\\_concat** :
    - `concat_two_lists`

"""
module listgeneric_concat
import ..UTCGP: FunctionBundle, append_method!, FunctionWrapper

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
        list_c = [deepcopy(list_a); deepcopy(list_b)]
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
