```@meta
CurrentModule = UTCGP
DocTestSetup = quote
  # PICK
  using UTCGP.element_pick:pick_element_from_vector
  using UTCGP.element_pick:pick_last_element
end
```

```@contents
Pages = ["element.md"]
```

# Element Operations

## Pick Element

### Module
```@docs
UTCGP.element_pick
```

### Functions

```@docs
UTCGP.element_pick.pick_element_from_vector
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
UTCGP.element_pick.pick_last_element
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
