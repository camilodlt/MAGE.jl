# -*- coding: utf-8 -*-


""" Split Operations

Exports :

- **bundle\\_liststring\\_split** :
    - `split_string_to_vector`

"""
module liststring_split

using ..UTCGP: FunctionBundle, append_method!
import UTCGP: CONSTRAINED, SMALL_ARRAY, NANO_ARRAY, BIG_ARRAY

# ########### #
# String Grep #
# ########### #
fallback(args...) = return String[]

bundle_liststring_split = FunctionBundle(fallback)

# FUNCTIONS ---
""" 
"""
function split_string_to_vector(s::String, by::String, args...)
    if CONSTRAINED
        bound = min(length(s), SMALL_ARRAY)
        return String.(split(s[begin:bound], by))
    end
    return String.(split(s, by))
end


append_method!(bundle_liststring_split, split_string_to_vector)

end
