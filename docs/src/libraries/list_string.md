```@meta
CurrentModule = UTCGP
DocTestSetup = quote
  using UTCGP.liststring_caps:capitalize_list_string
  using UTCGP.liststring_caps:uppercasefirst_list_string
end
```

```@contents
Pages = ["list_string.md"]
```

# List String Operations

## Capitalize Elements

### Module 
```@docs
UTCGP.liststring_caps
```
### Functions 

```@docs 
UTCGP.liststring_caps.capitalize_list_string
```

```jldoctest
julia> capitalize_list_string(["julia", "julia"])
2-element Vector{String}:
 "Julia"
 "Julia"
```
```jldoctest
julia> capitalize_list_string(["julia julia", "julia"])
2-element Vector{String}:
 "Julia Julia"
 "Julia"
```

```@docs 
UTCGP.liststring_caps.uppercasefirst_list_string
```
```jldoctest
julia> uppercasefirst_list_string(["julia julia", "julia"])
2-element Vector{String}:
 "Julia julia"
 "Julia"
```

