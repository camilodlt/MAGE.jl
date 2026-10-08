############################
# GraphMAGE: core types
############################

"""
    GraphMAGENode

One vertex of a GraphMAGE search graph: a unique program *behavior*.

`behavior_hash` is the node's identity (and its `MetaGraphsNext` label). It is
derived from rounding `genome`'s outputs on a fixed probe sample set -- see
`compute_behaviors_for_population` in `behavior.jl`.

`genome` is always expressed in the *canonical* (full) `MetaLibrary`'s index
space -- restricted, per-expansion libraries are a transient view used only
inside `expand_node!`; genomes are remapped back to canonical space before
being stored here. This keeps checkpointing and cross-node computation
sharing (see `eval_val.jl`) simple: one library, one index space, always.

`used_functions` is the set of real (non output-node) function names this
genome's own decoded programs call, grouped by chromosome/library index. It
is what a child expansion unions across parents to build its restricted
library -- see `library_subset.jl`.

`visits`/`reward_sum` back the UCB formula (`ucb.jl`): `reward_sum / visits`
is the node's mean reward (higher is better; reward is `-fitness` since MAGE
minimizes). `expanded` marks whether this node has already had its own GA
expansion run (per-node expansion happens at most once).
"""
mutable struct GraphMAGENode
    behavior_hash::String
    genome::UTGenome
    used_functions::Dict{Int, Vector{Symbol}}
    visits::Int
    reward_sum::Float64
    train_fitness::Float64
    val_fitness::Union{Float64, Nothing}
    expanded::Bool
end

function GraphMAGENode(
        behavior_hash::String,
        genome::UTGenome,
        used_functions::Dict{Int, Vector{Symbol}},
        train_fitness::Float64,
    )
    return GraphMAGENode(behavior_hash, genome, used_functions, 0, 0.0, train_fitness, nothing, false)
end

"""
    GraphMAGEConfig

Search hyperparameters. `n_expansions` is the outer search budget (the
GraphMAGE analogue of "generations" -- one expansion is one node's inner GA
run). `child_gens` is how many generations that inner GA run gets.
`n_elite`/`n_new`/`tour_size`/`mutation_rate`/`output_mutation_rate` configure
that inner GA exactly like `RunConfGA` does for a plain GA run.

`fn_union_mode` picks which of a parent's functions get unioned into a
child's restricted library (see `library_subset.jl`): `:phenotype` (default)
uses `used_function_names` -- only functions the parent's *decoded,
active-path* program actually calls; `:genotype` uses
`used_function_names_genotype` -- every function any node in the parent's
raw genome carries, active or not, since CGP genomes always carry dormant
material a mutation could reactivate later.

`time_budget_minutes`, if set, lets `run_graphmage` stop itself once that
many minutes of wall-clock time have elapsed, checked once per expansion --
the intended way to run for "about N hours" rather than a fixed expansion
count: set `n_expansions` to something effectively unreachable (e.g.
1_000_000) and let the time budget be what actually ends the run. This is
strictly better than an external kill/timeout: the loop exits cleanly after
finishing whichever expansion it was mid-way through, so the final
checkpoint and validation step still run instead of being cut off mid-write.
"""
Base.@kwdef mutable struct GraphMAGEConfig
    n_roots::Int
    n_expansions::Int
    child_gens::Int
    n_elite::Int
    n_new::Int
    tour_size::Int
    mutation_rate::Float64
    output_mutation_rate::Float64 = 0.1
    ucb_c::Float64 = 1.0
    anneal_ucb::Bool = false
    ucb_c_final::Float64 = 0.0
    behavior_n_probes::Int = 64
    behavior_round_digits::Int = 3
    checkpoint_every::Int = 5
    fn_union_mode::Symbol = :phenotype
    time_budget_minutes::Union{Nothing, Float64} = nothing
end

"""
    GraphMAGEArchive

The persistent state of one GraphMAGE search: the behavior graph itself
(`graph`, a `MetaGraphsNext.MetaGraph{String,GraphMAGENode,Nothing}`), the
current root node labels, the run configuration, and the fixed probe input
set (`probes`) that gives every behavior hash in this archive its meaning --
persisted so a reload or a merge stays hash-consistent with runs that
produced it.
"""
mutable struct GraphMAGEArchive
    graph::Any
    root_labels::Vector{String}
    config::GraphMAGEConfig
    probes::Vector{<:Tuple}
    expansions_done::Int
end

"""
    GraphMAGERunContext

Everything `expand_node!`/`run_graphmage` need to actually run GA and decode
programs, bundled once by the caller. `fitter_fn` is any function matching
the standard UTCGP GA-fitter calling convention (see `fit_ga_meanbatch_mt`);
GraphMAGE itself never inspects its internals, it only calls it -- this is
the seam that lets the caller plug in a problem-specific, time-aware,
population-graph-evaluator fitter without GraphMAGE's core code knowing
anything about regression, correlation, or time penalties.

`root_postprocess`, if not `nothing`, is called on every freshly built root
genome right after `correct_all_nodes!` (e.g. to freeze output-node wiring
the way `fit_surrogate.jl` does for its own initial population) -- a hook
rather than a hardcoded call so MAGE core stays free of repo-specific
conventions.
"""
struct GraphMAGERunContext
    dataloader::Any
    endpoint::Any
    model_architecture::modelArchitecture
    node_config::nodeConfig
    shared_inputs::SharedInput
    ml_full::MetaLibrary
    fitter_fn::Function
    pre_callbacks::Any
    population_callbacks::Any
    mutation_callbacks::Any
    output_mutation_callbacks::Any
    decoding_callbacks::Any
    final_step_callbacks::Any
    elite_selection_callbacks::Any
    early_stop_callbacks::Any
    last_callback::Any
    root_postprocess::Union{Nothing, Function}
end

function GraphMAGERunContext(;
        dataloader, endpoint, model_architecture, node_config, shared_inputs, ml_full, fitter_fn,
        pre_callbacks = nothing,
        population_callbacks = (:ga_population_callback,),
        mutation_callbacks = (:ga_numbered_new_material_mutation_callback,),
        output_mutation_callbacks = (:ga_output_mutation_callback,),
        decoding_callbacks = (:default_decoding_callback,),
        final_step_callbacks = nothing,
        elite_selection_callbacks = (:ga_elite_selection_callback,),
        early_stop_callbacks = nothing,
        last_callback = nothing,
        root_postprocess = nothing,
    )
    return GraphMAGERunContext(
        dataloader, endpoint, model_architecture, node_config, shared_inputs, ml_full, fitter_fn,
        pre_callbacks, population_callbacks, mutation_callbacks, output_mutation_callbacks,
        decoding_callbacks, final_step_callbacks, elite_selection_callbacks, early_stop_callbacks,
        last_callback, root_postprocess,
    )
end
