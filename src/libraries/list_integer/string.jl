# # -*- coding: utf-8 -*-

""" String to list of Ints

Exports :

- **bundle\\_listinteger\\_string** :
    - `match_with_overlap`
    - `parse_from_list_string`
"""
module listinteger_string
using Debugger

using ..UTCGP: FunctionBundle, append_method!
import UTCGP: CONSTRAINED, SMALL_ARRAY, NANO_ARRAY, BIG_ARRAY

# ########### #
# String Grep #
# ########### #

fallback(args...) = return Int[]

bundle_listinteger_string = FunctionBundle(fallback)

# FUNCTIONS ---

"""
    match_with_overlap(s::String, pattern::String)

Returns the indices of the start of the overlaping matches between `s` and the `pattern`.

Kind of like python's `re.findall` with the option `overlapped=True`.
"""
function match_with_overlap(s::String, pattern::String, args...)
    if CONSTRAINED[]
        @assert length(s) < 100000
    end
    cond = true
    starts = Int[]
    start = 1
    while cond
        f = findnext(pattern, s, start)
        if isnothing(f)
            cond = false
        else
            push!(starts, f.start)
            start = f.start + 1
        end
    end
    return starts
end

"""
    parse_from_list_string(v::Vector{String}, args...)

Parse all the strings to Integers. 
If any of the strings is not convertible, it will throw an Argument Error.
Decimal numbers are parsed as Float64 but then floored to Int.
"""
function parse_from_list_string(v::Vector{String}, args...)
    v2 = parse.(Float64, v)
    v2 = floor.(Int, v2)
    return v2
end

"""
    length_broadcast(v::Vector{String}, args...)

Broadcasts `length` to every element in `v`
"""
function length_broadcast(v::Vector{String}, args...)
    if CONSTRAINED[]
        m = min(length(v), SMALL_ARRAY[])
        return length.(v[begin:m])
    end
    return length.(v)
end

# APPEND ---
append_method!(bundle_listinteger_string, match_with_overlap)
append_method!(bundle_listinteger_string, parse_from_list_string)
append_method!(bundle_listinteger_string, length_broadcast)

end

