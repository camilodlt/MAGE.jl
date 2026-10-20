```@meta
CurrentModule = UTCGP
DocTestSetup = quote
  using UTCGP
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
UTCGP.bool_basic
```

## Functions

```@docs
UTCGP.bool_basic.identity_bool
```

```@docs
UTCGP.bool_basic.ret_true
```
```jldoctest
julia> UTCGP.bool_basic.ret_true()
true
```

```@docs
UTCGP.bool_basic.ret_false
```
```jldoctest
julia> UTCGP.bool_basic.ret_false()
false
```

```@docs
UTCGP.bool_basic.parse_string
```

`parse_string` parses its argument and evaluates it inside a sandbox
`baremodule`, reporting whether the result is `true`. Anything that fails to
parse or evaluate — which, in a baremodule, includes most operators — yields
`false`, so the operator is total.

## Bundle

```@docs
bundle_bool_basic
```
