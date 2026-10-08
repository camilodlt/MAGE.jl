```@meta
CurrentModule = UTCGP
```

# Generated Functions

MAGE can grow its own operators. A language model is asked for a function that
fits the model's types, and the candidate is only admitted to a
[`Library`](@ref) after it has been rendered, compiled and validated — at which
point it is an ordinary [`FunctionWrapper`](@ref) and the search cannot tell it
apart from a hand-written one.

This complements [Automatically Defined Functions](@ref), which build new
operators out of material the search itself discovered.

```@contents
Pages = ["generated_functions.md"]
Depth = 2
```

## The pipeline

```
make_llm_generated_function_client       pick a backend
        │
        ▼
generate_function_spec                   ask for a GeneratedFunctionSpec
        │
        ▼
render_generated_function_source         spec -> Julia source
        │
        ▼
compile_generated_function               source -> SourceBackedFunction
        │
        ▼
validate_generated_function              run it on sample inputs
        │                                     │ fails
        │                                     ▼
        │                                repair_function_spec  (retry)
        ▼
install_generated_function!              into the MetaLibrary
```

[`synthesize_validated_function`](@ref) drives the whole loop, including the
repair retries, and is the entry point most callers want.

A generated function is given namespaces of the library's existing operators
under readable names, so it can build on what is already there:

```julia
tmp   = fns_returning_intensity_img.laplacian3_image2D(x1)
score = fns_returning_float.region_mean_10p(x1, 0.5, 0.5)
```

The context handed to the model — the allowed input and output types, the
maximum arity, the available namespaces — is produced by
[`render_generated_function_context`](@ref) from your
[`modelArchitecture`](@ref), [`nodeConfig`](@ref) and [`MetaLibrary`](@ref), so
a generated function is type-correct by construction rather than by review.

## Everything

```@autodocs
Modules = [UTCGP]
Pages = ["libraries/llm_generated_functions.jl"]
```

## Backend hooks

Concrete backends are provided by package extensions; these two hooks are the
only thing UTCGP's core knows about them. See [Package Extensions](@ref).

```@docs; canonical = false
llm_generated_function_client_backend
llm_generated_function_client_status
```
