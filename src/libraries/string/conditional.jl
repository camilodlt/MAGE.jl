# # -*- coding: utf-8 -*-

""" Conditional Operations

Exports :

- **bundle\\_string\\_conditional** :
    - `if_string`
    - `if_not_string`
    - `if_else_string`
    - `longest_string`
    - `shortest_string`

"""
module str_conditional

using ..UTCGP: FunctionBundle, append_method!

# ################### #
# String Conditional  #
# ################### #

fallback(args...) = return ""

bundle_string_conditional = FunctionBundle(fallback)

# FUNCTIONS ---

# ---  IF, NOT IF and IF ELSE

""" 
    if_string(s::String, cond::Number, args...)::String

Returns the string `s` if the cond is different than 0. Else an empty string is returned.

`cond` is a `Number`, it is `trunc` to Int before comparison with 0. 
"""
function if_string(s::String, cond::Number, args...)::String
    cond = trunc(Int, cond)
    if cond !== 0
        return s
    end
    return ""
end

""" 
    if_not_string(s::String, cond::Number, args...)::String

This functions is the inverse of `if_string`.

Returns the string `s` if the cond is equal to 0. Else an empty string is returned.
`cond` is a `Number`, it is `trunc` to Int before comparison with 0. 
"""
function if_not_string(s::String, cond::Number, args...)::String
    cond = trunc(Int, cond)
    if cond === 0
        return s
    end
    return ""
end

""" 
    if_else_string(s1::String, s2::String, cond::Number, args...)::String

Returns the string `s1` if the cond is different than 0. Else `s2` is returned.
`cond` is a `Number`, it is `trunc` to Int before comparison with 0. 

"""
function if_else_string(s1::String, s2::String, cond::Number, args...)::String
    cond = trunc(Int, cond)
    if cond !== 0
        return s1
    end
    return s2
end


# ---  IF, NOT IF and IF ELSE

"""
    longest_string(s1::String, s2::String, args...)::String

Returns the longest string between `s1` and `s2`. 
If the length is the same, it returns `s1`.

"""
function longest_string(s1::String, s2::String, args...)::String
    a = length(s1)
    b = length(s2)
    if a > b || a == b
        return s1
    end
    return s2
end
"""
    shortest_string(s1::String, s2::String, args...)::String

Returns the shortest string between `s1` and `s2`. 
If the length is the same, it returns `s1`.

"""
function shortest_string(s1::String, s2::String, args...)::String
    a = length(s1)
    b = length(s2)
    if a < b || a == b
        return s1
    end
    return s2
end

append_method!(bundle_string_conditional, if_string)
append_method!(bundle_string_conditional, if_not_string)
append_method!(bundle_string_conditional, if_else_string)
append_method!(bundle_string_conditional, longest_string)
append_method!(bundle_string_conditional, shortest_string)

end
