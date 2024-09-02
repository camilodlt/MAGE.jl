# -*- coding: utf-8 -*-
"""
Where operations

Exports :

- **bundle\\_listgeneric\\_where** :
    - `replace_vec_at`

"""
module listgeneric_where
using ..UTCGP: listgeneric_basic, FunctionBundle, FunctionWrapper, append_method!
import UTCGP: CONSTRAINED, SMALL_ARRAY, NANO_ARRAY, BIG_ARRAY

# ############################### #
# REPLACE VECTOR WITH ANOTHER AT  #
# ############################### #
fallback() = []

bundle_listgeneric_where = FunctionBundle(fallback)
bundle_listgeneric_where_factory = FunctionBundle(fallback)


# Replace Vec At --- 
function replace_vec_at_factory(T::DataType)
    return @eval ((v1::Vector{V}, v2::Vector{V}, at::Vector{Int}, args...) where {V<:$T}) ->
        begin
            if CONSTRAINED[]
                @assert length(v1) <= SMALL_ARRAY[]
                @assert length(v2) <= SMALL_ARRAY[]
                @assert length(at) <= SMALL_ARRAY[]
            end
            @assert length(at) == length(v1) "mask is not of the same size as vector"
            m = at .> 0.0
            @assert length(v2) == sum(m) "Replacing vector has incorrect size"
            final_v = deepcopy(v1)
            final_v[m] = deepcopy(v2)
            return final_v
        end
end
"""
    replace_vec_at(v1::Vector{T}, v2::Vector{T}, at::Vector{Int}, args...)

Replaces the elements where `at` is 1 from `v1` with the element in `v2` at that index.
"""
replace_vec_at = replace_vec_at_factory(Any)

# APPEND
append_method!(bundle_listgeneric_where, replace_vec_at, :replace_vec_at)
append_method!(bundle_listgeneric_where_factory, replace_vec_at_factory, :replace_vec_at)
end

