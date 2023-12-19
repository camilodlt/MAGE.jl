# # -*- coding: utf-8 -*-

""" Lower Upper and Capitalize functions

Exports :

- **bundle\\_string\\_caps** :
    - `uppercase_`
    - `uppercase_at`
    - `uppercase_after`
    - `uppercase_char_after`
    - `uppercase_before`
    - `uppercase_char_before  `
    - `lowercase_`
    - `lowercase_at`
    - `lowercase_after`
    - `lowercase_char_after`
    - `lowercase_before`
    - `lowercase_char_before  `
    - `capitalize_first`
    - `capitalize_all`
    - `capitalize_list_string`

"""
module str_caps

using ..UTCGP: FunctionBundle, append_method!

# ################### #
# String Conditional  #
# ################### #

fallback(args...) = return ""

bundle_string_caps = FunctionBundle(fallback)

# FUNCTIONS ---


function _each_strict_match(sub::String, s::String; start::Bool)
    marks = []
    index = 1
    if isempty(sub)
        return marks
    end
    while index <= length(s)
        match = findnext(sub, s, index)
        if isnothing(match)
            break
        end
        if start
            push!(marks, match.start)
        else
            push!(marks, match.stop)
        end
        index = match.stop + 1
    end
    return marks
end

## UPPERCASE FUNCTIONS --- ---

"""
    uppercase_(s::String, args...)

Uppercases `s`
"""
function uppercase_(s::String, args...)
    return uppercase(s)
end

"""
    uppercase_at(s::String, at::Number, args...)

Uppercases `s` at a given index `at`. 

The index is clipped between 1 (the first index) and the length of `s` (the last index).
"""
function uppercase_at(s::String, at::Number, args...)
    at = trunc(Int, at)
    at = max(1, at) # in case at is < 1
    at = min(length(s), at) # in case the nb is too big
    tmp = collect(s)
    tmp[at] = uppercase(tmp[at])
    return join(tmp)
end



"""
    uppercase_after(s::String, after::String, args...)

Uppercases everything that comes after a match. 

If `after` is empty, it returns the string `s`.
"""
function uppercase_after(s::String, after::String, args...)
    tmp = collect(s)
    m = findnext(after, s, 1)
    if isnothing(m) || m.stop == 0
        return s
    end
    stop = m.stop
    if stop <= length(s) - 1
        tmp[stop+1:end] = uppercase.(tmp[stop+1:end])
    end
    return join(tmp)
end

"""
    uppercase_char_after(s::String, after::String, args...)

Uppercases one character that comes after a match. It does that for every match. 

If `after` is empty, it returns the string `s`.
"""
function uppercase_char_after(s::String, after::String, args...)
    tmp = collect(s)
    stops = _each_strict_match(after, s, start = false)
    for stop in stops
        if stop <= length(s) - 1 && stop !== 0
            tmp[stop+1] = uppercase(tmp[stop+1])
        end
    end
    return join(tmp)
end

# -- BEFORE 

"""
    uppercase_before(s::String, before::String, args...)

Uppercases everything that comes before a match. 

If `before` is empty, it returns the string `s`.
"""
function uppercase_before(s::String, before::String, args...)
    if isempty(before)
        return s
    end
    tmp = collect(s)
    m = findprev(before, s, length(s))
    if isnothing(m)
        return s
    end
    start = m.start
    if start > 1
        tmp[begin:start-1] = uppercase.(tmp[begin:start-1])
    end
    return join(tmp)
end



"""
    uppercase_char_before(s::String, before::String, args...)

Uppercases one character that comes before a match. It does that for every match. 

If `before` is empty, it returns the string `s`.
"""
function uppercase_char_before(s::String, before::String, args...)
    tmp = collect(s)
    starts = _each_strict_match(before, s, start = true)
    for start in starts
        if start > 1
            tmp[start-1] = uppercase(tmp[start-1])
        end
    end
    return join(tmp)
end


## LOWERCASE FUNCTIONS --- ---

"""
    lowercase_(s::String, args...)

Lowercases `s`
"""
function lowercase_(s::String, args...)
    return lowercase(s)
