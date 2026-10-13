# # -*- coding: utf-8 -*-

"""
Parse a string into another type.

# Bundles

- [`bundle_string_parse`](@ref)

The exhaustive, always-current list of operators in each bundle is on the
[Bundle Catalogue](@ref) page.
"""
module str_parse

using ..UTCGP: FunctionBundle, append_method!

# ################### #
# PARSE FROM NUMBER   #
# ################### #

fallback(args...) = return ""

"""
    bundle_string_parse

`parse_number`: convert a number to its string representation (`string(n)`).
"""
bundle_string_parse = FunctionBundle(fallback)

# FUNCTIONS ---
"""
    parse_number(n::Number, args...)

Returns `string(n)`. For example, `parse_number(2.5) == "2.5"`.
"""
function parse_number(n::Number, args...)
    return string(n)
end

# APPEND ---
append_method!(
    bundle_string_parse,
    parse_number;
    description = "Converts a numeric input to a string.",
)

end
