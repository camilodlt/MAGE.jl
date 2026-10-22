```@meta
CurrentModule = MAGE
DocTestSetup = quote
  using MAGE
end
```

```@contents
Pages = ["bool.md"]
```

# Bool Operations

A `Bool` chromosome is useful when a program has to produce a decision rather
than a value — a classification, a stopping condition, a gate feeding a
multiplexer.

## Module

```@docs
MAGE.bool_basic
```

## Functions

```@docs
MAGE.bool_basic.identity_bool
```

```@docs
MAGE.bool_basic.ret_true
```
```jldoctest
julia> MAGE.bool_basic.ret_true()
true
```

```@docs
MAGE.bool_basic.ret_false
```
```jldoctest
julia> MAGE.bool_basic.ret_false()
false
```

```@docs
MAGE.bool_basic.parse_string
```

`parse_string` parses its argument and evaluates it inside a sandbox
`baremodule`, reporting whether the result is `true`. Anything that fails to
parse or evaluate — which, in a baremodule, includes most operators — yields
`false`, so the operator is total.

## Bundle

```@docs
bundle_bool_basic
```
