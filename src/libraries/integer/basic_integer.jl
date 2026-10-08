# -*- coding: utf-8 -*-

"""
Basic `Int` operators.

# Bundles

- [`bundle_integer_basic`](@ref)

The exhaustive, always-current list of operators in each bundle is on the
[Bundle Catalogue](@ref) page.
"""
module integer_basic

using ..UTCGP: FunctionBundle, append_method!

# ################### #
# IDENTITY            #
# ################### #

fallback(args...) = return 0

"""
    bundle_integer_basic

Integer basics: `identity_int` and the constant `ret_1`.
"""
bundle_integer_basic = FunctionBundle(fallback)

# FUNCTIONS ---

## is superatior than 0
"""
    identity_int(from::Int, args...)
"""
function identity_int(from::Int, args...)
    return identity(from)
end

"""
    ret_1()
Returns 1
"""
function ret_1(args...)
    return 1
end

append_method!(
    bundle_integer_basic,
    identity_int;
    description = "Returns the integer input unchanged.",
)
append_method!(
    bundle_integer_basic,
    ret_1;
    description = "Returns the constant integer value 1.",
)
end
