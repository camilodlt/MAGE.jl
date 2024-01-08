

# # -*- coding: utf-8 -*-

""" `Is` conditions: Return 1 or 0 for every element

Exports :

- **bundle\\_listinteger\\_iscond** :
    - `is_sup_0`
    - `is_eq_0`
    - `is_less_0`

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


append_method!(bundle_listinteger_iscond, is_sup_0)
append_method!(bundle_listinteger_iscond, is_eq_0)
append_method!(bundle_listinteger_iscond, is_less_0)
append_method!(bundle_listinteger_iscond, compare_tuple_a_gr_b)
append_method!(bundle_listinteger_iscond, compare_tuple_a_eq_b)
append_method!(bundle_listinteger_iscond, compare_tuple_a_less_b)
end
