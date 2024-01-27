# -*- coding: utf-8 -*-

""" `Is` conditions: Return 1 or 0 for every element

Exports :

- **bundle\\_listinteger\\_iscond** :
    - `is_sup_0`
    - `is_eq_0`
    - `is_less_0`
    - `is_eq_to`
    - `compare_tuple_a_gr_b`
    - `compare_tuple_a_eq_b`
    - `compare_tuple_a_less_b`
    - `is_more_than_right`
    - `is_more_eq_than_right`
    - `is_eq_to_prev`
    - `even_indices_mask`
    - `odd_indices_mask`
    - `mask`
    - `inverse_mask`
    - `greater_than_broadcast`
    - `less_than_broadcast`
    - `eq_broadcast`
    - `compare_two_vectors`

"""
module listinteger_iscond

using ..UTCGP: FunctionBundle, append_method!

# ################### #
# NUMBER REDUCE       #
# ################### #

fallback(args...) = return Int[]

bundle_listinteger_iscond = FunctionBundle(fallback)

# FUNCTIONS ---

## is superatior than 0
"""

    is_sup_0(from::Vector{<:Number}, args...)

Indicator function. 1 where element is > 0
"""
function is_sup_0(from::Vector{<:Number}, args...)
    return Int.(from .> 0)
end

## is equal to 0
"""

    is_eq_0(from::Vector{<:Number}, args...)

Indicator function. 1 where element is == 0
"""
function is_eq_0(from::Vector{<:Number}, args...)
    return Int.(from .== 0)
end

## is less than 0
"""

    is_less_0(from::Vector{<:Number}, args...)

Indicator function. 1 where element is < 0
"""
function is_less_0(from::Vector{<:Number}, args...)
    return Int.(from .< 0)
end



##################################
# Is Eq to a number #
##################################

"""
    is_eq_to(from::Vector{<:Number}, to::Number, args...)

Indicator function. 1 where element is `==` to `to`.
"""
function is_eq_to(from::Vector{<:Number}, to::Number, args...)
    return Int.(from .== to)
end

##################################
# FROM VECTOR TO 2 Number tuples #
##################################

"""
    compare_tuple_a_gr_b(combinations::Vector{Tuple{T,T}}, args...) where {T<:Number}

For every tuple of elements (a,b), return whether a>b.
"""
function compare_tuple_a_gr_b(combinations::Vector{Tuple{T,T}}, args...) where {T<:Number}
    odds = [Int(a > b) for (a, b) in combinations]
    return odds
end
"""
    compare_tuple_a_eq_b(combinations::Vector{Tuple{T,T}}, args...) where {T<:Number}

For every tuple of elements (a,b), return whether a==b.
"""
function compare_tuple_a_eq_b(combinations::Vector{Tuple{T,T}}, args...) where {T<:Number}
    odds = [Int(a == b) for (a, b) in combinations]
    return odds
end
"""
    compare_tuple_a_less_b(combinations::Vector{Tuple{T,T}}, args...) where {T<:Number}

For every tuple of elements (a,b), return whether a<b.
"""
function compare_tuple_a_less_b(combinations::Vector{Tuple{T,T}}, args...) where {T<:Number}
    odds = [Int(a < b) for (a, b) in combinations]
    return odds
end

"""
    is_more_than_right(x::Vector{T}, args...)

Returns a vector of the same size where each element is :
    - 1 if the element is > than all elements to the right (one by one) 
    - 0 otherwise 
"""
function is_more_than_right(x::Vector{T}, args...) where {T<:Number}
    l = T[]
    for (ith, n) in enumerate(x)
        is_l = Int(all(n .> x[ith+1:end]))
        push!(l, is_l)
    end
    return l
end

"""
    is_more_than_right(x::Vector{T}, args...)

Returns a vector of the same size where each element is :
    - 1 if the element is >= than all elements to the right (one by one)  
    - 0 otherwise 
"""
function is_more_eq_than_right(x::Vector{T}, args...) where {T<:Number}
    l = T[]
    for (ith, n) in enumerate(x)
        is_l = Int(all(n .>= x[ith+1:end]))
        push!(l, is_l)
    end
    return l
end

