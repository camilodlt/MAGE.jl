# -*- coding: utf-8 -*-
using Statistics

### FIT API ###

function fit(
    X::Any,
    Y::Any,
    shared_inputs::SharedInput,
    genome::UTGenome,
    model_architecture::modelArchitecture,
    node_config::nodeConfig,
    run_config::runConf,
    meta_library::MetaLibrary,
    # Callbacks before training
    pre_callbacks::Union{Nothing,Vector{Symbol}},
    # Callbacks before step (before looping through data)
    population_callbacks::Vector{Symbol},
    mutation_callbacks::Vector{Symbol},
    output_mutation_callbacks::Vector{Symbol},
    decoding_callbacks::Vector{Symbol},
    # Callbacks per step (while looping through data)
    endpoint_callback::Type{<:BatchEndpoint},
    final_step_callbacks::Union{Nothing,Vector{Function}},
    # Callbacks after step ::
    elite_selection_callbacks::Vector{Symbol},
    epoch_callbacks::Union{Nothing,Vector{<:Union{Symbol,AbstractCallable}}},
    early_stop_callback::Union{Nothing,Symbol} = nothing,
) # Tuple{UTGenome, IndividualPrograms, GenerationLossTracker}::

    local early_stop = false
    local best_program = nothing

    # CALL PRE CALLBACKS
    if !isnothing(pre_callbacks) && length(pre_callbacks) > 1
        for pre_callback in pre_callbacks
            pre_callback()
        end
    end

    M_gen_loss_tracker = GenerationLossTracker()
    for iteration = 1:run_config.generations
        if early_stop
            break
        end
        @warn "Iteration : $iteration"
        M_individual_loss_tracker = IndividualLossTracker()
        # Population
        parent = deepcopy(genome)

        population, time_pop = _make_population(
            deepcopy(genome),
            iteration,
            run_config,
            model_architecture,
            node_config,
            meta_library,
            population_callbacks,
        )
        print(size(population))

        population, time_mut = _make_mutations(
            population,
            iteration,
            run_config,
            model_architecture,
            node_config,
            meta_library,
            shared_inputs,
            mutation_callbacks,
        )

        population, time_out_mut = _make_output_mutations(
            population,
            iteration,
            run_config,
            model_architecture,
            node_config,
            meta_library,
            output_mutation_callbacks,
        )

        # ADD Parent
        if iteration > 1
            push!(population.pop, parent)
        end

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

        for ith_x = 1:length(X)
            # unpack input nodes
            x, y = X[ith_x], Y[ith_x]
            input_nodes = [
                InputNode(value, pos, pos, model_architecture.inputs_types_idx[pos]) for
                (pos, value) in enumerate(x)
            ]
            # append input nodes to pop
            replace_shared_inputs!(shared_inputs, input_nodes) # update 
            # Eval pop wrt training data
            time_eval = @elapsed outputs = evaluate_population_programs(
                population_programs,
                model_architecture,
                meta_library,
            )
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

        # pdb.set_trace()
        # Elite selection callbacks
        elite_idx, time_elite = _make_elite_selection(
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

        best_loss = ind_performances[elite_idx]
        std_ = std(ind_performances)
        best_program = population_programs[elite_idx]
        genome = deepcopy(population[elite_idx])

        # EPOCH CALLBACK
        if !isnothing(epoch_callbacks)
            _make_epoch_callbalcks_calls(
                ind_performances,
                population,
                iteration,
                run_config,
                model_architecture,
                node_config,
                meta_library,
                population_programs,
                best_loss,
                best_program,
                elite_idx,
                epoch_callbacks,
            )
        end
        # MU CALLBACKS # TODO

        # LAMBDA CALLBACKS # TODO

        # GENOME SIZE CALLBACKS # TODO

        # store iteration loss/fitness
        affect_fitness_to_loss_tracker!(M_gen_loss_tracker, iteration, best_loss)

        println(" Iteration loss: $best_loss at index $elite_idx. Std: $(round(std_))")

        # EARLY STOP CALLBACK # TODO
        if !isnothing(early_stop_callback)
            early_stop = get_fn_from_symbol(early_stop_callback)(
                M_gen_loss_tracker,
                iteration,
                run_config.generations,
                model_architecture,
                node_config,
            )
        end

        # LAST CALLBACK # TODO

        if early_stop
            g = run_config.generations
            @warn "Early returning at iteration : $iteration from $g total iterations"
            return tuple(genome, best_program, M_gen_loss_tracker)
        end
    end
    return (genome, best_program, M_gen_loss_tracker)
end

