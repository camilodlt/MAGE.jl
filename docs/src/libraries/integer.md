
```@meta
CurrentModule = UTCGP
DocTestSetup = quote

  # INTEGER Basic
  using UTCGP.integer_basic:identity_int

  # INTEGER FIND
  using UTCGP.integer_find:find_first
  
  # INTEGER MODULO
  using UTCGP.integer_modulo:modulo
end
```

```@contents
Pages = ["integer.md"]
```

# Integer Operations

## Basic operations 

### Module 

```@docs
UTCGP.integer_basic
```
### Functions 


```@docs
UTCGP.integer_basic.identity_int
```
```jldoctest
julia> identity_int(3)
3
```

## Find First in vector

### Module
```@docs
UTCGP.integer_find
```

### Functions

```@docs
UTCGP.integer_find.find_first
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
UTCGP.integer_modulo
```
### Functions 

```@docs
UTCGP.integer_modulo.modulo
```
```jldoctest
julia> modulo(10,2)
0
```
```jldoctest
julia> modulo(11,2)
1
```
