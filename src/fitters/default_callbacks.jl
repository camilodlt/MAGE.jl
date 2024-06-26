# # -*- coding:: utf-8 -*-

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
    run_config::runConf,
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

    # Reverse the phenotype
    for ind_programs in population_programs
        for program in ind_programs
            reverse!(program.program)
        end
    end
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

    # Reverse the phenotype
    for ind_programs in population_programs
        for program in ind_programs
            reverse!(program.program)
        end
    end
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

function (obj::eval_budget_early_stop)(
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
    n_evals = sum([length(i[2]) for i in ind_loss_tracker.store]) # sum all evals for all individuals
    obj.cur_budget += n_evals
    decision = decide_max_budget(obj)

    return decision
end
