# -*- coding: utf-8 -*-

""" Conditional functions

Exports :

- **bundle\\_element\\_conditional** :
    - `if_else_multiplexer`

"""
module element_conditional

using ..UTCGP: FunctionBundle, append_method!

# ################### #
#  CONDITIONAL        #
# ################### #

fallback(args...) = return nothing

bundle_element_conditional = FunctionBundle(fallback)

# FUNCTIONS ---

"""
    if_else_multiplexer(cond::Number, a::T, b::T, args...)

Returns `a` if `cond` > 0, `b` otherwise.
"""
function if_else_multiplexer(cond::Number, a::T, b::T, args...) where {T<:Any}
    if cond > 0
        return a
    else
        return b
    end
end


append_method!(bundle_element_conditional, if_else_multiplexer)

end

