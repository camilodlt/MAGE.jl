############################
# Genome-Level ADF Flattening
############################

"""
    copied_adf_body(program)

Return the active non-output operations that must be inserted into the caller
genome. Output nodes are handled separately because the original ADF call node
is rewritten to perform the ADF output operation.

Example: for `tmp1 = add(x, y); out1 = tmp1`, this returns only the `add` operation.
"""
function copied_adf_body(program::Program)::Vector{Operation}
    seen = Set{String}()
    body = Operation[]
    for operation in program
        operation.calling_node isa OutputNode && continue
        operation.calling_node.id in seen && continue
        push!(body, operation)
        push!(seen, operation.calling_node.id)
    end
    return body
end

"""
Return the ADF slot used by one decoded operation, or `nothing` for normal functions.

Example: a decoded `adf_2(x)` operation returns slot 2.
"""
function adf_slot_from_call(operation::Operation)
    return adf_slot_from_wrapper(operation.fn)
end

"""
    active_adf_calls(genome, shared_inputs, model_architecture, meta_library)

Decode the genome and list active ADF calls in execution order. Inactive genome
material is ignored here because flattening only needs calls that affect the
phenotype; inactive material is preserved later by the genome-widening copy.

Example: a genome whose active path calls `adf_3` once returns that decoded call operation.
"""
function active_adf_calls(
        genome::UTGenome,
        shared_inputs::SharedInput,
        model_architecture::modelArchitecture,
        meta_library::MetaLibrary,
    )::Vector{Operation}
    decoded = decode_with_output_nodes(genome, meta_library, model_architecture, shared_inputs)
    calls = Operation[]
    seen = Set{String}()
    for program in decoded
        for operation in program
            slot = adf_slot_from_call(operation)
            isnothing(slot) && continue
            adf_is_empty(slot) && continue
            operation.calling_node.id in seen && continue
            push!(calls, operation)
            push!(seen, operation.calling_node.id)
        end
    end
    sort!(calls; by = operation -> operation.calling_node.x_position)
    return calls
end

"""
    copied_node_positions!(node, new_x, new_real_x, new_y)

Move a copied node to a new genome slot and update every evolvable element so
future mutations still see coherent node coordinates.

Example: moving a node to `(10, 1)` renames it to `nd (10,1)` and updates its inner element positions.
"""
function copied_node_positions!(node::AbstractEvolvableNode, new_x::Int, new_real_x::Int, new_y::Int)
    node.x_position = new_x
    node.x_real_position = new_real_x
    node.y_position = new_y
    node.id = node isa OutputNode ? "out ($new_x,$new_y)" : "nd ($new_x,$new_y)"
    for element in node
        set_node_position(element, (new_x, new_real_x, new_y))
    end
    return node
end

"""
    shift_connection_value(value, cut_x, width)

Move one x-position reference to the right when it points into or after an
inserted ADF body.

Example: `shift_connection_value(10, 8, 3)` returns `13`.
"""
shift_connection_value(value::Int, cut_x::Int, width::Int)::Int =
    value >= cut_x ? value + width : value

"""
    shift_node_connections!(node, cut_x, width)

Shift references that point to nodes at or after the inserted ADF body. The
same width is inserted in every chromosome, so the x-coordinate shift is valid
independently of the referenced type row.

Example: after inserting width 3 at x=8, a connection to x=10 becomes x=13.
"""
function shift_node_connections!(node::AbstractEvolvableNode, cut_x::Int, width::Int)
    for connexion in extract_connexions_from_node(node)
        connexion.value = shift_connection_value(connexion.value, cut_x, width)
    end
    return node
end

"""
    shifted_original_node(node, target_real_index, cut_x, width, chromosome_index)

Copy one original genome node into the widened genome and shift both its own
position and any connections that cross the insertion point.

Example: an old node at x=9 copied across width 2 at x=7 becomes a node at x=11.
"""
function shifted_original_node(
        node::AbstractGenomeNode,
        target_real_index::Int,
        cut_x::Int,
        width::Int,
        chromosome_index::Int,
    )::AbstractGenomeNode
    copied = deepcopy(node)
    copied_node_positions!(
        copied,
        shift_connection_value(node.x_position, cut_x, width),
        target_real_index,
        chromosome_index,
    )
    shift_node_connections!(copied, cut_x, width)
    return copied
end

"""
    shifted_output_node(node, cut_x, width)

Copy an output node into the widened genome and shift its source reference so
it still points at the same semantic computation.

Example: an output pointing to old x=9 points to x=11 after width 2 is inserted before it.
"""
function shifted_output_node(node::AbstractOutputNode, cut_x::Int, width::Int)::AbstractOutputNode
    copied = deepcopy(node)
    copied_node_positions!(copied, node.x_position + width, node.x_real_position + width, node.y_position)
    shift_node_connections!(copied, cut_x, width)
    return copied
