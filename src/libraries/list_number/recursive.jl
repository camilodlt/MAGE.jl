

# # -*- coding: utf-8 -*-

""" Recursive functions 

Exports :

- **bundle\\_listnumber\\_recursive** :
    - `recsum`

"""
module listnumber_recursive

using ..UTCGP: FunctionBundle, append_method!

# ##################### #
# List NUMBER RECURSIVE #
# ##################### #

fallback(args...) = return Number[]

bundle_listnumber_recursive = FunctionBundle(fallback)

# FUNCTIONS ---

# RECURSIVE SUM
"""
    recsum(from::Vector{<:Number}, args...)

Returns the recursive sum of the elements in the vector.


The size of the return is the same as 
the size of the input.
"""
function recsum(from::Vector{<:Number}, args...)
    s = 0 # it will get promoted to the type of the other numbers
    rec_sum = [((i) -> (s += i; s))(i) for i in from]
    return identity.(rec_sum)
end

append_method!(bundle_listnumber_recursive, recsum)
end
