# -*- coding: utf-8 -*-
"""
Basic vectors 
 
Exports : **bundle\\_listnumber\\_basic**: 
- `ones_`
- `zeros_`

"""
module listnumber_basic

import ..UTCGP: FunctionBundle, append_method!, FunctionWrapper
import UTCGP: CONSTRAINED, SMALL_ARRAY, NANO_ARRAY, BIG_ARRAY

fallback(args...) = Number[]

bundle_listnumber_basic = FunctionBundle(fallback)

VECTORNUM = Vector{<:Number}

# ONES

"""
    ones_(v::VECTORNUM, args...)

"Ones_like"
"""
function ones_(v::VECTORNUM, args...)
    if CONSTRAINED[]
        bound = min(length(v), SMALL_ARRAY[])
        return ones(length(v[begin:bound]))
    end
    return ones(length(v))
end

"""
    ones_(n::Int, args...)

`n` ones.
"""
function ones_(n::Int, args...)
    n_::Int = 0
    if CONSTRAINED[]
        n_ += min(SMALL_ARRAY[], n)
        return ones(n_)
    end
    return ones(n)
end


# ZEROS

"""
    zeros_(v::VECTORNUM, args...)

"zeros_like"
"""
function zeros_(v::VECTORNUM, args...)
    if CONSTRAINED[]
        bound = min(length(v), SMALL_ARRAY[])
        return zeros(length(v[begin:bound]))
    end
    return zeros(length(v))
end

"""
    zeros_(n::Int, args...)

`n` zeros.
"""
function zeros_(n::Int, args...)
    if CONSTRAINED[]
        n_ = min(SMALL_ARRAY[], n)
        return zeros(n_)
    end
    return zeros(n)
end

append_method!(bundle_listnumber_basic, ones_)
append_method!(bundle_listnumber_basic, zeros_)
end
