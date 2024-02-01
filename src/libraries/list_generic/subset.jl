# -*- coding: utf-8 -*-
"""
Exports :

- **bundle\\_listgeneric\\_subset** :
    - `pick_from_exclusive_generic`
    - `pick_from_inclusive_generic`
    - `pick_until_exclusive_generic`
    - `pick_until_inclusive_generic`
    - `subset_list_of_tuples`
    - `subset_by_mask`
    - `subset_by_indices`

"""
module listgeneric_subset

using ..UTCGP: listgeneric_basic, FunctionBundle, FunctionWrapper, append_method!
import .listgeneric_basic: new_list, identity_list
import UTCGP: CONSTRAINED, SMALL_ARRAY, NANO_ARRAY, BIG_ARRAY

# ########### #
# SUBSET LIST #
# ########### #

bundle_listgeneric_subset = FunctionBundle(identity_list, new_list)
bundle_listgeneric_subset_factory = FunctionBundle(identity_list, new_list)

# FUNCTIONS ---

# Pick From Inclusive ---

function pick_from_inclusive_generic_factory(T::DataType)
    return @eval ((list_gen::Vector{V}, from_i::Int, args...) where {V<:$T}) -> begin
        mx_legnth = length(list_gen)
        from_i = max(from_i, 1)
        if CONSTRAINED
            tmp = list_gen[from_i:mx_legnth]
            bound = min(length(tmp), SMALL_ARRAY)
            return tmp[begin:bound]
        end
        return list_gen[from_i:mx_legnth]
    end
end

"""
    pick_from_inclusive_generic(
        list_gen::Vector{T},
        from_i::Int,
        args...,
    )

Subsets a list from (inclusive) until the end of the list

In principle, `from_i` can also be negative, it will return the vector from the first index.
"""
pick_from_inclusive_generic = pick_from_inclusive_generic_factory(Any)


# Pick From Exclusive ---

function pick_from_exclusive_generic_factory(T::DataType)
    return @eval ((list_gen::Vector{V}, from_i::Int, args...) where {V<:$T}) -> begin
        from_i = max(from_i, 1)
        if CONSTRAINED
            tmp = list_gen[from_i+1:end]
            bound = min(length(tmp), SMALL_ARRAY)
            return tmp[begin:bound]
        end
        return list_gen[from_i+1:end]
    end
end
"""
    pick_from_exclusive_generic(
        list_gen::Vector{T},
        from_i::Int,
        args...,
    )

Subsets a list from (exclusive) until the end of the list

In principle, `from_i` can also be negative.
"""
pick_from_exclusive_generic = pick_from_exclusive_generic_factory(Any)


# Pick Until Inclusive --- 

function pick_until_inclusive_generic_factory(T::DataType)
    return @eval ((list_gen::Vector{V}, until_i::Int, args...) where {V<:$T}) -> begin
        until_i = min(length(list_gen), until_i)
        if CONSTRAINED
            tmp = list_gen[begin:until_i]
            bound = min(length(tmp), SMALL_ARRAY)
            return tmp[begin:bound]
        end
        return list_gen[begin:until_i]
    end
end

"""

    pick_until_inclusive_generic(
        list_gen::Vector{T},
        until_i::Int,
        args...,
    )

Subsets a list from the beginning until (inclusive) a given index

In principle, `until_i` can also be negative

"""
pick_until_inclusive_generic = pick_until_inclusive_generic_factory(Any)

# Pick Until Exclusive --- 

function pick_until_exclusive_generic_factory(T::DataType)
    return @eval ((list_gen::Vector{V}, until_i::Int, args...) where {V<:$T}) -> begin
        mx = length(list_gen)
        until = until_i - 1
        until = min(mx, until)
        if CONSTRAINED
            tmp = list_gen[begin:until]
            bound = min(length(tmp), SMALL_ARRAY)
            return tmp[begin:bound]
        end
        return list_gen[begin:until]
    end
end

# Pick Until Exclusive ---

