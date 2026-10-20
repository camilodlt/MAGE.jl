```@meta
CurrentModule = MAGE
DocTestSetup = quote
  using MAGE
  # COMBINATORICS
  using MAGE.listtuple_combinatorics:vector_of_products
  using MAGE.listtuple_combinatorics:vector_of_combinations
end
```

```@contents
Pages = ["list_tuple.md"]
```


# List Tuple Operations

Operators producing and consuming `Vector{Tuple{T,T}}` — the chromosome type
that lets a program carry pairs around, for instance a list of coordinates or a
mapping between two lists.

## Combinatorics

### Module
```@docs
MAGE.listtuple_combinatorics
```

### Functions

```@docs
MAGE.listtuple_combinatorics.vector_of_products
```
```jldoctest
julia> vector_of_products(["hungry"],["yes","no"])
2-element Vector{Tuple{String, String}}:
 ("hungry", "yes")
 ("hungry", "no")
```

```@docs
MAGE.listtuple_combinatorics.vector_of_combinations
```
```jldoctest
julia> vector_of_combinations(["hungry","yes","no"])
3-element Vector{Tuple{String, String}}:
 ("hungry", "yes")
 ("hungry", "no")
 ("yes", "no")
```

## Mappings

### Module
```@docs
MAGE.listtuple_mappings
```

### Functions

```@docs
MAGE.listtuple_mappings.mappings_a_to_b
```
```jldoctest
julia> MAGE.listtuple_mappings.mappings_a_to_b(["a","b"], ["x","y"])
2-element Vector{Tuple{String, String}}:
 ("a", "x")
 ("b", "y")
```

## Bundles

```@docs
bundle_listtuple_combinatorics
bundle_listtuple_combinatorics_factory
bundle_listtuple_mappings
bundle_listtuple_mappings_factory
```
