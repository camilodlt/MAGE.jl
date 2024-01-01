```@meta
CurrentModule = UTCGP
DocTestSetup = quote

  # LIST GENERIC SUBSET
  using UTCGP.listgeneric_basic:identity_list
  using UTCGP.listgeneric_basic:new_list
  using UTCGP.listgeneric_basic:reverse_list
  
  # LIST GENERIC SUBSET
  using UTCGP.list_generic_subset:pick_from_exclusive_generic
  using UTCGP.list_generic_subset:pick_from_inclusive_generic
  using UTCGP.list_generic_subset:pick_until_exclusive_generic
  using UTCGP.list_generic_subset:pick_until_inclusive_generic
end
```

```@contents
Pages = ["list_generic.md"]
```

# List Generic Operations

## Basic operations 

### Module 

```@docs
UTCGP.listgeneric_basic
```
### Functions 

```@docs
UTCGP.listgeneric_basic.identity_list
```
```jldoctest
julia> identity_list([1,2,3,4])
4-element Vector{Int64}:
 1
 2
 3
 4
```

```@docs
UTCGP.listgeneric_basic.new_list
```
```jldoctest
julia> new_list()
Any[]
```

```@docs
UTCGP.listgeneric_basic.reverse_list
```
```jldoctest
julia> reverse_list([1,2])
2-element Vector{Int64}:
 2
 1
```

## Subset functions

### Module
```@docs
UTCGP.list_generic_subset
```

### Functions

```@docs
UTCGP.list_generic_subset.pick_from_exclusive_generic
```


```@docs
UTCGP.list_generic_subset.pick_from_inclusive_generic
```
```jldoctest
julia> pick_from_inclusive_generic([1,2,3,4], -1)
4-element Vector{Int64}:
 1
 2
 3
 4
```
```jldoctest
julia> pick_from_inclusive_generic([1,2,3,4], 2)
3-element Vector{Int64}:
 2
 3
 4
```
```jldoctest
julia> pick_from_inclusive_generic([1,2,3,4], 10)
Int64[]
```

```@docs
UTCGP.list_generic_subset.pick_until_exclusive_generic
```
```@docs
UTCGP.list_generic_subset.pick_until_inclusive_generic
```

