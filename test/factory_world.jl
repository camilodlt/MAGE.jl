# Factories define methods with eval. At top-level test sites, advance to the
# resulting world before inspecting or calling the operator. This is a Julia
# 1.12 top-level directive, not an operator wrapper: calls and @inferred checks
# remain ordinary compiled calls. Julia 1.11 already advances at these sites.
# Do not use this macro inside a function; prepare its operators at top level.
macro test_factory(expression)
    VERSION < v"1.12" && return esc(expression)
    quote
        local operator = $(esc(expression))
        Core.@latestworld
        operator
    end
end
