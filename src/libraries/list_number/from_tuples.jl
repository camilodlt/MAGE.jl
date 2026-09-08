# -*- coding: utf-8 -*-
"""
Numeric lists derived from lists of pairs.

# Bundles

- [`bundle_listnumber_vectuples`](@ref)

The exhaustive, always-current list of operators in each bundle is on the
[Bundle Catalogue](@ref) page.
"""
module listnumber_vectuples

import ..UTCGP: FunctionBundle, append_method!, FunctionWrapper
import UTCGP: CONSTRAINED, SMALL_ARRAY, NANO_ARRAY, BIG_ARRAY

fallback(args...) = Number[]

"""
    bundle_listnumber_vectuples

`sum_tuples_in_vector`: turn a list of pairs into the list of their sums.

Reads from a `Vector{Tuple{T,T}}` chromosome and writes into a numeric-list one.
"""
bundle_listnumber_vectuples = FunctionBundle(fallback)

VECTORNUM = Vector{<:Number}

# ABS VALUE

"""

"""
function sum_tuples_in_vector(v::Vector{Tuple{T,T}}, args...) where {T<:Number}
    # println("Sum_tuples_in_vector : length v : $(length(v))")
    if CONSTRAINED[]
        bound = min(length(v), SMALL_ARRAY[])
        # println("Sum_tuples_in_vector : length v cons : $(length(v))")
        return identity.([a + b for (a, b) in v[begin:bound]])
    end
    return identity.([a + b for (a, b) in v])
end

append_method!(
    bundle_listnumber_vectuples,
    sum_tuples_in_vector;
    description = "Sums each numeric tuple (a, b) in the vector and returns the resulting vector.",
)
end
