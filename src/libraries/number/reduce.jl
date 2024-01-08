
# # -*- coding: utf-8 -*-

""" REDUCE Functions : from vector of number to number

Exports :

- **bundle\\_number\\_reduce** :
    - `reduce_sum`
    - `reduce_min`
    - `reduce_max`
    - `reduce_argmin`
    - `reduce_argmax`
    - `reduce_length`

"""
module number_reduce

using ..UTCGP: FunctionBundle, append_method!

# ################### #
# NUMBER REDUCE       #
# ################### #

fallback(args...) = return 0.0

bundle_number_reduce = FunctionBundle(fallback)

# FUNCTIONS ---

## reduce sum

"""
    reduce_sum(from :: Vector{<:Number}, args...)

Returns the sum of the vector
"""
function reduce_sum(from::Vector{<:Number}, args...)
    return sum(from)
end

## reduce min

"""
    reduce_min(from::Vector{<:Number}, args...)
Returns the minimum in the vector.
"""
function reduce_min(from::Vector{<:Number}, args...)
    return minimum(from)
end
## reduce max

"""
    reduce_max(from::Vector{<:Number}, args...)

Returns the maximum in the vector.
"""
function reduce_max(from::Vector{<:Number}, args...)
    return maximum(from)
end
## reduce argmin

"""
    reduce_argmin(from::Vector{<:Number}, args...)
Returns the `argmin` of the vector.
"""
function reduce_argmin(from::Vector{<:Number}, args...)
    return argmin(from)
end
## reduce argmax

"""
    reduce_argmax(from::Vector{<:Number}, args...)
Returns the `argmax` of the vector.
"""
function reduce_argmax(from::Vector{<:Number}, args...)
    return argmax(from)
end

## reduce length

"""
    reduce_length(from::Vector{<:Any}, args...)
Returns the length of the vector
"""
function reduce_length(from::Vector{<:Any}, args...)
    return length(from)
end

append_method!(bundle_number_reduce, reduce_sum)
append_method!(bundle_number_reduce, reduce_min)
append_method!(bundle_number_reduce, reduce_max)
append_method!(bundle_number_reduce, reduce_argmin)
append_method!(bundle_number_reduce, reduce_argmax)
append_method!(bundle_number_reduce, reduce_length)
end
