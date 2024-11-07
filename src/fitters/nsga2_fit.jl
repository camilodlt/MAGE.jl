# copied from ME fit, can we remove it and import it from there?
function fix_all_output_nodes!(ut_genome::UTGenome)
    for (ith_out_node, output_node) in enumerate(ut_genome.output_nodes)
        to_node = output_node[2].highest_bound + 1 - ith_out_node
        set_node_element_value!(output_node[2], to_node)
        set_node_freeze_state(output_node[2])
        set_node_freeze_state(output_node[1])
        set_node_freeze_state(output_node[3])
        println("Output node at $ith_out_node: $(output_node.id) pointing to $to_node")
        println("Output Node material : $(node_to_vector(output_node))")
    end
end

# copied from ME fit, can we remove it and import it from there?
function init_pop(genome, ma, ml, si, n_pop::Int)
    new_pop = Vector{UTGenome}(undef, n_pop)
    for i = 1:n_pop
        g_new = deepcopy(genome)
        # UTCGP.reset_genome!(g_new)
        # initialize_genome!(g_new)
        # correct_all_nodes!(g_new, ma, ml, si)
        # fix_all_output_nodes!(g_new)
        new_pop[i] = g_new
    end
    Population(deepcopy(new_pop))
end

function _nsga2_init_params(genome::UTGenome, run_config::RunConfNSGA2)
    early_stop = false
    best_programs = nothing
    pareto_front_idx = nothing
    population = UTCGP.Population([deepcopy(genome) for i = 1:run_config.pop_size]) # initial pop 
    ranks = [1 for i=1:run_config.pop_size]
    distances = [0. for i=1:run_config.pop_size]
    return early_stop, best_programs, pareto_front_idx, population, ranks, distances
end

# computes the ranks in terms of pareto fronts
function _rank_population(fitness_values::Vector{Vector{Float64}})
    ranks = Vector{Int64}(undef, length(fitness_values))
    for rank = 1:length(fitness_values)
        current_fitnesses = fitness_values[ranks.>rank]
        if length(current_fitnesses) < 1
            break
        end
        for (fit_idx, fit) in enumerate(fitness_values)
            if isdefined(ranks, fit_idx)
                continue
            end
            dominated = [all(diff -> diff >= 0, fit .- f) && any(diff -> diff > 0, fit .- f) for f in current_fitnesses]
            if all(!, dominated)
                ranks[fit_idx] = rank
            end
        end
    end
    return ranks
end

# computes the crowding distance regardless of the dominance
function _crowding_distance(fitness_values::Vector{Vector{Float64}})
    matrix_fitnesses = mapreduce(permutedims, vcat, fitness_values)
    distances = Vector{Float64}(0., length(fitness_values))
    for m = 1:length(fitness_values[1])
        min_m = minimum(matrix_fitnesses[:,m])
        max_m = maximum(matrix_fitnesses[:,m])
        sorted_indexes = sortperm(matrix_fitnesses[:,m])
        distances[sorted_indexes[1]] = inf
        distances[sorted_indexes[length(sorted_indexes)]] = inf
        for idx in 2:length(sorted_indexes)-1
            distances[idx] += (matrix_fitnesses[sorted_indexes[idx+1],m] - matrix_fitnesses[sorted_indexes[idx-1],m]) / (max_m - min_m)
        end
    end
    return distances
end

function _ranks_and_crowding_distances(fitness_values::Vector{Vector{Float64}})
    ranks = _rank_population(fitness_values)
    distances = Vector{Float64}(0., length(fitness_values))
    for rank = minimum(ranks):maximum(ranks)
        current_rank_indexes = findall(==(rank), ranks)
        distances[current_rank_indexes] = _crowding_distance(fitness_values[current_rank_indexes])
    end
    return (ranks, distances)
end

