# -*- coding: utf-8 -*-

"""
Pick one element out of a vector.

The type returned is the type of the element, so these operators are what let a
list chromosome feed a scalar one.

# Bundles

- [`bundle_element_pick`](@ref)

The exhaustive, always-current list of operators in each bundle is on the
[Bundle Catalogue](@ref) page.
"""
module element_pick

using ..UTCGP: FunctionBundle, append_method!

# ################### #
# Pick From Vector    #
# ################### #

fallback(args...) = return nothing

"""
    bundle_element_pick

Read one element out of a vector: `pick_element_from_vector` (by index) and
`pick_last_element`.

The chromosome type is the *element* type, so this is how a list chromosome
feeds a scalar one.
"""
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

append_method!(
    bundle_element_pick,
    pick_element_from_vector;
    description = "Returns the element located at the requested index in the input vector.",
)
append_method!(
    bundle_element_pick,
    pick_last_element;
    description = "Returns the last element of the input vector.",
)

end
