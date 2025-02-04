# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~#
# Map Elite Callbacks Default Population Callback
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~#

abstract type Abstract_ME_POP_ARGS end
abstract type Abstract_ME_MUTATION_ARGS end
abstract type Abstract_ME_OMUTATION_ARGS end
abstract type Abstract_ME_DECODE_ARGS end
abstract type Abstract_ME_SELECTION_ARGS end


"""
"""
struct ME_POP_ARGS <: Abstract_ME_POP_ARGS
    archive::Abstract_MapElitesRepertoire
    population::Population
    generation::Int
    run_config::RunConfME
    model_architecture::modelArchitecture
    node_config::nodeConfig
    meta_library::MetaLibrary
end

"""
"""
struct ME_MUTATION_ARGS <: Abstract_ME_MUTATION_ARGS
    archive::Abstract_MapElitesRepertoire
    population::Population
    generation::Int
    run_config::RunConfME
    model_architecture::modelArchitecture
    node_config::nodeConfig
    meta_library::MetaLibrary
    shared_inputs::SharedInput
end

"""
"""
struct ME_DECODE_ARGS <: Abstract_ME_POP_ARGS
    archive::Abstract_MapElitesRepertoire
    population::Population
    generation::Int
    run_config::RunConfME
    model_architecture::modelArchitecture
    node_config::nodeConfig
    meta_library::MetaLibrary
    shared_inputs::SharedInput
end

######################################################
# CALLBACKS                                          #
######################################################

"""
Sample `sample size` from archive
"""
function me_population_callback(pop_args::ME_POP_ARGS)::Option{Population}
    Config = pop_args.run_config
    Archive = pop_args.archive
    pop_size = Config.sample_size
    new_pop = sample(Archive, pop_size)
    UTCGP.reset_genome!.(new_pop)
    return some(new_pop)
end

"""

Mutates the whole population
"""
function me_numbered_new_material_mutation_callback(
    args::Abstract_ME_MUTATION_ARGS,
)::Option{Population}
    Config = args.run_config
    # fs = fieldnames(typeof(Config))
    Pop = args.population
    for individual in Pop
        new_material_mutation!(
            individual,
            args.run_config,
            args.model_architecture,
            args.meta_library,
            args.shared_inputs,
        )
    end
    return some(Pop)
end

"""
Normal Decoding
"""
function me_decoding_callback(decode_args::ME_DECODE_ARGS)::PopulationPrograms
    ml = decode_args.meta_library
    ma = decode_args.model_architecture
    si = decode_args.shared_inputs
    pop = decode_args.population
    # Decoding all programs
    population_programs =
        [decode_with_output_nodes(individual, ml, ma, si) for individual in pop]

    return PopulationPrograms(population_programs)
end

function me_decoding_callback(
    population::Population,
    generation::Int,
    run_config::AbstractRunConf,
    model_architecture::modelArchitecture,
    node_config::nodeConfig,
    meta_library::MetaLibrary,
    shared_inputs::SharedInput,
)::PopulationPrograms
    # Decoding all programs
    population_programs = [
        decode_with_output_nodes(
            individual,
            meta_library,
            model_architecture,
            shared_inputs,
        ) for individual in population
    ]

    return PopulationPrograms(population_programs)
end

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~#
#                 CALLBACK CALLERS FOR ME                    #
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~#

"""
"""
function _make_me_population(
    me_args::ME_POP_ARGS,
    population_callbacks,
    args...,
)::Option{Tuple{Population,Float64}}
    t = []
    for population_callback in population_callbacks
        fn = get_fn_from_symbol(population_callback)
        t_e = @elapsed pop_result = fn(me_args)
        pop = @unwrap_or pop_result throw("ME Pop function did not return a population")
        empty!(me_args.population.pop)
        push!(me_args.population.pop, pop.pop...) # replace pop for succequent calls
        push!(t, t_e)
    end
    tt = mean(t)
    @info "Time Population $tt"
    return some(tuple(me_args.population, tt))
end

"""
"""
function _make_me_mutations!(
    me_args::ME_MUTATION_ARGS,
    mutation_callbacks,
    args...,
)::Option{Tuple{Population,Float64}}
    t = []
    for mutation_callback in mutation_callbacks
        fn = get_fn_from_symbol(mutation_callback)
        t_e = @elapsed pop_res = fn(me_args)
        pop = @unwrap_or pop_res throw("ME Mutation function did not return a population")
        push!(t, t_e)
    end
    tt = mean(t)
    @info "Time Mutations $tt"
    return some(tuple(me_args.population, tt))
