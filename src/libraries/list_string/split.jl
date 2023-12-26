# -*- coding: utf-8 -*-


""" Split Operations

Exports :

- **bundle\\_list_string\\_split** :
    - split_string_to_vector

"""
module list_string_split

using ..UTCGP: FunctionBundle, append_method!

# ########### #
# String Grep #
# ########### #
fallback(args...) = return String[]

bundle_list_string_split = FunctionBundle(fallback)

# FUNCTIONS ---
""" 
"""
function split_string_to_vector(s::String, by::String, args...)::Vector{String}
    return split(s, by)
end


append_method!(bundle_list_string_split, split_string_to_vector)

end
