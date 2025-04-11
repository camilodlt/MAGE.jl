using StatsBase: sample
using Statistics

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~#
# GA Default Population Callback
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~#

abstract type Abstract_GA_POP_ARGS end

"""
"""
struct GA_POP_ARGS <: Abstract_GA_POP_ARGS
    population::Population
    generation::Int
    run_config::RunConfGA
    model_architecture::modelArchitecture
    node_config::nodeConfig
    meta_library::MetaLibrary
    fitnesses::Vector{Float64}
    extras::Dict

    function GA_POP_ARGS(
        population::Population,
        generation::Int,
        run_config::RunConfGA,
        model_architecture::modelArchitecture,
        node_config::nodeConfig,
        meta_library::MetaLibrary,
        fitnesses::Vector{Float64};
        extras::Dict = Dict(),
    )
        @assert length(fitnesses) == length(population) "The nb of fitnesses (per elite ind.) do not correspond to the number of individuals in the population. $(length(fitnesses)) vs $(length(population))"

        new(
            population,
            generation,
            run_config,
            model_architecture,
            node_config,
            meta_library,
            fitnesses,
            extras,
        )
    end
end

function tournament_selection(
    population::Population,
    tournament_size::Int,
    fitnesses::Vector{Float64};
    return_idx = false,
)::Union{Option{UTGenome},Tuple{Option{UTGenome},Option{Int}}}
    # Sample the elite
    indices = 1:length(population) # to sort both vectors (fitnesses and pop)
    subset = sample(indices, tournament_size, replace = false) # sample a portion of the elite population

    # Select among the subset
    f_subset = fitnesses[subset] # the fitnesses of the subset
    index_best = subset[argmin(f_subset)] # which individual it represent
    if return_idx
        some(population[index_best]), some(index_best)
    else
        some(population[index_best])
    end
end



"""

"""
function ga_population_callback(pop_args::GA_POP_ARGS)::Option{Population}
    Config = pop_args.run_config
    Pop = pop_args.population
    n_elite = Config.n_elite
    @assert length(Pop) == n_elite "While making new pop. More individuals in the population than needed. Actual $(length(Pop)) vs Needed (by the config) : $(n_elite)"
    pop_size = n_elite + Config.n_new
    inds = Vector{UTCGP.UTGenome}(undef, pop_size)

    # Truncation
    for (elite_ith, elite_ind) in enumerate(pop_args.population)
        inds[elite_ith] = deepcopy(elite_ind)
    end

    # Tournament 
    for ith_new = 1:Config.n_new
        new_index = n_elite + ith_new
        winner =
            @unwrap_or tournament_selection(Pop, Config.tournament_size, pop_args.fitnesses) throw(
                "Tournament could not take place with config : $(Config) and fitnesses : $pop_args.fitnesses",
            )
        inds[new_index] = deepcopy(winner)
    end
    return some(Population(inds))
end

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~#
# Default Mutation Callback
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~#


# function default_mutation_callback(population::Population, args...)
#     run_config = args[2]
#     model_architecture = args[3]
#     meta_library = args[5]
#     shared_inputs = args[6]
#     @assert run_config isa runConf
#     @assert shared_inputs isa SharedInput
#     @assert meta_library isa MetaLibrary
#     @assert model_architecture isa modelArchitecture

#     # chromosomes_types = model_architecture.chromosomes_types
#     # input_types = model_architecture.inputs_type_idx
#     for individual in population
#         standard_mutate!(
#             individual,
#             run_config,
#             model_architecture,
#             meta_library,
#             shared_inputs,
#         )
#     end
#     return population
# end

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~#
# Default Mutation Callback (Numbered)
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~#

# function default_numbered_mutation_callback(population::Population, args...)
#     run_config = args[2]
#     model_architecture = args[3]
#     meta_library = args[5]
#     shared_inputs = args[6]
#     @assert run_config isa runConf
#     @assert shared_inputs isa SharedInput
#     @assert meta_library isa MetaLibrary
#     @assert model_architecture isa modelArchitecture

#     # chromosomes_types = model_architecture.chromosomes_types
#     # input_types = model_architecture.inputs_type_idx
#     for individual in population
#         numbered_mutation!(
#             individual,
#             run_config,
#             model_architecture,
#             meta_library,
#             shared_inputs,
#         )
#     end
#     return population
# end

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~#
# Default Mutation Callback (Numbered)
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~#

