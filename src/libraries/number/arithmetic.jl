# -*- coding: utf-8 -*-

"""
Scalar arithmetic.

The fallback returns an `Int`. To target another type, re-point the bundle with
`update_caster!` and `update_fallback!`.

# Bundles

- [`bundle_number_arithmetic`](@ref)
- [`bundle_number_arithmetic_sr`](@ref)

The exhaustive, always-current list of operators in each bundle is on the
[Bundle Catalogue](@ref) page.
"""
module number_arithmetic

using ..UTCGP: FunctionBundle, append_method!

# ################### #
# NUMBER ARITHMETIC   #
# ################### #

fallback(args...) = return 0

"""
    bundle_number_arithmetic

Scalar arithmetic: `number_sum`, `number_minus`, `number_mult`, `number_div`,
`power_of`, and `safe_div`, which returns `0` instead of failing on a zero
denominator.
"""
bundle_number_arithmetic = FunctionBundle(fallback)

"""
    bundle_number_arithmetic_sr

Unary arithmetic used by symbolic regression: `number_square`, `number_cube`,
`number_negate`, and `number_inverse`, which returns `0` for a zero input. Kept
apart from `bundle_number_arithmetic` so libraries built from that bundle are
unchanged.
"""
bundle_number_arithmetic_sr = FunctionBundle(fallback)

# FUNCTIONS ---

## sum
"""
    number_sum(a::Number, b::Number, args...)
Returns `a`+`b`
"""
function number_sum(a::Number, b::Number, args...)
    return a + b
end

## Minus 
"""
    number_minus(a::Number, b::Number, args...)
Returns `a`-`b`
"""
function number_minus(a::Number, b::Number, args...)
    return a - b
end

## mult
"""
    number_mult(a::Number, b::Number, args...)
Returns `a`*`b`
"""
function number_mult(a::Number, b::Number, args...)
    return a * b
end

## div
"""
    number_div(a::Number, b::Number, args...)

Throws `DivideError` if the divisor is equal to 0.

Returns `a`/`b`
"""
function number_div(a::Number, b::Number, args...)
    if b == 0
        throw(DivideError())
    end
    return a / b
end

## safe div
"""
    safe_div(a::Number, b::Number, args...)

If the divisor is equal (`==`) to 0, then the function returns 0 and does not 
raise an Error. 

Else, the division works as expected. 
"""
function safe_div(a::Number, b::Number, args...)
    if b == 0
        return b
    end
    return a / b
end


## Power of
"""
    power_of(a::Number, b::Number, args...)

`a` ^ `b`.
"""
function power_of(a::Number, b::Number, args...)
    return a^b
end

## Square, cube, negate, inverse
"""
    number_square(a::Number, args...)
Returns `a`²
"""
function number_square(a::Number, args...)
    return a * a
end

"""
    number_cube(a::Number, args...)
Returns `a`³
"""
function number_cube(a::Number, args...)
    return a * a * a
end

"""
    number_negate(a::Number, args...)
Returns `-a`
"""
function number_negate(a::Number, args...)
    return -a
end

"""
    number_inverse(a::Number, args...)

Returns `1/a`, or `0` when `a` is zero (same protection as `safe_div`).
"""
function number_inverse(a::Number, args...)
    if a == 0
        return zero(a)
    end
    return 1 / a
end

append_method!(
    bundle_number_arithmetic,
    number_sum;
    description = "Adds two numeric inputs.",
)
append_method!(
    bundle_number_arithmetic,
    number_minus;
    description = "Subtracts the second numeric input from the first.",
)
append_method!(
    bundle_number_arithmetic,
    number_mult;
    description = "Multiplies two numeric inputs.",
)
append_method!(
    bundle_number_arithmetic,
    number_div;
    description = "Divides the first numeric input by the second and throws on division by zero.",
)
append_method!(
    bundle_number_arithmetic,
    safe_div;
    description = "Divides two numeric inputs and returns 0 when the divisor is zero.",
)
append_method!(
    bundle_number_arithmetic,
    power_of;
    description = "Raises the first numeric input to the power of the second.",
)
append_method!(
    bundle_number_arithmetic_sr,
    number_square;
    description = "Squares the numeric input.",
)
append_method!(
    bundle_number_arithmetic_sr,
    number_cube;
    description = "Cubes the numeric input.",
)
append_method!(
    bundle_number_arithmetic_sr,
    number_negate;
    description = "Negates the numeric input.",
)
append_method!(
    bundle_number_arithmetic_sr,
    number_inverse;
    description = "Returns the reciprocal of the numeric input, or 0 when the input is zero.",
)

end
