
```@meta
CurrentModule = UTCGP
DocTestSetup = quote
  # INTEGER REDUCE

  using UTCGP.number_reduce:reduce_sum
  using UTCGP.number_reduce:reduce_min
  using UTCGP.number_reduce:reduce_max
  using UTCGP.number_reduce:reduce_argmin
  using UTCGP.number_reduce:reduce_argmax
  using UTCGP.number_reduce:reduce_recsum
end
```

```@contents
Pages = ["number.md"]
```

# Integer Operations

## Basic operations 

### Module 

### Functions 


## Reduce functions

### Module
```@docs
UTCGP.number_reduce
```

### Functions

```@docs
UTCGP.number_reduce.reduce_sum
```
```jldoctest
julia> reduce_sum([1,2,3])
6
```

```@docs
UTCGP.number_reduce.reduce_min
```
```jldoctest
julia> reduce_min([1,2,3])
1
```

```@docs
UTCGP.number_reduce.reduce_max
```
```jldoctest
julia> reduce_max([1,2,3])
3
```

```@docs
UTCGP.number_reduce.reduce_argmin
```
```jldoctest
julia> reduce_argmin([1,2,3])
1
```

```@docs
UTCGP.number_reduce.reduce_argmax
```
```jldoctest
julia> reduce_argmax([1,2,3])
3
```

```@docs
UTCGP.number_reduce.reduce_recsum
```
```jldoctest
julia> reduce_recsum([1,2,3])
3-element Vector{Int64}:
 1
 3
 6
```
