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

# FUNCTIONS ---

"""
    list_concat(list_a::Vector{T}, list_b::Vector{T}, args...)

Concats two lists, should be of the same type.

Although the types of the lists elements are not enforced.

T is a generic type.
"""
function concat_two_lists(list_a::Vector{T}, list_b::Vector{T}, args...) where {T}
    list_c = [deepcopy(list_a); deepcopy(list_b)]
    return identity.(list_c)
end

append_method!(bundle_listgeneric_concat, concat_two_lists)
end
