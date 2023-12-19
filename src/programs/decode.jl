# -*- coding: utf-8 -*-

function extract_fn_connexions_types_from_node(
    node::AbstractEvolvableNode,
    library::Library,
)::Tuple{FunctionWrapper,Vector{CGPElement},Vector{CGPElement}}

    # Extract Function
    fn_element = extract_function_from_node(node)
    fn = fn_element.value
    fn = library[fn]

    # Connexions 
    connexions = extract_connexions_from_node(node)
    connexions_types = extract_connexions_types_from_node(node)
    return tuple(fn, connexions, connexions_types)
end

function _validate_connexions(
    connexions::Vector{CGPElement},
    connexions_types::Vector{CGPElement},
)
    # validate CGP ELEMENTS
    for con in connexions
        @assert con.element_type == CONNEXION
    end
    for con_t in connexions_types
        @assert con_t.element_type == TYPE
    end
    @assert length(connexions) == length(connexions_types)
end



function _operation_input_from_shared_inputs(
    shared_inputs::SharedInput,
    index_at::Int,
    model_architecture::modelArchitecture,
)
    input_wrapper = InputPromise(shared_inputs.inputs, index_at)
    #node_type_idx = shared_inputs[index_at].y_position. Not using y_pos since Inputs is uni dim
    type = model_architecture.inputs_types[index_at]
    #this type will be used to get the method that julia will call
    # the idx type of input is not relevant
    op_input = OperationInput(input_wrapper, -1, type)
    return op_input
end

function _operation_input_from_chromosome(
    concerned_chromosome::AbstractGenome,
    index_at::Int,
    model_architecture::modelArchitecture,
)

    node = concerned_chromosome.chromosome[index_at]  # CGP NODE
    node_type_idx = node.y_position
    # this node_type_idx will be used to index the metalibrary in the call n+1
    # since all inputs nodes will be the calling_node in the call n+1
    type = model_architecture.chromosomes_types[node_type_idx]
    #this type will be used to get the method that julia will call
    op_input = OperationInput(node, node_type_idx, type)
    return op_input
end

"""
From node's connections, makes a vector of OperationInput s

An OperationInput wraps the input, which might be an InputNode or a normal CGPNode
"""
function inputs_for_node(
    connexions::Vector{CGPElement},
    connexions_types::Vector{CGPElement},
    ut_genome::UTGenome,
    shared_inputs::SharedInput,
    model_architecture::modelArchitecture,
)::Vector{OperationInput}
    _validate_connexions(connexions, connexions_types)
    # Extract Inputs
    inputs = OperationInput[]

    for idx = 1:length(connexions)
        # # get the element objs
        connexion_value = get_node_element_value(connexions[idx])
        connexion_type_value = get_node_element_value(connexions_types[idx]) # to filter the utgenome
        concerned_chromosome = ut_genome.genomes[connexion_type_value]
        connexion_is_input_node = false

        # GET THE ACTUAL INDEX VALUE
        # either from share_input or from the genome
        if connexion_value <= concerned_chromosome.starting_point
            @debug "Input is in SharedInput"
            # the connection is an input node
            connexion_is_input_node = true
            index_at = connexion_value # index the inputs
        else
            @debug "Input is in Chromosome"
            # offset by the n inputs. Index the genome
            index_at = connexion_value - concerned_chromosome.starting_point
        end
        @debug "Index at : $index_at"
        # GET THE NODE OR A WAY TO GET THE INPUT NODE
        if connexion_is_input_node
            op_input = _operation_input_from_shared_inputs(
                shared_inputs,
                index_at,
                model_architecture,
            )
        else
            op_input = _operation_input_from_chromosome(
                concerned_chromosome,
                index_at,
                model_architecture,
            )
        end
        push!(inputs, op_input)
    end
    return inputs
end


