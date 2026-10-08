```@meta
CurrentModule = UTCGP
```

# Symbolic Regression

Symbolic regression is the smallest interesting MAGE problem: a single
`Float64` chromosome, so none of the multimodal machinery is in play and the
search loop is easy to watch.

This page runs a complete search on synthetic data. If you have not read
[Getting Started](@ref) yet, do that first — it explains each object as it is
built; here they are assembled at once.

```@contents
Pages = ["sr_example.md"]
Depth = 2
```

## The problem

Rediscover `f(x1, x2) = x1^2 + 2*x2` from samples, with `1.0` and `2.0`
available as constants.

```@example sr
using UTCGP
using Logging
using Random
Random.seed!(1234)

target(x1, x2) = x1^2 + 2 * x2

samples = [(round(rand() * 4 - 2; digits = 3), round(rand() * 4 - 2; digits = 3)) for _ in 1:60]
X = [Any[x1, x2, 1.0, 2.0] for (x1, x2) in samples]
Y = [target(x1, x2) for (x1, x2) in samples]

length(X), X[1] => Y[1]
```

## The loss

Mean absolute error, with a large penalty for a `NaN` output so that a program
that blows up is never selected.

```@example sr
struct EndpointMAE <: UTCGP.BatchEndpoint
    fitness_results::Vector{Float64}
    function EndpointMAE(preds::Vector{<:Vector{<:Number}}, y::Number)
        res = Float64[]
        for ind_outputs in preds
            p = ind_outputs[1]
            push!(res, isnan(p) || isinf(p) ? 1e6 : abs(p - y))
        end
        return new(res)
    end
end
nothing # hide
```

## The model

```@example sr
lib = Library(UTCGP.get_sr_float_bundles())
ml  = MetaLibrary([lib])

n_inputs = length(X[1])
model_arch = modelArchitecture(
    [Float64 for _ in 1:n_inputs], [1 for _ in 1:n_inputs],
    [Float64],
    [Float64], [1],
)
node_config = nodeConfig(40, 1, 2, n_inputs)

shared_inputs, ut_genome = make_evolvable_utgenome(model_arch, ml, node_config)
initialize_genome!(ut_genome)
correct_all_nodes!(ut_genome, model_arch, ml, shared_inputs)

list_functions_names(lib)
```

### Pinning the output

A common trick is to force the output node to read the *last* node of the
chromosome, so the graph always has the full depth available. Freeze its
connexion after setting it:

```@example sr
set_node_element_value!(
    ut_genome.output_nodes[1][2],
    ut_genome.output_nodes[1][2].highest_bound,
)
set_node_freeze_state(ut_genome.output_nodes[1][2])
nothing # hide
```

## The search

```@example sr
run_conf = runConf(10, 60, 1.1, 0.1)

best_genome, best_program, history = with_logger(NullLogger()) do
    fit(
        X, Y, shared_inputs, ut_genome, model_arch, node_config, run_conf, ml,
        nothing,
        (:default_population_callback,),
        (:default_numbered_new_material_mutation_callback,),
        (:default_ouptut_mutation_callback,),
        (:default_decoding_callback,),
        EndpointMAE,
        nothing,
        (:default_elite_selection_callback,),
        nothing,
        (:default_early_stop_callback,),
        nothing,
    )
end

losses = [history[g][1] for g in 1:length(history)]
(first = losses[1], last = losses[end], generations = length(losses))
```

## The evolved program

Compiling the decoded program renders it as plain Julia source — only the nodes
the output actually depends on appear, which is what makes an evolved MAGE model
readable.

```@example sr
seq = compile_program(best_program, model_arch, ml)
print(sequential_source(seq))
```

The compiled program is callable, so it can be checked against the target:

```@example sr
[(x, seq(x...)[1], y) for (x, y) in zip(X[1:5], Y[1:5])]
```

## Stopping on a budget

`fit` stops when it runs out of generations, or when an early-stop callback
returns `true`. [`default_early_stop_callback`](@ref) stops at a loss of zero;
[`eval_budget_early_stop`](@ref) stops after a fixed number of evaluations,
which is the fair way to compare configurations:

```julia
eval_stopper = eval_budget_early_stop(10_000)

fit(
    ...,
    (:default_early_stop_callback, eval_stopper),
    nothing,
)
```

## Tracking a validation loss

Anything callable can be passed as an epoch callback, which is how a held-out
loss is followed during the run. The callback receives the population, the
elite index and the best program of the generation:

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

val_tracker = ValidationTracker(X_val, Y_val, Float64[])

fit(..., (val_tracker,), (:default_early_stop_callback,), nothing)
```

See [Fitters and Callbacks](@ref) for the full pipeline and the exact signature
of each phase.

## A real dataset

A version of this example running against
[PMLB](https://github.com/EpistasisLab/pmlb) regression datasets — fetched
through `PythonCall`, with a train/validation split and a validation tracker —
ships with the repository as
[`docs/examples/pmlb_symbolic_regression.jl`](https://github.com/camilodlt/MAGE.jl/blob/main/docs/examples/pmlb_symbolic_regression.jl).
It needs the `pmlb` Python package and `MLJ`, so it is not run as part of the
documentation build; edit the `JULIA_PYTHONCALL_EXE` line at the top to point at
your own environment before running it.
