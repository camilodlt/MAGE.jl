# -*- coding: utf-8 -*-

""" `modulo`

Exports :

- **bundle\\_integer\\_modulo** :
    - `modulo`

"""
module integer_modulo

using ..UTCGP: FunctionBundle, append_method!

# ################## #
# MODULO             #
# ################## #

fallback(args...) = return 0

bundle_integer_modulo = FunctionBundle(fallback)

# FUNCTIONS ---

## modulo a%b
"""

    modulo(a::Number, b::Number, args...)

Returns a % b. 

Throws error if b == 0.
"""
function modulo(a::Number, b::Number, args...)
    return a % b
end

append_method!(bundle_integer_modulo, modulo)
end
