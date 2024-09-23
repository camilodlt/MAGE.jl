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

function _me_init_params(genome::UTGenome, run_config::AbstractRunConf, ma, ml, si)
    early_stop = false
    best_programs = nothing
    elite_idx = nothing
    population = init_pop(genome, ma, ml, si, run_config.sample_size)
    return early_stop, best_programs, elite_idx, population
end

function fit_me_atari_mt(
    shared_inputs::SharedInput,
    genome::UTGenome,
    model_architecture::modelArchitecture,
    node_config::nodeConfig,
    run_config::RunConfME,
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
) # Tuple{UTGenome, IndividualPrograms, GenerationLossTracker}::

    local early_stop, best_programs, elite_idx, population =
        _me_init_params(genome, run_config, model_architecture, meta_library, shared_inputs)

    # PRE CALLBACKS
    _make_pre_callbacks_calls(pre_callbacks)
    M_gen_loss_tracker = GenerationLossTracker()
    ARCHIVE = MapelitesRepertoire(run_config.centroids)
    for iteration = 1:run_config.generations
        early_stop ? break : nothing
        @warn "Iteration : $iteration"
        # Population
        me_pop_args = ME_POP_ARGS(
            ARCHIVE,
            population,
            iteration,
            run_config,
            model_architecture,
            node_config,
            meta_library,
        )
        if iteration != 1
            population, time_pop =
                @unwrap_or _make_me_population(me_pop_args, population_callbacks) throw(
                    "Could not unwrap make_population",
                )
        end
        # Program mutations ---
        me_mutation_args = ME_MUTATION_ARGS(
            ARCHIVE,
            population,
            iteration,
            run_config,
            model_architecture,
            node_config,
            meta_library,
            shared_inputs,
        )
        population, time_mut =
            @unwrap_or _make_me_mutations!(me_mutation_args, mutation_callbacks) throw(
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
        endpoint_holder =
            endpoint_callback(population_programs, model_architecture, meta_library)
        fitness_values, descriptor_values = get_endpoint_results(endpoint_holder)
        # @show fitness_values descriptor_values
        UTCGP.add_pop_loss_to_ind_tracker!(M_individual_loss_tracker, fitness_values)  # appends the loss for the ith x sample to the


        # Resetting the population (removes node values)
        [reset_genome!(g) for g in population]

        # ME INSERTS
        batch_insert!(ARCHIVE, population.pop, fitness_values, descriptor_values)
        @show coverage(ARCHIVE)
        @show best_fitness(ARCHIVE)



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
            histogram(collect(skipmissing(ARCHIVE.fitness_values)))
        catch e
            @error "Could not drawn histogram"
        end

        # EPOCH CALLBACK
        if !isnothing(epoch_callbacks)
            epoch_callbacks[1](
            # _make_epoch_callbacks_calls(
                ind_performances,
                ARCHIVE,
                iteration
                # ind_performances,
                # population,
                # iteration,
                # run_config,
                # model_architecture,
                # node_config,
                # meta_library,
                # shared_inputs,
                # population_programs,
                # [],
                # best_programs,
                # elite_idx,
                # view([], :),
                # epoch_callbacks,
            )
        end

        # store iteration loss/fitness
        affect_fitness_to_loss_tracker!(
            M_gen_loss_tracker,
            iteration,
            UTCGP.best_fitness(ARCHIVE),
        )
        println("Iteration $iteration. 
                 Archive best fitness : $(round(UTCGP.best_fitness(ARCHIVE), digits = 10))")

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
            return tuple(genome, best_programs, M_gen_loss_tracker)
        end

        gct = @elapsed GC.gc(false)
        @warn "Running GC at the end of iteration. GC time : $gct"

    end
    return (genome, best_programs, M_gen_loss_tracker)
end
