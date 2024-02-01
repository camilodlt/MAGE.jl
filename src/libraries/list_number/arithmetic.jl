# -*- coding: utf-8 -*-
"""
Vector to Vector arithmetic or Vector to Number arithmetic by broadcasting. 
 
Exports : **bundle\\_listnumber\\_arithmetic**: 
- `sum_broadcast`
- `subtract_broadcast`
- `mult_broadcast`
- `div_broadcast`
- `sum_vector`
- `subtract_vector`
- `mult_vector`
- `div_vector`
"""
module listnumber_arithmetic

import ..UTCGP: FunctionBundle, append_method!, FunctionWrapper
import UTCGP: CONSTRAINED, SMALL_ARRAY, NANO_ARRAY, BIG_ARRAY

fallback(args...) = Number[]

bundle_listnumber_arithmetic = FunctionBundle(fallback)



VECTORNUM = Vector{<:Number}

# BROADCAST 

"""
    sum_broadcast(v::Vector{<:Number}, n::Number, args...)

Sum every element in the vector `v` with `n`
"""
function sum_broadcast(v::VECTORNUM, n::Number, args...)
    if CONSTRAINED
        bound = min(length(v), SMALL_ARRAY)
        return v[begin:bound] .+ n
    end
    v .+ n
end

"""
    subtract_broadcast(v::Vector{<:Number}, n::Number, args...)

Substract `n` from every element in `v`
"""
function subtract_broadcast(v::VECTORNUM, n::Number, args...)
    if CONSTRAINED
        bound = min(length(v), SMALL_ARRAY)
        return v[begin:bound] .- n
    end
    v .- n
end

"""
    mult_broadcast(v::Vector{<:Number}, n::Number, args...)

Multiply `n` by every element in `v`
"""
function mult_broadcast(v::VECTORNUM, n::Number, args...)
    if CONSTRAINED
        bound = min(length(v), SMALL_ARRAY)
        return v[begin:bound] .* n
    end
    v .* n
end

"""

    div_broadcast(v::Vector{<:Number}, n::Number, args...)

Divides every element in `v` by `n`.

If n == 0 it throws `DivideError` instead of allowing Inf.
"""
function div_broadcast(v::VECTORNUM, n::Number, args...)
    if n == 0
        throw(DivideError())
    end
    if CONSTRAINED
        bound = min(length(v), SMALL_ARRAY)
        return v[begin:bound] ./ n
    end
    v ./ n
end

# BETWEEN 2 VECTORS

"""
    sum_vector(v1::Vector{<:Number}, v2::Vector{<:Number}, args...)

Element wise sum between `v1` and `v2`.

Can throw DimensionMismatch.
"""
function sum_vector(v1::VECTORNUM, v2::VECTORNUM, args...)
    if CONSTRAINED
        if length(v1) != length(v2)
            throw(DimensionMismatch())
        end
        bound = min(length(v1), SMALL_ARRAY)
        return v1[begin:bound] + v2[begin:bound]
    end
    v1 + v2
end

"""
    subtract_vector(v1::Vector{<:Number}, v2::Vector{<:Number}, args...)

Element wise substraction between `v1` and `v2`

Can throw DimensionMismatch.
"""
function subtract_vector(v1::VECTORNUM, v2::VECTORNUM, args...)
    if CONSTRAINED
        if length(v1) != length(v2)
            throw(DimensionMismatch())
        end
        bound = min(length(v1), SMALL_ARRAY)
        return v1[begin:bound] .- v2[begin:bound]
    end
    v1 .- v2
end

"""
    mult_vector(v1::Vector{<:Number}, v2::Vector{<:Number}, args...)

Element wise multiplication between `v1` and `v2`.

Can throw DimensionMismatch.
"""
function mult_vector(v1::VECTORNUM, v2::VECTORNUM, args...)
    if CONSTRAINED
        if length(v1) != length(v2)
            throw(DimensionMismatch())
        end
        bound = min(length(v1), SMALL_ARRAY)
        return v1[begin:bound] .* v2[begin:bound]
    end
    v1 .* v2
end

"""
    div_vector(v1::Vector{<:Number}, v2::Vector{<:Number}, args...)

Element wise division between `v1` and `v2`.

A division always return a float, even if the two elements are integers.

If one element in `v2` is 0, it will throw `DivideError`. 

Can throw DimensionMismatch.
"""
function div_vector(v1::VECTORNUM, v2::VECTORNUM, args...)
    if any(v2 .== 0)
        throw(DivideError())
    end
    if CONSTRAINED
        if length(v1) != length(v2)
            throw(DimensionMismatch())
        end
        bound = min(length(v1), SMALL_ARRAY)
        return v1[begin:bound] ./ v2[begin:bound]
    end
    v1 ./ v2
end


# Broadcast
append_method!(bundle_listnumber_arithmetic, sum_broadcast)
append_method!(bundle_listnumber_arithmetic, subtract_broadcast)
append_method!(bundle_listnumber_arithmetic, mult_broadcast)
append_method!(bundle_listnumber_arithmetic, div_broadcast)

# Vector (same size)
append_method!(bundle_listnumber_arithmetic, sum_vector)
append_method!(bundle_listnumber_arithmetic, subtract_vector)
append_method!(bundle_listnumber_arithmetic, mult_vector)
append_method!(bundle_listnumber_arithmetic, div_vector)

end
