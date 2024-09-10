using Statistics
using Term
using DataFlowTasks

function _fit_mt_init_params(genome::UTGenome)
    early_stop = false
    best_program = nothing
    elite_idx = nothing
    population = UTCGP.Population([deepcopy(genome)])
    ind_performances = [1.0]
    return early_stop, best_program, elite_idx, population, ind_performances
end

### FIT API ###
function _eval_batch_on_pop(
    batch::SubArray,
    store_col::SubArray{Float64},
    non_shared_pop_programs::PopulationPrograms,
    model_arch::modelArchitecture,
    meta_library::MetaLibrary,
    endpoint_callback::Type{<:BatchEndpoint},
)

    @timeit_debug to "fit_mt. Thread setup bf eval" begin
        tid = Threads.threadid()
        @info "Started Batch fit at Thread $(tid). $(now())"
        non_shared_pop_programs = deepcopy(non_shared_pop_programs)
        # s = Base.summarysize(non_shared_pop_programs) / 1e+9
        # @info "Non Shared Programs size in thread $tid in GB: $s"
    end

    # Sequential
    @timeit_debug to "fit_mt. Thread eval loop" for (col_idx, (x, y)) in enumerate(batch)
        @timeit_debug to "fit_mt. Reset Progs" UTCGP.reset_programs!(
            non_shared_pop_programs,
        )
        # input_nodes = [
        #     InputNode(value, pos, pos, model_arch.inputs_types_idx[pos]) for
        #     (pos, value) in enumerate(x)
        # ]
        # append input nodes to pop
        @timeit_debug to "fit_mt. replace inputs" replace_shared_inputs!(
            non_shared_pop_programs,
            x,
        ) # update 
        @timeit_debug to "fit_mt. Eval pop" time_eval =
            @elapsed outputs = evaluate_population_programs(
                non_shared_pop_programs,
                model_arch,
                meta_library,
            )

        # Endpoint results
        @timeit_debug to "fit_mt. Endpoint" fitness = endpoint_callback(outputs, y)
        @timeit_debug to "fit_mt. get results" fitness_values =
            get_endpoint_results(fitness)
        @timeit_debug to "fit_mt. Add losses" add_pop_loss_to_ind_tracker!(
            store_col,
            col_idx,
            fitness_values,
        )
    end
    @info "Ended Batch fit at Thread $(tid). $(now())"
end

