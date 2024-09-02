using StatsBase: sample, ProbabilityWeights

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~#
# Default Population Callback
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~#

"""

A population of size 1 is expanded to a population of size lambda_. 

Where each offspring is a `deepcopy` of the only UTGenome in the population.
"""
function default_population_callback(
    population::Population,
    generation::Int,
    run_config::runConf,
    model_architecture::modelArchitecture,
    node_config::nodeConfig,
    meta_library::MetaLibrary,
    args...,
)::Population
    lambda_ = run_config.lambda_
    @assert size(population) == 1
    parent = population[1]
    population = Population([deepcopy(parent) for i = 1:lambda_])
    return population
end

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~#
# Default Mutation Callback
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~#


function default_mutation_callback(population::Population, args...)
    run_config = args[2]
    model_architecture = args[3]
    meta_library = args[5]
    shared_inputs = args[6]
    @assert run_config isa runConf
    @assert shared_inputs isa SharedInput
    @assert meta_library isa MetaLibrary
    @assert model_architecture isa modelArchitecture

    # chromosomes_types = model_architecture.chromosomes_types
    # input_types = model_architecture.inputs_type_idx
    for individual in population
        standard_mutate!(
            individual,
            run_config,
            model_architecture,
            meta_library,
            shared_inputs,
        )
    end
    return population
end

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~#
# Default Mutation Callback (Numbered)
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~#

function default_numbered_mutation_callback(population::Population, args...)
    run_config = args[2]
    model_architecture = args[3]
    meta_library = args[5]
    shared_inputs = args[6]
    @assert run_config isa runConf
    @assert shared_inputs isa SharedInput
    @assert meta_library isa MetaLibrary
    @assert model_architecture isa modelArchitecture

    # chromosomes_types = model_architecture.chromosomes_types
    # input_types = model_architecture.inputs_type_idx
    for individual in population
        numbered_mutation!(
            individual,
            run_config,
            model_architecture,
            meta_library,
            shared_inputs,
        )
    end
    return population
end

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~#
# Default Mutation Callback (Numbered)
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~#

function default_numbered_new_material_mutation_callback(population::Population, args...)
    run_config = args[2]
    model_architecture = args[3]
    meta_library = args[5]
    shared_inputs = args[6]
    @assert run_config isa runConf
    @assert shared_inputs isa SharedInput
    @assert meta_library isa MetaLibrary
    @assert model_architecture isa modelArchitecture

    # chromosomes_types = model_architecture.chromosomes_types
    # input_types = model_architecture.inputs_type_idx
    for individual in population
        new_material_mutation!(
            individual,
            run_config,
            model_architecture,
            meta_library,
            shared_inputs,
        )
    end
    return population
end

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~#
# Default Mutation Callback
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~#
function default_free_mutation_callback(population::Population, args...)
    run_config = args[2]
    model_architecture = args[3]
    meta_library = args[5]
    shared_inputs = args[6]
    @assert run_config isa runConf
    @assert shared_inputs isa SharedInput
    @assert meta_library isa MetaLibrary
    @assert model_architecture isa modelArchitecture

    # chromosomes_types = model_architecture.chromosomes_types
    # input_types = model_architecture.inputs_type_idx
    for individual in population
        free_mutate!(
            individual,
            run_config,
            model_architecture,
            meta_library,
            shared_inputs,
        )
    end
    return population
end


# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~#
# Default Mutation Callback
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~#
function default_free_numbered_mutation_callback(population::Population, args...)
    run_config = args[2]
    model_architecture = args[3]
    meta_library = args[5]
    shared_inputs = args[6]
    @assert run_config isa runConf
    @assert shared_inputs isa SharedInput
    @assert meta_library isa MetaLibrary
    @assert model_architecture isa modelArchitecture

    # chromosomes_types = model_architecture.chromosomes_types
    # input_types = model_architecture.inputs_type_idx
    for individual in population
        free_numbered_mutation!(
            individual,
            run_config,
            model_architecture,
            meta_library,
            shared_inputs,
        )
    end
    return population
