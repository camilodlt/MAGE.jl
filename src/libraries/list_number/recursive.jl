

# # -*- coding: utf-8 -*-

""" Recursive functions 

Exports :

- **bundle\\_listnumber\\_recursive** :
    - `recsum`
    - `recmult`
    - `range_`

"""
module listnumber_recursive

using ..UTCGP: FunctionBundle, append_method!
import UTCGP: CONSTRAINED, SMALL_ARRAY, NANO_ARRAY, BIG_ARRAY

# ##################### #
# List NUMBER RECURSIVE #
# ##################### #

fallback(args...) = return Number[]

bundle_listnumber_recursive = FunctionBundle(fallback)

# FUNCTIONS ---

# RECURSIVE SUM
"""
    recsum(from::Vector{<:Number}, args...)

Returns the recursive sum of the elements in the vector.


The size of the return is the same as 
the size of the input.
"""
function recsum(from::Vector{<:Number}, args...)
    if CONSTRAINED
        bound = min(length(from), SMALL_ARRAY)
        from = from[begin:bound]
    end
    s = 0 # it will get promoted to the type of the other numbers
    rec_sum = [((i) -> (s += i; s))(i) for i in from]
    return identity.(rec_sum)
end

"""
    recmult(init_number::Number, mult_by::Number, n_times::Int, args...)

Multiplies recursively the `init_number` by `mult_by` `n_times`.

Returns the vector holding all the results. 
The first entry of the vector is returned as is. 
"""
function recmult(init_number::Number, mult_by::Number, n_times::Int, args...)
    @assert n_times < 10_000
    if CONSTRAINED
        @assert mult_by < 10000
        @assert mult_by > -10000
    end
    vec = []
    for i = 1:(n_times+1)
        push!(vec, init_number)
        init_number = init_number * mult_by
    end
    vec = identity.(vec)
    # print("recmult length : $(length(vec))")
    return vec
end

"""
    range_(max_n::Number)

Returns the range between 1 (inclusive) and max_n (inclusive).
"""
function range_(max_n::Number, args...)
    if CONSTRAINED
        @assert max_n <= SMALL_ARRAY
    end
    return collect(1:max_n)
end

append_method!(bundle_listnumber_recursive, recsum)
append_method!(bundle_listnumber_recursive, recmult)
append_method!(bundle_listnumber_recursive, range_)
end
