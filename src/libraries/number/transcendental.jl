# -*- coding: utf-8 -*-

""" Transcendental constants and fns 

The default is int for the `fallback` to 0 .  
To cast to other types, use `update_caster!` and `update_fallback!`

Exports :

- **bundle\\_number\\_transcendental** :
    - `pi_`
    - `exp_`
    - `log_`
    - `log10_`

"""
module number_transcendental

using ..UTCGP: FunctionBundle, append_method!

# ##################### #
# NUMBER TRANSCENDENTAL #
# ##################### #

fallback(args...) = return 0

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

append_method!(bundle_number_transcendental, pi_)
append_method!(bundle_number_transcendental, exp_)
append_method!(bundle_number_transcendental, log_)
append_method!(bundle_number_transcendental, log10_)

end
