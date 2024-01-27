# -*- coding: utf-8 -*-

""" Divisors of a number

Exports :

- **bundle\\_listinteger\\_primes** :
    - `int_divisors`
"""
module listinteger_primes

using ..UTCGP: FunctionBundle, append_method!
using Primes

# ########### #
# PRIMES      #
# ########### #

fallback(args...) = return Int[]

bundle_listinteger_primes = FunctionBundle(fallback)

# FUNCTIONS ---

## Divisors for an Int
"""

    int_divisors(n::Int, args...)

Returns the divisors for an integer.
"""
function int_divisors(n::Int, args...)
    return divisors(n)
end

append_method!(bundle_listinteger_primes, int_divisors)
end
