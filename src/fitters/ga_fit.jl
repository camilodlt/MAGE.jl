# -*- coding: utf-8 -*-
using Statistics
using Debugger
using UnicodePlots
using Term

function _ga_init_params(genome::UTGenome, run_config::AbstractRunConf)
    early_stop = false
    best_programs = nothing
    elite_idx = nothing
    population = UTCGP.Population([deepcopy(genome) for i = 1:run_config.n_elite]) # initial pop 
    ind_performances = [1.0 for i = 1:run_config.n_elite]
    return early_stop, best_programs, elite_idx, population, ind_performances
end

function fit_ga(
    X::Any,
    Y::Union{Any,Nothing},
    shared_inputs::SharedInput,
    genome::UTGenome,
    model_architecture::modelArchitecture,
    node_config::nodeConfig,
    run_config::RunConfGA,
    meta_library::MetaLibrary,
    # Callbacks before training
    pre_callbacks::Optional_FN,
    # Callbacks before step (before looping through data)
    population_callbacks::Mandatory_FN,
    mutation_callbacks::Mandatory_FN,
    output_mutation_callbacks::Mandatory_FN,
    decoding_callbacks::Mandatory_FN,
    # Callbacks per step (while looping through data)
    endpoint_callback::Union{Type{<:BatchEndpoint},<:BatchEndpoint},
    final_step_callbacks::Optional_FN,
    # Callbacks after step ::
    elite_selection_callbacks::Mandatory_FN,
    epoch_callbacks::Optional_FN,
    early_stop_callbacks::Optional_FN,
    last_callback::Optional_FN,
) # Tuple{UTGenome, IndividualPrograms, GenerationLossTracker}::

    local early_stop, best_programs, elite_idx, population, ind_performances, =
        _ga_init_params(genome, run_config)

    # PRE CALLBACKS
    _make_pre_callbacks_calls(pre_callbacks)
    M_gen_loss_tracker = GenerationLossTracker()

    for iteration = 1:run_config.generations
        early_stop ? break : nothing
        @warn "Iteration : $iteration"
        M_individual_loss_tracker = IndividualLossTracker()
        # Population
        ga_pop_args = GA_POP_ARGS(
            population,
            iteration,
            run_config,
            model_architecture,
            node_config,
            meta_library,
            ind_performances,
        )
        population, time_pop =
            @unwrap_or _make_ga_population(ga_pop_args, population_callbacks) throw(
                "Could not unwrap make_population",
            )
        @info "Time Population $time_pop"

        # Program mutations ---
        ga_mutation_args = GA_MUTATION_ARGS(
            population,
            iteration,
            run_config,
            model_architecture,
            node_config,
            meta_library,
            shared_inputs,
        )
        population, time_mut =
            @unwrap_or _make_ga_mutations!(ga_mutation_args, mutation_callbacks) throw(
                "Could not unwrap make_ga_mutations",
            )
        @info "Time Mutation $time_mut"

        # Output mutations ---
        population, time_out_mut = @unwrap_or _make_ga_output_mutations!(
            ga_mutation_args,
            output_mutation_callbacks,
        ) throw("Could not unwrap make_ga_output_mutations")
        @info "Time Out Mutation $time_out_mut"

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
        @info "Time Decoding $time_pop_prog"

        @warn "Graphs evals"
        for ith_x = 1:length(X)
            # unpack input nodes
            if isnothing(Y) # X is dataloader
                x, y = X[ith_x]
            else
                x, y = X[ith_x], Y[ith_x]
            end
            input_nodes = [
                InputNode(value, pos, pos, model_architecture.inputs_types_idx[pos]) for
                (pos, value) in enumerate(x)
            ]
            # append input nodes to pop
            replace_shared_inputs!(population_programs, input_nodes) # update 
            time_eval = @elapsed outputs = evaluate_population_programs(
                population_programs,
                model_architecture,
                meta_library,
            )
            @info "Time Eval $time_eval"
            # Endpoint results
            fitness = endpoint_callback(outputs, y)
            fitness_values = get_endpoint_results(fitness)

            add_pop_loss_to_ind_tracker!(M_individual_loss_tracker, fitness_values)  # appends the loss for the ith x sample to the

            # Resetting the population (removes node values)
            [reset_genome!(g) for g in population]

            # final step call...
            if !isnothing(final_step_callbacks)
                for final_step_callback in final_step_callbacks
                    get_fn_from_symbol(final_step_callback)()
                end
            end
        end

        # DUPLICATES # TODO

        # Selection
        ind_performances = resolve_ind_loss_tracker(M_individual_loss_tracker)
        @bp
        # Elite selection callbacks
        @warn "Selection"
        ga_selection_args = GA_SELECTION_ARGS(
            ind_performances,
            population,
            iteration,
            run_config,
            model_architecture,
            node_config,
            meta_library,
            population_programs,
        )
        elite_idx, time_elite = @unwrap_or _make_ga_elite_selection(
            ga_selection_args,
            elite_selection_callbacks,
        ) throw("Could not unwrap make_ga_selection")

        elite_fitnesses = ind_performances[elite_idx]
        elite_best_fitness = minimum(skipmissing(elite_fitnesses))
        elite_best_fitness_idx = elite_fitnesses[1]
        elite_avg_fitness = mean(skipmissing(elite_fitnesses))
        elite_std_fitness = std(filter(!isnan, ind_performances))
        best_programs = population_programs[elite_idx]
        # genome = deepcopy(population[elite_idx])
        try
            histogram(ind_performances) |> println
        catch e
            @error "Could not drawn histogram"
        end

        # Subset Based on Elite IDX---
        old_pop = deepcopy(population.pop[elite_idx])
        empty!(population.pop)
        push!(population.pop, old_pop...)
        ind_performances = ind_performances[elite_idx]

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
                elite_fitnesses,
                best_programs,
                elite_idx,
                epoch_callbacks,
            )
        end
        # MU CALLBACKS # TODO

        # LAMBDA CALLBACKS # TODO

        # GENOME SIZE CALLBACKS # TODO

        # store iteration loss/fitness
        affect_fitness_to_loss_tracker!(M_gen_loss_tracker, iteration, elite_best_fitness)
        println(
            "Iteration $iteration. 
            Best fitness: $(round(elite_best_fitness, digits = 10)) at index $elite_best_fitness_idx 
            Elite mean fitness : $(round(elite_avg_fitness, digits = 10)). Std: $(round(elite_std_fitness)) at indices : $(elite_idx)",
        )

        # EARLY STOP CALLBACK # TODO
        if !isnothing(early_stop_callbacks) && length(early_stop_callbacks) != 0
            early_stop_args = GA_EARLYSTOP_ARGS(
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
                elite_fitnesses,
                best_programs,
                elite_idx,
            )

            early_stop =
                _make_ga_early_stop_callbacks_calls(early_stop_args, early_stop_callbacks) # true if any
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
                    elite_fitnesses,
                    best_programs,
                    elite_idx,
                )
            end
            # UTCGP.show_program(program)
            return tuple(genome, best_programs, M_gen_loss_tracker)
        end

    end
    return (genome, best_programs, M_gen_loss_tracker)
