############################
# GraphMAGE: top-level search loop
############################

"""
    build_fresh_archive(config, ctx, trainx) -> GraphMAGEArchive

Build `config.n_roots` fresh random root genomes (skipping any that collide
in behavior with an already-added root), each visited zero times, forming
the starting frontier of a new search. `n_roots` can reasonably be large
(hundreds to low thousands): more roots means more independently-random
function-usage patterns available to seed later multi-parent unions (see
`library_subset.jl`), which is the mechanism that lets a child's search space
be "informed by what the parents use" instead of always the full library.

Genome construction/repair is embarrassingly parallel per root (each root is
independent, and Julia's per-task RNG makes concurrent `rand()` calls safe),
so it runs hyperthreaded via `Threads.@threads`. Behavior is then computed
for the *entire* batch in one call to `compute_behaviors_for_population`,
which merges every root into a single shared `PopulationSequentialProgram`
and evaluates hyperthreaded over probes -- one evaluation pass for all roots,
not one pass per root.
"""
function build_fresh_archive(config::GraphMAGEConfig, ctx::GraphMAGERunContext, trainx::AbstractVector)::GraphMAGEArchive
    graph = new_graphmage_graph()
    probes = build_behavior_probes(trainx, config.behavior_n_probes)

    @info "GraphMAGE: building root genomes (hyperthreaded)" n_roots = config.n_roots
    genomes = Vector{UTGenome}(undef, config.n_roots)
    Threads.@threads for i in 1:config.n_roots
        _, genome = make_evolvable_utgenome(ctx.model_architecture, ctx.ml_full, ctx.node_config)
        initialize_genome!(genome)
        correct_all_nodes!(genome, ctx.model_architecture, ctx.ml_full, ctx.shared_inputs)
        isnothing(ctx.root_postprocess) || ctx.root_postprocess(genome)
        genomes[i] = genome
    end

    @info "GraphMAGE: computing root behaviors (hyperthreaded across roots)" n_roots = config.n_roots n_probes = length(probes)
    behaviors = compute_behaviors_independently(
        genomes, ctx.model_architecture, ctx.ml_full, ctx.shared_inputs, probes, config.behavior_round_digits,
    )

    roots = String[]
    for (i, (genome, behavior)) in enumerate(zip(genomes, behaviors))
        if haskey(graph, behavior)
            @info "GraphMAGE: duplicate root behavior, skipping" root_index = i behavior = behavior
            continue
        end
        fns = if config.fn_union_mode === :genotype
            used_function_names_genotype(genome, ctx.ml_full)
        else
            individual_programs = decode_with_output_nodes(genome, ctx.ml_full, ctx.model_architecture, ctx.shared_inputs)
            used_function_names(individual_programs)
        end
        # Behavior evaluation (compute_behaviors_independently, above) leaves
        # cached evaluation results (e.g. whole intermediate images) sitting
        # on the genome's own node objects. Genomes stored in the archive
        # must always be pure/index-based -- reset before storing, not just
        # for memory (checkpoints otherwise carry image data per node,
        # ballooning file size), but because it's the correctness invariant
        # every other GraphMAGE genome is expected to hold.
        reset_genome!(genome)
        add_node!(graph, GraphMAGENode(behavior, genome, fns, NaN))
        push!(roots, behavior)
    end
    @assert !isempty(roots) "GraphMAGE: no roots could be created (all collided in behavior?)"
    @info "GraphMAGE: built fresh archive" n_roots = length(roots) n_probes = length(probes)
    return GraphMAGEArchive(graph, roots, config, probes, 0)
end

graph_node_train_fitness(graph, label::String) = get_node(graph, label).train_fitness

"""
    best_train_node_label(graph) -> Union{String, Nothing}

The label with the lowest `train_fitness` among nodes that have actually been
GA-evaluated (excludes roots, whose `train_fitness` is `NaN` until they are
themselves rediscovered as someone's offspring). `nothing` if no node has
been evaluated yet. Plain `argmin` cannot be used directly here: Julia's
`argmin`/`findmin` do not treat `NaN` as the worst value, so an unevaluated
root can incorrectly "win" over real, finite fitnesses.
"""
function best_train_node_label(graph)::Union{String, Nothing}
    evaluated = [l for l in all_node_labels(graph) if !isnan(graph_node_train_fitness(graph, l))]
    isempty(evaluated) && return nothing
    return argmin(l -> graph_node_train_fitness(graph, l), evaluated)