abstract type Abstract_GA_MUTATION_ARGS end

struct GA_MUTATION_ARGS <: Abstract_GA_MUTATION_ARGS
    population::Population
    generation::Int
    run_config::RunConfGA
    model_architecture::modelArchitecture
    node_config::nodeConfig
    meta_library::MetaLibrary
    shared_inputs::SharedInput
    extras::Dict

    function GA_MUTATION_ARGS(
        population::Population,
        generation::Int,
        run_config::RunConfGA,
        model_architecture::modelArchitecture,
        node_config::nodeConfig,
        meta_library::MetaLibrary,
        shared_inputs::SharedInput;
        extras = Dict(),
    )
        new(
            population,
            generation,
            run_config,
            model_architecture,
            node_config,
            meta_library,
            shared_inputs,
            extras,
        )
    end
end

function ga_numbered_new_material_mutation_callback(
    args::Abstract_GA_MUTATION_ARGS,
)::Option{Population}
    Config = args.run_config
    fs = fieldnames(typeof(Config))
    :n_elite in fs ? n_elite = Config.n_elite : (return none)
    Pop = args.population
    Pop_subset = @view Pop.pop[n_elite+1:end] # only mutate the rest of the population, not the elite, truncated, part.
    for individual in Pop_subset
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

# FOR GA
function (rm::racing_mutation)(args::Abstract_GA_MUTATION_ARGS)::Option{Population}
    Config = args.run_config
    fs = fieldnames(typeof(Config))
    :n_elite in fs ? n_elite = Config.n_elite : none
    Pop = args.population
    Pop_subset = @view Pop.pop[n_elite+1:end] # only mutate the rest of the population, not the elite, truncated, part.
    for (i, individual) in enumerate(Pop_subset)
        @info "Racing ind $i"
        racing_mutation!(
            individual,
            args.run_config,
            args.model_architecture,
            args.meta_library,
            args.shared_inputs,
            rm,
        )
    end
    return some(Pop)
end


# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~#
# Default Mutation Callback
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~#
# function default_free_mutation_callback(population::Population, args...)
#     run_config = args[2]
#     model_architecture = args[3]
#     meta_library = args[5]
#     shared_inputs = args[6]
#     @assert run_config isa runConf
#     @assert shared_inputs isa SharedInput
#     @assert meta_library isa MetaLibrary
#     @assert model_architecture isa modelArchitecture

#     # chromosomes_types = model_architecture.chromosomes_types
#     # input_types = model_architecture.inputs_type_idx
#     for individual in population
#         free_mutate!(
#             individual,
#             run_config,
#             model_architecture,
#             meta_library,
#             shared_inputs,
#         )
#     end
#     return population
# end


# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~#
# Default Mutation Callback
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~#
# function default_free_numbered_mutation_callback(population::Population, args...)
#     run_config = args[2]
#     model_architecture = args[3]
#     meta_library = args[5]
#     shared_inputs = args[6]
#     @assert run_config isa runConf
#     @assert shared_inputs isa SharedInput
#     @assert meta_library isa MetaLibrary
#     @assert model_architecture isa modelArchitecture

#     # chromosomes_types = model_architecture.chromosomes_types
#     # input_types = model_architecture.inputs_type_idx
#     for individual in population
#         free_numbered_mutation!(
#             individual,
#             run_config,
#             model_architecture,
#             meta_library,
#             shared_inputs,
#         )
#     end
#     return population
# end

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~#
# Default Mutation Callback
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~#
# function correct_all_nodes_callback(population::Population, args...)
#     model_architecture = args[3]
#     meta_library = args[5]
#     shared_inputs = args[6]
#     @assert shared_inputs isa SharedInput
#     @assert meta_library isa MetaLibrary
#     @assert model_architecture isa modelArchitecture

#     for individual in population
#         correct_all_nodes!(individual, model_architecture, meta_library, shared_inputs)
#     end
#     return population
# end


# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~#
# Default Output Mutation Callback
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~#

function ga_output_mutation_callback(args::Abstract_GA_MUTATION_ARGS)::Option{Population}
    Config = args.run_config
    fs = fieldnames(typeof(Config))
    :n_elite in fs ? n_elite = Config.n_elite : return none
    Pop = args.population
    Pop_subset = @view Pop.pop[n_elite+1:end] # only mutate the rest of the population, not the elite, truncated, part.
    for individual in Pop_subset
        for output_node in individual.output_nodes
            :output_mutation_rate in fieldnames(typeof(Config)) ?
            μ = Config.output_mutation_rate : return none
            if rand() < μ
                mutate_one_element_from_node!(output_node)
            end
        end
    end
    return some(Pop)