function fit_nsga2_atari_mt(
    shared_inputs::SharedInput,
    genome::UTGenome,
    model_architecture::modelArchitecture,
    node_config::nodeConfig,
    run_config::RunConfNSGA2,
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
    survival_selection_callbacks::Optional_FN,
    epoch_callbacks::Optional_FN,
    early_stop_callbacks::Optional_FN,
    last_callback::Optional_FN,
) # Tuple{Vector{UTGenome}, Vector{IndividualPrograms}, GenerationMultiObjectiveLossTracker}::

    local early_stop, best_programs, pareto_front_idx, population, ranks, distances =
        _nsga2_init_params(genome, run_config)

    # PRE CALLBACKS
    _make_pre_callbacks_calls(pre_callbacks)
    M_gen_loss_tracker = GenerationMultiObjectiveLossTracker()
    for iteration = 1:run_config.generations
        early_stop ? break : nothing
        @warn "Iteration : $iteration"
            
        # Population
        nsga2_pop_args = NSGA2_POP_ARGS(
            population,
            iteration,
            run_config,
            model_architecture,
            node_config,
            meta_library,
            ind_performances,
            ranks,
            distances
        )
        if iteration > 1
            # Compute offspring 
            offspring, time_pop =
                @unwrap_or _make_nsga2_population(nsga2_pop_args, population_callbacks) throw(
                    "Could not unwrap make_population",
                )
            # Offspring mutation
            nsga2_mutation_args = NSGA2_MUTATION_ARGS(
                offspring,
                iteration,
                run_config,
                model_architecture,
                node_config,
                meta_library,
                shared_inputs,
            )
            offspring, time_mut =
                @unwrap_or _make_nsga2_mutations!(nsga2_mutation_args, mutation_callbacks) throw(
                    "Could not unwrap make_me_mutations",
                )

            # Output mutations ---
            # offspring, time_out_mut = @unwrap_or _make_ga_output_mutations!(
            #     ga_mutation_args,
            #     output_mutation_callbacks,
            # ) throw("Could not unwrap make_ga_output_mutations")
        else
         offspring = population
        end

        # Genotype to Phenotype mapping --- 
        offspring_programs, time_pop_prog = _make_decoding(
            offspring,
            iteration,
            run_config,
            model_architecture,
            node_config,
            meta_library,
            shared_inputs,
            decoding_callbacks,
        )

        UTCGP.reset_programs!.(offspring_programs)

        # TODO implement tracker for vector fitnesses
        # M_individual_loss_tracker = IndividualLossTracker() # size of []

        @warn "MT Graphs evals"
        endpoint_holder = endpoint_callback(
            offspring_programs,
            model_architecture,
            meta_library,
            iteration,
        )
        offspring_fitness_values = get_endpoint_results(endpoint_holder) # Vector{Vector{Float64}}
        
        # TODO implement tracker for vector fitnesses
        # UTCGP.add_pop_loss_to_ind_tracker!(M_individual_loss_tracker, fitness_values)  # appends the loss for the ith x sample to the

        # Resetting the population (removes node values)
        [reset_genome!(g) for g in offspring]

        # final step call...
        if !isnothing(final_step_callbacks)
            for final_step_callback in final_step_callbacks
                UTCGP.get_fn_from_symbol(final_step_callback)()
            end
        end

        # Merge parents and offspring
        if generation > 1
            fitness_values = vcat(ind_performances, offspring_fitness_values)
            full_population = Population(vcat(population.pop, offspring.pop))
        else
            fitness_values = offspring_fitness_values
            full_population = offspring.pop
        end

        ranks, distances = _ranks_and_crowding_distances(fitness_values)

        # Survival selection
        nsga2_selection_args = NSGA2_SELECTION_ARGS(
            ranks,
            distances,
            full_population,
            run_config,
        )
        survival_idx, time_survival = @unwrap_or _make_nsga2_survival_selection(
            nsga2_selection_args,
            survival_selection_callbacks,
        ) throw("Could not unwrap make_nsga2_selection")

        ind_performances = fitness_values[survival_idx]
        elite_ranks = ranks[survival_idx]
        population = full_population[survival_idx]

        # TODO loss trackers
        # ind_performances = UTCGP.resolve_ind_loss_tracker(M_individual_loss_tracker)

        # try
        #     # histogram(ind_performances) |> println
        #     # histogram([d[1] for d in descriptor_values]) |> println
        #     # @show ARCHIVE.descriptors
        #     histogram(collect(skipmissing(ARCHIVE.fitness_values)))
        # catch e
        #     @error "Could not drawn histogram"
        # end

        # EPOCH CALLBACK
        if !isnothing(epoch_callbacks)
            _make_epoch_callbacks_calls(
                ind_performances,
                elite_ranks,
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
                epoch_callbacks,
            )
        end

        pareto_front_individuals = population[findall(==(minimum(elite_ranks)), elite_ranks)]
        pareto_front_fitnesses = ind_performances[findall(==(minimum(elite_ranks)), elite_ranks)]
        best_programs = decode_with_output_nodes.(
            pareto_front_individuals,
            meta_library,
            model_architecture,
            shared_inputs,
        )

        # store iteration loss/fitness
        affect_fitness_to_loss_tracker!(
            M_gen_loss_tracker,
            iteration,
            pareto_front_fitnesses,
        )
        println("Iteration $iteration. 
                 Pareto front fitness values : $pareto_front_fitnesses")

        # EARLY STOP CALLBACK 
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
            return tuple(pareto_front_individuals, best_programs, M_gen_loss_tracker)
        end

        gct = @elapsed GC.gc(false)
        @warn "Running GC at the end of iteration. GC time : $gct"

    end

    return (pareto_front_individuals, best_programs, M_gen_loss_tracker)
end
