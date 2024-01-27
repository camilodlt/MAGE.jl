# # -*- coding: utf-8 -*-

""" `find` conditions and return the position

Exports :

- **bundle\\_integer\\_find** :
    - `find_first`
    - `index_of_first_true`

"""
module integer_find

using ..UTCGP: FunctionBundle, append_method!

# ################### #
# FIND                #
# ################### #

fallback(args...) = return 0

bundle_integer_find = FunctionBundle(fallback)

# FUNCTIONS ---

## is superatior than 0
"""
    find_first(from::Vector{<:Number}, what::Number, args...)

Returns the position of the first match between elements in `from` and `what`.

If there is no match, it returns 0. 

"""
function find_first(from::Vector{<:Number}, what::Number, args...)
    res = 0
    for (pos, el) in enumerate(from)
        if el == what
            res = pos
            break
        end
    end
    return res
end


"""
    index_of_first_true(from::Vector{<:Number}, args...)

Returns the index of the first element >=1. 
"""
function index_of_first_true(from::Vector{<:Number}, args...)
    conds = [ith for (ith, int_bool) in enumerate(from) if int_bool >= 1]
    if isempty(conds)
        return -1
    else
        return conds[1]
    end

end

append_method!(bundle_integer_find, find_first)
append_method!(bundle_integer_find, index_of_first_true)
end
