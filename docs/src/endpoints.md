```@meta
CurrentModule = UTCGP
```

# Endpoints and Tracking

An **endpoint** states the problem: it turns program outputs into fitness.
**Trackers** record what happened during the run.

```@contents
Pages = ["endpoints.md"]
Depth = 2
```

## Endpoints

An endpoint is a struct, not a function. Its constructor receives the outputs of
every individual in the batch plus the expected value, and stores one score per
individual in a `fitness_results` field. Lower is better — MAGE minimises.

You hand the *type* to the fitter; it is constructed once per batch.

```@autodocs
Modules = [UTCGP]
Pages = ["endpoints/endpoint_structs.jl"]
```

### Ready-made endpoints

The three standard PSB2 error functions.

```@autodocs
Modules = [UTCGP]
Pages = ["endpoints/psb2_metrics.jl"]
```

### Writing one

```julia
struct EndpointMAE <: UTCGP.BatchEndpoint
    fitness_results::Vector{Float64}
    function EndpointMAE(preds::Vector{<:Vector{<:Number}}, y::Number)
        res = Float64[]
        for ind_outputs in preds
            p = ind_outputs[1]                 # this individual's first output
            push!(res, isnan(p) ? 1e6 : abs(p - y))
        end
        return new(res)
    end
end
```

Two details matter in practice. Give a non-finite output a large finite penalty
rather than letting `NaN` propagate — the selection callbacks treat `NaN` as
`Inf`, but an explicit penalty keeps the loss history readable. And index
`ind_outputs` by output position: with several output nodes, each individual
hands you a vector.

## Loss trackers

```@autodocs
Modules = [UTCGP]
Pages = ["metrics_trackers/individual_loss_tracker.jl"]
```

The `GenerationLossTracker` returned by a fitter is indexed by generation, and
holds that generation's losses with the best one first:

```julia
best_per_generation = [history[g][1] for g in 1:length(history)]
```

## Experiment tracking

```@autodocs
Modules = [UTCGP]
Pages = ["metrics_trackers/aim_callback.jl", "metrics_trackers/local_file.jl"]
```

For a full record of the search — every individual, every transition — see
[Search Networks](@ref).

## Stopping early

Two built-ins, both passed in the `early_stop_callbacks` slot:

- [`default_early_stop_callback`](@ref) stops when the best loss reaches `0.0`.
- [`eval_budget_early_stop`](@ref) stops after a fixed number of evaluations,
  which is the fair way to compare configurations that differ in population
  size.

```julia
fit(..., (:default_early_stop_callback, eval_budget_early_stop(10_000)), nothing)
```