end

"""
    previous_same_type_position(x_position, chromosome_index, shared_inputs)

Find a valid same-type value that can feed a placeholder node in a new gap.
This keeps inactive gap nodes type-correct so later EA mutations can safely
connect to them.

Example: for a Float64 chromosome at x=12, this returns an earlier Float64 input or node position.
"""
function previous_same_type_position(
        x_position::Int,
        chromosome_index::Int,
        shared_inputs::SharedInput,
    )::Int
    for input in shared_inputs
        input.y_position == chromosome_index && input.x_position < x_position && return input.x_position
    end
    @assert x_position > length(shared_inputs) + 1 "Cannot create a default node before any same-type value exists"
    return x_position - 1
end

"""
    default_gap_node(...)

Create a type-correct placeholder for one newly inserted slot. These nodes are
overwritten by copied ADF body nodes when they are active, and remain safe
identity-like material when the corresponding slot is unused.

Example: an unused inserted Float64 slot becomes a valid node that forwards an earlier Float64 value.
"""
function default_gap_node(
        arity::Int,
        x_position::Int,
        x_real_position::Int,
        chromosome_index::Int,
        max_fn_index::Int,
        max_type_index::Int,
        shared_inputs::SharedInput,
    )::CGPNode
    node = make_evolvable_node(
        arity,
        1,
        max_fn_index,
        1,
        x_position - 1,
        1,
        max_type_index,
        x_position,
        x_real_position,
        chromosome_index,
    )
    identity_input = previous_same_type_position(x_position, chromosome_index, shared_inputs)
    extract_function_from_node(node).value = 1
    for connexion in extract_connexions_from_node(node)
        connexion.value = identity_input
    end
    for connexion_type in extract_connexions_types_from_node(node)
        connexion_type.value = chromosome_index
    end
    return node
end

"""
    inferred_arity(genome)

Reuse the chromosome arity from existing nodes. Empty chromosomes fall back to
one input so placeholder nodes remain constructible.

Example: a chromosome whose nodes have three connection fields returns `3`.
"""
function inferred_arity(genome::SingleGenome)::Int
    isempty(genome.chromosome) && return 1
    return length(extract_connexions_from_node(genome.chromosome[1]))
end

"""
    genome_with_inserted_time_slice(genome, shared_inputs, meta_library, cut_x, width)

Return a widened copy of `genome` with `width` new node positions inserted at
`cut_x` in every chromosome. Original active and inactive material is preserved
by shifting old nodes and their references to the right.

Example: inserting width 2 at x=5 moves old node x=5 to x=7 and creates slots x=5 and x=6.
"""
function genome_with_inserted_time_slice(
        genome::UTGenome,
        shared_inputs::SharedInput,
        meta_library::MetaLibrary,
        cut_x::Int,
        width::Int,
    )::UTGenome
    width == 0 && return deepcopy(genome)
    new_genomes = AbstractGenome[]
    max_type_index = length(genome.genomes)

    for chromosome_index in eachindex(genome.genomes)
        old_chromosome = genome.genomes[chromosome_index]
        arity = inferred_arity(old_chromosome)
        new_nodes = AbstractGenomeNode[]
        max_fn_index = length(meta_library[chromosome_index])

        for old_node in old_chromosome
            # Nodes before the insertion keep their real index; nodes at/after
            # the ADF call move right to make acyclic space for the copied body.
            target_real_index = old_node.x_position < cut_x ?
                old_node.x_real_position :
                old_node.x_real_position + width
            push!(
                new_nodes,
                shifted_original_node(old_node, target_real_index, cut_x, width, chromosome_index),
            )
        end

        for gap_offset in 0:(width - 1)
            # Every chromosome gets a valid node in every inserted x-position
            # because future mutations can reference any type row at that time.
            gap_x = cut_x + gap_offset
            gap_real_index = gap_x - old_chromosome.starting_point
            push!(
                new_nodes,
                default_gap_node(
                    arity,
                    gap_x,
                    gap_real_index,
                    chromosome_index,
                    max_fn_index,
                    max_type_index,
                    shared_inputs,
                ),
            )
        end

        sort!(new_nodes; by = node -> node.x_real_position)
        push!(new_genomes, SingleGenome(old_chromosome.starting_point, new_nodes))
    end

    new_outputs = AbstractOutputNode[
        shifted_output_node(output_node, cut_x, width) for output_node in genome.output_nodes
    ]
    return UTGenome(new_genomes, new_outputs)
end

"""
Set the function index stored inside one evolvable node.

Example: `set_node_function_index!(node, 4)` makes the node call library function 4.
"""
function set_node_function_index!(node::AbstractEvolvableNode, fn_index::Int)
    extract_function_from_node(node).value = fn_index
    return node
