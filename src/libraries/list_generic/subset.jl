# -*- coding: utf-8 -*-

module list_generic_subset

"""
Exports :

- **bundle_suset_list_generic** :
    - pick_from_exclusive_generic
    - pick_from_inclusive_generic
    - pick_until_exclusive_generic
    - pick_until_inclusive_generic
"""

using ..UTCGP: list_generic_basic, FunctionBundle, FunctionWrapper, append_method!
import .list_generic_basic

# ########### #
# SUBSET LIST #
# ########### #

bundle_subset_list_generic =
    FunctionBundle(list_generic_basic.identity_list, list_generic_basic.new_list)

# FUNCTIONS ---


"""Subsets a list from (inclusive) until the end of the list

T is a generic type.

In principle, `from_i` can also be negative

Parameters
----------
list_gen : Vector{T}
           A given list. In this case all elements are asumed
           to be of the same type.
from_i : int
         The `from` index to use for subset

Returns
-------
Vector{T}
        The subsetted list

Examples
--------
>>> pick_from_inclusive_generic([1,2,3,4], 1)
[2,3,4]

>>> pick_from_inclusive_generic([1,2,3,4], 3)
[4]


>>> pick_from_inclusive_generic([1,2,3,4], 5)
[]
"""
function pick_from_inclusive_generic(
    list_gen::Vector{T},
    from_i::Int,
    args...,
)::Vector{T} where {T}
    mx_legnth = length(list_gen)
    from_i = max(from_i, 1)
    if from_i > mx_legnth
        return T[]
    end
    return list_gen[from_i:mx_legnth]
end



"""Subsets a list from (exclusive) until the end of the list

T is a generic type.
This function adds 1 to `from_i` to exclude the `from_i` element.
In principle, `from_i` can also be negative.

Parameters
----------
list_gen : Vector{T}
           A given list. In this case all elements are asumed
           to be of the same type.
from_i : int
         The `from` index to use for subset

Returns
-------
Vector{T}
        The subsetted list

Examples
--------
>>> pick_from_exclusive_generic([1,2,3,4], 1)
[3,4]

>>> pick_from_exclusive_generic([1,2,3,4], 3)
[]
"""
function pick_from_exclusive_generic(
    list_gen::Vector{T},
    from_i::Int,
    args...,
)::Vector{T} where {T}
    mx_legnth = length(list_gen)
    from_i = max(from_i, 1)
    if from_i >= mx_legnth
        return T[]
    end
    return list_gen[from_i+1:mx_legnth]
end


"""Subsets a list from the beginning until (inclusive) a given index

T is a generic type.

In principle, `until_i` can also be negative

Parameters
----------
list_gen : Vector{T}
           A given list. In this case all elements are asumed
           to be of the same type.
until_i : int
         The **until** index to use for subset

Returns
-------
Vector{T}
        The subsetted list

Examples
--------
>>> pick_until_inclusive_generic([1,2,3,4], 1)
[1,2]

>>> pick_until_inclusive_generic([1,2,3,4], 0)
[1]


>>> pick_until_inclusive_generic([1,2,3,4], 10)
[1,2,3,4]
"""
function pick_until_inclusive_generic(
    list_gen::Vector{T},
    until_i::Int,
    args...,
)::Vector{T} where {T}
    until_i = min(length(list_gen)until_i)
    return list_gen[1:until_i]
end


"""Subsets a list from the beginning until (exclusive) a given index

T is a generic type.

In principle, `until_i` can also be negative

Parameters
----------
list_gen : list[T]
           A given list. In this case all elements are asumed
           to be of the same type.
until_i : int
         The **until** index to use for subset

Returns
-------
list[T]
        The subsetted list

Examples
--------
>>> pick_until_exclusive_generic([1,2,3,4], 1)
[1]

>>> pick_until_exclusive_generic([1,2,3,4], 2)
[1,2]

>>> pick_until_exclusive_generic([1,2,3,4], 0)
[]

>>> pick_until_exclusive_generic([1,2,3,4], 10)
[1,2,3,4]
"""
function pick_until_exclusive_generic(
    list_gen::Vector{T},
    until_i::Int,
    args...,
)::Vector{T} where {T}
    if until_i < 1
        return T[] # [1,2,3] , 0 => []
    end
    mx = length(list_gen)
    if until_i > mx
        return list_gen[1:mx] # [1,2,3] , 4 => [1,2,3]
    end
    return list_gen[1:until_i-1] # [1,2,3] , 3  => [1,2]
    # if until_i is 1: the range is 1:0 the result is []
end

append_method!(bundle_subset_list_generic, pick_from_inclusive_generic)
append_method!(bundle_subset_list_generic, pick_from_exclusive_generic)
append_method!(bundle_subset_list_generic, pick_until_inclusive_generic)
append_method!(bundle_subset_list_generic, pick_until_exclusive_generic)

export bundle_subset_list_generic

end
