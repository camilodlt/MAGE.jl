# -*- coding: utf-8 -*-

"""
Transcendental constants and functions.

The fallback returns `0`. To target another type, re-point the bundle with
`update_caster!` and `update_fallback!`.

# Bundles

- [`bundle_number_transcendental`](@ref)

The exhaustive, always-current list of operators in each bundle is on the
[Bundle Catalogue](@ref) page.
"""
module number_transcendental

using ..UTCGP: FunctionBundle, append_method!

# ##################### #
# NUMBER TRANSCENDENTAL #
# ##################### #

fallback(args...) = return 0

"""
    bundle_number_transcendental

Transcendental scalars: the constant `pi_`, and `exp_`, `log_`, `log10_`.
"""
bundle_number_transcendental = FunctionBundle(fallback)

# FUNCTIONS ---

## π

"""
    pi_(args...)

Returns π
"""
function pi_(args...)
    return Float64(π)
end

## Exp
"""
    exp_(a::Number, args...)

Returns `exp(a)`
"""
function exp_(a::Number, args...)
    return exp(a)
end

## Base log
"""
    log_(a::Number, args...)

`a` is clipped in the lower bound. The minimum value is 
0+ 1/(10^10)

Returns `log(a)`
"""
function log_(a::Number, args...)
    a = max(a, 0 + 1 / (10^10))
    return log(a)
end

## Log Base 10
"""
    log10_(a::Number, args...)

`a` is clipped in the lower bound. The minimum value is 
0+ 1/(10^10)

Returns `log10(a)`
"""
function log10_(a::Number, args...)
    a = max(a, 0 + 1 / (10^10))
    return log10(a)
end

append_method!(
    bundle_number_transcendental,
    pi_;
    description = "Returns the mathematical constant pi as Float64.",
)
append_method!(
    bundle_number_transcendental,
    exp_;
    description = "Computes the exponential of the numeric input.",
)
append_method!(
    bundle_number_transcendental,
    log_;
    description = "Computes the natural logarithm after clipping the input to a positive minimum.",
)
append_method!(
    bundle_number_transcendental,
    log10_;
    description = "Computes the base-10 logarithm after clipping the input to a positive minimum.",
)

end
