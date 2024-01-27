# -*- coding: utf-8 -*-

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

append_method!(bundle_float_basic, identity_float)
end
