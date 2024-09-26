# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~#
# STN UTILS
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~#
mutable struct MutablePair
    first::String
    second::String
end

abstract type IndividualHierarchy end
struct Parent <: IndividualHierarchy end
struct Offspring <: IndividualHierarchy end

function _stn_verif_mappings_length(pop::Population, mappings::Vector{MutablePair})
    @assert length(mappings) == length(pop) "Mappings don't have the same length as population"
end
function _update_stn_pair!(pair::MutablePair, id_hash::String, ind_is::Parent)
    pair.first = id_hash
end
function _update_stn_pair!(pair::MutablePair, id_hash::String, ind_is::Offspring)
    pair.second = id_hash
end
function _stn_id_hash_pop!(
    pop::Population,
    mappings::Vector{MutablePair},
    ind_is::IndividualHierarchy,
)
    _stn_verif_mappings_length(pop, mappings)
    i = 1
    for (ind, mapping) in zip(pop, mappings)
        id_hash = UTCGP.general_hasher_sha(ind)
        _update_stn_pair!(mapping, id_hash, ind_is)
        i += 1
    end
end
function _stn_id_hash_pop!(
    pop::Population,
    mappings::Vector{MutablePair},
    id_hashes::Vector{String},
    ind_is::IndividualHierarchy,
)
    _stn_verif_mappings_length(pop, mappings)
    @assert length(mappings) == length(id_hashes)
    i = 1
    for (ind, mapping) in zip(pop, mappings)
        id_hash = id_hashes[i]
        _update_stn_pair!(mapping, id_hash, ind_is)
        i += 1
    end
end

# SERIALIZE INDIVIDUAL TO STRING
function serialize_ind_to_string(ind::UTGenome)
    reset_genome!(ind)
    join(string.(UTCGP.general_serializer(ind)), "_")
end
function deserialize_ind_from_string(serialized_string::String)
    serialized_ints = parse.(UInt8, split(serialized_string, "_"))
    io = IOBuffer()
    write(io, serialized_ints)
    seekstart(io)
    ind = deserialize(io)
    close(io)
    ind
end
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~#
# STN Archive Callbacks 
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~#

abstract type Abstract_STN_POP_ARGS end
abstract type Abstract_STN_MUTATION_ARGS end
abstract type Abstract_STN_OMUTATION_ARGS end
abstract type Abstract_STN_DECODE_ARGS end
abstract type Abstract_STN_SELECTION_ARGS end
abstract type Abstract_STN_EPOCH_ARGS end

"""
"""
struct STN_POP_ARGS <: Abstract_STN_POP_ARGS
    population::Population
    con::DuckDB.DB
    mappings::Vector{MutablePair}
    generation::Int
    run_config::RunConfSTN
    model_architecture::modelArchitecture
    node_config::nodeConfig
    meta_library::MetaLibrary
end

"""
"""
struct STN_MUTATION_ARGS <: Abstract_STN_MUTATION_ARGS
    population::Population
    con::DuckDB.DB
    mappings::Vector{MutablePair}
    generation::Int
    run_config::RunConfSTN
    model_architecture::modelArchitecture
    node_config::nodeConfig
    meta_library::MetaLibrary
    shared_inputs::SharedInput
end

"""
"""
struct STN_DECODE_ARGS <: Abstract_STN_POP_ARGS
    population::Population
    generation::Int
    run_config::RunConfSTN
    model_architecture::modelArchitecture
    node_config::nodeConfig
    meta_library::MetaLibrary
    shared_inputs::SharedInput
end

struct STN_EPOCH_ARGS <: Abstract_STN_EPOCH_ARGS
    ind_performances::Union{Vector{<:Number},Vector{Vector{<:Number}}}
    con::DuckDB.DB
    mappings::Vector{MutablePair}
    population::Population
    generation::Int
    run_config::AbstractRunConf
    model_architecture::modelArchitecture
    node_config::nodeConfig
    meta_library::MetaLibrary
    shared_inputs::SharedInput
    programs::PopulationPrograms
    best_loss::Union{Nothing,Float64,Vector{Float64}}
    best_program::Union{Nothing,IndividualPrograms,Vector{IndividualPrograms}}
    elite_idx::Union{Nothing,Int,Vector{Int}}
    Batch::Union{SubArray,Nothing}
