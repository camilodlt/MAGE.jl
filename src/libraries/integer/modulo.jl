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

Returns `a % b`, or `0` when `b == 0` (like `safe_div`): an integer modulo by
zero would throw and a float one would give `NaN`, which then spreads through
every node that uses it.
"""
function modulo(a::Number, b::Number, args...)
    b == 0 && return zero(a % one(b))   # 0 of the type a % b would have
    return a % b
end

append_method!(
    bundle_integer_modulo,
    modulo;
    description = "Remainder a % b; 0 when b == 0 (like safe_div).",
)
end
