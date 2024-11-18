const parent_pop::Ref{Int} = Ref{Int}()

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
    semantics_n = Config.semantics_n
    # get the list of the current behaviors

    # TEMP
    initial_temp = 1000
    current_iteration = pop_args.generation
    current_temp = max(1, initial_temp - current_iteration)
    @info "Current TEMP population STN : $current_temp"

    NON_ELITE_POP = 1000
    ELITE_POP = 5
    CROSSOVER_POP = 10
    elite_inds = DataFrame(
        sn._execute_command(
            con,
            """
            WITH top3 AS (
                SELECT DISTINCT _to, fitness
                FROM EDGES
                ),
                best_behaviors as (
                 SELECT $behavior_col, avg(fitness) as fitness, count() as c
                 FROM NODES
                 JOIN top3 ON (
                     NODES.id_hash = top3._to
                 )
                 GROUP BY $behavior_col
                 ORDER BY fitness ASC
                 LIMIT $ELITE_POP
                 )


              SELECT *
              FROM (
                   SELECT id_hash, NODES.$behavior_col, NODES.$serialization_col, 
                   fitness, row_number() OVER (PARTITION BY NODES.$behavior_col ORDER BY random()) as rn, 
                   best_behaviors.c as c, best_behaviors.c as c_temp
                   FROM NODES
                   JOIN best_behaviors ON (
                       best_behaviors.$behavior_col= NODES.$behavior_col
                   )
               )
               WHERE rn = 1
               ORDER BY fitness
            """,
        ),
    )

    elite_inds[:, "c_temp"] .+= current_temp
    best_id = elite_inds[1, "id_hash"]
    behavior_cols_0 = ["b0_$i" for i = 1:semantics_n]
    behavior_cols_1 = ["b1_$i" for i = 1:semantics_n]
    best_f = elite_inds[1, "fitness"]
    th = 1.3 * best_f
    pareto_front =
        sn._execute_command(
            con,
            """
               WITH best_vector as (
                   SELECT behavior_hash, 
                   ARRAY[$(join(behavior_cols_0, ", "))]::DOUBLE[] as behavior0,
                   ARRAY[$(join(behavior_cols_1, ", "))]::DOUBLE[] as behavior1
                   FROM NODES
                   WHERE id_hash = '$best_id'),

                   other_vectors as (
                   SELECT behavior_hash , 
                   ARRAY[$(join(behavior_cols_0, ", "))]::DOUBLE[] as behavior0,
                   ARRAY[$(join(behavior_cols_1, ", "))]::DOUBLE[] as behavior1
                   FROM NODES
                   WHERE id_hash != '$best_id'
                   ),

                   avg_fitness_per_hash as (
                   SELECT behavior_hash, avg(fitness) as avg_fitness, count() as c
                   FROM EDGES
                   JOIN NODES ON (
                       NODES.id_hash = EDGES._to
                       )
                   GROUP BY NODES.behavior_hash
                   ORDER BY avg_fitness
                   ),

                   DISTANCES as (
                   SELECT best_vector.behavior_hash as behavior_hash,
                   best_vector.behavior0, best_vector.behavior1,
                   other_vectors.behavior_hash as behavior_hash_1, other_vectors.behavior0, other_vectors.behavior1,
                   list_distance(other_vectors.behavior0, best_vector.behavior0::Double[]) as dist1,
                   list_distance(other_vectors.behavior1, best_vector.behavior1::Double[]) as dist2,                
                   avg_fitness, c
                   FROM other_vectors, best_vector
                   JOIN avg_fitness_per_hash ON (
                       avg_fitness_per_hash.behavior_hash = other_vectors.behavior_hash
                       )
                   WHERE avg_fitness <= $th
                   ),  
                   
                   DISTANCE_SUMMED as (
                   SELECT DISTANCES.behavior_hash, DISTANCES.behavior_hash_1, DISTANCES.dist1 + DISTANCES.dist2 as dist, DISTANCES.avg_fitness , c
                   FROM DISTANCES
                   ),

                   PARETO_FRONT as (
                   SELECT DISTINCT t1.behavior_hash, t1.behavior_hash_1, t1.dist, t1.avg_fitness, t1.c as c_temp
                   FROM DISTANCE_SUMMED t1
                   WHERE NOT EXISTS (
                       SELECT 1
                       FROM DISTANCE_SUMMED t2
                       WHERE t2.dist >= t1.dist
                       AND t2.avg_fitness <= t1.avg_fitness
                       AND (t2.dist > t1.dist OR t2.avg_fitness < t1.avg_fitness)
                       AND t1.behavior_hash_1 != t2.behavior_hash
                       )
                   )

                   SELECT *
                   FROM (
                       SELECT id_hash, NODES.$behavior_col, NODES.$serialization_col,
                       PARETO_FRONT.avg_fitness as fitness, row_number() OVER (PARTITION BY NODES.$behavior_col ORDER BY random()) as rn,
                       PARETO_FRONT.c_temp as c, PARETO_FRONT.c_temp as c_temp
                       FROM NODES
                       JOIN PARETO_FRONT ON (
                          PARETO_FRONT.behavior_hash_1 = NODES.$behavior_col
                          )
                      )
                   WHERE rn = 1
                   ORDER BY fitness
               """,
        ) |> DataFrame

    pareto_front[:, "c_temp"] .+= current_temp
    @info "Number of rows in the pareto front $(pareto_front)"

    # TOURNAMENT ON DECEPTIVENESS

    elite_behaviors = unique(elite_inds[:, behavior_col])
    elite_behaviors_query = ["("]
    for i in elite_behaviors
        push!(elite_behaviors_query, "\$\$" * i * "\$\$" * ",")
    end
    push!(elite_behaviors_query, ")")
    elite_behaviors_queryS = join(elite_behaviors_query, "")
    neigborhood = DataFrame(
        sn._execute_command(
            con,
            """
            with SAMPLED_IDS as (
                SELECT DISTINCT id_hash, $behavior_col, $serialization_col
                FROM NODES 
                WHERE $behavior_col in $elite_behaviors_queryS
            ), fittest_inds as (
                SELECT sampled_ids.$behavior_col, quantile_cont(fitness,0.2) as std_f
                FROM EDGES
                JOIN SAMPLED_IDS ON (
                    EDGES._from = sampled_ids.id_hash
                )
                GROUP BY sampled_ids.$behavior_col
            )
            SELECT *
            FROM fittest_inds
            """,
        ),
    )

    # behaviors_rows =
    #     df = DataFrame(sn._execute_command(
    #         con,
    #         """
    #     with SUBSET AS (
    #         SELECT id_hash, $behavior_col
    #         FROM NODES
    #     ) 

    #     SELECT DISTINCT $behavior_col, ITERATION
    #     FROM EDGES
    #     JOIN SUBSET ON (
    #         EDGES._to = SUBSET.id_hash
    #     ) 
    #     """,
    #     ))
    # behaviors = collect(skipmissing(DataFrame(behaviors_rows)[:, 1]))
    # newness = collect(skipmissing(DataFrame(behaviors_rows)[:, 2]))
    # # if isdefined(Main, :Infiltrator)
    # #     Main.infiltrate(@__MODULE__, Base.@locals, @__FILE__, @__LINE__)
    # # end
    # # @show df
    # # @show behaviors
    # @info "Number of behaviors in DB : $(length(behaviors))"
    # # sampled_behaviors = sample(behaviors, pop_size, replace = true) # maybe here pick the fittest behaviors ????
    # sampled_behaviors = sample(behaviors, Weights(newness), NON_ELITE_POP, replace = true)
    # sampled_behaviors = unique(sampled_behaviors)
    # # @show sampled_behaviors
    # @info "Number of sampled behaviors $(length(sampled_behaviors))"
    # sampled_behaviors_query = ["("]
    # for i in sampled_behaviors
    #     push!(sampled_behaviors_query, "\$\$" * i * "\$\$" * ",")
    # end
    # sampled_behaviors_query = push!(sampled_behaviors_query, ")")
    # sampled_behaviors_queryS = join(sampled_behaviors_query, "")
    # # Recreate the individuals
    # DF_fittest_per_behavior = DataFrame(
    #     sn._execute_command(
    #         con,
    #         """
    #         with SAMPLED_IDS as (
    #             SELECT DISTINCT id_hash, $behavior_col, $serialization_col
    #             FROM NODES 
    #             WHERE $behavior_col in $sampled_behaviors_queryS
    #         ), fittest_inds as (
    #             SELECT *
    #             FROM (
    #                 SELECT *, ROW_NUMBER() OVER (PARTITION BY $behavior_col ORDER BY fitness ASC) AS rn
    #                 FROM ( 
    #                     /* join nodes and edges. Subset by the behaviors chosen
    #                     For each Behaviors. Many individuals exist
    #                     Having the same behavior does not guarantee that they all have the same fitness (Behaviors can be coarse descriptos)
    #                     */
    #                     SELECT EDGES._to, EDGES.fitness, SAMPLED_IDS.$behavior_col
    #                     FROM EDGES
    #                     JOIN SAMPLED_IDS ON (
    #                         EDGES._to = sampled_ids.id_hash
    #                     )
    #                 )
    #             ) /* The fittest individual (id_hash) for each group */
    #             /* => 1 fittest individual for each behavior */
    #             WHERE rn = 1
    #         )

    #         /* -- For the select fittest inds for each behavior. */
    #         /* -- Get the serialized information */
    #         SELECT id_hash, SAMPLED_IDS.$behavior_col, SAMPLED_IDS.$serialization_col
    #         FROM sampled_ids
    #         JOIN fittest_inds ON (
    #             sampled_ids.id_hash = fittest_inds._to
    #         )
    #         """,
    #     ),
    # )
    DF_fittest_per_behavior = vcat(elite_inds, pareto_front)
    # DF_fittest_per_behavior = elite_inds
    new_pop = []
    behaviors_serialized = DF_fittest_per_behavior[:, serialization_col]
    ids = deepcopy(collect(skipmissing(DF_fittest_per_behavior[:, "id_hash"])))
    behavior_ids = deepcopy(collect(skipmissing(DF_fittest_per_behavior[:, behavior_col])))
    for ind_to_resuscitate in behaviors_serialized
        ind = deserialize_ind_from_string(ind_to_resuscitate)
        push!(new_pop, ind)
    end
    UTCGP.reset_genome!.(new_pop)
    # @assert length(unique(DF_fittest_per_behavior[:, behavior_col])) == length(new_pop) # there is one individual for each behavior

    n = length(new_pop)
    parent_pop[] = n

    i = 0
    while n < pop_size && i < CROSSOVER_POP
        p_index = sample(1:n, 2)
        ps = [new_pop[p_index[1]], new_pop[p_index[2]]]
        chromosome_idx = rand(1:2)
        p1 = pop!(ps)
        p2 = pop!(ps)
        new_ind = deepcopy(p1)
        p2 = deepcopy(p2)
        empty!(new_ind[chromosome_idx].chromosome)
        push!(new_ind[chromosome_idx].chromosome, p2[chromosome_idx]...)
        push!(new_pop, new_ind)
        parent_id = ids[p_index[1]]
        push!(ids, deepcopy(parent_id))
        i += 1
    end
    # if n < pop_size
    #     # we have to oversample because there is no enough behaviors 
    #     # in order to sample the req amount
    #     @info "Oversampling the fittest ind. per behavior bc $(length(new_pop)) behaviors while $(pop_size) are required"
    #     while length(new_pop) != pop_size
    #         chosen_one = rand(1:n)
    #         ind = new_pop[chosen_one]
    #         push!(new_pop, deepcopy(ind))
    #         push!(ids, ids[chosen_one])
    #     end
    # end

    # tournament select by robustness
    if n < pop_size
        # we have to oversample because there is no enough behaviors 
        # in order to sample the req amount
        @info "Oversampling the fittest ind. per behavior bc $(length(new_pop)) behaviors while $(pop_size) are required"
        while length(new_pop) != pop_size
            # tournament
            chosen_three = (rand(1:n), rand(1:n), rand(1:n))
            weights = []
            for i in chosen_three
                id = behavior_ids[i]
                counts = DF_fittest_per_behavior[
                    DF_fittest_per_behavior[:, behavior_col].==id,
                    "c_temp",
                ][1]
                push!(weights, counts)
            end
            winner_idx = sample(collect(chosen_three), Weights(identity.(weights)), 1)[1] # the idx w.r.t the DF
            winner = new_pop[winner_idx]
            winner_id = ids[winner_idx]
            push!(new_pop, deepcopy(winner))
            push!(ids, winner_id)
        end
    end
    # if n < pop_size
    #     # we have to oversample because there is no enough behaviors 
    #     # in order to sample the req amount
    #     @info "Oversampling the fittest ind. per behavior bc $(length(new_pop)) behaviors while $(pop_size) are required"
    #     while length(new_pop) != pop_size
    #         # tournament
    #         chosen_three = (rand(1:n), rand(1:n), rand(1:n))
    #         deceptiveness = []
    #         for i in chosen_three
    #             id = behavior_ids[i]
    #             std_f = 0.0
    #             try
    #                 std_f += neigborhood[neigborhood[:, behavior_col].==id, "std_f"][1]
    #             catch
    #                 std_f += mean(skipmissing(neigborhood[:, "std_f"]))
    #             end
    #             push!(deceptiveness, std_f)
    #         end
    #         winner = new_pop[chosen_three[argmin(deceptiveness)]]
    #         winner_id = ids[chosen_three[argmin(deceptiveness)]]
    #         push!(new_pop, deepcopy(winner))
    #         push!(ids, winner_id)

    #     end
    # end
    e = length(new_pop) > pop_size ? pop_size : length(new_pop)
    if n > pop_size
        @warn "Population could be larger 50 vs $(n)"
    end
    pop = Population(new_pop[1:e])
    # Get id_hashes from parents
    _stn_id_hash_pop!(pop, pop_args.mappings, ids[1:e], Parent())
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
    n = length(Pop)
    parent_n = parent_pop[]
    @info "Mutating from $(parent_n+1) to $n"
    for individual in Pop.pop[parent_n+1:n] # truncated mut && allows for update on the true value of that behavior
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
function (obj::eval_budget_early_stop)(budget_args::STN_EPOCH_ARGS)::Bool
    n_evals = @unwrap_or _count_evals(budget_args.ind_loss_tracker) (
        @error "Could not count evals for budget"; return false
    )
    obj.cur_budget += n_evals
    decision = decide_max_budget(obj)
    @info "Eval Budget. Curr budget : $(obj.cur_budget)"
    return decision
end



