
```@meta
CurrentModule = MAGE
DocTestSetup = quote
  using MAGE
  # STR GREP
  using MAGE.str_grep:replace_pattern
  using MAGE.str_grep:replace_first_pattern
  using MAGE.str_grep:remove_pattern

  # STR PASTE
  using MAGE.str_paste:paste
  using MAGE.str_paste:paste0
  using MAGE.str_paste:paste_with_space
  using MAGE.str_paste:paste_space_list_string
  using MAGE.str_paste:paste_list_string_sep
  using MAGE.str_paste:paste_list_string

  # STR CONDITIONAL
  using MAGE.str_conditional:if_string
  using MAGE.str_conditional:if_not_string
  using MAGE.str_conditional:if_else_string
  using MAGE.str_conditional:longest_string
  using MAGE.str_conditional:shortest_string


  # STR CAPS
  using MAGE.str_caps:uppercase_
  using MAGE.str_caps:uppercase_at
  using MAGE.str_caps:uppercase_after
  using MAGE.str_caps:uppercase_char_after
  using MAGE.str_caps:uppercase_before
  using MAGE.str_caps:uppercase_char_before
  using MAGE.str_caps:lowercase_
  using MAGE.str_caps:lowercase_at
  using MAGE.str_caps:lowercase_after
  using MAGE.str_caps:lowercase_char_after
  using MAGE.str_caps:lowercase_before
  using MAGE.str_caps:lowercase_char_before
  using MAGE.str_caps:capitalize_first
  using MAGE.str_caps:capitalize_all

  # STR BASIC
  using MAGE.str_basic: number_to_string
end
```

```@contents
Pages = ["string.md"]
```

# String Operations

## Basic operations

### Module
```@docs
MAGE.str_basic
```
### Functions

```@docs
MAGE.str_basic.number_to_string
```
```jldoctest
julia> number_to_string(121)
"121"
```
```jldoctest
julia> number_to_string(121.12)
"121.12"
```

## Grep Module

### Module
```@docs
MAGE.str_grep
```

### Functions

```@docs
MAGE.str_grep.replace_pattern
```

```jldoctest
julia> replace_pattern("HelloHello", "Hello", "hello")
"hellohello"
```
Also can remove a char :

```jldoctest
julia> replace_pattern("Camel_case", "_", "")
"Camelcase"
```

```@docs
MAGE.str_grep.replace_first_pattern
```

```jldoctest
julia> replace_first_pattern("HelloHello", "Hello", "hello")
"helloHello"
```

```jldoctest
julia> replace_first_pattern("CCDC", "C", "A")
"ACDC"
```

```@docs
MAGE.str_grep.remove_pattern
```
```jldoctest
julia> remove_pattern("HelloHello", "Hello")
""
```

## Paste

### Module

```@docs
MAGE.str_paste
```

### Paste Strings

```@docs
MAGE.str_paste.paste
```

```jldoctest
julia> paste("kebab", "case", "-")
"kebab-case"
```

```@docs
MAGE.str_paste.paste0
```

```jldoctest
julia> paste0("ju", "lia")
"julia"
```

```@docs
MAGE.str_paste.paste_with_space
```

```jldoctest
julia> paste_with_space("ju", "lia")
"ju lia"
```

### Paste List Strings

```@docs
MAGE.str_paste.paste_space_list_string
```

```jldoctest
julia> paste_space_list_string(["kebab", "case"])
"kebab case"
```

```@docs
MAGE.str_paste.paste_list_string_sep
```

```jldoctest
julia> paste_list_string_sep(["kebab", "case"], "-")
"kebab-case"
```

```@docs
MAGE.str_paste.paste_list_string
```

```jldoctest
julia> paste_list_string(["kebab", "case"])
"kebabcase"
```

## Conditional

```@docs
MAGE.str_conditional
```

For `if_string`, `if_not_string` and `if_else_string`, the `cond` parameter is `trunc`ed to Int.

```@docs
MAGE.str_conditional.if_string
```

```jldoctest
julia> if_string("julia", 0)
""
```
```jldoctest
julia> if_string("julia", 137287.2)
"julia"
```

```@docs
MAGE.str_conditional.if_not_string
```

