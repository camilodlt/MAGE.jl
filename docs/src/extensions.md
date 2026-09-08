```@meta
CurrentModule = UTCGP
```

# Package Extensions

Two capabilities live outside UTCGP proper, so that the core package does not
depend on Python or on an HTTP client. Both are declared as stubs that error
until the corresponding package is loaded.

```@contents
Pages = ["extensions.md"]
Depth = 2
```

## CMA-ES constants (`MAGE_PYCMA`)

MAGE evolves graph *structure* discretely. Numeric constants are a poor fit for
that: nudging a threshold from `0.31` to `0.32` is not something a mutation
operator over integers does well. The `MAGE_PYCMA` extension bridges to Python's
[`cma`](https://github.com/CMA-ES/pycma) so the constants held in
[`ConstantNode`](@ref)s are tuned by CMA-ES while the graph around them keeps
evolving.

```julia
using UTCGP
using MAGE_PYCMA     # provides the real methods below
```

```@autodocs
Modules = [UTCGP]
Pages = ["ext.jl"]
```

## LLM backends

The clients that back [Generated Functions](@ref) —
`LlamaCppGeneratedFunctionClient`, `GeminiGeneratedFunctionClient` and
`OpenAICompatibleGeneratedFunctionClient` — are constructed through
[`make_llm_generated_function_client`](@ref). The two hooks above
(`llm_generated_function_client_backend` and
`llm_generated_function_client_status`) are how runner code asks a client what
it is and whether it is ready, without branching on the provider.
