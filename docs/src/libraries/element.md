```@meta
CurrentModule = MAGE
DocTestSetup = quote
  using MAGE
  # PICK
  using MAGE.element_pick:pick_element_from_vector
  using MAGE.element_pick:pick_last_element
end
```

```@contents
Pages = ["element.md"]
```

# Element Operations

## Pick Element

### Module
```@docs
MAGE.element_pick
```

### Functions

```@docs
MAGE.element_pick.pick_element_from_vector
```
```jldoctest
julia> pick_element_from_vector([1,2,3,4], 2)
2
```
```jldoctest
julia> pick_element_from_vector(["a","b","c"], 3)
"c"
```
```jldoctest
julia> pick_element_from_vector([1,2,3,4], 0)
ERROR: BoundsError: attempt to access 4-element Vector{Int64} at index [0]
[...]
```

```@docs
MAGE.element_pick.pick_last_element
```
```jldoctest
julia> pick_last_element([1,2,3,4])
4
```
```jldoctest
julia> pick_last_element([(1,2),(2,2)])
(2, 2)
```
```jldoctest
julia> pick_last_element([])
ERROR: BoundsError: attempt to access 0-element Vector{Any} at index [0]
[...]
```

## Conditional

### Module
```@docs
MAGE.element_conditional
```

### Functions

`if_else_multiplexer(cond, a, b, args...)` returns `a` when `cond > 0` and `b`
otherwise. Both branches must have the same type, which is what keeps the node
type-correct whichever way the condition goes.

```@docs
MAGE.element_conditional.if_else_multiplexer
```

```jldoctest
julia> MAGE.element_conditional.if_else_multiplexer(1, "yes", "no")
"yes"
```
```jldoctest
julia> MAGE.element_conditional.if_else_multiplexer(0, "yes", "no")
"no"
```

### Bundles

```@docs
bundle_element_pick
bundle_element_conditional
bundle_element_conditional_factory
```