end

function _make_epoch_callbacks_calls(
    ind_performances::Union{Vector{<:Number},Vector{Vector{<:Number}}},
    archive::MapelitesRepertoire,
    population::Population,
    generation::Int,
    run_config::AbstractRunConf,
    model_architecture::modelArchitecture,
    node_config::nodeConfig,
    meta_library::MetaLibrary,
    shared_inputs::SharedInput,
    programs::PopulationPrograms,
    best_loss::Union{Nothing,Float64,Vector{Float64}},
    best_program::Union{Nothing,IndividualPrograms,Vector{IndividualPrograms}},
    elite_idx::Union{Nothing,Int,Vector{Int}},
    Batch::Union{SubArray,Nothing},
    epoch_callbacks::FN_TYPE,
)::Float64
    t = []
    for epoch_callback in epoch_callbacks
        fn = epoch_callback isa Symbol ? get_fn_from_symbol(epoch_callback) : epoch_callback
        t_e = @elapsed fn(
            ind_performances,
            archive,
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

# function _make_ga_output_mutations!(
#     ga_args::GA_MUTATION_ARGS,
#     output_mutation_callbacks::FN_TYPE,
#     args...,
# )::Option{Tuple{Population,Float64}}
#     t = []
#     for output_callback in output_mutation_callbacks
#         fn = get_fn_from_symbol(output_callback)
#         t_e = @elapsed pop_res = fn(ga_args)
#         pop =
#             @unwrap_or pop_res throw("GA Out Mutation function did not return a population")
#         # empty!(ga_args.population.pop)
#         # push!(ga_args.population.pop, pop.pop...) # replace pop for succequent calls
#         push!(t, t_e)
#     end
#     tt = mean(t)
#     @info "Time Output Mutations $tt"
#     return some(tuple(ga_args.population, tt))
# end

########################################
############# EARLY STOP ###############
########################################

# struct GA_EARLYSTOP_ARGS <: Abstract_GA_SELECTION_ARGS
#     generation_loss_tracker::GenerationLossTracker
#     ind_loss_tracker::AbstractIndLossTracker # either for MultiT or not
#     ind_performances::Union{Vector{<:Number},Vector{Vector{<:Number}}}
#     population::Population
#     generation::Int
#     run_config::RunConfGA
#     model_architecture::modelArchitecture
#     node_config::nodeConfig
#     meta_library::MetaLibrary
#     shared_inputs::SharedInput
#     programs::PopulationPrograms
#     best_losses::Vector{Float64}
#     best_programs::Vector{IndividualPrograms}
#     elite_idx::Vector{Int}
# end

# """
# Make Early stop Calls
# """
# function _make_ga_early_stop_callbacks_calls(
#     early_stop_args::GA_EARLYSTOP_ARGS,
#     early_stop_callbacks::FN_TYPE,
# )::Bool
#     decisions = []
#     t = []
#     for early_stop_callback in early_stop_callbacks
#         fn =
#             early_stop_callback isa Symbol ? get_fn_from_symbol(early_stop_callback) :
#             early_stop_callback
#         t_e = @elapsed tmp_decision = fn(early_stop_args)
#         push!(t, t_e)
#         push!(decisions, tmp_decision)
#     end
#     @assert length(decisions) > 0 "The early stop decisions is empty. Early stop functions are not returning a decision"
#     decision_time = mean(t)
#     @debug "Early stop decision time $decision_time"
#     decision = any(decisions)
#     if decision
#         @warn "Early stop decision $decision"
#     else
#         @debug "Early stop decision $decision"
#     end
#     return decision
# end

# """

# EVAL BUDGET for GA and MultiThreaded
# """
# function (obj::eval_budget_early_stop)(ga_early_stop_args::GA_EARLYSTOP_ARGS)::Bool
#     n_evals = @unwrap_or _count_evals(ga_early_stop_args.ind_loss_tracker) (
#         @error "Could not count evals for budget"; return false
#     )
#     obj.cur_budget += n_evals
#     decision = decide_max_budget(obj)
#     @info "Eval Budget. Curr budget : $(obj.cur_budget)"
#     return decision
# end