end

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~#
# Default Mutation Callback
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~#
function correct_all_nodes_callback(population::Population, args...)
    model_architecture = args[3]
    meta_library = args[5]
    shared_inputs = args[6]
    @assert shared_inputs isa SharedInput
    @assert meta_library isa MetaLibrary
    @assert model_architecture isa modelArchitecture

    for individual in population
        correct_all_nodes!(individual, model_architecture, meta_library, shared_inputs)
    end
    return population
end


# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~#
# Default Output Mutation Callback
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~#


function default_ouptut_mutation_callback(
    population::Population,
    generation::Int,
    run_config::runConf,
    model_architecture::modelArchitecture,
    node_config::nodeConfig,
    meta_library::MetaLibrary,
    args...,
)
    for individual in population
        for output_node in individual.output_nodes
            if rand() < run_config.output_mutation_rate
                mutate_one_element_from_node!(output_node)
            end
        end
    end
    return population
end

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~#
# Default Decoding Callbacks
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~#

# Normal Decoding Callback
function default_decoding_callback(
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

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~#
# Default FREE decoding
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~#

# Normal Decoding Callback
function default_free_decoding_callback(
    population::Population,
    generation::Int,
    run_config::runConf,
    model_architecture::modelArchitecture,
    node_config::nodeConfig,
    meta_library::MetaLibrary,
    shared_inputs::SharedInput,
)::PopulationPrograms
    # Decoding all programs
    population_programs = [
        free_decode_with_output_nodes(
            individual,
            meta_library,
            model_architecture,
            shared_inputs,
        ) for individual in population
    ]

    return PopulationPrograms(population_programs)
end

# # Remove Duplicates callback --- [OPTIONAL]
# @define
# class Duplicates_removal::
#     """
#     This class keeps track of already computed programs an filters them out.

#     The call method abides the Decoding Protocol
#     """

#     already_runned_programs:: dict[str, int] = field(
#         init=False,
#         default=Factory(dict),
#     )  # store hashes

#     function __call__(
#         self,
#         population:: Population,
#         meta_library:: MetaLibrary,
#         *args,
#         **kwargs:: Unpack[decodingKwargs],
#     ) -> PopulationPrograms::
#         """
#         NOT THREAD SAFE BC IT HAS TO MODIFY POPULATION OBJECT PASSED BY
#         REFERENCE.
#             => a thread safe alternative can be to enable/disable a given
#             => individual_programs in the population.
#             => so that the object size remains the same
#             => In this method there will be racing

#         Has to run at least as the second decoding callback because it expects
#         the kwarg "programs". Which are the already decoded programs.
#         """

#         programs = kwargs.get("programs")
#         assert programs is not None, "Duplicates Removal callback needs\
#         decoded programs in order to check duplicates"
#         assert isinstance(programs, PopulationPrograms)

#         elite_ind = len(population) - 1  # always the last. Always kept
#         unique_indices = unique_programs(
#             programs, self.already_runned_programs
#         )
#         unique_indices = set(unique_indices)
#         unique_indices.add(elite_ind)
#         unique_indices = sorted(unique_indices)
#         filtered_programs = PopulationPrograms(
#             [programs[i] for i in unique_indices]
#         )
#         logger.info(
#             "Number of unique programs (with elite) :: %i", len(unique_indices)
#         )

#         # ⚠  SIDE EFFECT ⚠  #
#         if len(unique_indices) != len(population)::  # pop has to be mod
#             # log it
#             for ith_ind in range(len(population))::
#                 if ith_ind not in unique_indices::
#                     logger.debug(
#                         "Side Effect Subsetting Population.\
#                         Removing %i element in population.",
#                         ith_ind,
#                     )
#             # actually slice the pop
#             new_pop = [
#                 individual
#                 for ith_ind, individual in enumerate(population)
#                 if ith_ind in unique_indices
#             ]
#             population.pop.clear()  # keep ref to list but empty it
#             population.pop.extend(new_pop)  # fill with new pop

#         assert len(population) == len(filtered_programs)
#         return filtered_programs


# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~#
# Default Elite selection Callbacks
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~#


function default_elite_selection_callback(
    ind_performances::Union{Vector{<:Number},Vector{Vector{<:Number}}},
    population::Population,
    generation::Int,
    run_config::runConf,
    model_architecture::modelArchitecture,
    node_config::nodeConfig,
    meta_library::MetaLibrary,
    programs::PopulationPrograms,
    args...,
)::Int

    if ind_performances[1] isa Vector
        throw(ErrorException("Pareto Front not implemented yet"))
    else
        ind_performances_ = deepcopy(ind_performances)
        m = findall(isnan.(ind_performances_))
        ind_performances_[m] .= Inf # so Nan are the worst solutions
        return argmin(ind_performances_)
    end
end

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~#
# Default Elite selection Callback : Distribution
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~#


function default_eliteDistribution_selection_callback(
    ind_performances::Union{Vector{<:Number},Vector{Vector{<:Number}}},
    population::Population,
    generation::Int,
    run_config::runConf,
    model_architecture::modelArchitecture,
    node_config::nodeConfig,
    meta_library::MetaLibrary,
    programs::PopulationPrograms,
    args...,
)::Int

    if ind_performances[1] isa Vector
        throw(ErrorException("Pareto Front not implemented yet"))
    else
        TS::String = get(ENV, "MAGE_TEMPERATURE", "0.3")
        T = parse(Float64, TS)
        m = findall(isnan.(ind_performances)) # missing
        n = length(ind_performances) # pop size & parent index
        # mask nan
        masked_individual_performances = deepcopy(ind_performances)
        masked_individual_performances[m] .= typemax(Float64) # inf bad
        β′ = masked_individual_performances[end] # parent fitness
        β★ = minimum(masked_individual_performances) # best fitness
        @assert β′ == ind_performances[end] # that the filtering step did not remove the parent ? 
        if β★ <= β′ # return best if new best fitness 
            return argmin(masked_individual_performances) # its the true index of the individual who got β★
        else # return from sampling the distribution Φ
            Φ = [exp(-(α - β′) / T) for α in masked_individual_performances]
            sampled_individual = sample(collect(eachindex(Φ)), ProbabilityWeights(Φ))
            return sampled_individual
        end
    end
end

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~#
# Default early stop callback
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~#


function default_early_stop_callback(
    generation_loss_tracker::GenerationLossTracker,
    ind_loss_tracker::IndividualLossTracker,
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
)::Bool
    return generation_loss_tracker[generation][1] ≈ 0.0
end

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~#
# MAX EVAL BUDGET
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~#


mutable struct eval_budget_early_stop <: AbstractCallable
    max_budget::Int
    cur_budget::Int
    function eval_budget_early_stop(b::Int)
        @assert b > 0
        return new(b, 0)
    end
end

function decide_max_budget(tracker::eval_budget_early_stop)
    decision = tracker.cur_budget >= tracker.max_budget
    @debug "Max eval budget early stop decision : $decision. Because current : $(tracker.cur_budget) while max : $(tracker.max_budget) "
    decision
end

function _count_evals(tracker::IndividualLossTracker)::Option{Int}
    n_evals = sum([length(i[2]) for i in tracker.store]) # sum all evals for all individuals
    some(n_evals)

end
function _count_evals(tracker::IndividualLossTrackerMT)::Option{Int}
    n_evals = tracker.n_individuals * tracker.n_samples
    some(n_evals)
end

function _count_evals(::AbstractIndLossTracker)::Option{Int}
    none
end

"""

Normal Eval Budget
"""
function (obj::eval_budget_early_stop)(
    generation_loss_tracker::GenerationLossTracker,
    ind_loss_tracker::AbstractIndLossTracker, # either for MultiT or not
    ind_performances::Union{Vector{<:Number},Vector{Vector{<:Number}}},
    population::Population,
    generation::Int,
    run_config::runConf,
    model_architecture::modelArchitecture,
    node_config::nodeConfig,
    meta_library::MetaLibrary,
    shared_inputs::SharedInput,
    programs::PopulationPrograms,
    best_losses::Float64,
    best_programs::IndividualPrograms,
    elite_idx::Int,
)::Bool
    n_evals = @unwrap_or _count_evals(ind_loss_tracker) (
        @error "Could not count evals for budget"; return false
    )
    obj.cur_budget += n_evals
    decision = decide_max_budget(obj)
    return decision
end


# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~#
# Racing mutation (Numbered + new mat)
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~#
struct racing_mutation <: AbstractCallable
    fitness_callback::Function
    get_instances::Function #(xs, ys)
    max_calls_new_material::Int
    max_calls_racing::Int
    accept_race::Function
    bookkeeper::Dict
    budgeter::AbstractCallable
end

function (rm::racing_mutation)(population::Population, args...)
    run_config = args[2]
    model_architecture = args[3]
    meta_library = args[5]
    shared_inputs = args[6]
    @assert run_config isa runConf
    @assert shared_inputs isa SharedInput
    @assert meta_library isa MetaLibrary
    @assert model_architecture isa modelArchitecture

    for (i, individual) in enumerate(population)
        @info "Racing ind $i"
        racing_mutation!(
            individual,
            run_config,
            model_architecture,
            meta_library,
            shared_inputs,
            rm,
        )
    end
    return population
end

function racing_mutation!(
    ut_genome::UTGenome,
    run_config::AbstractRunConf,
    model_architecture::modelArchitecture,
    meta_library::MetaLibrary,
    shared_inputs::SharedInput,
    racing_struct::racing_mutation,
)
    @assert run_config.mutation_rate > 1.0 "Mutation should be > 1."
    @assert length(model_architecture.inputs_types) > 0 "At least one input ? "
    @assert length(model_architecture.chromosomes_types) == length(ut_genome.genomes) "Need to give all chromosome types (Int, Float64, ...) in order so we check that nodes function with available signatures"  # noqa :: 3501
    # n to sample 
    n = floor(Int, run_config.mutation_rate)
    # decode 
    ind_progs =
        decode_with_output_nodes(ut_genome, meta_library, model_architecture, shared_inputs)
    # get active nodes 
    active_nodes = get_active_nodes(ind_progs)
    n_mutable_nodes = length(active_nodes)
    # 
    if n > n_mutable_nodes
        @warn "A mutation of $n nodes was asked. But active graph only has $n_mutable_nodes. It will mutate $n_mutable_nodes"
        n = n_mutable_nodes
    end
    if n > 0
        sampled_idx = sample_n(length(active_nodes), n)
        selected_nodes = active_nodes[sampled_idx]
        @debug "Selected node(s) to mutate : $([n.id for n in selected_nodes])"
        racing_mutation!(
            selected_nodes,
            meta_library,
            model_architecture,
            ut_genome,
            shared_inputs,
            racing_struct,
        )
        return selected_nodes, sampled_idx
    end
end

function racing_mutation!(
    nodes::Vector{<:AbstractGenomeNode},
    meta_library::MetaLibrary,
    model_architecture::modelArchitecture,
    ut_genome::UTGenome,
    shared_inputs::SharedInput,
    racing_struct::racing_mutation,
)
    previous_prog = decode_with_output_nodes(
        deepcopy(ut_genome),
        meta_library,
        model_architecture,
        shared_inputs,
    )
    xs, ys = racing_struct.get_instances() # to use the same data on all inds
    parent_error_tracker = fill(NaN, length(xs)) # will at most be computed 1 time in full
    # parent_outputs_tracker = fill(NaN, length(xs)) # will at most be computed 1 time in full
    parent_outputs_tracker = Vector{Vector{Float64}}(undef, length(xs))
    # prev_fitness = racing_struct.fitness_callback(
    #     previous_prog,
    #     model_architecture,
    #     meta_library,
    #     shared_inputs,
    #     racing_struct,
    # )
    has_to_race = true
    n = 0
    prev_material = [
        get_active_node_material(
            node,
            meta_library[node.y_position],
            ut_genome,
            shared_inputs,
            model_architecture,
        ) for node in deepcopy(nodes)
    ]
    prev_all_material = node_to_vector.(nodes)
    tested_nodes_material = []
    tested_nodes_dist = []
    while has_to_race
        # reset node to their previous state
        for (i, node_to_mutate) in enumerate(nodes)
            for (j, node_element) in enumerate(node_to_mutate)
                set_node_element_value!(node_element, Int(prev_all_material[i][j]))
            end
        end
        # 
        for node_to_mutate in nodes
            library = meta_library[node_to_mutate.y_position]
            racing_mutation!(
                node_to_mutate,
                model_architecture,
                library,
                ut_genome,
                shared_inputs,
                racing_struct,
            ) # mutates in place the ut_genome, so now we can decode again and see if the offspring is better
        end
        new_material = [
            get_active_node_material(
                node,
                meta_library[node.y_position],
                ut_genome,
                shared_inputs,
                model_architecture,
            ) for node in nodes
        ]

        if all(prev_material .== new_material) # if all nodes are equal to the orig version, try again
            # @bp
            # continue TODO
            println("TODO, do not let an identical node leave.")
            continue
        end
        new_prog = decode_with_output_nodes(
            deepcopy(ut_genome),
            meta_library,
            model_architecture,
            shared_inputs,
        )
        hash = UTCGP.individual_phen_hasher(new_prog)
        if hash in keys(racing_struct.bookkeeper)
            racing_struct.bookkeeper[hash] += 1
            continue
            # continue
        else
            racing_struct.bookkeeper[hash] = 1
        end
        # if get(racing_struct.bookkeeper, hash, 1) > 1
        #     @error "the continue did not work ? "
        # end
        prev_fitness, new_fitness, parent_f, child_f = racing_struct.fitness_callback(
            previous_prog,
            new_prog,
            xs,
            ys,
            parent_outputs_tracker,
            parent_error_tracker,
            model_architecture,
            meta_library,
            shared_inputs,
            racing_struct,
        )
        has_to_race, forced, dist = racing_struct.accept_race(
            prev_fitness,
            new_fitness,
            parent_f,
            child_f,
            n,
            racing_struct,
        )
        n += 1

        if !forced
            push!(tested_nodes_dist, dist)
            push!(tested_nodes_material, node_to_vector.(nodes))
        end

        # IF HAS TO HACE FORCED (out of budget). Pick the closest one
        if forced
            # if isdefined(Main, :Infiltrator)
            #     Main.infiltrate(@__MODULE__, Base.@locals, @__FILE__, @__LINE__)
            # end
            subset = abs.(tested_nodes_dist) .> eps(Float64) .&& tested_nodes_dist .!= 0.0
            if sum(subset) == 0 # none is diff than 0
                @info "Could not set to closest one. Last one is picked"
                break
            end
            idx = sortperm(tested_nodes_dist[subset])[1]
            closest_one = tested_nodes_material[subset][idx]
            for (i, node_to_mutate) in enumerate(nodes)
                for (j, node_element) in enumerate(node_to_mutate)
                    set_node_element_value!(node_element, Int(closest_one[i][j]))
                end
            end
            @info "Set to the closest one at idx : $idx, with dist : $(tested_nodes_dist[idx]). Other candidates : $tested_nodes_dist"
        end

        # @info "Individual is up to a new race because it was not accepted"
    end
    # new_prog =
    #     decode_with_output_nodes(ut_genome, meta_library, model_architecture, shared_inputs)

end

function racing_mutation!(
    node::CGPNode,
    model_architecture::modelArchitecture,
    library::Library,
    ut_genome::UTGenome,
    shared_inputs::SharedInput,
    racing_struct::racing_mutation,
)
    max_calls = racing_struct.max_calls_new_material
    call_nb = 0
    prev = get_active_node_material(
        node,
        library,
        ut_genome,
        shared_inputs,
        model_architecture,
    )
    while !check_functionning_node(
        node,
        library,
        ut_genome,
        shared_inputs,
        model_architecture,
    ) ||
        get_active_node_material(
            node,
            library,
            ut_genome,
            shared_inputs,
            model_architecture,
        ) == prev
        mutate_one_element_from_node!(node)
        if call_nb > max_calls
            @warn "Can't find a correct mutation after $call_nb"
            @warn node_to_vector(node)
            @warn node.id
            node.node_material[1].value = 2 # CONVENTION BY DEFAULT
            @warn "Node didn't find a functionning call after $max_calls iterations. Current call : $call_nb"
            break
        end
        call_nb += 1
    end
end


