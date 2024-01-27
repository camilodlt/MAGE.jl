# -*- coding: utf-8 -*-

""" Combinatios of 2 elements

Exports :

- **bundle\\_listtuple\\_combinatorics** :
    - `vector_of_products`
    - `vector_of_combinations`

"""
module listtuple_combinatorics
import ..UTCGP: FunctionBundle, append_method!, FunctionWrapper
using Base: product
using Combinatorics

# ############# #
# COMBINATORICS #
# ############# #

fallback() = [(nothing, nothing)]
bundle_listtuple_combinatorics = FunctionBundle(fallback)
bundle_listtuple_combinatorics_factory = FunctionBundle(fallback)

###############
# FUNCTIONS 
###############

# Products --- 
function vector_of_products_factory(T::DataType)
    return @eval ((list_a::Vector{V}, list_b::Vector{V}, args...) where {V<:$T}) -> begin
        @assert length(list_a) <= 1000
        @assert length(list_b) <= 1000
        p = collect(product(list_a, list_b))
        p = reshape(p, length(p))
        return identity.(p)
    end
end

"""
    _vector_of_products(list_a::Vector{T}, list_b::Vector{T}, args...) 

Calculates the product (combinations) between `list_a` and `list_b` and flattens the result.
"""
vector_of_products = vector_of_products_factory(Any)

# Combinations --- 

function vector_of_combinations_factory(T::DataType)
    return @eval ((v::Vector{V}) where {V<:$T}) -> begin
        @assert !isempty(v) && length(unique(typeof.(v))) == 1
        combs = collect(combinations(v, 2))
        combs = [Tuple(_ for _ in c) for c in combs]
        return combs
    end
end
"""
    vector_of_combinations(v::Vector{T})

Returns all combinations (of size 2) between the elements of the vector.
"""

vector_of_combinations = vector_of_combinations_factory(Any)

#########
# APPEND
#########

# Normal Bundle ---
append_method!(bundle_listtuple_combinatorics, vector_of_products, :vector_of_products)
append_method!(
    bundle_listtuple_combinatorics,
    vector_of_combinations,
    :vector_of_combinations,
)

# Factory rundle ---
append_method!(
    bundle_listtuple_combinatorics_factory,
    vector_of_products_factory,
    :vector_of_products,
)
append_method!(
    bundle_listtuple_combinatorics_factory,
    vector_of_combinations_factory,
    :vector_of_combinations,
)
end

