# -*- coding: utf-8 -*-

""" Basic Int functions

Exports :

- **bundle\\_integer\\_basic** :
    - `identity_int`

"""
module integer_basic

using ..UTCGP: FunctionBundle, append_method!

# ################### #
# IDENTITY            #
# ################### #

fallback(args...) = return 0

bundle_integer_basic = FunctionBundle(fallback)

# FUNCTIONS ---

## is superatior than 0
"""
    identity_int(from::Int, args...)
"""
function identity_int(from::Int, args...)
    return identity(from)
end

append_method!(bundle_integer_basic, identity_int)
end
