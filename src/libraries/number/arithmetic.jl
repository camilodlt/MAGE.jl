# -*- coding: utf-8 -*-

""" Simple arithmetic functions

The default is int for the `fallback`. 
To cast to other types, use `update_caster!` and `update_fallback!`
Exports :

- **bundle\\_number\\_arithmetic** :
    - `number_sum`
    - `number_minus`
    - `number_mult`
    - `number_div`
    - `safe_div`
    - `power_of`

"""
module number_arithmetic

using ..UTCGP: FunctionBundle, append_method!

# ################### #
# NUMBER ARITHMETIC   #
# ################### #

fallback(args...) = return 0

bundle_number_arithmetic = FunctionBundle(fallback)

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
        throw(DivideError)
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

end