"""
Depth-first search (DFS)

Args:
    node (CGP_Node): _description_
    type_idx (int): _description_
    program (list[Any]): _description_
"""
function recursive_decode_node!(
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
    # fn_idx = extract_function_from_node(calling_node).value
    # connexions = extract_connexions_from_node(calling_node)
    # connexions_types = extract_connexions_types_from_node(calling_node)
    inputs = inputs_for_node(
        connexions,
        connexions_types,
        ut_genome,
        shared_inputs,
        model_architecture,
    )
    fn_name = fn.name
    arg_types = tuple([op.type for op in inputs]...)
    # check will function will be called 
    local m = nothing
    try
        m = which(fn.fn, arg_types)
    catch
        @error "No method for fn $fn_name with types : $arg_types"
        throw(MethodError(fn, arg_types))
    end

    n_used_inputs = m.nargs - 2 # - the fn - the varargs
    inputs = inputs[1:n_used_inputs]
    push!(operations_list, Operation(fn, calling_node, inputs))

    # TODO EXTRA PARAMS ???
    for operation_input in inputs
        next_calling_node = extract_input_node_from_operationInput(operation_input)
        next_type_idx = operation_input.type_idx # op_input is the next 
        # calling_node. Hence, its type idx is going to be used 
        # to get the function.
        # If the node is InputNode. The recursion will stop for that branch.
        recursive_decode_node!(
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
function recursive_decode_node!(
    calling_node::InputNode,
    args...,
    # meta_library::MetaLibrary,
    # type_idx::Int,
    # operations_list::Vector{<:AbstractOperation},
    # model_architecture::modelArchitecture,
    # ut_genome::UTGenome,
    # shared_inputs::SharedInput,
) end

function decode_with_output_node(
    ut_genome::UTGenome,
    output_node::OutputNode,
    meta_library::MetaLibrary,
    model_architecture::modelArchitecture,
    shared_inputs::SharedInput,
)::Program
    operations = Operation[]
    # the last in the selected chromosome
    # output_node = genome.genomes[output_chromosome_idx].genome[-1]
    recursive_decode_node!(
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

function decode_with_output_nodes(
    ut_genome::UTGenome,
    meta_library::MetaLibrary,
    model_architecture::modelArchitecture,
    shared_inputs::SharedInput,
)::IndividualPrograms

    # @bp
    output_nodes = ut_genome.output_nodes
    ind_progs = Program[]
    for output_node in output_nodes
        prog = decode_with_output_node(
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

# # REMOVE DUPLICATES #


# def unique_programs(
#     pop_programs: list[list[Any]], already_runned_programs: List[Any]
# ) -> List[int]:
#     pop_programs_representations = []  # will hold 1d representations of
#     for programs_of_individual in pop_programs:
#         programs_of_ind_as_1d_array = []
#         for program in programs_of_individual:
#             program_representation = []
#             for operation in program:
#                 # fn, calling_node, input_node
#                 operation_representation = []
#                 for input_node, type_of_input in operation[2]:
#                     if isinstance(input_node, InputNode):
#                         operation_representation.extend(
#                             [input_node.position, type_of_input]
#                         )
#                     else:
#                         operation_representation.extend(
#                             node_to_vector(input_node)
#                         )
#                 operation_representation.extend(
#                     node_to_vector(operation[1])
#                 )  # calling node
#                 program_representation.extend(operation_representation)
#             programs_of_ind_as_1d_array.extend(program_representation)
#         pop_programs_representations.append(programs_of_ind_as_1d_array)

#     n_progs = len(pop_programs_representations)

#     # CACHE
#     #   => list of vectors of diff size
#     if len(already_runned_programs) > 0:
#         max_length_in_cache = max(
#             len(prog_repr) for prog_repr in already_runned_programs
#         )
#     else:
#         max_length_in_cache = 0

#     # get unique programs
#     max_length_in_current_progs = max(
#         len(prog_repr) for prog_repr in pop_programs_representations
#     )

#     max_length = max(max_length_in_cache, max_length_in_current_progs)
#     pop_programs_representations_padded = [
#         np.pad(prog_repr, (0, max_length - len(prog_repr)))
#         for prog_repr in pop_programs_representations
#     ]
#     cached_padded = [
#         np.pad(prog_repr, (0, max_length - len(prog_repr)))
#         for prog_repr in already_runned_programs
#     ]

#     # Add cached to the right
#     pop_programs_representations_padded.extend(cached_padded)

#     progs = np.array(pop_programs_representations_padded, dtype=np.int32)

#     unique_progs, indices, counts = np.unique(
#         progs, axis=0, return_counts=True, return_index=True
#     )

#     # get the unique in the current programs
#     indices = indices[indices < n_progs]
#     # let's say that unique indices after the sorting done by np.unique are
#     # [200, 31, 99, 1]
#     # we ran two individuals
#     # [...] < n_progs  = [F, F, F, T] = [3] => ↓
#     # the actual index of the unique program in this round

#     # max index (parent)
#     max_index = n_progs - 1
#     indices = set(indices)
#     indices.add(max_index)
#     indices = list(indices)

#     return [pop_programs_representations[i] for i in indices], indices
