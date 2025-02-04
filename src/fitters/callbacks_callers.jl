# -*- coding:: utf-8 -*-
using Statistics

abstract type CallbackParameters end

CALLBACKS_FNS = Tuple{Symbol}

function _make_population(
    genome::UTGenome,
    generation::Int,
    run_config::runConf,
    model_architecture::modelArchitecture,
    node_config::nodeConfig,
    meta_library::MetaLibrary,
    population_callbacks::CALLBACKS_FNS,
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
    time_pop = mean(t)
    @info "Time Population $time_pop"
    return tuple(population, time_pop)
end

function _make_mutations(
    population::Population,
    generation::Int,
    run_config::runConf,
    model_architecture::modelArchitecture,
    node_config::nodeConfig,
    meta_library::MetaLibrary,
    shared_inputs::SharedInput,
    mutation_callbacks::Mandatory_FN,
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
    time_mut = mean(t)
    @info "Time Mutation $time_mut"
    return tuple(population, time_mut)
end

function _make_output_mutations(
    population::Population,
    generation::Int,
    run_config::runConf,
    model_architecture::modelArchitecture,
    node_config::nodeConfig,
    meta_library::MetaLibrary,
    output_mutation_callbacks::CALLBACKS_FNS,
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
    time_out_mut = mean(t)
    @info "Time Out Mutation $time_out_mut"
    return tuple(population, time_out_mut)
end


function _make_decoding(
    population::Population,
    generation::Int,
    run_config::AbstractRunConf,
    model_architecture::modelArchitecture,
    node_config::nodeConfig,
    meta_library::MetaLibrary,
    shared_inputs::SharedInput,
    decoding_callbacks::FN_TYPE,
    args...,
)::Tuple{PopulationPrograms,Float64}
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
    tt = mean(t)
    @info "Time Decoding $tt"
    return tuple(programs, tt)
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
    elite_selection_callbacks::CALLBACKS_FNS,
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
    first_callback = elite_selection_callbacks[1]
    # FIRST CALL TO CREATE PROGRAMS 
    fn = get_fn_from_symbol(first_callback)
    t_e = @elapsed elite_idx = fn(
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
    tt = mean(t)
    @info "Time in Elite selection $tt"
    return tuple(elite_idx, tt)
end


"""

The normal parameters accepted for an epoch callback.
"""
mutable struct ParametersStandardEpoch <: CallbackParameters
    ind_performances::Union{Vector{<:Number},Vector{Vector{<:Number}}}
    population::Population
    generation::Int
    run_config::AbstractRunConf
    model_architecture::modelArchitecture
    node_config::nodeConfig
    meta_library::MetaLibrary
    shared_inputs::SharedInput
    programs::PopulationPrograms
    best_loss::Float64
    best_program::IndividualPrograms
    elite_idx::Int
    other::Union{Nothing,Any}
end

function _make_epoch_callbacks_calls(
    ind_performances::Union{Vector{<:Number},Vector{Vector{<:Number}}},
    population::Population,
    generation::Int,
    run_config::AbstractRunConf,
    model_architecture::modelArchitecture,
    node_config::nodeConfig,
    meta_library::MetaLibrary,
    shared_inputs::SharedInput,
    programs::PopulationPrograms,
    best_loss::Union{Float64,Vector{Float64}},
    best_program::Union{IndividualPrograms,Vector{IndividualPrograms}},
    elite_idx::Union{Int,Vector{Int}},
    Batch::SubArray,
    epoch_callbacks::FN_TYPE,
)::Float64
    t = []
    for epoch_callback in epoch_callbacks
        fn = epoch_callback isa Symbol ? get_fn_from_symbol(epoch_callback) : epoch_callback
        t_e = @elapsed fn(
            ind_performances,
            population,
            generation,
            run_config,
            model_architecture,
            node_config,
            meta_library,
            shared_inputs,
            programs,
            best_loss,
            best_program,
            elite_idx,
            Batch,
        )
        push!(t, t_e)
    end
    return mean(t)
end

function _make_early_stop_callbacks_calls(
    generation_loss_tracker::GenerationLossTracker,
    ind_loss_tracker::AbstractIndLossTracker,
    ind_performances::Union{Vector{<:Number},Vector{Vector{<:Number}}},
    population::Population,
    generation::Int,
    run_config::runConf,
    model_architecture::modelArchitecture,
    node_config::nodeConfig,
    meta_library::MetaLibrary,
    shared_inputs::SharedInput,
    programs::PopulationPrograms,
    best_loss::Float64,
    best_program::IndividualPrograms,
    elite_idx::Int,
    early_stop_callbacks::Tuple{Vararg{T where {T<:Union{Symbol,<:AbstractCallable}}}},
)::Bool
    decisions = []
    t = []
    for early_stop_callback in early_stop_callbacks
        fn =
            early_stop_callback isa Symbol ? get_fn_from_symbol(early_stop_callback) :
            early_stop_callback
        t_e = @elapsed tmp_decision = fn(
            generation_loss_tracker,
            ind_loss_tracker,
            ind_performances,
            population,
            generation,
            run_config,
            model_architecture,
            node_config,
            meta_library,
            shared_inputs,
            programs,
            best_loss,
            best_program,
            elite_idx,
        )
        push!(t, t_e)
        push!(decisions, tmp_decision)
    end
    @assert length(decisions) > 0 "The early stop decisions is empty. Early stop functions are not returning a decision"
    decision_time = mean(t)
    @debug "Early stop decision time $decision_time"
    decision = any(decisions)
    if decision
        @warn "Early stop decision $decision"
    else
        @debug "Early stop decision $decision"
    end
    return decision
end

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ #
# ~~~~~~~~~~~~~ PRE CALLBACKS ~~~~~~~~~~~~~ #
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ #
function _make_pre_callbacks_calls(pre_callbacks::Optional_FN)
    if !isnothing(pre_callbacks) && length(pre_callbacks) > 1
        for pre_callback in pre_callbacks
            pre_callback()
        end
    end
end
