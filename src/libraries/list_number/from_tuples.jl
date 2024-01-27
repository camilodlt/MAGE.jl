# -*- coding: utf-8 -*-
"""
Sums tuples in a vector 
 
Exports : **bundle\\_listnumber\\_vectuples**: 
- `sum_tuples_in_vector`

"""
module listnumber_vectuples

import ..UTCGP: FunctionBundle, append_method!, FunctionWrapper

fallback(args...) = Number[]

bundle_listnumber_vectuples = FunctionBundle(fallback)

VECTORNUM = Vector{<:Number}

# ABS VALUE

"""

"""
function sum_tuples_in_vector(v::Vector{Tuple{T,T}}, args...) where {T<:Number}
    return identity.([a + b for (a, b) in v])
end

append_method!(bundle_listnumber_vectuples, sum_tuples_in_vector)
end

