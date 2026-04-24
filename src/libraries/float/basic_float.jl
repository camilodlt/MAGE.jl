""" Basic Int functions

Exports :

- **bundle\\_float\\_basic** :
    - `identity_float`

"""
module float_basic

using DispatchDoctor
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


function tanh_(x::T, args...) where {T <: Number}
    return tanh(x)
end

function relu_(x::T, args...) where {T <: Number}
    return ifelse(x > zero(T), x, zero(T))
end

append_method!(
    bundle_float_basic,
    identity_float;
    description = "Returns the input Float64 value unchanged.",
)
append_method!(
    bundle_float_basic,
    ret_1;
    description = "Returns the constant float value 1.0.",
)
append_method!(
    bundle_float_basic,
    tanh_,
    :tanh;
    description = "Applies hyperbolic tangent to a numeric input.",
)
append_method!(
    bundle_float_basic,
    relu_,
    :relu;
    description = "Applies ReLU by returning max(x, 0) for numeric inputs.",
)
end