"""
    pick_until_exclusive_generic(
        list_gen::Vector{T},
        until_i::Int,
        args...,
    )
Subsets a list from the beginning until (exclusive) a given index

In principle, `until_i` can also be negative
"""
pick_until_exclusive_generic = pick_until_exclusive_generic_factory(Any)


#####################
# SUBSET VEC TUPLES 
#####################

# Subset list of Tuples --- 
function subset_list_of_tuples_factory(T::DataType)
    return @eval ((v::Vector{Tuple{V,V}}, at::Int, args...) where {V<:$T}) -> begin
        t = v[at]
        return identity.([el for el in t])
    end
end

"""

    subset_list_of_tuples(v::Vector{Tuple{T,T}}, at::Int, args...)

Subsets the vector at the given index and return a vector with the two elements.

Can raise BoundsError if the index is wrong.
"""
subset_list_of_tuples = subset_list_of_tuples_factory(Any)


# Subset Vector By Mask--- 

function subset_by_mask_factory(T::DataType)
    return @eval ((v::Vector{V}, m::Vector{<:Number}) where {V<:$T}) -> begin
        if CONSTRAINED
            @assert length(m) < BIG_ARRAY
            @assert length(v) < BIG_ARRAY
        end
        mask = m .> 0.0
        return v[mask]
    end
end

"""
    subset_by_mask(v::Vector{<:Any}, m::Vector{<:Number})

The mask is transformed to a boolean mask, where an element is 1
if the orginal element is > than 0.0.

Then the mask is used to subset the vector `v`.
"""
subset_by_mask = subset_by_mask_factory(Any)

# Subset By Indices --- 

function subset_by_indices_factory(T::DataType)
    return @eval ((v::Vector{V}, m::Vector{Int}) where {V<:$T}) -> begin
        if CONSTRAINED
            @assert length(m) < BIG_ARRAY
            @assert length(v) < BIG_ARRAY
        end
        v_ = deepcopy(v)
        return v_[m]
    end
end
"""
    subset_by_mask(v::Vector{<:Any}, m::Vector{Int})

Returns the elements of vector `v` at the indices in `m`.
"""
subset_by_indices = subset_by_indices_factory(Any)


#########
# APPEND #
#########

# GENERIC BUNDLE 
# Pick
append_method!(
    bundle_listgeneric_subset,
    pick_from_inclusive_generic,
    :pick_from_inclusive_generic,
)
append_method!(
    bundle_listgeneric_subset,
    pick_from_exclusive_generic,
    :pick_from_exclusive_generic,
)
append_method!(
    bundle_listgeneric_subset,
    pick_until_inclusive_generic,
    :pick_until_inclusive_generic,
)
append_method!(
    bundle_listgeneric_subset,
    pick_until_exclusive_generic,
    :pick_until_exclusive_generic,
)
# Subset Tuples
append_method!(bundle_listgeneric_subset, subset_list_of_tuples, :subset_list_of_tuples)
# Subset mask & Indices
append_method!(bundle_listgeneric_subset, subset_by_mask, :subset_by_mask)
append_method!(bundle_listgeneric_subset, subset_by_indices, :subset_by_indices)

# FACTORY
# Pick
append_method!(
    bundle_listgeneric_subset_factory,
    pick_from_inclusive_generic_factory,
    :pick_from_inclusive_generic,
)
append_method!(
    bundle_listgeneric_subset_factory,
    pick_from_exclusive_generic_factory,
    :pick_from_exclusive_generic,
)
append_method!(
    bundle_listgeneric_subset_factory,
    pick_until_inclusive_generic_factory,
    :pick_until_inclusive_generic,
)
append_method!(
    bundle_listgeneric_subset_factory,
    pick_until_exclusive_generic_factory,
    :pick_until_exclusive_generic,
)
# Subset Tuples
append_method!(
    bundle_listgeneric_subset_factory,
    subset_list_of_tuples_factory,
    :subset_list_of_tuples,
)
# Subset mask & Indices
append_method!(bundle_listgeneric_subset_factory, subset_by_mask_factory, :subset_by_mask)
append_method!(
    bundle_listgeneric_subset_factory,
    subset_by_indices_factory,
    :subset_by_indices,
)

end
