# -*- coding:: utf-8 -*-
using Statistics

function _make_population(
    genome::UTGenome,
    generation::Int,
    run_config::runConf,
    model_architecture::modelArchitecture,
    node_config::nodeConfig,
    meta_library::MetaLibrary,
    population_callbacks::Vector{Symbol},
    args...,
)::Tuple{Population,Float64}
    """
    Make the population based on first/elite genome

    Returns the population and the time it took to make the final population
    """

    t = []
    population = Population(UTGenome[genome])

    for population_callback in population_callbacks
        fn = get_fn_from_symbol(population_callback)
        t_e = @elapsed population = fn(
            population,
            generation,
            run_config,
            model_architecture,
            node_config,
            meta_library,
        )
        push!(t, t_e)
    end
    return tuple(population, mean(t))
end

function _make_mutations(
    population::Population,
    generation::Int,
    run_config::runConf,
    model_architecture::modelArchitecture,
    node_config::nodeConfig,
    meta_library::MetaLibrary,
    shared_inputs::SharedInput,
    mutation_callbacks::Vector{Symbol},
    args...,
)::Tuple{Population,Float64}
    """

    Mutate the population

    Returns the population and the time it took to make the final population
    """
    t = []

    for mutation_callback in mutation_callbacks
        fn = get_fn_from_symbol(mutation_callback)
        t_e = @elapsed population = fn(
            population,
            generation,
            run_config,
            model_architecture,
            node_config,
            meta_library,
            shared_inputs,
        )
        push!(t, t_e)
    end
    return tuple(population, mean(t))
end

function _make_output_mutations(
    population::Population,
    generation::Int,
    run_config::runConf,
    model_architecture::modelArchitecture,
    node_config::nodeConfig,
    meta_library::MetaLibrary,
    output_mutation_callbacks::Vector{Symbol},
    args...,
)::Tuple{Population,Float64}
    """
    Mutate the ouput nodes of ALL the population

    Returns the population and the time it took to make the final population
    """
    t = []

    for output_callback in output_mutation_callbacks
        fn = get_fn_from_symbol(output_callback)
        t_e = @elapsed population = fn(
            population,
            generation,
            run_config,
            model_architecture,
            node_config,
            meta_library,
        )
        push!(t, t_e)
    end
    return tuple(population, mean(t))
end


function _make_decoding(
    population::Population,
    generation::Int,
    run_config::runConf,
    model_architecture::modelArchitecture,
    node_config::nodeConfig,
    meta_library::MetaLibrary,
    shared_inputs::SharedInput,
    decoding_callbacks::Vector{Symbol},
    args...,
)::Tuple[PopulationPrograms, Float64]
    """
    Decode the graph of ALL the POP.

    Accepts multiple fns. The first one will output a PopulationPrograms.
    The output will be reinjected in following calls.
    Either way, all calls have to return the PopulationPrograms

    Returns the population and the time it took to make the final population
    """

    t = []
    first_callback = decoding_callbacks[1]
    # FIRST CALL TO CREATE PROGRAMS 
    fn = get_fn_from_symbol(first_callback)
    t_e = @elapsed programs = fn(
        population,
        generation,
        run_config,
        model_architecture,
        node_config,
        meta_library,
        shared_inputs,
    )
    push!(t, t_e)

    # CONSECUTIVE CALLS 

    for decoding_callback in decoding_callbacks[2:end]
        fn = get_fn_from_symbol(decoding_callback)
        t_e = @elapsed programs = fn(
            population,
            generation,
            run_config,
            model_architecture,
            node_config,
            meta_library,
            shared_inputs,
            programs,
        )
        push!(t, t_e)
    end
    return tuple(programs, mean(t))
end




function _make_elite_selection(
    ind_performances::Union{Vector{<:Number},Vector{Vector{<:Number}}},
    population::Population,
    generation::Int,
    run_config::runConf,
    model_architecture::modelArchitecture,
    node_config::nodeConfig,
    meta_library::MetaLibrary,
    programs::PopulationPrograms,
    elite_selection_callbacks::Vector{Symbol},
    args...,
)::Tuple{Int,Float64}
    """
    Selects the best individual in the population.
    Return its index.

    Accepts multiple fns. The first one will output an elite idx.
    The output will be reinjected in following calls
    Either way, all calls have to return the elite_idx
    """

    t = []
    elite_idx::Int = nothing
    first_callback = elite_selection_callbacks[1]
    # FIRST CALL TO CREATE PROGRAMS 
    fn = get_fn_from_symbol(first_callback)
    t_e = @elapsed programs = fn(
        ind_performances,
        population,
        generation,
        run_config,
        model_architecture,
        node_config,
        meta_library,
        programs,
    )
    push!(t, t_e)

    # CONSECUTIVE CALLS 

    for elite_selection_callback in elite_selection_callbacks[2:end]
        fn = get_fn_from_symbol(elite_selection_callback)
        t_e = @elapsed elite_idx = fn(
            ind_performances,
            elite_idx,
            population,
            generation,
            run_config,
            model_architecture,
            node_config,
            meta_library,
            programs,
        )
        push!(t, t_e)
    end
    return tuple(elite_idx, mean(t))
end



function _make_epoch_callbalcks_calls(
    ind_performances::Union{Vector{<:Number},Vector{Vector{<:Number}}},
    population::Population,
    generation::Int,
    run_config::runConf,
    model_architecture::modelArchitecture,
    node_config::nodeConfig,
    meta_library::MetaLibrary,
    programs::PopulationPrograms,
    best_loss::Float64,
    best_program::IndividualPrograms,
    elite_idx::Int,
    epoch_callbacks::Vector{Symbol},
)::Float64

    t = []
    for epoch_callback in epoch_callbacks
        fn = get_fn_from_symbol(epoch_callback)
        t_e = @elapsed fn(
            ind_performances,
            population,
            generation,
            run_config,
            model_architecture,
            node_config,
            meta_library,
            programs,
            best_loss,
            best_program,
            elite_idx,
        )
        push!(t, t_e)
    end
    return mean(t)
end