end

"""
    lowercase_at(s::String, at::Number, args...)

Lowercases `s` at a given index `at`. 

The index is clipped between 1 (the first index) and the length of `s` (the last index).
"""
function lowercase_at(s::String, at::Number, args...)
    at = trunc(Int, at)
    at = max(1, at) # in case at is < 1
    at = min(length(s), at) # in case the nb is too big
    tmp = collect(s)
    tmp[at] = lowercase(tmp[at])
    return join(tmp)
end


"""
    lowercase_after(s::String, after::String, args...)

Lowercases everything that comes after a match. 

If `after` is empty, it returns the string `s`.
"""
function lowercase_after(s::String, after::String, args...)
    tmp = collect(s)
    m = findnext(after, s, 1)
    if isnothing(m) || m.stop == 0
        return s
    end
    stop = m.stop
    if stop <= length(s) - 1
        tmp[stop+1:end] = lowercase.(tmp[stop+1:end])
    end
    return join(tmp)
end

"""
    lowercase_char_after(s::String, after::String, args...)

Lowercases one character that comes after a match. It does that for every match. 

If `after` is empty, it returns the string `s`.
"""
function lowercase_char_after(s::String, after::String, args...)
    tmp = collect(s)
    stops = _each_strict_match(after, s, start = false)
    for stop in stops
        if stop <= length(s) - 1 && stop !== 0
            tmp[stop+1] = lowercase(tmp[stop+1])
        end
    end
    return join(tmp)
end

# -- BEFORE 

"""
    lowercase_before(s::String, before::String, args...)

Lowercases everything that comes before a match. 

If `before` is empty, it returns the string `s`.
"""
function lowercase_before(s::String, before::String, args...)
    if isempty(before)
        return s
    end
    tmp = collect(s)
    m = findprev(before, s, length(s))
    if isnothing(m)
        return s
    end
    start = m.start
    if start > 1
        tmp[begin:start-1] = lowercase.(tmp[begin:start-1])
    end
    return join(tmp)
end



"""
    lowercase_char_before(s::String, before::String, args...)

Lowercases one character that comes before a match. It does that for every match. 

If `before` is empty, it returns the string `s`.
"""
function lowercase_char_before(s::String, before::String, args...)
    tmp = collect(s)
    starts = _each_strict_match(before, s, start = true)
    for start in starts
        if start > 1
            tmp[start-1] = lowercase(tmp[start-1])
        end
    end
    return join(tmp)
end

## CAPITALIZE FUNCTIONS --- ---
"""
    capitalize_first(s::String, args...)::String

Applies the `Base.uppercasefirst` function.

"""
function capitalize_first(s::String, args...)::String
    return uppercasefirst(s)
end

"""
    capitalize_all(s::String, args...)::String
Applies the `Base.titlecase` function.
"""
function capitalize_all(s::String, args...)::String
    return titlecase(s)
end

"""
    capitalize_list_string(strings::Vector{String}, args...)::Vector{String}

Broadccasts the `Base.titlecase` function to every element in the vector. 
"""
function capitalize_list_string(strings::Vector{String}, args...)::Vector{String}
    return titlecase.(strings)
end


append_method!(bundle_string_caps, uppercase_)
append_method!(bundle_string_caps, uppercase_at)
append_method!(bundle_string_caps, uppercase_after)
append_method!(bundle_string_caps, uppercase_char_after)
append_method!(bundle_string_caps, lowercase_)
append_method!(bundle_string_caps, lowercase_at)
append_method!(bundle_string_caps, lowercase_after)
append_method!(bundle_string_caps, lowercase_char_after)

append_method!(bundle_string_caps, uppercase_before)
append_method!(bundle_string_caps, uppercase_char_before)
append_method!(bundle_string_caps, lowercase_before)
append_method!(bundle_string_caps, lowercase_char_before)

append_method!(bundle_string_caps, capitalize_first)
append_method!(bundle_string_caps, capitalize_all)
append_method!(bundle_string_caps, capitalize_list_string)
end
