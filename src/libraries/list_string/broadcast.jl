# -*- coding: utf-8 -*-

""" 
Broadcast some operations to every element in a list of strings.

Exports :

- **bundle\\_string\\_broadcast** :
    - `reverse_broadcast`
    - `numbers_to_string`

"""
module liststring_broadcast

using ..UTCGP: FunctionBundle, append_method!
import UTCGP: CONSTRAINED, SMALL_ARRAY, NANO_ARRAY, BIG_ARRAY

# ################### #
# FUNCTIONS           #
# ################### #

fallback(args...) = return String[]

bundle_liststring_broadcast = FunctionBundle(fallback)


"""
    reverse_broadcast(strings::Vector{String}, args...)

Reverse every element in the vector
"""
function reverse_broadcast(strings::Vector{String}, args...)
    if CONSTRAINED
        bound = min(length(strings), SMALL_ARRAY)
        return reverse.(strings[begin:bound])
    end
    return reverse.(strings)
end

"""
    numbers_to_string(strings::Vector{<:Number}, args...)

Casts each number to string.
"""
function numbers_to_string(strings::Vector{<:Number}, args...)
    if CONSTRAINED
        bound = min(length(strings), SMALL_ARRAY)
        return string.(strings[begin:bound])
    end
    return string.(strings)
end

# APPEND ---
append_method!(bundle_liststring_broadcast, reverse_broadcast)
append_method!(bundle_liststring_broadcast, numbers_to_string)
end

