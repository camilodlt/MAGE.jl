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
    return reverse.(strings)
end

"""
    numbers_to_string(strings::Vector{<:Number}, args...)

Casts each number to string.
"""
function numbers_to_string(strings::Vector{<:Number}, args...)
    return string.(strings)
end

# APPEND ---
append_method!(bundle_liststring_broadcast, reverse_broadcast)
append_method!(bundle_liststring_broadcast, numbers_to_string)
end