end

"""
    set_node_inputs_from_positions!(node, positions)

Write decoded source positions into the node connection slots. Extra arity
slots keep their existing placeholder values because decode only consumes the
inputs required by the selected function method.

Example: `[(1, 1), (4, 2)]` writes x/type references for the first two node inputs.
"""
function set_node_inputs_from_positions!(node::AbstractEvolvableNode, positions::Vector{Tuple{Int, Int}})
    connexions = extract_connexions_from_node(node)
    connexion_types = extract_connexions_types_from_node(node)
    @assert length(positions) <= length(connexions) "Node cannot store all copied ADF inputs"
    for (index, (x_position, y_position)) in enumerate(positions)
        connexions[index].value = x_position
        connexion_types[index].value = y_position
    end
    return node
end

"""
    operation_input_position(op_input, program, input_mapping, node_mapping)

Translate one ADF-local decoded input into the corresponding caller-genome
position. ADF formal inputs use `input_mapping`; copied internal ADF nodes use
`node_mapping`.

Example: ADF-local input `x1` maps to the caller node that was passed as the first ADF argument.
"""
function operation_input_position(
        op_input::OperationInput,
        program::Program,
        input_mapping::Dict{Int, Tuple{Int, Int}},
        node_mapping::Dict{String, Tuple{Int, Int}},
    )::Tuple{Int, Int}
    source_node = _extract_input_node_from_operationInput(program.program_inputs, op_input) |> unwrap
    return operation_input_position(source_node, input_mapping, node_mapping)
end

operation_input_position(
    source_node::InputNode,
    input_mapping::Dict{Int, Tuple{Int, Int}},
    ::Dict{String, Tuple{Int, Int}},
)::Tuple{Int, Int} = input_mapping[source_node.x_position]

operation_input_position(
    source_node::AbstractGenomeNode,
    ::Dict{Int, Tuple{Int, Int}},
    node_mapping::Dict{String, Tuple{Int, Int}},
)::Tuple{Int, Int} = node_mapping[source_node.id]

"""
    source_fn_index(operation)

Read the raw function-library index from the decoded operation's source node so
the flattened genome calls the same function as the ADF genome.

Example: if an ADF body node calls function index 4, the copied caller node also gets index 4.
"""
function source_fn_index(operation::Operation)::Int
    return extract_function_from_node(operation.calling_node).value
end

"""
    copy_adf_body_node!(target_genome, operation, adf_program, new_x, input_mapping, node_mapping)

Overwrite one inserted placeholder with a copied ADF body operation and record
where that ADF-local node now lives in the caller genome.

Example: copying ADF `tmp1 = add(x, y)` writes an `add` node into the inserted caller slot.
"""
function copy_adf_body_node!(
        target_genome::UTGenome,
        operation::Operation,
        adf_program::Program,
        new_x::Int,
        input_mapping::Dict{Int, Tuple{Int, Int}},
        node_mapping::Dict{String, Tuple{Int, Int}},
    )
    source_node = operation.calling_node
    target_chromosome = target_genome.genomes[source_node.y_position]
    target_real_index = new_x - target_chromosome.starting_point
    target_node = target_chromosome[target_real_index]

    copied_node_positions!(target_node, new_x, target_real_index, source_node.y_position)
    set_node_function_index!(target_node, source_fn_index(operation))
    set_node_inputs_from_positions!(
        target_node,
        Tuple{Int, Int}[
            operation_input_position(op_input, adf_program, input_mapping, node_mapping) for
                op_input in operation.inputs
        ],
    )
    node_mapping[source_node.id] = (target_node.x_position, target_node.y_position)
    return target_node
end

"""
    call_input_mapping(call_operation, call_program)

Map ADF formal input index `1:n` to the real nodes used by the original call
site. This is the step that turns `adf(x, y)` internals into caller references.

Example: `adf_1(tmp4, x2)` maps ADF input 1 to `tmp4` and input 2 to `x2`.
"""
function call_input_mapping(call_operation::Operation, call_program::Program)::Dict{Int, Tuple{Int, Int}}
    mapping = Dict{Int, Tuple{Int, Int}}()
    for (input_index, op_input) in enumerate(call_operation.inputs)
        source_node = _extract_input_node_from_operationInput(call_program.program_inputs, op_input) |> unwrap
        mapping[input_index] = (source_node.x_position, source_node.y_position)
    end
    return mapping
end

"""
Return the decoded output operation for a single-output ADF program.

Example: for `out1 = tmp3`, this returns the output-node operation that points to `tmp3`.
"""
function output_operation(program::Program)::Operation
    @assert program.program[end].calling_node isa OutputNode "ADF program must end with an OutputNode"
    return program.program[end]
end