"""
    is_eq_to_prev(v::Vector{T}, args...) where {T}

Returns a vector of the same size as `v` where each element is :
- 1 if the element is == to the previous element
- 0 otherwise

The first element is always 0.
"""
function is_eq_to_prev(v::Vector{T}, args...) where {T}
    is_eq = zeros(Int, length(v))
    for (pos, cur) in enumerate(v)
        if pos > 1
            if cur == v[pos-1]
                is_eq[pos] = 1
            end
        end
    end
    return Int.(is_eq)
end

"""
    even_indices_mask(v::Vector{<:Any}, args...)

Retunrs a vector of the same size where an element is : 

    - 1 if the index is even
    - 0 otherwise
"""
function even_indices_mask(v::Vector{<:Any}, args...)
    return [(i % 2 == 0) ? 1 : 0 for (i, _) in enumerate(v)]
end

"""
    odd_indices_mask(v::Vector{<:Any}, args...)

Retunrs a vector of the same size where an element is : 

    - 1 if the index is odd
    - 0 otherwise
"""
function odd_indices_mask(v::Vector{<:Any}, args...)
    return [(i % 2 != 0) ? 1 : 0 for (i, _) in enumerate(v)]
end

####### 
# MASK 
#######
"""
    mask(v::Vector{<:Number}, args...)

Returns a vector of the same size as `v` where each element is : 
    - 1 if the element is > to 0 
    - 0 otherwise
"""
function mask(v::Vector{<:Number}, args...)
    return Int.(v .> 0)
end

"""
    inverse_mask(v::Vector{<:Number}, args...)

Returns a vector of the same size as `v` where each element is : 
    - 0 if the element is > to 0 
    - 1 otherwise
"""
function inverse_mask(v::Vector{<:Number}, args...)
    return Int.(v .<= 0)
end

###################
# Broadcast Compare 
###################

"""
    greater_than_broadcast(v::Vector{<:Number}, than::Number, args...)

Returns a list of the same size as `v` where each element is : 
    - 1 of the element is > than `than`
    - 0 otherwise
"""
function greater_than_broadcast(v::Vector{<:Number}, than::Number, args...)
    return Int.(v .> than)
end

"""
    less_than_broadcast(v::Vector{<:Number}, than::Number, args...)

Returns a list of the same size as `v` where each element is : 
    - 1 of the element is < than `than`
    - 0 otherwise
"""
function less_than_broadcast(v::Vector{<:Number}, than::Number, args...)
    return Int.(v .< than)
end

"""
    eq_broadcast(v::Vector{<:Number}, than::Number, args...)

Returns a list of the same size as `v` where each element is : 
    - 1 of the element is == than `than`
    - 0 otherwise
"""
function eq_broadcast(v::Vector{<:Number}, than::Number, args...)
    return Int.(v .== than)
end


# ################ #
# COMPARE VECTORS  #
# ################ #

"""
"""
function compare_two_vectors(v1::Vector{T}, v2::Vector{T}, args...) where {T}
    @assert length(v1) == length(v2)
    return Int.(v1 .== v2)
end

append_method!(bundle_listinteger_iscond, is_sup_0)
append_method!(bundle_listinteger_iscond, is_eq_0)
append_method!(bundle_listinteger_iscond, is_less_0)
append_method!(bundle_listinteger_iscond, is_eq_to)
append_method!(bundle_listinteger_iscond, compare_tuple_a_gr_b)
append_method!(bundle_listinteger_iscond, compare_tuple_a_eq_b)
append_method!(bundle_listinteger_iscond, compare_tuple_a_less_b)
append_method!(bundle_listinteger_iscond, is_more_than_right)
append_method!(bundle_listinteger_iscond, is_more_eq_than_right)
append_method!(bundle_listinteger_iscond, is_eq_to_prev)

append_method!(bundle_listinteger_iscond, even_indices_mask)
append_method!(bundle_listinteger_iscond, odd_indices_mask)

append_method!(bundle_listinteger_iscond, mask)
append_method!(bundle_listinteger_iscond, inverse_mask)

append_method!(bundle_listinteger_iscond, greater_than_broadcast)
append_method!(bundle_listinteger_iscond, less_than_broadcast)
append_method!(bundle_listinteger_iscond, eq_broadcast)

# COMPARE VECTORS
append_method!(bundle_listinteger_iscond, compare_two_vectors)
end
