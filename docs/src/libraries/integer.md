
```@meta
CurrentModule = MAGE
DocTestSetup = quote
  using MAGE

  # INTEGER Basic
  using MAGE.integer_basic:identity_int

  # INTEGER FIND
  using MAGE.integer_find:find_first
  
  # INTEGER MODULO
  using MAGE.integer_modulo:modulo
end
```

```@contents
Pages = ["integer.md"]
```

# Integer Operations

## Basic operations 

### Module 

```@docs
MAGE.integer_basic
```
### Functions 


```@docs
MAGE.integer_basic.identity_int
```
```jldoctest
julia> identity_int(3)
3
```

## Find First in vector

### Module
```@docs
MAGE.integer_find
```

### Functions

```@docs
MAGE.integer_find.find_first
```
```jldoctest
julia> find_first([1,2,3], 3)
3
```
```jldoctest
julia> find_first([1,2,3], 10)
0 
```

## Modulo Operations

### Module 

```@docs
MAGE.integer_modulo
```
### Functions 

```@docs
MAGE.integer_modulo.modulo
```
```jldoctest
julia> modulo(10,2)
0
```
```jldoctest
julia> modulo(11,2)
1
```

## Conditions

### Module
```@docs
MAGE.integer_cond
```

### Functions

Predicates return `1` or `0` rather than a `Bool`, so their result stays in the
integer chromosome and can be fed straight to arithmetic or to a multiplexer.

```@docs
MAGE.integer_cond.is_eq_to
```
```jldoctest
julia> MAGE.integer_cond.is_eq_to(3, 3)
1
```

```@docs
MAGE.integer_cond.str_is_empty
```
```jldoctest
julia> MAGE.integer_cond.str_is_empty("")
1
```

```@docs
MAGE.integer_cond.experimental_is_gt
```
```jldoctest
julia> MAGE.integer_cond.experimental_is_gt(3, 2)
1
```

```@docs
MAGE.integer_cond.experimental_is_lt
```

```@docs
MAGE.integer_cond.experimental_not
```
```jldoctest
julia> MAGE.integer_cond.experimental_not(1)
0
```

## Bundles

```@docs
bundle_integer_basic
bundle_integer_find
bundle_integer_modulo
bundle_integer_cond
```