function fit_mt(
    X::Any,
    Y::Union{Any,Nothing},
    shared_inputs::SharedInput,
    genome::UTGenome,
    model_architecture::modelArchitecture,
    node_config::nodeConfig,
    run_config::runConf,
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
    elite_selection_callbacks::Mandatory_FN,
    epoch_callbacks::Optional_FN,
    early_stop_callbacks::Optional_FN,
    last_callback::Optional_FN,
) # Tuple{UTGenome, IndividualPrograms, GenerationLossTracker}::

    local early_stop, best_program, elite_idx, population, ind_performances =
        _fit_mt_init_params(genome)

    # DataLoader 
    BatchSize = X.batch_size
    TrainSize = length(X)

    # PRE CALLBACKS
    _make_pre_callbacks_calls(pre_callbacks)
    M_gen_loss_tracker = GenerationLossTracker()

    for iteration = 1:run_config.generations
        early_stop ? break : nothing
        @warn "Iteration : $iteration"

        # Population
        population, _ = _make_population( # migrate to @unwrap
            genome,
            iteration,
            run_config,
            model_architecture,
            node_config,
            meta_library,
            population_callbacks,
        )

        # Program mutations ---
        population, _ = _make_mutations(
            population,
            iteration,
            run_config,
            model_architecture,
            node_config,
            meta_library,
            shared_inputs,
            mutation_callbacks,
        )

        # population, _ = _make_output_mutations(
        #     population,
        #     iteration,
        #     run_config,
        #     model_architecture,
        #     node_config,
        #     meta_library,
        #     output_mutation_callbacks,
        # )

        # ADD Parent
        if iteration > 1
            push!(population.pop, deepcopy(genome))
        end

        population_programs, _ = _make_decoding(
            population,
            iteration,
            run_config,
            model_architecture,
            node_config,
            meta_library,
            shared_inputs,
            decoding_callbacks,
        )

        @warn "Graphs evals"
        M_individual_loss_tracker = IndividualLossTrackerMT(length(population), length(X))
        UTCGP.reset_programs!(population_programs)
        batch = X[1:TrainSize] # should do in parallel
        for ith_x in Iterators.partition(1:length(X), X.batch_size)
            @debug "Spawn training batch $ith_x. $(now()) "
            store_col = view(M_individual_loss_tracker, :, ith_x)
            B = @view batch[ith_x]

            let
                store_view = store_col
                pop_progs = population_programs
                ma = model_architecture
                ml = meta_library
                endpoint = endpoint_callback
                B = B
                @dspawn begin
                    @W store_view
                    @R B
                    _eval_batch_on_pop(B, store_view, pop_progs, ma, ml, endpoint)
                end
            end
        end
        @debug "Waiting on all training batches. $(now()) "
        final_task = @dspawn @R(M_individual_loss_tracker.store) label = "result"
        fetch(final_task)
        @debug "All workers are done with their batches. All fitness were fetched. $(now())"

        # final step call...
        if !isnothing(final_step_callbacks)
            for final_step_callback in final_step_callbacks
                get_fn_from_symbol(final_step_callback)()
            end
        end
        # DUPLICATES # TODO

        # Selection
        ind_performances = resolve_ind_loss_tracker(M_individual_loss_tracker)

        # Elite selection callbacks
        elite_idx, _ = _make_elite_selection(
            ind_performances,
            population,
            iteration,
            run_config,
            model_architecture,
            node_config,
            meta_library,
            population_programs,
            elite_selection_callbacks,
        )

        elite_best_fitness = ind_performances[elite_idx]
        elite_std_fitness = std(filter(!isnan, ind_performances))
        best_program = population_programs[elite_idx]
        genome = deepcopy(population[elite_idx])

        try
            histogram(ind_performances, nbins = 20) |> println
        catch e
            @error "Could not drawn histogram"
        end

        # EPOCH CALLBACK
        if !isnothing(epoch_callbacks)
            _make_epoch_callbacks_calls(
                ind_performances,
                population,
                iteration,
                run_config,
                model_architecture,
                node_config,
                meta_library,
                shared_inputs,
                population_programs,
                elite_best_fitness,
                best_program,
                elite_idx,
                view(batch, :),
                epoch_callbacks,
            )
        end
        # MU CALLBACKS # TODO

        # LAMBDA CALLBACKS # TODO

        # GENOME SIZE CALLBACKS # TODO

        # store iteration loss/fitness
        affect_fitness_to_loss_tracker!(M_gen_loss_tracker, iteration, elite_best_fitness)

        println(
            "Iteration $iteration loss: $(round(elite_best_fitness, digits = 10)) at index $elite_idx. Std: $(round(elite_std_fitness))",
        )

        # EARLY STOP CALLBACK # TODO
        if !isnothing(early_stop_callbacks) && length(early_stop_callbacks) != 0
            early_stop = _make_early_stop_callbacks_calls(
                M_gen_loss_tracker,
                M_individual_loss_tracker,
                ind_performances,
                population,
                iteration,
                run_config,
                model_architecture,
                node_config,
                meta_library,
                shared_inputs,
                population_programs,
                elite_best_fitness,
                best_program,
                elite_idx,
                early_stop_callbacks,
            ) # true if any
        end

        if early_stop
            g = run_config.generations
            @warn "Early returning at iteration : $iteration from $g total iterations"
            if !isnothing(last_callback)
                last_callback(
                    ind_performances,
                    population,
                    iteration,
                    run_config,
                    model_architecture,
                    node_config,
                    meta_library,
                    population_programs,
                    elite_best_fitness,
                    best_program,
                    elite_idx,
                )
            end
            return tuple(genome, best_program, M_gen_loss_tracker)
        end

    end
    # LAST CALLBACK 
    # if !isnothing(last_callback)
    #     last_callback(
    #         ind_performances,
    #         population,
    #         iteration,
    #         run_config,
    #         model_architecture,
    #         node_config,
    #         meta_library,
    #         population_programs,
    #         best_loss,
    #         best_program,
    #         elite_idx,
    #     )
    # end
    return (genome, best_program, M_gen_loss_tracker)
end