end

"""
    run_graphmage(config, ctx, trainx; checkpoint_path_prefix=nothing, starting_archives=GraphMAGEArchive[]) -> GraphMAGEArchive

Run GraphMAGE's Monte Carlo Graph Search: build fresh roots, or -- if
`starting_archives` is non-empty -- merge them (island continuation) and use
the merged graph as the starting state; then repeatedly select -> expand ->
backpropagate for `config.n_expansions` iterations (or until
`config.time_budget_minutes` elapses, whichever comes first -- see its
docstring on `GraphMAGEConfig`), checkpointing every `config.checkpoint_every`
expansions (and once more at the end) if `checkpoint_path_prefix` is given.
Returns the final archive; validation evaluation is the caller's
responsibility (see `evaluate_archive_outputs_on_samples` in `eval_val.jl`),
since it needs endpoint-specific fitness computation MAGE core does not know
about.
"""
function run_graphmage(
        config::GraphMAGEConfig,
        ctx::GraphMAGERunContext,
        trainx::AbstractVector;
        checkpoint_path_prefix::Union{Nothing, String} = nothing,
        starting_archives::Vector{GraphMAGEArchive} = GraphMAGEArchive[],
    )::GraphMAGEArchive
    archive = if isempty(starting_archives)
        build_fresh_archive(config, ctx, trainx)
    else
        merged = merge_graphmage_archives(starting_archives)
        @assert merged.config.behavior_round_digits == config.behavior_round_digits "GraphMAGE: continuation config's behavior_round_digits must match the merged archives' (probes were hashed with the old value)"
        merged.config = config
        merged
    end

    @info "GraphMAGE: starting search" n_expansions = config.n_expansions n_roots = length(archive.root_labels) starting_nodes = length(all_node_labels(archive.graph)) time_budget_minutes = config.time_budget_minutes
    run_start = time()

    for t in 1:config.n_expansions
        elapsed_minutes = (time() - run_start) / 60
        if !isnothing(config.time_budget_minutes) && elapsed_minutes >= config.time_budget_minutes
            @info "GraphMAGE: time budget exhausted, stopping" iteration = t elapsed_minutes = elapsed_minutes budget_minutes = config.time_budget_minutes
            break
        end

        c = if !config.anneal_ucb
            config.ucb_c
        elseif !isnothing(config.time_budget_minutes)
            # A time budget is normally paired with a large dummy
            # n_expansions (see GraphMAGEConfig's docstring), so t/n_expansions
            # would stay near 0 forever -- anneal on elapsed-time fraction
            # instead, which is what's actually being consumed.
            annealed_c(config.ucb_c, config.ucb_c_final, elapsed_minutes / config.time_budget_minutes)
        else
            annealed_c(config.ucb_c, config.ucb_c_final, t, config.n_expansions)
        end
        selected = select_node(archive, c)
        @info "GraphMAGE: expansion $t/$(config.n_expansions)" selected = selected c = c

        offspring = expand_node!(archive, selected, ctx)
        for (label, reward) in offspring
            backpropagate!(archive, label, reward)
        end
        archive.expansions_done += 1

        best_label = best_train_node_label(archive.graph)
        n_nodes = length(all_node_labels(archive.graph))
        if isnothing(best_label)
            @info "GraphMAGE: best train fitness so far" iteration = t n_nodes = n_nodes note = "no evaluated node yet"
        else
            @info "GraphMAGE: best train fitness so far" iteration = t node = best_label fitness = get_node(archive.graph, best_label).train_fitness n_nodes = n_nodes
        end

        if !isnothing(checkpoint_path_prefix) && t % config.checkpoint_every == 0
            # A single overwritten "latest" file, not one per expansion: the
            # archive only grows over a run, so per-expansion snapshots would
            # accumulate unbounded disk usage (this is exactly what filled a
            # disk during development with a small checkpoint_every).
            save_graphmage_archive(archive, "$(checkpoint_path_prefix)_latest.jld2")
        end
    end

    if !isnothing(checkpoint_path_prefix)
        save_graphmage_archive(archive, "$(checkpoint_path_prefix)_final.jld2")
    end

    return archive
end
