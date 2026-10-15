############################
# GraphMAGE: node expansion
############################

"""
    GraphMAGEEliteStash

An epoch-callback that stashes the current generation's elite genomes and
fitnesses every time it fires, ending with the last generation's values once
the fitter's loop completes.

This is needed because `fit_ga_meanbatch_mt`-family fitters do not reliably
return the true best/elite genomes: their first return value is either the
unmodified input genome or the final (unsorted, elite+new) population, not
specifically the elite subset. The codebase's own established pattern for
capturing the real result is exactly this kind of epoch-callback stash (see
`jsonTrackerGA` in `utils_aml.jl`), which has direct access to `population`
and `elite_idx` for the generation it fires on.
"""
mutable struct GraphMAGEEliteStash <: AbstractCallable
    genomes::Vector{UTGenome}
    fitnesses::Vector{Float64}
end

GraphMAGEEliteStash() = GraphMAGEEliteStash(UTGenome[], Float64[])

function (stash::GraphMAGEEliteStash)(
        ind_performances, population::Population, generation::Int, run_config::AbstractRunConf,
        model_architecture::modelArchitecture, node_config::nodeConfig, meta_library::MetaLibrary,
        shared_inputs::SharedInput, programs, best_loss, best_program, elite_idx, Batch;
        extras::Dict = Dict(),
    )
    stash.genomes = deepcopy(population.pop[elite_idx])
    stash.fitnesses = Float64.(deepcopy(best_loss))
    return nothing
end

"""
    expand_node!(archive, node_label, ctx) -> Vector{Tuple{String, Float64}}

Expand `node_label`: gather its current parent(s) (or, for a root with none,
itself) as seeds; build a restricted function library from the union of
those seeds' `used_functions`; seed a GA population from their genomes
(round-robin duplicated to `n_elite`, remapped canonical -> restricted);
run `ctx.fitter_fn` for `archive.config.child_gens` generations; remap the
resulting elite genomes restricted -> canonical; compute their behaviors;
insert each as a new node (or merge into an existing one, keeping the
first-found genome on collision) with an edge from `node_label`. Marks
`node_label` as expanded. Returns `(offspring_label, reward)` pairs -- reward
is `-fitness`, since MAGE minimizes and UCB maximizes -- for the caller to
`backpropagate!`.
"""
function expand_node!(
        archive::GraphMAGEArchive,
        node_label::String,
        ctx::GraphMAGERunContext,
    )::Vector{Tuple{String, Float64}}
    graph = archive.graph
    config = archive.config
    node = get_node(graph, node_label)

    parents = parent_labels(graph, node_label)
    seed_labels = isempty(parents) ? [node_label] : parents
    @info "GraphMAGE: expanding node" node = node_label n_parents = length(seed_labels) visits = node.visits expanded = node.expanded

    used = merge_used_function_names(Dict{Int, Vector{Symbol}}[get_node(graph, l).used_functions for l in seed_labels])
    child_ml = subset_metalibrary(ctx.ml_full, used)
    @info "GraphMAGE: restricted child library" n_functions = sum(length, values(used); init = 0) per_chromosome = length.(child_ml.libraries)

    seed_genomes = UTGenome[]
    for label in seed_labels
        seed = deepcopy(get_node(graph, label).genome)
        remap_genome_to_library!(seed, ctx.ml_full, child_ml, ctx.model_architecture, ctx.shared_inputs)
        push!(seed_genomes, seed)
    end
    initial_pop = UTGenome[
        deepcopy(seed_genomes[mod1(i, length(seed_genomes))]) for i in 1:config.n_elite
    ]

    run_config = RunConfGA(
        config.n_elite, config.n_new, config.tour_size,
        config.mutation_rate, config.output_mutation_rate, config.child_gens,
    )

    stash = GraphMAGEEliteStash()

    ctx.fitter_fn(
        ctx.dataloader, nothing, ctx.shared_inputs, initial_pop,
        ctx.model_architecture, ctx.node_config, run_config, child_ml,
        ctx.pre_callbacks, ctx.population_callbacks, ctx.mutation_callbacks,
        ctx.output_mutation_callbacks, ctx.decoding_callbacks, ctx.endpoint,
        ctx.final_step_callbacks, ctx.elite_selection_callbacks,
        (stash,), ctx.early_stop_callbacks, ctx.last_callback,
    )

    @assert !isempty(stash.genomes) "GraphMAGE: expansion of $node_label produced no elite genomes"

    for genome in stash.genomes
        remap_genome_to_library!(genome, child_ml, ctx.ml_full, ctx.model_architecture, ctx.shared_inputs)
    end

    behaviors = compute_behaviors_for_population(
        stash.genomes, ctx.model_architecture, ctx.ml_full, ctx.shared_inputs,
        archive.probes, config.behavior_round_digits,
    )

    results = Tuple{String, Float64}[]
    for (genome, fitness, offspring_label) in zip(stash.genomes, stash.fitnesses, behaviors)
        if !haskey(graph, offspring_label)
            fns = if config.fn_union_mode === :genotype
                used_function_names_genotype(genome, ctx.ml_full)
            else
                individual_programs = decode_with_output_nodes(genome, ctx.ml_full, ctx.model_architecture, ctx.shared_inputs)
                used_function_names(individual_programs)
            end
            # Genomes stored in the archive must always be pure/index-based,
            # never carrying cached evaluation results (e.g. whole
            # intermediate images) from the GA run that produced them -- see
            # the matching reset in run.jl's build_fresh_archive.
            reset_genome!(genome)
            add_node!(graph, GraphMAGENode(offspring_label, genome, fns, fitness))
            @info "GraphMAGE: new behavior discovered" behavior = offspring_label fitness = fitness parent = node_label
        else
            # A rediscovered node (e.g. a root that never got its own GA
            # fitness) only gets this measurement backfilled if it doesn't
            # already have one -- never overwritten once set. Behavior-hash
            # equality is already this whole system's definition of node
            # identity (it's what lets two nodes merge into one at all), so
            # treating a same-hash fitness as belonging to the existing node
            # is no new assumption; but two *different* genomes can still
            # coincidentally hash to the same rounded probe output, so a
            # later measurement must never clobber an earlier, possibly
            # genome-specific one.
            existing = get_node(graph, offspring_label)
            if isnan(existing.train_fitness)
                existing.train_fitness = fitness
                @info "GraphMAGE: behavior rediscovered, backfilling train_fitness" behavior = offspring_label fitness = fitness parent = node_label
            else
                @info "GraphMAGE: behavior rediscovered" behavior = offspring_label fitness = fitness parent = node_label
            end
        end
        add_edge_checked!(graph, node_label, offspring_label)
        push!(results, (offspring_label, -fitness))
    end

    node.expanded = true
    return results
end
