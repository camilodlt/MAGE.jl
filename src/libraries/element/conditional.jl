# -*- coding: utf-8 -*-

"""
Type-agnostic branching over elements.

# Bundles

- [`bundle_element_conditional`](@ref)
- [`bundle_element_conditional_factory`](@ref)

The exhaustive, always-current list of operators in each bundle is on the
[Bundle Catalogue](@ref) page.
"""
module element_conditional

using ..UTCGP: FunctionBundle, append_method!

# ################### #
#  CONDITIONAL        #
# ################### #

fallback(args...) = return nothing

"""
    bundle_element_conditional

`if_else_multiplexer`: pick between two values of the same type according to a
numeric condition.

Together with the comparison bundles this is what gives an evolved program
branching, without ever leaving the type it is declared in.
"""
bundle_element_conditional = FunctionBundle(fallback)
"""
    bundle_element_conditional_factory

Factory form of [`bundle_element_conditional`](@ref), specialisable to any
element type.

This is a *factory* bundle: each entry is a function of a type that returns the
method specialised for it, so the same operator can be instantiated for several
image or element types. See [Libraries](@ref) for how factories are specialised
into a library.
"""
bundle_element_conditional_factory = FunctionBundle(fallback)

# FUNCTIONS ---

# """
#     if_else_multiplexer(cond::Number, a::T, b::T, args...)

# Returns `a` if `cond` > 0, `b` otherwise.
# """
# function if_else_multiplexer(cond::Number, a::T, b::T, args...) where {T<:Any}
#     if cond > 0
#         return a
#     else
#         return b
#     end
# end

function if_else_multiplexer_factory(element_type::Type{T}) where {T}
    m1 = @eval ((cond::Number, a::E, b::E, args::Vararg{Any}) where {E<:$T}) -> begin
        if cond > 0
            return a
        else
            return b
        end
    end
    m1
end
"""
    if_else_multiplexer(cond::Number, a, b, args...)

Return `a` when `cond > 0`, `b` otherwise.

Both branches must have the same type, which is what keeps the node
type-correct whichever way the condition goes. Built by
`if_else_multiplexer_factory(Any)`; the factory bundle
[`bundle_element_conditional_factory`](@ref)
holds the un-specialised form.
"""
if_else_multiplexer = if_else_multiplexer_factory(Any)

append_method!(
    bundle_element_conditional,
    if_else_multiplexer,
    :if_else_multiplexer;
    description = "Selects between two values of the same type using a numeric condition.",
)
append_method!(
    bundle_element_conditional_factory,
    if_else_multiplexer_factory,
    :if_else_multiplexer,
    ;
    description = "Selects between two same-type values based on whether cond is greater than zero.",
)

end
