# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~#
# NSGA-II Callbacks Default Population Callback
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~#

abstract type Abstract_NSGA2_POP_ARGS end
abstract type Abstract_NSGA2_MUTATION_ARGS end
abstract type Abstract_NSGA2_OMUTATION_ARGS end
abstract type Abstract_NSGA2_DECODE_ARGS end
abstract type Abstract_NSGA2_SELECTION_ARGS end


"""
"""
struct NSGA2_POP_ARGS <: Abstract_NSGA2_POP_ARGS
    population::Population
    generation::Int
    run_config::RunConfNSGA2
    model_architecture::modelArchitecture
    node_config::nodeConfig
    meta_library::MetaLibrary
    fitnesses::Vector{Vector{Float64}}
    ranks::Vector{Int64}
    distances::Vector{Float64}
end

"""
"""
struct NSGA2_MUTATION_ARGS <: Abstract_NSGA2_MUTATION_ARGS
    population::Population
    generation::Int
    run_config::RunConfNSGA2
    model_architecture::modelArchitecture
    node_config::nodeConfig
    meta_library::MetaLibrary
    shared_inputs::SharedInput
end

struct NSGA2_SELECTION_ARGS <: Abstract_NSGA2_SELECTION_ARGS
    ranks::Vector{Int64}
    distances::Vector{Float64}
    population::Population
    run_config::AbstractRunConf
end

function tournament_selection_multiobj(
    population::Population,
    tournament_size::Int,
    ranks::Vector{Int64},
    distances::Vector{Float64}
)::Option{UTGenome}
    # Sample the elite
    indices = 1:length(population) # to sort both vectors (fitnesses and pop)
    subset = sample(indices, tournament_size, replace = false) # sample a portion of the elite population

    # Select among the subset
    r_subset = ranks[subset] # the ranks of the subset
    d_subset = distances[subset] # the crowding distance of the subset
    indexes_best_ranks = findall(==(minimum(r_subset)), r_subset)
    # In case of ties among the ranks, compare crowding distances (the larger the better)
    if length(indexes_best_ranks) > 1
        index_best_ranks = subset[indexes_best_ranks]
        d_subset_rank = d_subset[indexes_best_ranks]
        index_best = index_best_ranks[argmax(d_subset_rank)]
    else
        index_best = subset[indexes_best_ranks[1]]
    end
    some(population[index_best])
end

######################################################
# CALLBACKS                                          #
######################################################

"""
Compute offspring with tournament selection based on rank and crowding distance
"""
function nsga2_population_callback(pop_args::NSGA2_POP_ARGS)::Option{Population}
    Config = pop_args.run_config
    Pop = pop_args.population
    pop_size = Config.pop_size
    @assert length(Pop) == pop_size "While making new pop. More individuals in the population than needed. Actual $(length(Pop)) vs Needed (by the config) : $(pop_size)"
    inds = Vector{UTCGP.UTGenome}(undef, pop_size)

    # Tournament (adding individuals with others selected with tournament)
    for ith_new = 1:Config.pop_size
        winner =
            @unwrap_or tournament_selection_multiobj(Pop, Config.tournament_size, pop_args.ranks, pop_args.distances) throw(
                "Tournament could not take place with config : $(Config), ranks : $pop_args.ranks, and distances $pop_args.distances",
            )
        inds[ith_new] = deepcopy(winner)
    end
    return some(Population(inds))
end

"""
Mutates the offspring 
"""
function nsga2_numbered_new_material_mutation_callback(
    args::Abstract_NSGA2_MUTATION_ARGS,
)::Option{Population}
    Config = args.run_config
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

function nsga2_decoding_callback(
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
#                 CALLBACK CALLERS FOR NSGA2                    #
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~#

"""
"""
function _make_nsga2_population(
    nsga2_args::NSGA2_POP_ARGS,
    population_callbacks,
    args...,
)::Option{Tuple{Population,Float64}}
    t = []
    for population_callback in population_callbacks
        fn = get_fn_from_symbol(population_callback)
        t_e = @elapsed pop_result = fn(nsga2_args)
        pop = @unwrap_or pop_result throw("NSGA2 Pop function did not return a population")
        empty!(nsga2_args.population.pop)
        push!(nsga2_args.population.pop, pop.pop...) # replace pop for succequent calls
        push!(t, t_e)
    end
    tt = mean(t)
    @info "Time Population $tt"
    return some(tuple(nsga2_args.population, tt))
end

"""

"""
function _make_nsga2_mutations!(
    nsga2_args::NSGA2_MUTATION_ARGS,
    mutation_callbacks,
    args...,
)::Option{Tuple{Population,Float64}}
    t = []
    for mutation_callback in mutation_callbacks
        fn = get_fn_from_symbol(mutation_callback)
        t_e = @elapsed pop_res = fn(nsga2_args)
        pop = @unwrap_or pop_res throw("NSGA2 Mutation function did not return a population")
        push!(t, t_e)
    end
    tt = mean(t)
    @info "Time Mutations $tt"
    return some(tuple(nsga2_args.population, tt))
end

function _make_epoch_callbacks_calls(
    ind_performances::Union{Vector{<:Number},Vector{Vector{<:Number}}},
    ranks::Vector{Int64},
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
            ranks,
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

function _make_nsga2_survival_selection(
    nsga2_args::NSGA2_SELECTION_ARGS,
    survival_selection_callbacks,
    args...,
)::Option{Tuple{Vector{Int},Float64}}
    t = []

    # FIRST CALL TO CREATE PROGRAMS 
    first_callback = survival_selection_callbacks[1]
    fn = get_fn_from_symbol(first_callback)
    t_e = @elapsed elite_indices_result = fn(nsga2_args)
    elite_indices =
        @unwrap_or elite_indices_result throw(ErrorException("Problem in selection"))
    push!(t, t_e)

    # CONSECUTIVE CALLS 
    for selection_callback in survival_selection_callbacks[2:end]
        fn = get_fn_from_symbol(selection_callback)
        t_e = @elapsed elite_idx = fn(nsga2_args, elite_indices)
        elite_indices =
            @unwrap_or elite_indices_result throw(ErrorException("Problem in selection"))
        push!(t, t_e)
    end
    tt = mean(t)
    @info "Time Selection $tt"
    return some(tuple(elite_indices, tt))
end

function nsga2_survival_selection_callback(args::NSGA2_SELECTION_ARGS)::Option{Vector{Int}}
    ranks = args.ranks
    distances = args.distances
    full_population = args.population
    pop_size = args.pop_size
    @assert length(ranks) == length(full_population.pop) # "During Selection, the size of the individual performances does not match that of the run config : ($(n_fitnesses) vs elite: $(R.n_elite) + new $(R.n_new))"
    indexes = []
    for rank=minimum(ranks):maximum(ranks)
        current_rank_idxs = findall(==(rank), ranks)
        # promote current front if it fits
        if length(current_rank_idxs) + length(indexes) <= pop_size
            append!(indexes, current_rank_idxs)
        else
            # sort elements according to crowding distance (the larger the better)
            n_keep = pop_size - length(indexes)
            current_distances = distances[current_rank_idxs]
            sorted_indexes = sortperm(-current_distances)
            indexes_to_keep = sorted_indexes[1:n_keep] 
            append!(indexes, indexes_to_keep) 
            break          
        end
    end
    @assert length(indexes) == pop_size "During survival selection $length(indexes) elements were selected, expected $pop_size."
    return some(indexes)
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


