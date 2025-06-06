import StatsBase: sample, Weights
import Random

abstract type AbstractNumberedMutationArgs end
struct MissingNumberedMutationArgs <: AbstractNumberedMutationArgs end
struct NumberedMutationArgs <: AbstractNumberedMutationArgs
    mutation_n_active_nodes::Int64
    function NumberedMutationArgs(mutation_n_active_nodes::Number)
        @assert mutation_n_active_nodes >= 1.0 "Mutation should be > 1."
        new(Int64(mutation_n_active_nodes))
    end
end

numbered_mutation_trait(conf) = MissingNumberedMutationArgs
numbered_mutation_trait(conf::RunConfGA) = NumberedMutationArgs(conf.mutation_rate)
numbered_mutation_trait(conf::RunConfCrossOverGA) =
    NumberedMutationArgs(conf.mutation_n_active_nodes)
numbered_mutation_trait(conf::runConf) = NumberedMutationArgs(conf.mutation_rate)

function numbered_mutation!(
    ut_genome::UTGenome,
    numbered_mutation_args::NumberedMutationArgs,
    model_architecture::modelArchitecture,
    meta_library::MetaLibrary,
    shared_inputs::SharedInput,
)
    @assert length(model_architecture.inputs_types) > 0 "At least one input ? "
    @assert length(model_architecture.chromosomes_types) == length(ut_genome.genomes) "Need to give all chromosome types (Int, Float64, ...) in order so we check that nodes function with available signatures"

    # n to sample 
    n = numbered_mutation_args.mutation_n_active_nodes
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
        numbered_mutation!(
            selected_nodes,
            meta_library,
            model_architecture,
            ut_genome,
            shared_inputs,
        )
        return selected_nodes, sampled_idx
    end
end

function numbered_mutation!(
    ut_genome::UTGenome,
    run_config::AbstractRunConf,
    model_architecture::modelArchitecture,
    meta_library::MetaLibrary,
    shared_inputs::SharedInput,
)

    # TODO 
    numbered_mutation!(
        ut_genome,
        numbered_mutation_trait(run_config),
        model_architecture,
        meta_library,
        shared_inputs,
    )
end

function numbered_mutation!(
    nodes::Vector{<:AbstractGenomeNode},
    meta_library::MetaLibrary,
    model_architecture::modelArchitecture,
    ut_genome::UTGenome,
    shared_inputs::SharedInput,
)
    for node_to_mutate in nodes
        library = meta_library[node_to_mutate.y_position]
        standard_mutate!(
            node_to_mutate,
            model_architecture,
            library,
            ut_genome,
            shared_inputs,
        )
    end
end

# FREE NUMBERED MUTATION ##
function free_numbered_mutation!(
    ut_genome::UTGenome,
    run_config::runConf,
    model_architecture::modelArchitecture,
    meta_library::MetaLibrary,
    shared_inputs::SharedInput,
)
    @assert run_config.mutation_rate > 1.0 "Mutation should be > 1."
    @assert length(model_architecture.inputs_types) > 0 "At least one input ? "
    @assert length(model_architecture.chromosomes_types) == length(ut_genome.genomes) "Need to give all chromosome types (Int, Float64, ...) in order so we check that nodes function with available signatures"  # noqa :: 3501

    # n to sample 
    n = floor(Int, run_config.mutation_rate)
    # decode 
    ind_progs = free_decode_with_output_nodes(
        ut_genome,
        meta_library,
        model_architecture,
        shared_inputs,
    )
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
        free_numbered_mutation!(
            selected_nodes,
            meta_library,
            model_architecture,
            ut_genome,
            shared_inputs,
        )
        return selected_nodes, sampled_idx
    end
    return nothing
end


function free_numbered_mutation!(
    nodes::Vector{<:AbstractGenomeNode},
    meta_library::MetaLibrary,
    model_architecture::modelArchitecture,
    ut_genome::UTGenome,
    shared_inputs::SharedInput,
)
    for node_to_mutate in nodes
        library = meta_library[node_to_mutate.y_position]
        free_mutate!(node_to_mutate, model_architecture, library, ut_genome, shared_inputs)
    end
end

export NumberedMutationArgs, numbered_mutation_trait