end

######################################################
# CALLBACKS                                          #
######################################################

"""
Sample `sample size` from archive
"""
function stn_population_callback(pop_args::STN_POP_ARGS)::Option{Population}
    Config = pop_args.run_config
    pop_size = Config.sample_size
    con = pop_args.con
    behavior_col = Config.behavior_col
    serialization_col = Config.serialization_col
    # get the list of the current behaviors

    NON_ELITE_POP = pop_size - 3
    ELITE_POP = 3
    elite_inds =
        df = DataFrame(
            sn._execute_command(
                con,
                """
            WITH top3 AS (
                SELECT DISTINCT _to, fitness
                FROM EDGES
                ORDER BY fitness ASC, ITERATION DESC
                LIMIT 3
            )

            SELECT id_hash, $behavior_col, $serialization_col
            FROM NODES
            JOIN top3 ON (
                NODES.id_hash = top3._to
            )
            """,
            ),
        )


    behaviors_rows =
        df = DataFrame(sn._execute_command(
            con,
            """
        with SUBSET AS (
            SELECT id_hash, $behavior_col
            FROM NODES
        ) 

        SELECT DISTINCT $behavior_col, ITERATION
        FROM EDGES
        JOIN SUBSET ON (
            EDGES._to = SUBSET.id_hash
        ) 
        """,
        ))
    behaviors = collect(skipmissing(DataFrame(behaviors_rows)[:, 1]))
    newness = collect(skipmissing(DataFrame(behaviors_rows)[:, 2]))
    # if isdefined(Main, :Infiltrator)
    #     Main.infiltrate(@__MODULE__, Base.@locals, @__FILE__, @__LINE__)
    # end
    # @show df
    @show behaviors
    @info "Number of behaviors in DB : $(length(behaviors))"
    # sampled_behaviors = sample(behaviors, pop_size, replace = true) # maybe here pick the fittest behaviors ????
    sampled_behaviors = sample(behaviors, Weights(newness), NON_ELITE_POP, replace = true)
    sampled_behaviors = unique(sampled_behaviors)
    @show sampled_behaviors
    @info "Number of sampled behaviors $(length(sampled_behaviors))"
    sampled_behaviors_query = ["("]
    for i in sampled_behaviors
        push!(sampled_behaviors_query, "\$\$" * i * "\$\$" * ",")
    end
    sampled_behaviors_query = push!(sampled_behaviors_query, ")")
    sampled_behaviors_queryS = join(sampled_behaviors_query, "")
    # Recreate the individuals
    DF_fittest_per_behavior = DataFrame(
        sn._execute_command(
            con,
            """
            with SAMPLED_IDS as (
                SELECT DISTINCT id_hash, $behavior_col, $serialization_col
                FROM NODES 
                WHERE $behavior_col in $sampled_behaviors_queryS
            ), fittest_inds as (
                SELECT *
                FROM (
                    SELECT *, ROW_NUMBER() OVER (PARTITION BY $behavior_col ORDER BY fitness) AS rn
                    FROM ( 
                        /* join nodes and edges. Subset by the behaviors chosen
                        For each Behaviors. Many individuals exist
                        Having the same behavior does not guarantee that they all have the same fitness (Behaviors can be coarse descriptos)
                        */
                        SELECT EDGES._to, EDGES.fitness, SAMPLED_IDS.$behavior_col
                        FROM EDGES
                        JOIN SAMPLED_IDS ON (
                            EDGES._to = sampled_ids.id_hash
                        )
                    )
                ) /* The fittest individual (id_hash) for each group */
                /* => 1 fittest individual for each behavior */
                WHERE rn = 1
            )

            /* -- For the select fittest inds for each behavior. */
            /* -- Get the serialized information */
            SELECT id_hash, SAMPLED_IDS.$behavior_col, SAMPLED_IDS.$serialization_col
            FROM sampled_ids
            JOIN fittest_inds ON (
                sampled_ids.id_hash = fittest_inds._to
            )
            """,
        ),
    )
    DF_fittest_per_behavior = vcat(elite_inds, DF_fittest_per_behavior)
    new_pop = []
    behaviors_serialized = DF_fittest_per_behavior[:, serialization_col]
    ids = deepcopy(collect(skipmissing(DF_fittest_per_behavior[:, "id_hash"])))
    for ind_to_resuscitate in behaviors_serialized
        ind = deserialize_ind_from_string(ind_to_resuscitate)
        push!(new_pop, ind)
    end
    UTCGP.reset_genome!.(new_pop)
    # @assert length(unique(DF_fittest_per_behavior[:, behavior_col])) == length(new_pop) # there is one individual for each behavior

    n = length(new_pop)
    if n < pop_size
        # we have to oversample because there is no enough behaviors 
        # in order to sample the req amount
        @info "Oversampling the fittest ind. per behavior bc $(length(new_pop)) behaviors while $(pop_size) are required"
        while length(new_pop) != pop_size
            chosen_one = rand(1:n)
            ind = new_pop[chosen_one]
            push!(new_pop, deepcopy(ind))
            push!(ids, ids[chosen_one])
        end
    end
    pop = Population(new_pop)
    # Get id_hashes from parents
    @show ids
    _stn_id_hash_pop!(pop, pop_args.mappings, ids, Parent())
    return some(pop)
