# -*- coding: utf-8 -*-
using Statistics
using Debugger
using Term
using ErrorTypes

# using Infiltrator

### FIT API ###

function fit(
    X::Any,
    Y::Union{Any,Nothing},
    shared_inputs::SharedInput,
    genome::UTGenome,
    model_architecture::modelArchitecture,
    node_config::nodeConfig,
    run_config::runConf,
    meta_library::MetaLibrary,
    # Callbacks before training
    pre_callbacks::UTCGP.Optional_FN,
    # Callbacks before step (before looping through data)
    population_callbacks::UTCGP.Mandatory_FN,
    mutation_callbacks::UTCGP.Mandatory_FN,
    output_mutation_callbacks::UTCGP.Mandatory_FN,
    decoding_callbacks::UTCGP.Mandatory_FN,
    # Callbacks per step (while looping through data)
    endpoint_callback::Union{Type{<:UTCGP.BatchEndpoint},<:UTCGP.BatchEndpoint},
    final_step_callbacks::UTCGP.Optional_FN,
    # Callbacks after step ::
    elite_selection_callbacks::UTCGP.Mandatory_FN,
    epoch_callbacks::UTCGP.Optional_FN,
    early_stop_callbacks::UTCGP.Optional_FN,
    last_callback::UTCGP.Optional_FN,
) # Tuple{UTGenome, IndividualPrograms, GenerationLossTracker}::

    local early_stop = false
    local best_program = nothing
    local population = nothing
    local elite_idx
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
        @info "Time Population $time_pop"

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
        @info "Time Mutation $time_mut"

        population, time_out_mut = _make_output_mutations(
            population,
            iteration,
            run_config,
            model_architecture,
            node_config,
            meta_library,
            output_mutation_callbacks,
        )
        @info "Time Out Mutation $time_out_mut"

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
            @bp
            time_eval = @elapsed outputs = evaluate_population_programs(
                population_programs,
                model_architecture,
                meta_library,
            )
            # @info "Time Eval $time_eval"
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

        # Elite selection callbacks
        @warn "Selection"
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
        std_ = std(filter(!isnan, ind_performances))
        best_program = population_programs[elite_idx]
        genome = deepcopy(population[elite_idx])


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
                best_loss,
                best_program,
                elite_idx,
                view(X, :),
                epoch_callbacks,
            )
        end
        # MU CALLBACKS # TODO

        # LAMBDA CALLBACKS # TODO

        # GENOME SIZE CALLBACKS # TODO

        # store iteration loss/fitness
        affect_fitness_to_loss_tracker!(M_gen_loss_tracker, iteration, best_loss)

        println(
            "Iteration $iteration loss: $(round(best_loss, digits = 10)) at index $elite_idx. Std: $(round(std_))",
        )

        # EARLY STOP CALLBACK # TODO
        if !isnothing(early_stop_callbacks) && length(early_stop_callbacks) == 0
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
                best_loss,
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
                    best_loss,
                    best_program,
                    elite_idx,
                )
            end

            tree_dict = Dict()
            function print_node__(io, node; kw...)
                theme::Term.Theme = Term.TERM_THEME[]

                styled = if (node isa AbstractString || node isa Number)
                    Term.highlight(string(node), :string; theme = theme)
                else
                    styled = Term.highlight(typeof(node); theme = theme)
                end
                reshaped = Term.reshape_text(styled, theme.tree_max_leaf_width)
                print(io, reshaped)

            end


            for (i, prog) in enumerate(best_program)
                name = "Program n $i"
                ops = OrderedDict()
                for op in prog
                    node_name =
                        "$(typeof(op.calling_node)) " *
                        string(node_to_vector(op.calling_node)) *
                        " at $(op.calling_node.id)"
                    op_dict = Dict()
                    ins = [
                        UTCGP._extract_input_node_from_operationInput(
                            shared_inputs,
                            inp,
                        ).id for inp in op.inputs
                    ]
                    Base.insert!(ins, 1, string(op.fn.name))
                    op_dict[node_name] = ins
                    ops[op.calling_node.id] = op_dict
                end
                tree_dict[name] = ops
            end
            println(Term.Tree(tree_dict, print_node_function = print_node__))
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
    # LAST PRINT 
    # println("LAST OUTPUTS")
    # time_test_inference = @elapsed for ith_x = 1:length(X)
    #     reset_genome!(population[elite_idx])

    #     # unpack input nodes
    #     x, y = X[ith_x], Y[ith_x]
    #     input_nodes = [
    #         InputNode(value, pos, pos, model_architecture.inputs_types_idx[pos]) for
    #         (pos, value) in enumerate(x)
    #     ]
    #     # append input nodes to pop
    #     replace_shared_inputs!(shared_inputs, input_nodes) # update 
    #     outputs = evaluate_individual_programs(
    #         best_program,
    #         model_architecture.chromosomes_types,
    #         meta_library,
    #     )
    #     # Endpoint results
    #     @show ith_x x y outputs
    #     fitness = endpoint_callback([outputs], y) # batch of 1 ind
    #     @show fitness
    # end
    # @info "Time Test Inference $time_test_inference"

    tree_dict = Dict()
    function print_node_(io, node; kw...)
        theme::Term.Theme = Term.TERM_THEME[]

        styled = if (node isa AbstractString || node isa Number)
            Term.highlight(string(node), :string; theme = theme)
        else
            styled = Term.highlight(typeof(node); theme = theme)
        end
        reshaped = Term.reshape_text(styled, theme.tree_max_leaf_width)
        print(io, reshaped)

    end

    for (i, prog) in enumerate(best_program)
        name = "Program n $i"
        ops = OrderedDict()
        for op in prog
            node_name =
                "$(typeof(op.calling_node)) " *
                string(node_to_vector(op.calling_node)) *
                " at $(op.calling_node.id)"
            op_dict = Dict()
            ins = [
                unwrap_or(
                    UTCGP._extract_input_node_from_operationInput(shared_inputs, inp),
                    nothing,
                ).id for inp in op.inputs
            ]
            Base.insert!(ins, 1, string(op.fn.name))
            op_dict[node_name] = ins
            ops[op.calling_node.id] = op_dict
        end
        tree_dict[name] = ops
    end
    println(Term.Tree(tree_dict, print_node_function = print_node_))
    return (genome, best_program, M_gen_loss_tracker)
end

