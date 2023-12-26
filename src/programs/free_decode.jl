# -*- coding: utf-8 -*-

"""
Depth-first search (DFS)

Args:
    node (CGP_Node): _description_
    type_idx (int): _description_
    program (list[Any]): _description_
"""
function free_recursive_decode_node!(
    calling_node::Union{CGPNode,OutputNode},
    meta_library::MetaLibrary,
    type_idx::Int,
    operations_list::Vector{<:AbstractOperation},
    model_architecture::modelArchitecture,
    ut_genome::UTGenome,
    shared_inputs::SharedInput,
)

    fn, connexions, connexions_types = extract_fn_connexions_types_from_node(
        calling_node,
        meta_library.libraries[type_idx],
    )
    inputs = inputs_for_node(
        connexions,
        connexions_types,
        ut_genome,
        shared_inputs,
        model_architecture,
    )
    fn_name = fn.name
    push!(operations_list, Operation(fn, calling_node, inputs))

    # TODO EXTRA PARAMS ???
    for operation_input in inputs
        next_calling_node = extract_input_node_from_operationInput(operation_input)
        next_type_idx = operation_input.type_idx # op_input is the next 
        # calling_node. Hence, its type idx is going to be used 
        # to get the function.
        # If the node is InputNode. The recursion will stop for that branch.
        free_recursive_decode_node!(
            next_calling_node,
            meta_library,
            next_type_idx,
            operations_list,
            model_architecture,
            ut_genome,
            shared_inputs,
        )
    end
end

"""
The recursion is stopped at InputNode
"""
function free_recursive_decode_node!(
    calling_node::InputNode,
    args...,
    # meta_library::MetaLibrary,
    # type_idx::Int,
    # operations_list::Vector{<:AbstractOperation},
    # model_architecture::modelArchitecture,
    # ut_genome::UTGenome,
    # shared_inputs::SharedInput,
) end

function free_decode_with_output_node(
    ut_genome::UTGenome,
    output_node::OutputNode,
    meta_library::MetaLibrary,
    model_architecture::modelArchitecture,
    shared_inputs::SharedInput,
)::Program
    operations = Operation[]
    # the last in the selected chromosome
    # output_node = genome.genomes[output_chromosome_idx].genome[-1]
    free_recursive_decode_node!(
        output_node,
        meta_library,
        output_node.y_position, # its type ==  chromosome index
        operations,
        model_architecture,
        ut_genome,
        shared_inputs,
    )
    return Program(operations)

end

function free_decode_with_output_nodes(
    ut_genome::UTGenome,
    meta_library::MetaLibrary,
    model_architecture::modelArchitecture,
    shared_inputs::SharedInput,
)::IndividualPrograms

    output_nodes = ut_genome.output_nodes
    ind_progs = Program[]
    for output_node in output_nodes
        prog = free_decode_with_output_node(
            ut_genome,
            output_node,
            meta_library,
            model_architecture,
            shared_inputs,
        )
        push!(ind_progs, prog)
    end
    return IndividualPrograms(ind_progs)
end

