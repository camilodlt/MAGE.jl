# -*- coding: utf-8 -*-

""" Combinatios of 2 elements

Exports :

- **bundle\\_listtuple\\_mappings** :
    - `mappings`

"""
module listtuple_mappings
import ..UTCGP: FunctionBundle, append_method!, FunctionWrapper
import UTCGP: CONSTRAINED, SMALL_ARRAY, NANO_ARRAY, BIG_ARRAY

# ######### #
# MAPPINGS  #
# ######### #

fallback() = [(nothing, nothing)]
bundle_listtuple_mappings = FunctionBundle(fallback)
bundle_listtuple_mappings_factory = FunctionBundle(fallback)

###############
# FUNCTIONS 
###############

# Mappings a=>b --- 
function mappings_a_to_b_factory(T::DataType)
    return @eval ((from::Vector{V}, to::Vector{V}, args...) where {V<:$T}) -> begin
        if CONSTRAINED
            @assert length(from) <= SMALL_ARRAY
            @assert length(to) <= SMALL_ARRAY
        end
        tuples = [(a, b) for (a, b) in zip(from, to)]
        return tuples
    end
end

"""
    mappings_a_to_b (from::Vector{T}, to::Vector{T}, args...) 

Creates a=>b mappings in the form of Vector{Tuple{a,b}}.
"""
mappings_a_to_b = mappings_a_to_b_factory(Any)


#########
# APPEND
#########

# Normal Bundle ---
append_method!(bundle_listtuple_mappings, mappings_a_to_b, :mappings_a_to_b)

# Factory rundle ---
append_method!(bundle_listtuple_mappings_factory, mappings_a_to_b_factory, :mappings_a_to_b)

end

