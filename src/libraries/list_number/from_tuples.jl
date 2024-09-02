# -*- coding: utf-8 -*-
"""
Sums tuples in a vector 
 
Exports : **bundle\\_listnumber\\_vectuples**: 
- `sum_tuples_in_vector`

"""
module listnumber_vectuples

import ..UTCGP: FunctionBundle, append_method!, FunctionWrapper
import UTCGP: CONSTRAINED, SMALL_ARRAY, NANO_ARRAY, BIG_ARRAY

fallback(args...) = Number[]

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

append_method!(bundle_listnumber_vectuples, sum_tuples_in_vector)
end

