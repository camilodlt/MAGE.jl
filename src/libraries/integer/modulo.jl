# -*- coding: utf-8 -*-

"""
Modulo arithmetic.

# Bundles

- [`bundle_integer_modulo`](@ref)

The exhaustive, always-current list of operators in each bundle is on the
[Bundle Catalogue](@ref) page.
"""
module integer_modulo

using ..UTCGP: FunctionBundle, append_method!

# ################## #
# MODULO             #
# ################## #

fallback(args...) = return 0

"""
    bundle_integer_modulo

`modulo`: remainder of a division.
"""
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

append_method!(
    bundle_integer_modulo,
    modulo;
    description = "Computes the modulo remainder a % b for two numeric inputs.",
)
end
