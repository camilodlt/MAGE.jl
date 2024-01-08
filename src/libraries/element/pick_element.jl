# -*- coding: utf-8 -*-

""" Pick one element from a vector.

The type returned depends on the type of the element at a certain index.

Exports :

- **bundle\\_element\\_pick** :
    - `pick_element_from_vector`

"""
module element_pick

using ..UTCGP: FunctionBundle, append_method!

# ################### #
# Pick From Vector    #
# ################### #

fallback(args...) = return nothing

bundle_element_pick = FunctionBundle(fallback)

# FUNCTIONS ---

## Pick One element

"""
    pick_element_from_vector(vec::Vector{<:Any}, at::Int, args...)

Returns the element in vec at `at` index.
"""
function pick_element_from_vector(vec::Vector{<:Any}, at::Int, args...)
    return vec[at]
end


## Pick first Element
## Pick Middle Element
## Pick Last Element

"""
    pick_last_element(vec::Vector{<:Any}, args...)

Returns the element last element in `vec`.
Throws BoundsError if the vector is empty
"""
function pick_last_element(vec::Vector{<:Any}, args...)
    return vec[end]
end

append_method!(bundle_element_pick, pick_element_from_vector)
# append_method!(bundle_element_pick, pick_element_from_vector)
# append_method!(bundle_element_pick, pick_element_from_vector)
append_method!(bundle_element_pick, pick_last_element)

end