end


function fit_ga_mt(
    X::Any,
    Y::Union{Any,Nothing},
    shared_inputs::SharedInput,
    genome::UTGenome,
    model_architecture::modelArchitecture,
    node_config::nodeConfig,
    run_config::RunConfGA,
    meta_library::MetaLibrary,
    # Callbacks before training
    pre_callbacks::Optional_FN,
    # Callbacks before step (before looping through data)
    population_callbacks::Mandatory_FN,
    mutation_callbacks::Mandatory_FN,
    output_mutation_callbacks::Mandatory_FN,
    decoding_callbacks::Mandatory_FN,
    # Callbacks per step (while looping through data)
    endpoint_callback::Union{Type{<:BatchEndpoint},<:BatchEndpoint},
    final_step_callbacks::Optional_FN,
    # Callbacks after step ::
    elite_selection_callbacks::Mandatory_FN,
    epoch_callbacks::Optional_FN,
    early_stop_callbacks::Optional_FN,
    last_callback::Optional_FN,
) # Tuple{UTGenome, IndividualPrograms, GenerationLossTracker}::

    local early_stop, best_programs, elite_idx, population, ind_performances, =
        _ga_init_params(genome, run_config)
    # DL 
    BatchSize = X.batch_size
    TrainSize = length(X)

    # PRE CALLBACKS
    _make_pre_callbacks_calls(pre_callbacks)
    M_gen_loss_tracker = GenerationLossTracker()

    for iteration = 1:run_config.generations
        early_stop ? break : nothing
        @warn "Iteration : $iteration"
        # Population
        ga_pop_args = GA_POP_ARGS(
            population,
            iteration,
            run_config,
            model_architecture,
            node_config,
            meta_library,
            ind_performances,
        )
        population, time_pop =
            @unwrap_or _make_ga_population(ga_pop_args, population_callbacks) throw(
                "Could not unwrap make_population",
            )

        # Program mutations ---
        ga_mutation_args = GA_MUTATION_ARGS(
            population,
            iteration,
            run_config,
            model_architecture,
            node_config,
            meta_library,
            shared_inputs,
        )
        population, time_mut =
            @unwrap_or _make_ga_mutations!(ga_mutation_args, mutation_callbacks) throw(
                "Could not unwrap make_ga_mutations",
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

        # Storage for all evaluations (pop * X)
        M_individual_loss_tracker = IndividualLossTrackerMT(length(population), length(X))

        @warn "Multi Threaded Graphs evals"
        UTCGP.reset_programs!(population_programs)
        batch = X[1:TrainSize] # should do in parallel
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

        # final step call...
        if !isnothing(final_step_callbacks)
            for final_step_callback in final_step_callbacks
                get_fn_from_symbol(final_step_callback)()
            end
        end

        # DUPLICATES # TODO

        # Selection
        ind_performances = resolve_ind_loss_tracker(M_individual_loss_tracker)
        @bp
        # Elite selection callbacks
        ga_selection_args = GA_SELECTION_ARGS(
            ind_performances,
            population,
            iteration,
            run_config,
            model_architecture,
            node_config,
            meta_library,
            population_programs,
        )

        elite_idx, time_elite = @unwrap_or _make_ga_elite_selection(
            ga_selection_args,
            elite_selection_callbacks,
        ) throw("Could not unwrap make_ga_selection")

        elite_fitnesses = ind_performances[elite_idx]
        elite_best_fitness = minimum(skipmissing(elite_fitnesses))
        elite_best_ftiness_idx = argmin(elite_fitnesses)
        elite_avg_fitness = mean(skipmissing(elite_fitnesses))
        elite_std_fitness = std(filter(!isnan, ind_performances))
        best_programs = population_programs[elite_idx]
        # genome = deepcopy(population[elite_idx])
        try
            histogram(ind_performances) |> println
        catch e
            @error "Could not drawn histogram"
        end


        # Subset Based on Elite IDX---
        old_pop = deepcopy(population.pop[elite_idx])
        empty!(population.pop)
        push!(population.pop, old_pop...)
        ind_performances = ind_performances[elite_idx]
        try
            histogram(ind_performances) |> println
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
                elite_fitnesses,
                best_programs,
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
            "Iteration $iteration. 
            Best fitness: $(round(elite_best_fitness, digits = 10)) at index $elite_best_ftiness_idx 
            Elite mean fitness : $(round(elite_avg_fitness, digits = 10)). Std: $(round(elite_std_fitness)) at indices : $(elite_idx)",
        )

        # EARLY STOP CALLBACK # TODO
        if !isnothing(early_stop_callbacks) && length(early_stop_callbacks) != 0
            early_stop_args = GA_EARLYSTOP_ARGS(
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
                elite_fitnesses,
                best_programs,
                elite_idx,
            )
            early_stop =
                _make_ga_early_stop_callbacks_calls(early_stop_args, early_stop_callbacks) # true if any
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
                    elite_fitnesses,
                    best_programs,
                    elite_idx,
                )
            end
            # UTCGP.show_program(program)
            return tuple(genome, best_programs, M_gen_loss_tracker)
        end

        gct = @elapsed GC.gc(false)
        @warn "Running GC at the end of iteration. GC time : $gct"

    end
    return (genome, best_programs, M_gen_loss_tracker)
