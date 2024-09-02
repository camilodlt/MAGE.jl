# -*- coding: utf-8 -*-
"""
Utils to work with lists

Exports :

- **bundle\\_listgeneric\\_utils** :
    - `sort_list`
    - `append_to_list`
    - `unique_in_list`
    - `replace_by_mapping`

"""
module listgeneric_utils

using ..UTCGP: listgeneric_basic, FunctionBundle, FunctionWrapper, append_method!
import UTCGP: CONSTRAINED, SMALL_ARRAY, NANO_ARRAY, BIG_ARRAY

# ##### #
# SORT  #
# ##### #

fallback() = []

bundle_listgeneric_utils = FunctionBundle(fallback)
bundle_listgeneric_utils_factory = FunctionBundle(fallback)

# Sort --- 

function sort_list_factory(T::DataType)
    return @eval ((a::Vector{V}, args...) where {V<:$T}) -> begin
        if CONSTRAINED[]
            bound = min(length(a), SMALL_ARRAY[])
            return sort(a[begin:bound])
        end
        return sort(a)
    end
end

"""
    sort_list(a::Vector{T}, args...) where {T}

Sort the list, not inplace.
"""
sort_list = sort_list_factory(Any)

# Append To List --- 

function append_to_list_factory(T::DataType)
    return @eval ((v::Vector{V}, el::V, args...) where {V<:$T}) -> begin
        v2 = deepcopy(v)
        push!(v2, el)
        if CONSTRAINED[]
            bound = min(length(v2), SMALL_ARRAY[])
            return v2[begin:bound]
        end
        return v2
    end
end
"""
    append_to_list(v::Vector{T}, el::T, args...) where {T}

Pushes the `el`ement to the a copy of the list

"""
append_to_list = append_to_list_factory(Any)

# Unique In List 

function unique_in_list_factory(T::DataType)
    return @eval ((v::Vector{V}, args...) where {V<:$T}) -> begin
        if CONSTRAINED[]
            @assert length(v) <= SMALL_ARRAY[]
        end
        v2 = deepcopy(v)
        unique!(v2)
        if CONSTRAINED[]
            bound = min(length(v2), SMALL_ARRAY[])
            return v2[begin:bound]
        end
        return v2
    end
end
"""
    unique_in_list(v::Vector{<:Any}, args...)

Returns the unique items in a new list.
"""
unique_in_list = unique_in_list_factory(Any)

# Replace By Mapping --- 
function replace_by_mapping_factory(T::DataType)
    return @eval (
        (to_change::Vector{V}, from_to_mapping::Vector{Tuple{V,V}}, args...) where {V<:$T}
    ) -> begin
        if CONSTRAINED[]
            @assert length(to_change) <= SMALL_ARRAY[]
            @assert length(from_to_mapping) <= SMALL_ARRAY[]
        end
        # Replace by mapping
        res = []
        for a in to_change
            which_key = [a == b for (b, _) in from_to_mapping]
            matches = findall(==(true), which_key)
            if length(matches) > 0
                idx = matches[1]
                v = from_to_mapping[idx][2]
            else
                v = a
            end
            push!(res, v)
        end
        return identity.(res)
    end
end

"""
    replace_by_mapping(to_change::Vector{V}, from_to_mapping::Vector{Tuple{V,V}})

In `to_change`, it repleaces an element by the second value of the tuple in case 
the first value matched the element.

"""
replace_by_mapping = replace_by_mapping_factory(Any)

# APPEND
append_method!(bundle_listgeneric_utils, sort_list, :sort_list)
append_method!(bundle_listgeneric_utils, append_to_list, :append_to_list)
append_method!(bundle_listgeneric_utils, unique_in_list, :unique_in_list)
append_method!(bundle_listgeneric_utils, replace_by_mapping, :replace_by_mapping)

append_method!(bundle_listgeneric_utils_factory, sort_list_factory, :sort_list)
append_method!(bundle_listgeneric_utils_factory, append_to_list_factory, :append_to_list)
append_method!(bundle_listgeneric_utils_factory, unique_in_list_factory, :unique_in_list)
append_method!(
    bundle_listgeneric_utils_factory,
    replace_by_mapping_factory,
    :replace_by_mapping,
)

end


