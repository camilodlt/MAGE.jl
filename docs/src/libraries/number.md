
```@meta
CurrentModule = UTCGP
DocTestSetup = quote

  # NUMBER ARITHMETIC
  using UTCGP.number_arithmetic:number_sum
  using UTCGP.number_arithmetic:number_minus
  using UTCGP.number_arithmetic:number_mult
  using UTCGP.number_arithmetic:number_div
  using UTCGP.number_arithmetic:safe_div

  # INTEGER REDUCE

  using UTCGP.number_reduce:reduce_sum
  using UTCGP.number_reduce:reduce_min
  using UTCGP.number_reduce:reduce_max
  using UTCGP.number_reduce:reduce_argmin
  using UTCGP.number_reduce:reduce_argmax
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
UTCGP.number_arithmetic
```

### Functions

```@docs
UTCGP.number_arithmetic.number_sum
```
```jldoctest
julia> number_sum(0,1)
1
```

```@docs
UTCGP.number_arithmetic.number_minus
```
```jldoctest
julia> number_minus(0,1)
-1
```

```@docs
UTCGP.number_arithmetic.number_mult
```
```jldoctest
julia> number_mult(3,3)
9
```

```@docs
UTCGP.number_arithmetic.number_div
```
```jldoctest
julia> number_div(3,3)
1.0
```

```@docs
UTCGP.number_arithmetic.safe_div
```
```jldoctest
julia> safe_div(3,0)
0
```

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
