using DuckDB

"""
The pop is cloned from the first genome
"""
function _stn_init_pop(genome, ma, ml, si, n_pop::Int)
    new_pop = Vector{UTGenome}(undef, n_pop)
    for i = 1:n_pop
        g_new = deepcopy(genome)
        UTCGP.reset_genome!(g_new)
        # initialize_genome!(g_new)
        # correct_all_nodes!(g_new, ma, ml, si)
        # fix_all_output_nodes!(g_new)
        new_pop[i] = g_new
    end
    pop = Population(new_pop)
    mappings = [MutablePair("", "") for i = 1:length(new_pop)]
    _stn_id_hash_pop!(pop, mappings, Parent()) # updates the first element of each mutable pair (Parents) 
    Population(deepcopy(pop.pop)), mappings
end

function _stn_init_params(genome::UTGenome, run_config::AbstractRunConf, ma, ml, si)
    early_stop = false
    best_programs = nothing
    elite_idx = nothing
    population, mappings = _stn_init_pop(genome, ma, ml, si, run_config.sample_size)
    return early_stop, best_programs, elite_idx, population, mappings
end

function fit_stn_atari_mt(
    con::DuckDB.DB,
    shared_inputs::SharedInput,
    genome::UTGenome,
    model_architecture::modelArchitecture,
    node_config::nodeConfig,
    run_config::RunConfSTN,
    meta_library::MetaLibrary,
    # Callbacks before training
    pre_callbacks::Optional_FN,
    # Callbacks before step (before looping through data)
    population_callbacks::Mandatory_FN,
    mutation_callbacks::Mandatory_FN,
    output_mutation_callbacks::Mandatory_FN,
    decoding_callbacks::Mandatory_FN,
    # Callbacks per step (while looping through data)
    endpoint_callback::Type{<:BatchEndpoint},
    final_step_callbacks::Optional_FN,
    # Callbacks after step ::
    elite_selection_callbacks::Optional_FN,
    epoch_callbacks::Optional_FN,
    early_stop_callbacks::Optional_FN,
    last_callback::Optional_FN,
)
    local early_stop, best_programs, elite_idx, population, mappings = _stn_init_params(
        genome,
        run_config,
        model_architecture,
        meta_library,
        shared_inputs,
    )
    # PRE CALLBACKS
    _make_pre_callbacks_calls(pre_callbacks)
    M_gen_loss_tracker = GenerationLossTracker()
    # mappings = Vector{UTCGP.MutablePair}()
    for iteration = 1:run_config.generations
        early_stop ? break : nothing
        @warn "Iteration : $iteration"
        # Population
        me_pop_args = STN_POP_ARGS(
            population,
            con,
            mappings,
            iteration,
            run_config,
            model_architecture,
            node_config,
            meta_library,
        )
        if iteration != 1
            population, time_pop =
                @unwrap_or _make_stn_population(me_pop_args, population_callbacks) throw(
                    "Could not unwrap make_population",
                )
        end
        # Program mutations ---
        me_mutation_args = STN_MUTATION_ARGS(
            population,
            con,
            mappings,
            iteration,
            run_config,
            model_architecture,
            node_config,
            meta_library,
            shared_inputs,
        )
        population, time_mut =
            @unwrap_or _make_stn_mutations!(me_mutation_args, mutation_callbacks) throw(
                "Could not unwrap make_me_mutations",
            )

        # Output mutations ---
        # population, time_out_mut = @unwrap_or _make_ga_output_mutations!(
        #     ga_mutation_args,
        #     output_mutation_callbacks,
        # ) throw("Could not unwrap make_ga_output_mutations")

        # Genotype to Phenotype mapping --- 

        population_programs, time_pop_prog = _make_decoding(
            population,
            iteration,
            run_config,
            model_architecture,
            node_config,
            meta_library,
            shared_inputs,
            decoding_callbacks,
        )

        UTCGP.reset_programs!.(population_programs)

        # M_individual_loss_tracker = IndividualLossTrackerMT(length(population), 1)
        M_individual_loss_tracker = IndividualLossTracker() # size of []

        @warn "MT Graphs evals"
        endpoint_holder = endpoint_callback(
            population_programs,
            model_architecture,
            meta_library,
            iteration,
        )
        fitness_values, descriptor_values = get_endpoint_results(endpoint_holder)
        # @show fitness_values descriptor_values
        UTCGP.add_pop_loss_to_ind_tracker!(M_individual_loss_tracker, fitness_values)  # appends the loss for the ith x sample to the

        # Resetting the population (removes node values)
        [reset_genome!(g) for g in population]

        # final step call...
        if !isnothing(final_step_callbacks)
            for final_step_callback in final_step_callbacks
                UTCGP.get_fn_from_symbol(final_step_callback)()
            end
        end

        # Selection
        ind_performances = UTCGP.resolve_ind_loss_tracker(M_individual_loss_tracker)

        try
            # histogram(ind_performances) |> println
            # histogram([d[1] for d in descriptor_values]) |> println
            # @show ARCHIVE.descriptors
            histogram(ind_performances)
        catch e
            @error "Could not drawn histogram"
        end

        # EMPTY_TRACKER = IndividualLossTrackerMT(pop_size, TrainSize * n_repetitions)

        # EPOCH CALLBACK
        if !isnothing(epoch_callbacks)
            epoch_args = STN_EPOCH_ARGS(
                ind_performances,
                con,
                mappings,
                population,
                iteration,
                run_config,
                model_architecture,
                node_config,
                meta_library,
                shared_inputs,
                population_programs,
                nothing, # []
                nothing, # best_programs,
                nothing,# elite_idx,
                nothing,
            )
            _make_epoch_callbacks_calls(epoch_args, epoch_callbacks)
        end

        best_f = collect(sn._execute_command(
            con,
            """
            SELECT MIN(fitness) AS highest_fitness
            FROM EDGES;
            """,
        ))[1][1]
        # store iteration loss/fitness
        affect_fitness_to_loss_tracker!(
            M_gen_loss_tracker,
            iteration,
            minimum(ind_performances), #UTCGP.best_fitness(ARCHIVE),
        )

        println("Iteration $iteration. 
                 Archive best fitness : $(round(best_f, digits = 10))")

        # EARLY STOP CALLBACK # TODO
        if !isnothing(early_stop_callbacks) && length(early_stop_callbacks) != 0
            # early_stop_args = GA_EARLYSTOP_ARGS(
            #     M_gen_loss_tracker,
            #     M_individual_loss_tracker,
            #     ind_performances,
            #     population,
            #     iteration,
            #     run_config,
            #     model_architecture,
            #     node_config,
            #     meta_library,
            #     shared_inputs,
            #     population_programs,
            #     elite_fitnesses,
            #     best_programs,
            #     elite_idx,
            # )
            # early_stop =
            #     _make_ga_early_stop_callbacks_calls(early_stop_args, early_stop_callbacks) # true if any
        end
        best_individual = population[argmin(ind_performances)]
        best_program = decode_with_output_nodes(
            best_individual,
            meta_library,
            model_architecture,
            shared_inputs,
        )

        if early_stop
            g = run_config.generations
            @warn "Early returning at iteration : $iteration from $g total iterations"
            if !isnothing(last_callback)
                # last_callback(
                #     ind_performances,
                #     population,
                #     iteration,
                #     run_config,
                #     model_architecture,
                #     node_config,
                #     meta_library,
                #     population_programs,
                #     elite_fitnesses,
                #     best_programs,
                #     elite_idx,
                # )
            end
            # UTCGP.show_program(program)
            return tuple(best_individual, best_program, M_gen_loss_tracker)
        end

        gct = @elapsed GC.gc(false)
        @warn "Running GC at the end of iteration. GC time : $gct"

    end
    best_individual = population[1]
    best_program = decode_with_output_nodes(
        best_individual,
        meta_library,
        model_architecture,
        shared_inputs,
    )
    return (best_individual, best_program, M_gen_loss_tracker)
end

function fit_stn_trainable_mt(
    X::Any,
    Y::Union{Any,Nothing},
    n_repetitions::Int,
    con::DuckDB.DB,
    shared_inputs::SharedInput,
    genome::UTGenome,
    model_architecture::modelArchitecture,
    node_config::nodeConfig,
    run_config::RunConfSTN,
    meta_library::MetaLibrary,
    # Callbacks before training
    pre_callbacks::Optional_FN,
    # Callbacks before step (before looping through data)
    population_callbacks::Mandatory_FN,
    mutation_callbacks::Mandatory_FN,
    output_mutation_callbacks::Mandatory_FN,
    decoding_callbacks::Mandatory_FN,
    # Callbacks per step (while looping through data)
    endpoint_callback::Type{<:BatchEndpoint},
    final_step_callbacks::Optional_FN,
    # Callbacks after step ::
    elite_selection_callbacks::Optional_FN,
    epoch_callbacks::Optional_FN,
    early_stop_callbacks::Optional_FN,
    last_callback::Optional_FN,
)
    local early_stop, best_programs, elite_idx, population, mappings = _stn_init_params(
        genome,
        run_config,
        model_architecture,
        meta_library,
        shared_inputs,
    )

    BatchSize = X.batch_size
    TrainSize = length(X)

    # PRE CALLBACKS
    _make_pre_callbacks_calls(pre_callbacks)
    M_gen_loss_tracker = GenerationLossTracker()
    # mappings = Vector{UTCGP.MutablePair}()
    for iteration = 1:run_config.generations
        early_stop ? break : nothing
        @warn "Iteration : $iteration"
        # Population
        me_pop_args = STN_POP_ARGS(
            population,
            con,
            mappings,
            iteration,
            run_config,
            model_architecture,
            node_config,
            meta_library,
        )
        if iteration != 1
            population, time_pop =
                @unwrap_or _make_stn_population(me_pop_args, population_callbacks) throw(
                    "Could not unwrap make_population",
                )
        end
        # Program mutations ---
        me_mutation_args = STN_MUTATION_ARGS(
            population,
            con,
            mappings,
            iteration,
            run_config,
            model_architecture,
            node_config,
            meta_library,
            shared_inputs,
        )
        population, time_mut =
            @unwrap_or _make_stn_mutations!(me_mutation_args, mutation_callbacks) throw(
                "Could not unwrap make_me_mutations",
            )

        # Output mutations ---
        # population, time_out_mut = @unwrap_or _make_ga_output_mutations!(
        #     ga_mutation_args,
        #     output_mutation_callbacks,
        # ) throw("Could not unwrap make_ga_output_mutations")

        # Genotype to Phenotype mapping --- 

        population_programs, time_pop_prog = _make_decoding(
            population,
            iteration,
            run_config,
            model_architecture,
            node_config,
            meta_library,
            shared_inputs,
            decoding_callbacks,
        )

        UTCGP.reset_programs!.(population_programs)

        # M_individual_loss_tracker = IndividualLossTrackerMT(length(population), 1)
        M_individual_loss_tracker = IndividualLossTracker() # size of []

        pop_size = length(population)
        Repetitions_loss_tracker = Matrix{Float64}(undef, pop_size, n_repetitions)
        @warn "Multi Threaded Graphs evals"
        UTCGP.reset_programs!(population_programs)
        ALL_BATCHS = []
        for ith_repetition = 1:n_repetitions
            @info "Repetition n° $ith_repetition"
            UTCGP.reset_programs!(population_programs)
            # indices, batch = X[1:TrainSize] # should do in parallel # WRAMDl
            batch = X[1:TrainSize]
            push!(ALL_BATCHS, batch...)
            # Storage for all evaluations (pop * X)
            M_individual_loss_tracker =
                IndividualLossTrackerMT(length(population), length(X))
            for ith_x in Iterators.partition(1:TrainSize, BatchSize)
                @debug "Spawn training batch $ith_x. $(now()) "
                store_col = view(M_individual_loss_tracker, :, ith_x)
                B = @view batch[ith_x]

                let store_view = store_col,
                    pop_progs = population_programs,
                    ma = model_architecture,
                    ml = meta_library,
                    endpoint = endpoint_callback,
                    B = B

                    @dspawn begin
                        @W store_view
                        @R B
                        @timeit_debug to "ga_fit_mt. evalbatch" _eval_batch_on_pop(
                            B,
                            store_view,
                            pop_progs,
                            ma,
                            ml,
                            endpoint,
                        )
                    end
                end
            end
            @debug "Waiting on all training batches. $(now()) "
            final_task = @dspawn @R(M_individual_loss_tracker.store) label = "result"
            fetch(final_task)
            @debug "All workers are done with their batches. All fitness were fetched. $(now())"
            ind_performances = resolve_ind_loss_tracker(M_individual_loss_tracker)
            # m = median(ind_performances)
            # top_50 = ind_performances .>= m
            # if isdefined(Main, :Infiltrator)
            #     Main.infiltrate(@__MODULE__, Base.@locals, @__FILE__, @__LINE__)
            # end
            # println("Updating dataloader weigths")
            # X.ws[indices] += mean(M_individual_loss_tracker.store[top_50, :], dims = 1)[:] # or mean, maximum ? 
            Repetitions_loss_tracker[:, ith_repetition] .= ind_performances
        end
        ind_performances = median(Repetitions_loss_tracker, dims = 2)[:] # average over the 2nd dim => the repetitions

        # Resetting the population (removes node values)
        [reset_genome!(g) for g in population]

        # final step call...
        if !isnothing(final_step_callbacks)
            for final_step_callback in final_step_callbacks
                UTCGP.get_fn_from_symbol(final_step_callback)()
            end
        end

        try
            histogram(ind_performances) |> println
            # histogram([d[1] for d in descriptor_values]) |> println
            # @show ARCHIVE.descriptors
            histogram(ind_performances)
        catch e
            @error "Could not drawn histogram"
        end

        # EPOCH CALLBACK
        if !isnothing(epoch_callbacks)
            epoch_args = STN_EPOCH_ARGS(
                ind_performances,
                con,
                mappings,
                population,
                iteration,
                run_config,
                model_architecture,
                node_config,
                meta_library,
                shared_inputs,
                population_programs,
                ind_performances, # []
                population_programs.population_programs, # best_programs,
                argmin(ind_performances),# elite_idx,
                view(ALL_BATCHS, :),
            )
            _make_epoch_callbacks_calls(epoch_args, epoch_callbacks)
        end

        best_f = collect(sn._execute_command(
            con,
            """
            SELECT MIN(fitness) AS highest_fitness
            FROM EDGES;
            """,
        ))[1][1]
        # store iteration loss/fitness
        affect_fitness_to_loss_tracker!(
            M_gen_loss_tracker,
            iteration,
            minimum(ind_performances), #UTCGP.best_fitness(ARCHIVE),
        )

        println("Iteration $iteration. 
                 Archive best fitness : $(round(best_f, digits = 10))")

        # EARLY STOP CALLBACK # TODO
        if !isnothing(early_stop_callbacks) && length(early_stop_callbacks) != 0
            # early_stop_args = GA_EARLYSTOP_ARGS(
            #     M_gen_loss_tracker,
            #     M_individual_loss_tracker,
            #     ind_performances,
            #     population,
            #     iteration,
            #     run_config,
            #     model_architecture,
            #     node_config,
            #     meta_library,
            #     shared_inputs,
            #     population_programs,
            #     elite_fitnesses,
            #     best_programs,
            #     elite_idx,
            # )
            # early_stop =
            #     _make_ga_early_stop_callbacks_calls(early_stop_args, early_stop_callbacks) # true if any
        end
        best_individual = population[argmin(ind_performances)]
        best_program = decode_with_output_nodes(
            best_individual,
            meta_library,
            model_architecture,
            shared_inputs,
        )

        if early_stop
            g = run_config.generations
            @warn "Early returning at iteration : $iteration from $g total iterations"
            if !isnothing(last_callback)
                # last_callback(
                #     ind_performances,
                #     population,
                #     iteration,
                #     run_config,
                #     model_architecture,
                #     node_config,
                #     meta_library,
                #     population_programs,
                #     elite_fitnesses,
                #     best_programs,
                #     elite_idx,
                # )
            end
            # UTCGP.show_program(program)
            return tuple(best_individual, best_program, M_gen_loss_tracker)
        end

        gct = @elapsed GC.gc(false)
        @warn "Running GC at the end of iteration. GC time : $gct"

    end
    elite_ind = DataFrame(
        sn._execute_command(
            con,
            """
            WITH top AS (
                SELECT DISTINCT _to, fitness
                FROM EDGES
                ORDER BY fitness ASC, ITERATION DESC
                LIMIT 1
            )
            SELECT id_hash, $(run_config.behavior_col), $(run_config.serialization_col)
            FROM NODES
            JOIN top ON (
                NODES.id_hash = top._to
            )
            """,
        ),
    )
    best_individual =
        deserialize_ind_from_string(elite_ind[1, run_config.serialization_col])
    best_program = decode_with_output_nodes(
        best_individual,
        meta_library,
        model_architecture,
        shared_inputs,
    )
    return (best_individual, best_program, M_gen_loss_tracker)
end
