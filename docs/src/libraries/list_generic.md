```@meta
CurrentModule = UTCGP
DocTestSetup = quote

  # LIST GENERIC SUBSET
  using UTCGP.listgeneric_basic:identity_list
  using UTCGP.listgeneric_basic:new_list
  using UTCGP.listgeneric_basic:reverse_list
  
  # LIST GENERIC SUBSET
  using UTCGP.listgeneric_subset:pick_from_exclusive_generic
  using UTCGP.listgeneric_subset:pick_from_inclusive_generic
  using UTCGP.listgeneric_subset:pick_until_exclusive_generic
  using UTCGP.listgeneric_subset:pick_until_inclusive_generic

  # MAKE LIST 
  using UTCGP.listgeneric_makelist:make_list_from_one_element
  using UTCGP.listgeneric_makelist:make_list_from_two_elements
  using UTCGP.listgeneric_makelist:make_list_from_three_elements

 # Concat List
 using UTCGP.listgeneric_concat: concat_two_lists
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
UTCGP.listgeneric_subset
```

### Functions

```@docs
UTCGP.listgeneric_subset.pick_from_exclusive_generic
```


```@docs
UTCGP.listgeneric_subset.pick_from_inclusive_generic
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
UTCGP.listgeneric_subset.pick_until_exclusive_generic
```
```@docs
UTCGP.listgeneric_subset.pick_until_inclusive_generic
```



## Make Lists from elements

### Module
```@docs
UTCGP.listgeneric_makelist
```

### Functions

```@docs
UTCGP.listgeneric_makelist.make_list_from_one_element
```
```jldoctest
julia> make_list_from_one_element(12344)
1-element Vector{Int64}:
 12344
```

```@docs
UTCGP.listgeneric_makelist.make_list_from_two_elements
```
```jldoctest
julia> make_list_from_two_elements("ju","lia")
2-element Vector{String}:
 "ju"
 "lia"
```

Elements have to be of the same type (also applies for `make_list_from_three_elements`)  : 

```jldoctest
julia> make_list_from_two_elements("juli",'a')
ERROR: MethodError: no method matching make_list_from_two_elements(::String, ::Char)
[...] 
```

```@docs
UTCGP.listgeneric_makelist.make_list_from_three_elements
```
```jldoctest
julia> make_list_from_three_elements("ju", "l", "ia")
3-element Vector{String}:
 "ju"
 "l"
 "ia"
```


## Concat Operation

### Module
```@docs
UTCGP.listgeneric_concat
```

### Functions

```@docs
UTCGP.listgeneric_concat.concat_two_lists
```
```jldoctest
julia> concat_two_lists([1,2], [3,4])
4-element Vector{Int64}:
 1
 2
 3
 4
```

But lists have to be of the same type:

```jldoctest
julia> concat_two_lists([1,2], [3.0,4.0])
ERROR: MethodError: no method matching concat_two_lists(::Vector{Int64}, ::Vector{Float64})
[...]
```
