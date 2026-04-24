
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
    if isempty(from)
        throw(ArgumentError("vector is empty"))
    end
    return minimum(from)
end
## reduce max

"""
    reduce_max(from::Vector{<:Number}, args...)

Returns the maximum in the vector.
"""
function reduce_max(from::Vector{<:Number}, args...)
    if isempty(from)
        throw(ArgumentError("vector is empty"))
    end
    return maximum(from)
end
## reduce argmin

"""
    reduce_argmin(from::Vector{<:Number}, args...)
Returns the `argmin` of the vector.
"""
function reduce_argmin(from::Vector{<:Number}, args...)
    if isempty(from)
        throw(ArgumentError("vector is empty"))
    end
    return argmin(from)
end
## reduce argmax

"""
    reduce_argmax(from::Vector{<:Number}, args...)
Returns the `argmax` of the vector.
"""
function reduce_argmax(from::Vector{<:Number}, args...)
    if isempty(from)
        throw(ArgumentError("vector is empty"))
    end
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

"""
    reduce_length(from::String, args...)

Return the length of the string.
"""
function reduce_length(from::String, args...)
    return length(from)
end

append_method!(
    bundle_number_reduce,
    reduce_sum;
    description = "Returns the sum of numeric values in the input vector.",
)
append_method!(
    bundle_number_reduce,
    reduce_min;
    description = "Returns the minimum numeric value found in the input vector.",
)
append_method!(
    bundle_number_reduce,
    reduce_max;
    description = "Returns the maximum numeric value found in the input vector.",
)
append_method!(
    bundle_number_reduce,
    reduce_argmin;
    description = "Returns the index of the minimum value in the input vector.",
)
append_method!(
    bundle_number_reduce,
    reduce_argmax;
    description = "Returns the index of the maximum value in the input vector.",
)
append_method!(
    bundle_number_reduce,
    reduce_length;
    description = "Returns length for both supported signatures: reduce_length(vector) and reduce_length(string).",
)

end
