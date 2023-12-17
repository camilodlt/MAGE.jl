
##################################
# FILL GENOME WITH EVOLVABLE NODES
##################################
function make_evolvable_single_genome(
    n_nodes::Int,
    arity::Int,
    offset_by::Int,
    min_fn::Int,
    max_fn::Int,
    max_types::Int,
    y_pos::Int,
)::SingleGenome
    @assert n_nodes >= 1
    @assert offset_by >= 1
    @assert min_fn <= max_fn
    # @assert n_params >= 0
    nodes = Vector{CGPNode}()

    for ith_node = 1:n_nodes # directed graph
        x_pos = offset_by + ith_node
        x_real_pos = ith_node
        y_pos = y_pos
        highest_node_position = x_pos - 1
        node = make_evolvable_node(
            arity,
            min_fn,
            max_fn,
            1,
            highest_node_position,
            1,
            max_types,
            x_pos,
            x_real_pos,
            y_pos,
        )
        push!(nodes, node)
    end
    genome = SingleGenome(offset_by, nodes)
    return genome
end


function make_evolvable_utgenome(
    model_architecture::modelArchitecture,
    meta_library::MetaLibrary,
    node_config::nodeConfig,
)::Tuple{SharedInput,UTGenome}

    inputs_types = model_architecture.inputs_types
    inputs_types_idx = model_architecture.inputs_types_idx
    chromosomes_types = model_architecture.chromosomes_types
    outputs_types = model_architecture.outputs_types
    outputs_types_idx = model_architecture.outputs_types_idx

    n_inputs = length(inputs_types)
    n_chromosomes = length(chromosomes_types)
    n_outputs = length(outputs_types)

    # Assert consistency
    @assert n_chromosomes == length(meta_library.libraries) "UT GENOME not consistent"
    @assert n_inputs == node_config.offset_by

    # MAKE CHROMOSOMES 
    chromosomes = SingleGenome[]
    for ith_chromosome = 1:n_chromosomes
        lib = meta_library.libraries[ith_chromosome]
        # Make chromosomes :
        s_genome = make_evolvable_single_genome(
            node_config.n_nodes,
            node_config.arity,
            node_config.offset_by,
            1,
            length(lib),
            n_chromosomes,
            ith_chromosome,
        )
        push!(chromosomes, s_genome)
    end

    # MAKE THE OUTPUTS
    output_nodes = OutputNode[]
    max_connectable_node = node_config.n_nodes + n_inputs
    min_connectable_node = 1
    for ith_output = 1:n_outputs
        output_type_idx = outputs_types_idx[ith_output]  # the type of the output
        # lib_for_output = meta_library.libraries[outputs_types_idx]
        # convention that the first fn is the one used for output node
        x_pos = max_connectable_node + ith_output
        y_pos = output_type_idx
        output_node = make_output_node(
            1,
            min_connectable_node,
            max_connectable_node,
            output_type_idx,
            x_pos,
            y_pos,
        )
        push!(output_nodes, output_node)
    end


    # BUILD GENOME
    ut_genome = UTGenome(chromosomes, output_nodes)

    # MAKE THE INPUTS
    inputs = [
        InputNode(nothing, x_ith, x_ith, y_ith) for
        (x_ith, y_ith) in enumerate(inputs_types_idx)
    ]
    inputs = SharedInput(inputs)
    return (inputs, ut_genome)
end
