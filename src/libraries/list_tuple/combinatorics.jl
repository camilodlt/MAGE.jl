# -*- coding: utf-8 -*-

""" Combinatios of 2 elements

Exports :

- **bundle\\_listtuple\\_combinatorics** :
    - `vector_of_products`

"""
module listtuple_combinatorics
import ..UTCGP: FunctionBundle, append_method!, FunctionWrapper
using Base: product
# ############# #
# COMBINATORICS #
# ############# #

fallback() = [(nothing, nothing)]
bundle_listtuple_combinatorics = FunctionBundle(fallback)

# FUNCTIONS ---

"""
    vector_of_products(list_a::Vector{T}, list_b::Vector{T}, args...) 

Calculates the product (combinations) between `list_a` and `list_b` and flattens the result.
"""
function vector_of_products(list_a::Vector{T}, list_b::Vector{T}, args...) where {T}
    p = collect(product(list_a, list_b))
    p = reshape(p, length(p))
    return identity.(p)
end

append_method!(bundle_listtuple_combinatorics, vector_of_products)
end