```jldoctest
julia> if_not_string("julia", 0)
"julia"
```
```jldoctest
julia> if_not_string("julia", 137287.2)
""
```

```@docs
MAGE.str_conditional.if_else_string
```

```jldoctest
julia> if_else_string("julia", "R" , 0)
"R"
```
```jldoctest
julia> if_else_string("julia", "R" ,137287.2)
"julia"
```

```@docs
MAGE.str_conditional.longest_string
```
```jldoctest
julia> longest_string("julia", "R")
"julia"
```
```jldoctest
julia> longest_string("julia", "jjjjj")
"julia"
```

```@docs
MAGE.str_conditional.shortest_string
```

```jldoctest
julia> shortest_string("julia", "R")
"R"
```
```jldoctest
julia> shortest_string("julia", "jjjjj")
"julia"
```

## Lower, Upper, Capitalize

### Module

```@docs
MAGE.str_caps
```

### Upper Case

```@docs
MAGE.str_caps.uppercase_
```

```jldoctest
julia> uppercase_("julia")
"JULIA"
```

```@docs
MAGE.str_caps.uppercase_at
```

```jldoctest
# It can capitalize
julia> uppercase_at("julia",1)
"Julia"
```
```jldoctest
# index is clipped
julia> uppercase_at("julia",-100)
"Julia"
```

```@docs
MAGE.str_caps.uppercase_after
```

```jldoctest
julia> uppercase_after("julia","ju")
"juLIA"
```

```@docs
MAGE.str_caps.uppercase_char_after
```

```jldoctest
julia> uppercase_char_after("julia","ju")
"juLia"
```

```jldoctest
# it works on every match
julia> uppercase_char_after("julia julia","ju")
"juLia juLia"
```


```@docs
MAGE.str_caps.uppercase_before
```

```jldoctest
julia> uppercase_before("julia","lia")
"JUlia"
```

```@docs
MAGE.str_caps.uppercase_char_before
```

```jldoctest
julia> uppercase_char_before("julia","lia")
"jUlia"
```

```jldoctest
# it works on every match
julia> uppercase_char_before("julia julia","lia")
"jUlia jUlia"
```

### Lower Case

```@docs
MAGE.str_caps.lowercase_
```

```jldoctest
julia> lowercase_("JULIA")
"julia"
```

```@docs
MAGE.str_caps.lowercase_at
```

```jldoctest
julia> lowercase_at("JULIA",1)
"jULIA"
```
```jldoctest
# index is clipped
julia> lowercase_at("JULIA",100)
"JULIa"
```

```@docs
MAGE.str_caps.lowercase_after
```

```jldoctest
julia> lowercase_after("juLIA","ju")
"julia"
```

```@docs
MAGE.str_caps.lowercase_char_after
```

```jldoctest
julia> lowercase_char_after("JULIA","JU")
"JUlIA"
```

```jldoctest
# it works on every match
julia> lowercase_char_after("JULIA JULIA","JU")
"JUlIA JUlIA"
```


```@docs
MAGE.str_caps.lowercase_before
```

```jldoctest
julia> lowercase_before("JULIA","LIA")
"juLIA"
```

```@docs
MAGE.str_caps.lowercase_char_before
```

```jldoctest
julia> lowercase_char_before("JUlia","lia")
"Julia"
```

```jldoctest
# it works on every match
julia> lowercase_char_before("JULIA JULIA","LIA")
"JuLIA JuLIA"
```
### Capitalize

```@docs
MAGE.str_caps.capitalize_first
```

```jldoctest
julia> capitalize_first("julia julia")
"Julia julia"
```

```@docs
MAGE.str_caps.capitalize_all
```

```jldoctest
julia> capitalize_all("julia julia")
"Julia Julia"
```
```jldoctest
# The titlecase functions takes all non letters as separators
julia> capitalize_all("julia-julia")
"Julia-Julia"
```

## Parse

### Module
```@docs
MAGE.str_parse
```

## Bundles

```@docs
bundle_string_basic
bundle_string_caps
bundle_string_conditional
bundle_string_grep
bundle_string_parse
bundle_string_paste
bundle_string_concat_list_string
```
