# Reference decoder from acd3558:validation/decode_baseline.jl (frozen old implementation).
function baseline_extract_fn_connexions_types_from_node(
        node::AbstractEvolvableNode,
        library::Library,
    )::Tuple{FunctionWrapper, Vector{CGPElement}, Vector{CGPElement}}

    fn_element = extract_function_from_node(node)
    fn = fn_element.value
    fn = library[fn]

    connexions = extract_connexions_from_node(node)
    connexions_types = extract_connexions_types_from_node(node)
    return tuple(fn, connexions, connexions_types)
end

function baseline__validate_connexions(
        connexions::Vector{CGPElement},
        connexions_types::Vector{CGPElement},
    )
    for con in connexions
        @assert con.element_type == CONNEXION
    end
    for con_t in connexions_types
        @assert con_t.element_type == TYPE
    end
    return @assert length(connexions) == length(connexions_types)
end

function baseline__operation_input_from_shared_inputs(
        index_at::Int,
        model_architecture::modelArchitecture,
    )
    input_wrapper = InputPromise(index_at)
    type = model_architecture.inputs_types[index_at]
    op_input = OperationInput(input_wrapper, -1, type)
    return op_input
end

function baseline__operation_input_from_chromosome(
        concerned_chromosome::AbstractGenome,
        index_at::Int,
        model_architecture::modelArchitecture,
    )

    node = concerned_chromosome.chromosome[index_at]  # CGP NODE
    node_type_idx = node.y_position
    type = model_architecture.chromosomes_types[node_type_idx]
    op_input = OperationInput(node, node_type_idx, type)
    return op_input
end

function baseline_inputs_for_node(
        connexions::Vector{CGPElement},
        connexions_types::Vector{CGPElement},
        ut_genome::UTGenome,
        inputs_wrapper::SharedInput,
        model_architecture::modelArchitecture,
    )::Vector{OperationInput}
    baseline__validate_connexions(connexions, connexions_types)
    inputs = OperationInput[]

    for idx in 1:length(connexions)
        connexion_value = get_node_element_value(connexions[idx])
        connexion_type_value = get_node_element_value(connexions_types[idx]) # to filter the utgenome
        concerned_chromosome = ut_genome.genomes[connexion_type_value]
        connexion_is_input_node = false
        from = ""
        if connexion_value <= concerned_chromosome.starting_point
            from *= "ShareInput"
            connexion_is_input_node = true
            index_at = connexion_value # index the inputs
        else
            from *= "Chromosome"
            index_at = connexion_value - concerned_chromosome.starting_point
        end

        @debug "Decode : Conn. value : $connexion_value. Conn. input will be from $from. Index at : $index_at"
        if connexion_is_input_node
            op_input = baseline__operation_input_from_shared_inputs(index_at, model_architecture) # program has the weak ref to shared_inputs
        else
            op_input = baseline__operation_input_from_chromosome(
                concerned_chromosome,
                index_at,
                model_architecture,
            )
        end
        push!(inputs, op_input)
    end
    return inputs
end

function baseline_recursive_decode_node!(
        calling_node::Union{CGPNode, OutputNode},
        meta_library::MetaLibrary,
        type_idx::Int,
        operations_list::Vector{<:AbstractOperation},
        model_architecture::modelArchitecture,
        ut_genome::UTGenome,
        program::Program,
    )

    fn, connexions, connexions_types = baseline_extract_fn_connexions_types_from_node(
        calling_node,
        meta_library.libraries[type_idx],
    )
    inputs = baseline_inputs_for_node(
        connexions,
        connexions_types,
        ut_genome,
        program.program_inputs,
        model_architecture,
    )
    fn_name = fn.name
    arg_types = tuple([op.type for op in inputs]...)
    arg_tuple_type = Tuple{([op.type for op in inputs]...)}

    local m = nothing
    try
        m = which(fn.fn, arg_tuple_type)
    catch err
        declared_input_types = if hasfield(typeof(fn.fn), :input_types)
            try
                getfield(fn.fn, :input_types)
            catch
                nothing
            end
        else
            nothing
        end
        declared_argument_names = if hasfield(typeof(fn.fn), :argument_names)
            try
                getfield(fn.fn, :argument_names)
            catch
                nothing
            end
        else
            nothing
        end
        hasmethod_on_arg_types = try
            Base.hasmethod(fn.fn, arg_tuple_type)
        catch method_err
            "ERROR: " * sprint(showerror, method_err)
        end
        available_methods = try
            sprint(show, methods(fn.fn))
        catch methods_err
            "ERROR: " * sprint(showerror, methods_err)
        end
        @warn "Decode fallback: no matching method for node function" fn_name =
            fn_name node_id = getfield(calling_node, :id) node_y_position =
            getfield(calling_node, :y_position) arg_types = arg_types real_input_types =
            [op.type for op in inputs] declared_argument_names =
            declared_argument_names declared_input_types = declared_input_types hasmethod_on_arg_types =
            hasmethod_on_arg_types error = sprint(showerror, err) available_methods =
            available_methods
        throw(err)
    end

    n_used_inputs = m.nargs - 2 # - the fn - the varargs
    inputs = inputs[1:n_used_inputs]
    push!(operations_list, Operation(fn, calling_node, inputs))

    for operation_input in inputs
        R_next_calling_node =
            _extract_input_node_from_operationInput(program.program_inputs, operation_input)
        next_calling_node = @unwrap_or R_next_calling_node begin
            @show operation_input
            @show program
            throw(ErrorException("Could not get the input node from an operation"))
        end
        next_type_idx = operation_input.type_idx # op_input is the next
        baseline_recursive_decode_node!(
            next_calling_node,
            meta_library,
            next_type_idx,
            operations_list,
            model_architecture,
            ut_genome,
            program,
        )
    end
    return
end

function baseline_recursive_decode_node!(calling_node::InputNode, args...) end

function baseline_recursive_decode_node!(calling_node::ConstantNode, args...) end

function baseline_decode_with_output_node(
        ut_genome::UTGenome,
        output_node::OutputNode,
        meta_library::MetaLibrary,
        model_architecture::modelArchitecture,
        shared_inputs::SharedInput,
    )::Program
    operations = Operation[]
    program = Program(operations, shared_inputs)
    baseline_recursive_decode_node!(
        output_node,
        meta_library,
        output_node.y_position, # its type ==  chromosome index
        operations,
        model_architecture,
        ut_genome,
        program,
    )
    reverse!(program)
    return program

end

function baseline_decode_with_output_nodes(
        ut_genome::UTGenome,
        meta_library::MetaLibrary,
        model_architecture::modelArchitecture,
        shared_inputs::SharedInput,
    )::IndividualPrograms
    output_nodes = ut_genome.output_nodes
    ind_progs = Program[]
    for output_node in output_nodes
        prog = baseline_decode_with_output_node(
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