"""
    rewrite_shifted_call_node!(...)

After the ADF body has been inserted before the original call, rewrite the
shifted call node to compute the ADF output operation. Downstream references
keep pointing at the same call node, so the caller genome does not need another
global rewiring pass.

Example: the old `adf_1(tmp2)` node becomes the node that computes `out1` from the inserted ADF body.
"""
function rewrite_shifted_call_node!(
        target_genome::UTGenome,
        shifted_call_x::Int,
        call_y::Int,
        adf_program::Program,
        input_mapping::Dict{Int, Tuple{Int, Int}},
        node_mapping::Dict{String, Tuple{Int, Int}},
    )
    output_op = output_operation(adf_program)
    target_chromosome = target_genome.genomes[call_y]
    target_node = target_chromosome[shifted_call_x - target_chromosome.starting_point]
    set_node_function_index!(target_node, source_fn_index(output_op))
    set_node_inputs_from_positions!(
        target_node,
        Tuple{Int, Int}[
            operation_input_position(op_input, adf_program, input_mapping, node_mapping) for
                op_input in output_op.inputs
        ],
    )
    return target_node
end

"""
Find the decoded parent program that contains a specific active node id.

Example: searching for `nd (8,1)` returns the decoded output program whose path uses that node.
"""
function find_program_containing_node(programs::IndividualPrograms, node_id::String)::Program
    for program in programs
        for operation in program
            operation.calling_node.id == node_id && return program
        end
    end
    throw(ErrorException("Could not find decoded program containing node $node_id"))
end

"""
    flatten_one_adf_call(...)

Inline one active ADF call into a larger genome. The caller genome is widened,
the ADF active body is copied into the new space, and the original call node is
rewritten as the ADF output operation.

Example: `tmp5 = adf_blur(x)` becomes inserted blur nodes followed by `tmp5 = <adf output op>`.
"""
function flatten_one_adf_call(
        genome::UTGenome,
        shared_inputs::SharedInput,
        model_architecture::modelArchitecture,
        meta_library::MetaLibrary,
        call_operation::Operation,
    )::UTGenome
    slot = adf_slot_from_call(call_operation)
    @assert slot isa ADFSlotFunction "Selected operation is not an ADF call"
    @assert slot.definition isa ActiveADFDefinition "Cannot flatten an empty ADF slot"

    definition = slot.definition
    adf_decoded = decode_with_output_nodes(
        definition.genome,
        definition.meta_library,
        definition.model_architecture,
        definition.shared_inputs,
    )
    @assert length(adf_decoded) == 1 "ADF flattening currently supports single-output ADFs"

    adf_program = adf_decoded[1]
    adf_body = copied_adf_body(adf_program)
    width = length(adf_body)
    cut_x = call_operation.calling_node.x_position
    shifted_call_x = cut_x + width

    widened = genome_with_inserted_time_slice(genome, shared_inputs, meta_library, cut_x, width)
    parent_decoded = decode_with_output_nodes(genome, meta_library, model_architecture, shared_inputs)
    parent_program = find_program_containing_node(parent_decoded, call_operation.calling_node.id)
    input_mapping = call_input_mapping(call_operation, parent_program)
    node_mapping = Dict{String, Tuple{Int, Int}}()

    for (offset, operation) in enumerate(adf_body)
        # ADF operations are copied in decoded order, so internal references
        # always point to already-copied nodes or to formal inputs.
        copy_adf_body_node!(
            widened,
            operation,
            adf_program,
            cut_x + offset - 1,
            input_mapping,
            node_mapping,
        )
    end

    rewrite_shifted_call_node!(
        widened,
        shifted_call_x,
        call_operation.calling_node.y_position,
        adf_program,
        input_mapping,
        node_mapping,
    )
    return widened
end

"""
    flatten_adfs(genome, shared_inputs, model_architecture, meta_library, registry; max_depth)

Repeatedly inline active ADF calls. `max_depth=1` flattens only the first ADF
level; the default keeps going until the decoded genome contains no active ADF
calls.

Example: `flatten_adfs(genome, inputs, ma, ml, registry; max_depth=1)` removes one visible ADF layer.
"""
function flatten_adfs(
        genome::UTGenome,
        shared_inputs::SharedInput,
        model_architecture::modelArchitecture,
        meta_library::MetaLibrary,
        ::ADFRegistry;
        max_depth::Int = typemax(Int),
    )::UTGenome
    @assert max_depth >= 0 "max_depth must be non-negative"
    flattened = deepcopy(genome)
    for _ in 1:max_depth
        calls = active_adf_calls(flattened, shared_inputs, model_architecture, meta_library)
        isempty(calls) && return flattened
        flattened = flatten_one_adf_call(
            flattened,
            shared_inputs,
            model_architecture,
            meta_library,
            calls[1],
        )
    end
    return flattened
end
