using Random

"""
    _trace_dependencies(
        program::Program,
        start_node::AbstractEvolvableNode,
        visited_nodes::Set{AbstractNode},
        subgraph_ops::Vector{AbstractOperation},
    )

Recursively traces the dependencies of a `start_node` through the `program`.
It populates `visited_nodes` and `subgraph_ops` with the nodes and operations
that make up the subgraph ending at `start_node`.
"""
function _trace_dependencies(
        program::Program,
        start_node::AbstractEvolvableNode,
        visited_nodes::Set{AbstractNode},
        subgraph_ops::Vector{AbstractOperation},
    )
    # If we have already processed this node, stop.
    if start_node in visited_nodes
        return
    end
    push!(visited_nodes, start_node)

    # Find the operation that produces the start_node
    # In a valid program, a node is the output of exactly one operation.
    op_idx = findfirst(op -> op.calling_node == start_node, program.program)
    if isnothing(op_idx)
        # This can happen if the node is an input that was never used, but we start from a calling_node.
        @warn "Could not find operation for node $(start_node.id) in program. Is it a disconnected node?"
        return
    end
    operation = program[op_idx]
    push!(subgraph_ops, operation)

    # Recursively trace the dependencies of the inputs to this operation
    for op_input in operation.inputs
        # We need the actual node (CGPNode, ConstantNode, or InputNode)
        # The unwrap is safe if the program is valid.
        input_node =
            _extract_input_node_from_operationInput(program.program_inputs, op_input) |>
            unwrap

        # We only recurse on evolvable nodes within the chromosome body.
        # InputNodes and ConstantNodes are the leaves of our dependency trace.
        if input_node isa AbstractEvolvableNode
            _trace_dependencies(program, input_node, visited_nodes, subgraph_ops)
        else
            # Also add leaf nodes (like InputNode) to the visited set
            push!(visited_nodes, input_node)
        end
    end
    return
end

"""
    select_random_subgraph(
        program::Program,
        model_architecture::modelArchitecture,
        max_inputs::Int;
        min_ops = 2,
        rng,
        max_attempts
    )

Selects a random subgraph from a `program` that has at most `max_inputs`.

Returns a tuple containing:
1.  `subgraph_program::Program`: The new, self-contained program for the subgraph.
2.  `input_types::Vector{DataType}`: The inferred types of the subgraph's inputs.
3.  `output_type::DataType`: The inferred type of the subgraph's single output.

If a valid subgraph cannot be found after several attempts, it returns `nothing`.
"""
function select_random_subgraph(
        program::Program,
        model_architecture::modelArchitecture,
        max_inputs::Int;
        rng::AbstractRNG = Random.GLOBAL_RNG,
        min_ops = 2,
        max_attempts = 10,
    )
    # Get all possible end points for a sub-program (any evolvable node in the program)
    possible_end_nodes =
        [op.calling_node for op in program if op.calling_node isa CGPNode]

    if length(possible_end_nodes) < min_ops
        return nothing # Program is too small
    end

    for _ in 1:max_attempts
        # 1. Pick a random end node for our subgraph
        end_node = rand(rng, possible_end_nodes)

        # 2. Trace all its dependencies
        visited_nodes = Set{AbstractNode}()
        subgraph_ops = AbstractOperation[]
        _trace_dependencies(program, end_node, visited_nodes, subgraph_ops)

        if length(subgraph_ops) < min_ops
            continue # Subgraph is too small, try again
        end

        # 3. Identify the inputs of the subgraph
        # These are nodes that are used by the subgraph but whose generating operation is NOT in the subgraph.
        # These become the `InputNode`s of our new modular function.
        subgraph_inputs = Set{AbstractNode}()
        for op in subgraph_ops
            for op_input in op.inputs
                node =
                    _extract_input_node_from_operationInput(
                    program.program_inputs,
                    op_input,
                ) |> unwrap

                # An input to the subgraph is a node that is *used* by an operation
                # but is not *produced* by any operation within the subgraph.
                if !(node in [op.calling_node for op in subgraph_ops])
                    push!(subgraph_inputs, node)
                end
            end
        end

        # 4. Filter out if constraints are not met
        if length(subgraph_inputs) > max_inputs || length(subgraph_inputs) == 0
            continue # Too many inputs, or no inputs, try again
        end

        # 5. Get types and create the new Program
        inputs_list = collect(subgraph_inputs)

        # Infer types from the node's y_position (which chromosome it belongs to)
        # For original InputNodes, we use the architecture definition.
        function get_type_from_node(n::AbstractNode)
            if n isa InputNode
                return model_architecture.inputs_types[n.x_position]
            else # CGPNode, OutputNode, etc.
                return model_architecture.chromosomes_types[n.y_position]
            end
        end

        input_types = get_type_from_node.(inputs_list)
        output_type = get_type_from_node(end_node)

        # The new program needs its own `SharedInput` and correctly mapped `InputPromise`s
        new_program_inputs =
            SharedInput([InputNode(nothing, i, i, 1) for i in 1:length(inputs_list)])

        # Create a mapping from old nodes (that are now inputs) to their new index in the subgraph's input list
        node_to_new_input_idx =
            Dict(zip(inputs_list, 1:length(inputs_list)))

        new_ops = AbstractOperation[]
        for op in subgraph_ops
            new_op_inputs = OperationInput[]
            for op_input in op.inputs
                original_node = _extract_input_node_from_operationInput(program.program_inputs, op_input) |> unwrap
                if original_node in keys(node_to_new_input_idx)
                    # This was an input to the subgraph, create an InputPromise to the new SharedInput
                    new_idx = node_to_new_input_idx[original_node]
                    promise = InputPromise(new_idx)
                    type_idx = -1 # Not relevant for promises
                    type = get_type_from_node(original_node)
                    push!(new_op_inputs, OperationInput(promise, type_idx, type))
                else
                    # This is an internal node, so its OperationInput remains the same but references nodes within the subgraph.
                    push!(new_op_inputs, op_input)
                end
            end
            # Recreate the operation with the potentially modified inputs
            push!(new_ops, Operation(op.fn, op.calling_node, new_op_inputs))
        end

        # The operations need to be in execution order (dependencies first).
        # Our trace gives them in reverse order, so we reverse it back.
        reverse!(new_ops)

        new_program = Program(new_ops, new_program_inputs)
        new_program.is_reversed = true # It's already in execution order

        return new_program, input_types, output_type
    end

    return nothing # Failed to find a suitable subgraph
end
