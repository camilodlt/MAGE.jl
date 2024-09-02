# -*- coding: utf-8 -*-
"""
Set Operations.

Exports :

- **bundle\\_listgeneric\\_set** :
    - `intersect_`
    - `left_join`

"""
module listgeneric_set

using ..UTCGP: listgeneric_basic, FunctionBundle, FunctionWrapper, append_method!
import .listgeneric_basic: new_list, identity_list
import UTCGP: CONSTRAINED, SMALL_ARRAY, NANO_ARRAY, BIG_ARRAY

# ##### #
# SET #
# ##### #
fallback() = []

bundle_listgeneric_set = FunctionBundle(fallback)
bundle_listgeneric_set_factory = FunctionBundle(fallback)

# FUNCTIONS ---

# Intersect
function intersect_factory(T::DataType)
    return @eval ((a::Vector{V}, b::Vector{V}, args...) where {V<:$T}) -> begin
        if CONSTRAINED[]
            @assert length(a) < BIG_ARRAY[]
            @assert length(b) < BIG_ARRAY[]
        end
        return identity.([e for e in intersect(Set(a), Set(b))])
    end
end

"""
    intersect_(a::Vector{T}, b::Vector{T}, args...)

Returns the intersect (as a vector) between the set of a and the set of b.
"""
intersect_ = intersect_factory(Any)

# Left Join

function left_join_factory(T::DataType)
    return @eval ((a::Vector{V}, b::Vector{V}, args...) where {V<:$T}) -> begin
        if CONSTRAINED[]
            @assert length(a) < BIG_ARRAY[]
            @assert length(b) < BIG_ARRAY[]
        end
        # Intersect
        a_set = Set(a)
        b_set = Set(b)
        left_a = [el for el in a if el in b]
        return identity.(left_a)
    end
end

"""
    left_join(a::Vector{T}, b::Vector{T}, args...) where {T}

Return all elements in a that are also in b, hence allowing duplicates as opposed to `intersect_`

"""
left_join = left_join_factory(Any)

# Intersect with duplicates

function intersect_with_duplicates_factory(T::DataType)
    return @eval ((a::Vector{V}, b::Vector{V}, args...) where {V<:$T}) -> begin
        if CONSTRAINED[]
            @assert length(a) < BIG_ARRAY[]
            @assert length(b) < BIG_ARRAY[]
        end
        common = intersect(Set(a), Set(b))
        res = []
        for element in common
            n_times_in_a = sum(a .== element)
            n_times_in_b = sum(b .== element)
            min_count = min(n_times_in_a, n_times_in_b)
            push!(res, [deepcopy(element) for i = 1:min_count]...)
        end
        return identity.(res)
    end
end

"""

"""
intersect_with_duplicates = intersect_with_duplicates_factory(Any)


##########
# Append #
##########

append_method!(bundle_listgeneric_set, intersect_, :intersect_)
append_method!(bundle_listgeneric_set, left_join, :left_join)
append_method!(
    bundle_listgeneric_set,
    intersect_with_duplicates,
    :intersect_with_duplicates,
)

append_method!(bundle_listgeneric_set_factory, intersect_factory, :intersect)
append_method!(bundle_listgeneric_set_factory, left_join_factory, :left_join)
append_method!(
    bundle_listgeneric_set_factory,
    intersect_with_duplicates_factory,
    :intersect_with_duplicates_factory,
)

end