end


# MEAN BATCH #
function fit_ga_meanbatch_mt(
    X::Any,
    Y::Union{Any,Nothing},
    n_repetitions::Int,
    shared_inputs::SharedInput,
    genome::UTGenome,
    model_architecture::modelArchitecture,
    node_config::nodeConfig,
    run_config::RunConfGA,
    meta_library::MetaLibrary,
    # Callbacks before training
    pre_callbacks::Optional_FN,
    # Callbacks before step (before looping through data)
    population_callbacks::Mandatory_FN,
    mutation_callbacks::Mandatory_FN,
    output_mutation_callbacks::Mandatory_FN,
    decoding_callbacks::Mandatory_FN,
    # Callbacks per step (while looping through data)
    endpoint_callback::Union{Type{<:BatchEndpoint},<:BatchEndpoint},
    final_step_callbacks::Optional_FN,
    # Callbacks after step ::
    elite_selection_callbacks::Mandatory_FN,
    epoch_callbacks::Optional_FN,
    early_stop_callbacks::Optional_FN,
    last_callback::Optional_FN,
) # Tuple{UTGenome, IndividualPrograms, GenerationLossTracker}::

    local early_stop, best_programs, elite_idx, population, ind_performances, =
        _ga_init_params(genome, run_config)
    # DL 
    BatchSize = X.batch_size
    TrainSize = length(X)

    # PRE CALLBACKS
    _make_pre_callbacks_calls(pre_callbacks)
    M_gen_loss_tracker = GenerationLossTracker()

    for iteration = 1:run_config.generations
        early_stop ? break : nothing
        @warn "Iteration : $iteration"
        # Population
        ga_pop_args = GA_POP_ARGS(
            population,
            iteration,
            run_config,
            model_architecture,
            node_config,
            meta_library,
            ind_performances,
        )
        population, time_pop =
            @unwrap_or _make_ga_population(ga_pop_args, population_callbacks) throw(
                "Could not unwrap make_population",
            )

        # Program mutations ---
        ga_mutation_args = GA_MUTATION_ARGS(
            population,
            iteration,
            run_config,
            model_architecture,
            node_config,
            meta_library,
            shared_inputs,
        )
        population, time_mut =
            @unwrap_or _make_ga_mutations!(ga_mutation_args, mutation_callbacks) throw(
                "Could not unwrap make_ga_mutations",
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

        # Storage for all evaluations (pop * X)
        pop_size = length(population)
        Repetitions_loss_tracker = Matrix{Float64}(undef, pop_size, n_repetitions)
        @warn "Multi Threaded Graphs evals"
        UTCGP.reset_programs!(population_programs)
        ALL_BATCHS = []
        for ith_repetition = 1:n_repetitions
            @info "Repetition n° $ith_repetition"
            UTCGP.reset_programs!(population_programs)
            batch = X[1:TrainSize] # should do in parallel
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

            Repetitions_loss_tracker[:, ith_repetition] .= ind_performances
        end
        ind_performances = mean(Repetitions_loss_tracker, dims = 2)[:] # average over the 2nd dim => the repetitions

        # if isdefined(Main, :Infiltrator)
        #     Main.infiltrate(@__MODULE__, Base.@locals, @__FILE__, @__LINE__)
        # end

        # final step call...
        if !isnothing(final_step_callbacks)
            for final_step_callback in final_step_callbacks
                get_fn_from_symbol(final_step_callback)()
            end
        end

        # DUPLICATES # TODO

        # Selection
        # ind_performances = resolve_ind_loss_tracker(M_individual_loss_tracker)
        @bp
        # Elite selection callbacks
        ga_selection_args = GA_SELECTION_ARGS(
            ind_performances,
            population,
            iteration,
            run_config,
            model_architecture,
            node_config,
            meta_library,
            population_programs,
        )

        elite_idx, time_elite = @unwrap_or _make_ga_elite_selection(
            ga_selection_args,
            elite_selection_callbacks,
        ) throw("Could not unwrap make_ga_selection")

        elite_fitnesses = ind_performances[elite_idx]
        elite_best_fitness = minimum(skipmissing(elite_fitnesses))
        elite_best_ftiness_idx = argmin(elite_fitnesses)
        elite_avg_fitness = mean(skipmissing(elite_fitnesses))
        elite_std_fitness = std(filter(!isnan, ind_performances))
        best_programs = population_programs[elite_idx]
        # genome = deepcopy(population[elite_idx])
        try
            histogram(ind_performances) |> println
        catch e
            @error "Could not drawn histogram"
        end


        # Subset Based on Elite IDX---
        old_pop = deepcopy(population.pop[elite_idx])
        empty!(population.pop)
        push!(population.pop, old_pop...)
        ind_performances = ind_performances[elite_idx]
        try
            histogram(ind_performances) |> println
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
                elite_fitnesses,
                best_programs,
                elite_idx,
                view(ALL_BATCHS, :),
                epoch_callbacks,
            )
        end
        # MU CALLBACKS # TODO

        # LAMBDA CALLBACKS # TODO

        # GENOME SIZE CALLBACKS # TODO

        # store iteration loss/fitness
        affect_fitness_to_loss_tracker!(M_gen_loss_tracker, iteration, elite_best_fitness)
        println(
            "Iteration $iteration. 
            Best fitness: $(round(elite_best_fitness, digits = 10)) at index $elite_best_ftiness_idx 
            Elite mean fitness : $(round(elite_avg_fitness, digits = 10)). Std: $(round(elite_std_fitness)) at indices : $(elite_idx)",
        )

        # EARLY STOP CALLBACK # TODO
        EMPTY_TRACKER = IndividualLossTrackerMT(pop_size, TrainSize * n_repetitions)
        if !isnothing(early_stop_callbacks) && length(early_stop_callbacks) != 0
            early_stop_args = GA_EARLYSTOP_ARGS(
                M_gen_loss_tracker,
                EMPTY_TRACKER,
                ind_performances,
                population,
                iteration,
                run_config,
                model_architecture,
                node_config,
                meta_library,
                shared_inputs,
                population_programs,
                elite_fitnesses,
                best_programs,
                elite_idx,
            )
            early_stop =
                _make_ga_early_stop_callbacks_calls(early_stop_args, early_stop_callbacks) # true if any
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
                    elite_fitnesses,
                    best_programs,
                    elite_idx,
                )
            end
            # UTCGP.show_program(program)
            return tuple(genome, best_programs, M_gen_loss_tracker)
        end

        gct = @elapsed GC.gc(true)
        @warn "Running GC at the end of iteration. GC time : $gct"

    end
    return (genome, best_programs, M_gen_loss_tracker)
end

