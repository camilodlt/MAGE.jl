""" Basic Int functions

Exports :

- **bundle\\_float\\_basic** :
    - `identity_float`

"""
module float_basic

using ..UTCGP: FunctionBundle, append_method!

# ################### #
# IDENTITY            #
# ################### #

fallback(args...) = return 0

bundle_float_basic = FunctionBundle(fallback)

# FUNCTIONS ---

"""
    identity_float(from::Int, args...)
"""
function identity_float(from::Float64, args...)
    return identity(from)
end

"""
    ret_1(args...)
"""
function ret_1(args...)
    return 1.0
end


function tanh_(x::Float64, args...)
    return tanh(x)
end
function relu_(x::Float64, args...)
    return ifelse(x > 0, x, 0)
end

append_method!(bundle_float_basic, identity_float)
append_method!(bundle_float_basic, ret_1)
append_method!(bundle_float_basic, tanh_, :tanh)
append_method!(bundle_float_basic, relu_, :relu)
end
