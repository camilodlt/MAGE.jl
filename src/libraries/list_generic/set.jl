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

##########
# Append #
##########

append_method!(bundle_listgeneric_set, intersect_, :intersect_)
append_method!(bundle_listgeneric_set, left_join, :left_join)

append_method!(bundle_listgeneric_set_factory, intersect_factory, :intersect)
append_method!(bundle_listgeneric_set_factory, left_join_factory, :left_join)

end

