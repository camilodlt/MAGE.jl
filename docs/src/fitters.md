```@meta
CurrentModule = UTCGP
```

# Fitters and Callbacks

A fitter runs the search loop. Which one you call is decided by your run
configuration's type:

| Fitter | Run configuration | Strategy |
|:--|:--|:--|
| [`fit`](@ref) / [`fit_mt`](@ref) | [`runConf`](@ref) | `1 + λ` |
| [`fit_ga`](@ref) / [`fit_ga_mt`](@ref) | [`RunConfGA`](@ref) | generational GA, tournament selection |
| `UTCGP.fit_nsga2` | `RunConfNSGA2` | multi-objective (NSGA-II) |
| `UTCGP.fit_me` | `RunConfME` | MAP-Elites |
| `UTCGP.fit_stn` | `RunConfSTN` | search-network tracing |

All of them return the same triple: the best genome, its decoded programs, and a
`GenerationLossTracker`.

```@contents
Pages = ["fitters.md"]
Depth = 2
```

## The callback pipeline

Every fitter runs the same phases each generation, and each phase is a *tuple*
of callbacks. An entry may be a `Symbol` naming a built-in, a `Function`, or any
`UTCGP.AbstractCallable` — which is how stateful trackers are passed in.

```
pre_callbacks                once, before the loop
│
└─ per generation:
   population_callbacks      build this generation's individuals
   mutation_callbacks        mutate the node material
   output_mutation_callbacks mutate the output nodes
   decoding_callbacks        genome -> programs
   endpoint_callback         programs + expected value -> fitness
   final_step_callbacks      after each batch
   elite_selection_callbacks pick the survivor(s)
   epoch_callbacks           tracking, validation, logging
   early_stop_callbacks      return true to stop
│
last_callback                once, after the loop
```

`nothing` is accepted wherever a phase is optional.

### The `1 + λ` callbacks

These take a positional argument list.

```@autodocs
Modules = [UTCGP]
Pages = ["fitters/default_callbacks.jl"]
```

### The GA callbacks

These take a single args struct instead, so a custom callback can be written
against a stable signature.

```@autodocs
Modules = [UTCGP]
Pages = ["fitters/ga_callbacks.jl"]
```

### Calling the callbacks

```@autodocs
Modules = [UTCGP]
Pages = ["fitters/callbacks_callers.jl"]
```

## `1 + λ`

```@autodocs
Modules = [UTCGP]
Pages = ["fitters/fit.jl", "fitters/fit_mt.jl"]
```

## Genetic algorithm

```@autodocs
Modules = [UTCGP]
Pages = ["fitters/ga_fit.jl"]
```

## MAP-Elites

MAP-Elites keeps an archive of individuals indexed by a behaviour descriptor
rather than a single best, so the run returns a *repertoire* of diverse
solutions instead of one optimum.

```@autodocs
Modules = [UTCGP]
Pages = ["fitters/mapelites_callbacks.jl", "population/mapelites_repertoire.jl"]
```

## NSGA-II

For problems with several objectives to trade off — accuracy against program
size, say.

```@autodocs
Modules = [UTCGP]
Pages = ["fitters/nsga2_callbacks.jl"]
```

## Search-network tracing

The STN fitter records every step of the search into a
[search network](@ref "Search Networks") as it runs.

```@autodocs
Modules = [UTCGP]
Pages = ["fitters/stn_callbacks.jl", "fitters/stn_fit.jl"]
```

## Writing your own callback

Any callable object can be a callback. An epoch callback, for example, receives
the generation's state and can compute a held-out loss:

```julia
mutable struct ValidationTracker <: UTCGP.AbstractCallable
    X::Any
    y::Any
    losses::Vector{Float64}
end

function (vt::ValidationTracker)(
        ind_performances, population, iteration, run_config, model_architecture,
        node_config, meta_library, shared_inputs, population_programs,
        best_loss, best_program, elite_idx, batch,
    )
    seq = compile_program(best_program, model_architecture, meta_library)
    preds = [seq(row...)[1] for row in vt.X]
    push!(vt.losses, sum(abs, preds .- vt.y) / length(vt.y))
    return nothing
end
```

Pass it in the `epoch_callbacks` slot: `fit(..., (ValidationTracker(Xv, yv, Float64[]),), ...)`.