end

"""

Mutates the whole population
"""
function stn_numbered_new_material_mutation_callback(
    args::Abstract_STN_MUTATION_ARGS,
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
    UTCGP.reset_genome!.(Pop)
    # _stn_id_hash_pop!(Pop, args.mappings, Offspring()) # updates the second element of the mappings
    return some(Pop)
end

"""
Normal Decoding
"""
function stn_decoding_callback(
    population::Population,
    generation::Int,
    run_config::RunConfSTN,
    model_architecture::modelArchitecture,
    node_config::nodeConfig,
    meta_library::MetaLibrary,
    shared_inputs::SharedInput,
)::PopulationPrograms
    ml = meta_library
    ma = model_architecture
    si = shared_inputs
    pop = population
    # Decoding all programs
    population_programs =
        [decode_with_output_nodes(individual, ml, ma, si) for individual in pop]

    return PopulationPrograms(population_programs)
end

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~#
#                 CALLBACK CALLERS FOR STN                   #
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~#

"""
"""
function _make_stn_population(
    stn_args::STN_POP_ARGS,
    population_callbacks,
    args...,
)::Option{Tuple{Population,Float64}}
    t = []
    for population_callback in population_callbacks
        fn = get_fn_from_symbol(population_callback)
        t_e = @elapsed pop_result = fn(stn_args)
        pop = @unwrap_or pop_result throw("STN Pop function did not return a population")
        empty!(stn_args.population.pop)
        push!(stn_args.population.pop, pop.pop...) # replace pop for succequent calls
        push!(t, t_e)
    end
    tt = mean(t)
    @info "Time Population $tt"
    return some(tuple(stn_args.population, tt))
end

"""
"""
function _make_stn_mutations!(
    stn_args::STN_MUTATION_ARGS,
    mutation_callbacks,
    args...,
)::Option{Tuple{Population,Float64}}
    t = []
    for mutation_callback in mutation_callbacks
        fn = get_fn_from_symbol(mutation_callback)
        t_e = @elapsed pop_res = fn(stn_args)
        pop = @unwrap_or pop_res throw("STN Mutation function did not return a population")
        push!(t, t_e)
    end
    tt = mean(t)
    @info "Time Mutations $tt"
    return some(tuple(stn_args.population, tt))
end

function _make_epoch_callbacks_calls(
    args::Abstract_STN_EPOCH_ARGS,
    epoch_callbacks::FN_TYPE,
)::Float64
    t = []
    for epoch_callback in epoch_callbacks
        fn = epoch_callback isa Symbol ? get_fn_from_symbol(epoch_callback) : epoch_callback
        t_e = @elapsed fn(args)
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



