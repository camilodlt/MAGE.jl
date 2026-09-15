# -*- coding: utf-8 -*-

"""
Pairs built by combining elements of one or two lists.

# Bundles

- [`bundle_listtuple_combinatorics`](@ref)
- [`bundle_listtuple_combinatorics_factory`](@ref)

The exhaustive, always-current list of operators in each bundle is on the
[Bundle Catalogue](@ref) page.
"""
module listtuple_combinatorics
import ..UTCGP: FunctionBundle, append_method!, FunctionWrapper
using Base: product
using Combinatorics
import UTCGP: CONSTRAINED, SMALL_ARRAY, NANO_ARRAY, BIG_ARRAY

# ############# #
# COMBINATORICS #
# ############# #

fallback() = [(nothing, nothing)]
"""
    bundle_listtuple_combinatorics

Pair generation: `vector_of_products` (the cartesian product of two lists) and
`vector_of_combinations` (all unordered pairs of one list).
"""
bundle_listtuple_combinatorics = FunctionBundle(fallback)
"""
    bundle_listtuple_combinatorics_factory

Factory form of [`bundle_listtuple_combinatorics`](@ref).

This is a *factory* bundle: each entry is a function of a type that returns the
method specialised for it, so the same operator can be instantiated for several
image or element types. See [Libraries](@ref) for how factories are specialised
into a library.
"""
bundle_listtuple_combinatorics_factory = FunctionBundle(fallback)

###############
# FUNCTIONS 
###############

# Products --- 
function vector_of_products_factory(T::DataType)
    return @eval ((list_a::Vector{V}, list_b::Vector{V}, args...) where {V<:$T}) -> begin
        if CONSTRAINED[]
            @assert length(list_a) <= 1000
            @assert length(list_b) <= 1000
        end
        p = collect(product(list_a, list_b))
        p = reshape(p, length(p))
        if CONSTRAINED[]
            bound = min(length(p), BIG_ARRAY[])
            p = p[begin:bound]
        end
        return identity.(p)
    end
end

"""
    _vector_of_products(list_a::Vector{T}, list_b::Vector{T}, args...) 

Calculates the product (combinations) between `list_a` and `list_b` and flattens the result.
"""
vector_of_products = vector_of_products_factory(Any)

# Combinations --- 

"""
    vector_of_combinations_factory(T::DataType)

Factory function. 

Collects combinations (size 2) of elements of a vector.

Reacts to SMALL_ARRAY[].

Raises error if the vector hsa elements of different types or if the vector is empty. 
"""
function vector_of_combinations_factory(T::DataType)
    return @eval ((v::Vector{V}, args...) where {V<:$T}) -> begin
        @assert !isempty(v) && length(unique(typeof.(v))) == 1
        if CONSTRAINED[]
            @assert length(v) < SMALL_ARRAY[]
        end
        combs = collect(combinations(v, 2))
        combs = [Tuple(_ for _ in c) for c in combs]
        if CONSTRAINED[]
            bound = min(length(combs), SMALL_ARRAY[])
            return combs[begin:bound]
        end
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
append_method!(
    bundle_listtuple_combinatorics,
    vector_of_products,
    :vector_of_products;
    description = "Returns all ordered pair products from values in the input vector.",
)
append_method!(
    bundle_listtuple_combinatorics,
    vector_of_combinations,
    :vector_of_combinations,
    ;
    description = "Returns all size-2 combinations of elements from the input vector.",
)

# Factory rundle ---
append_method!(
    bundle_listtuple_combinatorics_factory,
    vector_of_products_factory,
    :vector_of_products,
    ;
    description = "Returns all ordered pair products from values in the input vector.",
)
append_method!(
    bundle_listtuple_combinatorics_factory,
    vector_of_combinations_factory,
    :vector_of_combinations,
    ;
    description = "Returns all size-2 combinations of elements from the input vector.",
)
end