end

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~#
# Default Decoding Callbacks
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~#

# Normal Decoding Callback
# function default_decoding_callback(
#     population::Population,
#     generation::Int,
#     run_config::runConf,
#     model_architecture::modelArchitecture,
#     node_config::nodeConfig,
#     meta_library::MetaLibrary,
#     shared_inputs::SharedInput,
# )::PopulationPrograms
#     # Decoding all programs
#     population_programs = [
#         decode_with_output_nodes(
#             individual,
#             meta_library,
#             model_architecture,
#             shared_inputs,
#         ) for individual in population
#     ]

#     return PopulationPrograms(population_programs)
# end

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~#
# Default FREE decoding
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~#

# Normal Decoding Callback
# function default_free_decoding_callback(
#     population::Population,
#     generation::Int,
#     run_config::runConf,
#     model_architecture::modelArchitecture,
#     node_config::nodeConfig,
#     meta_library::MetaLibrary,
#     shared_inputs::SharedInput,
# )::PopulationPrograms
#     # Decoding all programs
#     population_programs = [
#         free_decode_with_output_nodes(
#             individual,
#             meta_library,
#             model_architecture,
#             shared_inputs,
#         ) for individual in population
#     ]

#     return PopulationPrograms(population_programs)
# end

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~#
# Default Elite selection Callbacks
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~#

abstract type Abstract_GA_SELECTION_ARGS end

struct GA_SELECTION_ARGS <: Abstract_GA_SELECTION_ARGS
    ind_performances::Union{Vector{<:Number},Vector{Vector{<:Number}}}
    population::Population
    generation::Int
    run_config::AbstractRunConf
    model_architecture::modelArchitecture
    node_config::nodeConfig
    meta_library::MetaLibrary
    programs::PopulationPrograms
end

function ga_elite_selection_callback(args::Abstract_GA_SELECTION_ARGS)::Option{Vector{Int}}
    :ind_performances in fieldnames(typeof(args)) ? F = args.ind_performances : return none
    :run_config in fieldnames(typeof(args)) ? R = args.run_config : return none
    n_fitnesses = length(F)
    @assert n_fitnesses == R.n_elite + R.n_new "During Selection, the size of the individual performances does not match that of the run config : ($(n_fitnesses) vs elite: $(R.n_elite) + new $(R.n_new))"
    if F[1] isa Vector
        throw(ErrorException("Pareto Front not implemented yet"))
    else
        # Fix nan
        F_ = deepcopy(F)
        indices = collect(1:length(F_))
        m = findall(isnan.(F_))
        F_[m] .= Inf # so Nan are the worst solutions

        # Prefer children to parent
        reverse!(indices)
        F_ = reverse(F_)

        # Select μ best
        order = sortperm(F_) # the correct sorting, where children have preference if same F
        indices = indices[order] # Original individual indices, sorted w.r.t. fitnesses
        μ_best = indices[begin:R.n_elite]
        return some(μ_best)
    end
end



# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~#
#                 CALLBACK CALLERS FOR GA                    #
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~#


abstract type CallbackParameters end

"""
"""
function _make_ga_population(
    ga_args::GA_POP_ARGS,
    population_callbacks,
    args...,
)::Option{Tuple{Population,Float64}}
    t = []
    for population_callback in population_callbacks
        fn = get_fn_from_symbol(population_callback)
        t_e = @elapsed pop_result = fn(ga_args)
        pop = @unwrap_or pop_result throw("GA Pop function did not return a population")
        empty!(ga_args.population.pop)
        push!(ga_args.population.pop, pop.pop...) # replace pop for succequent calls
        push!(t, t_e)
    end
    tt = mean(t)
    @info "Time Population $tt"
    return some(tuple(ga_args.population, tt))
end

