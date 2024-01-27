
import StatsBase: sample, Weights
import Random
using Debugger

function new_material_mutation!(
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
        @info "Selected node(s) to mutate : $([n.id for n in selected_nodes])"
        new_material_mutation!(
            selected_nodes,
            meta_library,
            model_architecture,
            ut_genome,
            shared_inputs,
        )
        return selected_nodes, sampled_idx
    end
end

function new_material_mutation!(
    nodes::Vector{<:AbstractGenomeNode},
    meta_library::MetaLibrary,
    model_architecture::modelArchitecture,
    ut_genome::UTGenome,
    shared_inputs::SharedInput,
)
    for node_to_mutate in nodes
        library = meta_library[node_to_mutate.y_position]
        new_material_mutation!(
            node_to_mutate,
            model_architecture,
            library,
            ut_genome,
            shared_inputs,
        )
    end
end

function new_material_mutation!(
    node::CGPNode,
    model_architecture::modelArchitecture,
    library::Library,
    ut_genome::UTGenome,
    shared_inputs::SharedInput,
)
    max_calls = 1000
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

