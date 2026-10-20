```@meta
CurrentModule = MAGE
DocTestSetup = quote
  using MAGE
  using MAGE.liststring_caps:capitalize_list_string
  using MAGE.liststring_caps:uppercasefirst_list_string

  # Split string 

  using MAGE.liststring_split:split_string_to_vector
end
```

```@contents
Pages = ["list_string.md"]
```

# List String Operations

## Capitalize Elements

### Module 
```@docs
MAGE.liststring_caps
```
### Functions 

```@docs 
MAGE.liststring_caps.capitalize_list_string
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
MAGE.liststring_caps.uppercasefirst_list_string
```
```jldoctest
julia> uppercasefirst_list_string(["julia julia", "julia"])
2-element Vector{String}:
 "Julia julia"
 "Julia"
```

## Split String

### Module 
```@docs
MAGE.liststring_split
```
### Functions 

```@docs 
MAGE.liststring_split.split_string_to_vector
```

```jldoctest
julia> split_string_to_vector("julia", "")
5-element Vector{String}:
 "j"
 "u"
 "l"
 "i"
 "a"
```

## Broadcast

### Module
```@docs
MAGE.liststring_broadcast
```

## Bundles

```@docs
bundle_liststring_split
bundle_liststring_caps
bundle_liststring_broadcast
```