"""

Mutate the population

Returns the population and the time it took to make the final population
"""
function _make_ga_mutations!(
    ga_args::GA_MUTATION_ARGS,
    mutation_callbacks,
    args...,
)::Option{Tuple{Population,Float64}}
    t = []
    for mutation_callback in mutation_callbacks
        fn = get_fn_from_symbol(mutation_callback)
        t_e = @elapsed pop_res = fn(ga_args)
        pop = @unwrap_or pop_res throw("GA Mutation function did not return a population")
        # empty!(ga_args.population.pop)
        # push!(ga_args.population.pop, pop.pop...) # replace pop for succequent calls
        push!(t, t_e)
    end
    tt = isempty(t) ? 0.0 : mean(t)
    @info "Time Mutations $tt"
    return some(tuple(ga_args.population, tt))
end

"""
Mutate the ouput nodes of ALL the population

Returns the population and the time it took to make the final population
"""
function _make_ga_output_mutations!(
    ga_args::GA_MUTATION_ARGS,
    output_mutation_callbacks::FN_TYPE,
    args...,
)::Option{Tuple{Population,Float64}}
    t = []
    for output_callback in output_mutation_callbacks
        fn = get_fn_from_symbol(output_callback)
        t_e = @elapsed pop_res = fn(ga_args)
        pop =
            @unwrap_or pop_res throw("GA Out Mutation function did not return a population")
        # empty!(ga_args.population.pop)
        # push!(ga_args.population.pop, pop.pop...) # replace pop for succequent calls
        push!(t, t_e)
    end
    tt = mean(t)
    @info "Time Output Mutations $tt"
    return some(tuple(ga_args.population, tt))
end

# Decoding as 1 + \lambda 


"""
Selects the best individual in the population.
Return its index.

Accepts multiple fns. The first one will output an elite idx.
The output will be reinjected in following calls
Either way, all calls have to return the elite_idx
"""
function _make_ga_elite_selection(
    ga_args::GA_SELECTION_ARGS,
    elite_selection_callbacks,
    args...,
)::Option{Tuple{Vector{Int},Float64}}
    t = []

    # FIRST CALL TO CREATE PROGRAMS 
    first_callback = elite_selection_callbacks[1]
    fn = get_fn_from_symbol(first_callback)
    t_e = @elapsed elite_indices_result = fn(ga_args)
    elite_indices =
        @unwrap_or elite_indices_result throw(ErrorException("Problem in selection"))
    push!(t, t_e)

    # CONSECUTIVE CALLS 
    for elite_selection_callback in elite_selection_callbacks[2:end]
        fn = get_fn_from_symbol(elite_selection_callback)
        t_e = @elapsed elite_idx = fn(ga_args, elite_indices)
        elite_indices =
            @unwrap_or elite_indices_result throw(ErrorException("Problem in selection"))
        push!(t, t_e)
    end
    tt = mean(t)
    @info "Time Selection $tt"
    return some(tuple(elite_indices, tt))
end


########################################
############# EARLY STOP ###############
########################################

struct GA_EARLYSTOP_ARGS <: Abstract_GA_SELECTION_ARGS
    generation_loss_tracker::GenerationLossTracker
    ind_loss_tracker::AbstractIndLossTracker # either for MultiT or not
    ind_performances::Union{Vector{<:Number},Vector{Vector{<:Number}}}
    population::Population
    generation::Int
    run_config::RunConfGA
    model_architecture::modelArchitecture
    node_config::nodeConfig
    meta_library::MetaLibrary
    shared_inputs::SharedInput
    programs::PopulationPrograms
    best_losses::Vector{Float64}
    best_programs::Vector{IndividualPrograms}
    elite_idx::Vector{Int}
end

"""
Make Early stop Calls
"""
function _make_ga_early_stop_callbacks_calls(
    early_stop_args::GA_EARLYSTOP_ARGS,
    early_stop_callbacks::FN_TYPE,
)::Bool
    decisions = []
    t = []
    for early_stop_callback in early_stop_callbacks
        fn =
            early_stop_callback isa Symbol ? get_fn_from_symbol(early_stop_callback) :
            early_stop_callback
        t_e = @elapsed tmp_decision = fn(early_stop_args)
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

"""

EVAL BUDGET for GA and MultiThreaded
"""
function (obj::eval_budget_early_stop)(ga_early_stop_args::GA_EARLYSTOP_ARGS)::Bool
    n_evals = @unwrap_or _count_evals(ga_early_stop_args.ind_loss_tracker) (
        @error "Could not count evals for budget"; return false
    )
    obj.cur_budget += n_evals
    decision = decide_max_budget(obj)
    @info "Eval Budget. Curr budget : $(obj.cur_budget)"
    return decision
end


