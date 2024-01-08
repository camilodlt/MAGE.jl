# -*- coding: utf-8 -*-

"""
Make vectors from elements of the same type

Exports : **bundle\\_listgeneric\\_makelist**: 
- `make_list_from_one_element`
- `make_list_from_two_elements`
- `make_list_from_three_elements`

"""
module listgeneric_makelist

import ..UTCGP: FunctionBundle, append_method!, FunctionWrapper


# FALLBACK
fallback() = []

bundle_listgeneric_makelist = FunctionBundle(fallback)


"""
    make_list_from_one_element(e1::T, args...) 

Makes [e1]
"""
function make_list_from_one_element(e1::T, args...) where {T}
    v = [e1]
    return identity.(v)
end

"""
    make_list_from_two_elements(e1::T, e2::T, args...) 

Makes [e1,e2]
"""
function make_list_from_two_elements(e1::T, e2::T, args...) where {T}
    v = [e1, e2]
    return identity.(v)
end
"""
    make_list_from_three_elements(e1::T, e2::T, e3::T, args...)

Makes [e1,e2,e3]
"""
function make_list_from_three_elements(e1::T, e2::T, e3::T, args...) where {T}
    v = [e1, e2, e3]
    return identity.(v)
end


append_method!(bundle_listgeneric_makelist, make_list_from_one_element)
append_method!(bundle_listgeneric_makelist, make_list_from_two_elements)
append_method!(bundle_listgeneric_makelist, make_list_from_three_elements)

end
