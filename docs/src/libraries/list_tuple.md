```@meta
CurrentModule = UTCGP
DocTestSetup = quote
  # COMBINATORICS
  using UTCGP.listtuple_combinatorics:vector_of_products  
  using UTCGP.listtuple_combinatorics:vector_of_combinations  
end
```

```@contents
Pages = ["list_tuple.md"]
```


## Combinatorics

### Module
```@docs
UTCGP.listtuple_combinatorics
```

### Functions

```@docs
UTCGP.listtuple_combinatorics.vector_of_products
```
```jldoctest
julia> vector_of_products(["hungry"],["yes","no"])
2-element Vector{Tuple{String, String}}:
 ("hungry", "yes")
 ("hungry", "no")
```

```@docs
UTCGP.listtuple_combinatorics.vector_of_combinations
```
```jldoctest
julia> vector_of_combinations(["hungry","yes","no"])
3-element Vector{Tuple{String, String}}:
 ("hungry", "yes")
 ("hungry", "no")
 ("yes", "no")
```
