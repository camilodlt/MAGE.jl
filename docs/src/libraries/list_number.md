```@meta
CurrentModule = MAGE
DocTestSetup = quote
  using MAGE

  # LIST GENERIC RECURSIVE
  using MAGE.listnumber_recursive:recsum
  using MAGE.listnumber_recursive:recmult
  using MAGE.listnumber_recursive:range_

  # LIST NUMBER ARITHMETIC
  using MAGE.listnumber_arithmetic:sum_broadcast
  using MAGE.listnumber_arithmetic:subtract_broadcast
  using MAGE.listnumber_arithmetic:mult_broadcast
  using MAGE.listnumber_arithmetic:div_broadcast
  using MAGE.listnumber_arithmetic:sum_vector
  using MAGE.listnumber_arithmetic:subtract_vector
  using MAGE.listnumber_arithmetic:mult_vector
  using MAGE.listnumber_arithmetic:div_vector

  # LIST NUMBER ALGEBRAIC
  using MAGE.listnumber_algebraic:abs_vector
end
```

```@contents
Pages = ["list_number.md"]
```

# List Number Operations

## Arithmetic
### Module
```@docs
MAGE.listnumber_arithmetic
```
### Functions

#### Broadcast

```@docs
MAGE.listnumber_arithmetic.sum_broadcast
```
```jldoctest
julia> sum_broadcast([1,2,3],10)
3-element Vector{Int64}:
 11
 12
 13
```

```@docs
MAGE.listnumber_arithmetic.subtract_broadcast
```
```jldoctest
julia> subtract_broadcast([1,2,3],10)
3-element Vector{Int64}:
 -9
 -8
 -7
```

```@docs
MAGE.listnumber_arithmetic.mult_broadcast
```
```jldoctest
julia> mult_broadcast([1,2,3],10)
3-element Vector{Int64}:
 10
 20
 30
```

```@docs
MAGE.listnumber_arithmetic.div_broadcast
```
```jldoctest
julia> div_broadcast([1,2,3],10)
3-element Vector{Float64}:
 0.1
 0.2
 0.3
```
```jldoctest
julia> div_broadcast([1,2,3],0)
ERROR: DivideError: integer division error
[...]
```

#### Vector

```@docs
MAGE.listnumber_arithmetic.sum_vector
```
```jldoctest
julia> sum_vector([1,2,3],[-1,-2,-3])
3-element Vector{Int64}:
 0
 0
 0
```
```jldoctest
julia> sum_vector([1,2,3],[-1,-2])
ERROR: DimensionMismatch: a has size (3,), b has size (2,), mismatch at dim 1
[...]
```

```@docs
MAGE.listnumber_arithmetic.subtract_vector
```
```jldoctest
julia> subtract_vector([1,2,3],[1,2,3])
3-element Vector{Int64}:
 0
 0
 0
```

```@docs
MAGE.listnumber_arithmetic.mult_vector
```
```jldoctest
julia> mult_vector([1.,2.,3.],[1,2,3])
3-element Vector{Float64}:
 1.0
 4.0
 9.0
```

```@docs
MAGE.listnumber_arithmetic.div_vector
```
```jldoctest
julia> div_vector([1,2,3],[10,10,10])
3-element Vector{Float64}:
 0.1
 0.2
 0.3
```
```jldoctest
julia> div_vector([1,2,3],[10,10,0])
ERROR: DivideError: integer division error
[...]
```

## Algebraic
### Module
```@docs
MAGE.listnumber_algebraic
```
### Functions

```@docs
MAGE.listnumber_algebraic.abs_vector
```
```jldoctest
julia> abs_vector([-1,2,3])
3-element Vector{Int64}:
 1
 2
 3
```
## Recursive functions

### Module
```@docs
MAGE.listnumber_recursive
```

### Functions


```@docs
MAGE.listnumber_recursive.recsum
```
```jldoctest
julia> recsum([1,2,3])
3-element Vector{Int64}:
 1
 3
 6
```
```jldoctest
julia> recsum([1.,2.,3.])
3-element Vector{Float64}:
 1.0
 3.0
 6.0
```

```@docs
MAGE.listnumber_recursive.recmult
```
```jldoctest
julia> recmult(2,0.5,3)
4-element Vector{Real}:
 2
 1.0
 0.5
 0.25
```

```@docs
MAGE.listnumber_recursive.range_
```
```jldoctest
julia> range_(3)
3-element Vector{Int64}:
 1
 2
 3
```
```jldoctest
julia> range_(3.0)
3-element Vector{Float64}:
 1.0
 2.0
 3.0
```

## Basic

### Module
```@docs
MAGE.listnumber_basic
```

## From tuples

### Module
```@docs
MAGE.listnumber_vectuples
```

## Bundles

```@docs
bundle_listnumber_basic
bundle_listnumber_arithmetic
bundle_listnumber_algebraic
bundle_listnumber_recursive
bundle_listnumber_vectuples
```
