# -*- coding: utf-8 -*-
"""
Algebraic operations on a vector
 
Exports : **bundle\\_listnumber\\_algebraic**: 
- `abs_vector`

"""
module listnumber_algebraic

import ..UTCGP: FunctionBundle, append_method!, FunctionWrapper

fallback(args...) = Number[]

bundle_listnumber_algebraic = FunctionBundle(fallback)

VECTORNUM = Vector{<:Number}

# ABS VALUE

"""
    abs_vector(v::Vector{<:Number}, args...)

Element wise Abs value 
"""
function abs_vector(v::VECTORNUM, args...)
    return abs.(v)
end

append_method!(bundle_listnumber_algebraic, abs_vector)
end
