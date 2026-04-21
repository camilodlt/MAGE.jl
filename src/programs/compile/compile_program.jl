############################
# Sequential Reference Types
############################

abstract type AbstractSequentialRef end

"""
    SequentialProgramInputRef(input_index, name, type, node_key)

Reference to one original MAGE shared input. These references render as `x1`,
`x2`, ... because shared inputs are function arguments, not computed tmp values.
"""
struct SequentialProgramInputRef <: AbstractSequentialRef
    input_index::Int
    name::Symbol
    type::Type
    node_key::Tuple
end

"""
    SequentialTmpRef(tmp_index, tmp_name, type, node_key)

Reference to a previously emitted temporary value. These references render as
`tmp1`, `tmp2`, ... and always point back to the original node that produced
that tmp.
"""
struct SequentialTmpRef <: AbstractSequentialRef
    tmp_index::Int
    tmp_name::Symbol
    type::Type
    node_key::Tuple
end

############################
# Type Assertion Policy
############################

const SequentialReturnTypePolicy = Union{Type, NoTypeAssertion}

############################
# Sequential IR Types
############################

abstract type AbstractSequentialStep end

"""
    SequentialCallStep

One generated operation assignment of the shape
`tmpN = safe_call(fn, args...; return_type=policy)`.
"""
struct SequentialCallStep <: AbstractSequentialStep
    tmp_name::Symbol
    node_key::Tuple
    original_node::AbstractEvolvableNode
    fn::FunctionWrapper
    display_name::Symbol
    inputs::Vector{AbstractSequentialRef}
    return_type::Type
    return_type_policy::SequentialReturnTypePolicy
end

"""
    SequentialConstantStep

One generated constant assignment of the shape `tmpN = literal`.
"""
struct SequentialConstantStep <: AbstractSequentialStep
    tmp_name::Symbol
    node_key::Tuple
    original_node::ConstantNode
    value::Any
    return_type::Type
end

"""
    SequentialOutput

One generated output alias of the shape `outN = source`.
"""
struct SequentialOutput
    output_name::Symbol
    source::AbstractSequentialRef
    original_output_index::Int
    original_output_node::AbstractOutputNode
end

"""
    SequentialBuildState(model_architecture, assert_return_types)

Mutable state used while compiling. It is deliberately explicit so every
compiler decision can be inspected before finalizing a `SequentialProgram`.
"""
mutable struct SequentialBuildState
    model_architecture::modelArchitecture
    assert_return_types::Bool
    node_to_tmp::Dict{Tuple, Symbol}
    steps::Vector{AbstractSequentialStep}
    outputs::Vector{SequentialOutput}
    skipped_duplicates::Vector{Tuple{Tuple, Symbol}}
    operation_order::Vector{Tuple}
    notes::Vector{String}
end

function SequentialBuildState(
        model_architecture::modelArchitecture;
        assert_return_types::Bool = true,
    )
    return SequentialBuildState(
        model_architecture,
        assert_return_types,
        Dict{Tuple, Symbol}(),
        AbstractSequentialStep[],
        SequentialOutput[],
        Vector{Tuple{Tuple, Symbol}}(),
        Tuple[],
        String[],
    )
end

"""
    SequentialProgram

Readable, inspectable representation of a decoded MAGE program. Finalized IR
containers are stored as tuples so source rendering and future execution read a
stable instruction sequence.
"""
struct SequentialProgram <: Function
    compiled::Function
    backend::Symbol
    steps::Vector{AbstractSequentialStep}
    outputs::Vector{SequentialOutput}
    node_to_tmp::Dict{Tuple, Symbol}
    skipped_duplicates::Vector{Tuple{Tuple, Symbol}}
    operation_order::Vector{Tuple}
    notes::Vector{String}
    input_types::Vector{Type}
    output_types::Vector{Type}
end

############################
# Node Identity And Names
############################

"""
    sequential_node_key(node)

Build the identity used for deduplication and lookup. The key combines type,
printed id, x position, and y/type row because `id` alone is human-readable but
not a formal uniqueness contract.
"""
function sequential_node_key(node::AbstractNode)::Tuple
    return (typeof(node), node.id, node.x_position, node.y_position)
end

"""
    sequential_safe_identifier(name)

Sanitize a function name for generated source. The original `FunctionWrapper`
is still stored in `SequentialCallStep.fn`; this only affects display text.
"""
function sequential_safe_identifier(name::Symbol)::Symbol
    text = String(name)
    cleaned_chars = map(collect(text)) do c
        return isletter(c) || isdigit(c) || c == '_' ? c : '_'
    end
    cleaned = String(cleaned_chars)

    if isempty(cleaned) || !(isletter(cleaned[1]) || cleaned[1] == '_')
        cleaned = "fn_" * cleaned
    end

    return Symbol(cleaned)
end

"""
    sequential_node_type(node, model_architecture)

Resolve the declared type of a node using the same convention as decode/evaluate:
shared inputs use `inputs_types`; all other nodes use their chromosome y row.
"""
function sequential_node_type(
        node::AbstractNode,
        model_architecture::modelArchitecture,
    )::Type
    if node isa InputNode
        return model_architecture.inputs_types[node.x_position]
    end

    return model_architecture.chromosomes_types[node.y_position]
end

"""
    sequential_return_type_policy(state, return_type)

Translate the compile-time `safe` choice into the visible `safe_call` policy.
"""
function sequential_return_type_policy(
        state::SequentialBuildState,
        return_type::Type,
    )::SequentialReturnTypePolicy
    return state.assert_return_types ? return_type : NoTypeAssertion()
end

############################
# Reference Building
############################

"""
    sequential_ref_for_node(state, node)

Convert a MAGE node into the reference used by generated sequential code.

For computed nodes, this function does not infer a tmp number from position.
It looks up the tmp name already assigned in `state.node_to_tmp`. This is the
same mechanism that lets output aliases become `outN = tmpM`.
"""
function sequential_ref_for_node(
        state::SequentialBuildState,
        node::InputNode,
    )::SequentialProgramInputRef
    node_key = sequential_node_key(node)
    node_type = sequential_node_type(node, state.model_architecture)

    return SequentialProgramInputRef(
        node.x_position,
        Symbol("x$(node.x_position)"),
        node_type,
        node_key,
    )
end

function sequential_ref_for_node(
        state::SequentialBuildState,
        node::ConstantNode,
    )::SequentialTmpRef
    node_key = sequential_node_key(node)

    if haskey(state.node_to_tmp, node_key)
        # Reusing constants through tmp refs keeps generated code single-assignment and easy to parse back.
        return SequentialTmpRef(
            tmp_index_from_name(state.node_to_tmp[node_key]),
            state.node_to_tmp[node_key],
            sequential_node_type(node, state.model_architecture),
            node_key,
        )
    end

    tmp_name = next_tmp_name(state)
    return_type = sequential_node_type(node, state.model_architecture)
    state.node_to_tmp[node_key] = tmp_name
    push!(state.operation_order, node_key)

    push!(
        state.steps,
        SequentialConstantStep(
            tmp_name,
            node_key,
            node,
            get_node_value(node),
            return_type,
        ),
    )

    return SequentialTmpRef(tmp_index_from_name(tmp_name), tmp_name, return_type, node_key)
end

function sequential_ref_for_node(
        state::SequentialBuildState,
        node::CGPNode,
    )::SequentialTmpRef
    return sequential_ref_for_emitted_node(state, node)
end

function sequential_ref_for_node(
        state::SequentialBuildState,
        node::OutputNode,
    )::SequentialTmpRef
    return sequential_ref_for_emitted_node(state, node)
end

function sequential_ref_for_emitted_node(
        state::SequentialBuildState,
        node::Union{CGPNode, OutputNode},
    )::SequentialTmpRef
    node_key = sequential_node_key(node)
    node_type = sequential_node_type(node, state.model_architecture)

    # Decoded programs are already in execution order; a missing tmp means that invariant was broken.
    @assert haskey(state.node_to_tmp, node_key) "Node $(node.id) was used before its tmp was emitted"

    return SequentialTmpRef(
        tmp_index_from_name(state.node_to_tmp[node_key]),
        state.node_to_tmp[node_key],
        node_type,
        node_key,
    )
end

"""
    sequential_ref_for_operation_input(state, program, op_input)

Resolve an `OperationInput` through the program's `SharedInput`, then map the
actual node to a sequential reference.
"""
function sequential_ref_for_operation_input(
        state::SequentialBuildState,
        program::Program,
        op_input::OperationInput,
    )::AbstractSequentialRef
    node = _extract_input_node_from_operationInput(program.program_inputs, op_input) |>
        unwrap
    return sequential_ref_for_node(state, node)
end

############################
# Compiler Passes
############################

"""
    next_tmp_name(state)

Return the next tmp name. Tmp numbering follows emitted body-step order so
source order and metadata order stay aligned.
"""
function next_tmp_name(state::SequentialBuildState)::Symbol
    return Symbol("tmp$(length(state.steps) + 1)")
end

"""
    tmp_index_from_name(tmp_name)

Recover the numeric tmp slot from compiler-created names. Runtime refs store
this index so the interpreter never has to parse names during execution.
"""
function tmp_index_from_name(tmp_name::Symbol)::Int
    text = String(tmp_name)
    @assert startswith(text, "tmp") "Expected compiler tmp name, got $tmp_name"
    return parse(Int, text[4:end])
end

"""
    append_body_steps!(state, program)

First compiler pass: emit tmp assignments for every decoded operation,
including `OutputNode` operations. Output nodes can call real functions, so the
IR preserves that computation and lets the final output alias point to the
emitted tmp.
"""
function append_body_steps!(
        state::SequentialBuildState,
        program::Program,
    )::Nothing
    for operation in program
        node = operation.calling_node

        node_key = sequential_node_key(node)

        if haskey(state.node_to_tmp, node_key)
            # Multiple output paths can reach the same active node; one tmp should compute it once.
            push!(state.skipped_duplicates, (node_key, state.node_to_tmp[node_key]))
            continue
        end

        # Input resolution may emit constant tmp steps, so the call tmp is assigned after inputs are known.
        input_refs = AbstractSequentialRef[
            sequential_ref_for_operation_input(state, program, op_input) for
                op_input in operation.inputs
        ]
        return_type = sequential_node_type(node, state.model_architecture)
        tmp_name = next_tmp_name(state)
        state.node_to_tmp[node_key] = tmp_name
        push!(state.operation_order, node_key)

        push!(
            state.steps,
            SequentialCallStep(
                tmp_name,
                node_key,
                node,
                operation.fn,
                sequential_safe_identifier(operation.fn.name),
                input_refs,
                return_type,
                sequential_return_type_policy(state, return_type),
            ),
        )
    end

    return nothing
end

"""
    append_output_step!(state, output_index, program)

Second compiler pass: map one decoded output program to an `outN` alias.

A decoded `Program` ends with an `OutputNode` operation. The body pass emits
that operation as a normal tmp assignment because output nodes can call real
functions. This pass only looks up that already-emitted tmp and gives it the
stable public output name.

Running this pass after all body passes preserves the original
`IndividualPrograms` output order while still reusing shared tmp values.
"""
function append_output_step!(
        state::SequentialBuildState,
        output_index::Int,
        program::Program,
    )::Nothing
    @assert length(program) > 0 "Cannot compile an empty Program"

    last_operation = program.program[end]
    @assert last_operation.calling_node isa OutputNode "Expected Program to end with an OutputNode"
    source_ref = sequential_ref_for_node(state, last_operation.calling_node)

    push!(
        state.outputs,
        SequentialOutput(
            Symbol("out$output_index"),
            source_ref,
            output_index,
            last_operation.calling_node,
        ),
    )

    return nothing
end

############################
# Source Rendering
############################

"""
    render_ref(ref)

Render one sequential reference as source text.
"""
render_ref(ref::SequentialProgramInputRef)::String = String(ref.name)
render_ref(ref::SequentialTmpRef)::String = String(ref.tmp_name)

"""
    render_return_type_policy(policy)

Render the visible `return_type` keyword used by generated `safe_call` lines.
"""
render_return_type_policy(policy::Type)::String = string(policy)
render_return_type_policy(::NoTypeAssertion)::String = "NoTypeAssertion()"

"""
    render_step_line(step)

Render one sequential assignment.
"""
function render_step_line(step::SequentialConstantStep)::String
    return "    $(step.tmp_name) = $(repr(step.value))"
end

function render_step_line(step::SequentialCallStep)::String
    args = join(render_ref.(step.inputs), ", ")
    return_type = render_return_type_policy(step.return_type_policy)
    return "    $(step.tmp_name) = safe_call($(step.display_name), $args; return_type=$return_type)"
end

"""
    render_output_line(output)

Render one output alias.
"""
function render_output_line(output::SequentialOutput)::String
    return "    $(output.output_name) = $(render_ref(output.source))"
end

"""
    render_return_line(outputs)

Render the return line. A one-output program still returns a singleton tuple so
the output container shape remains stable across one-output and multi-output
programs.
"""
function render_return_line(outputs)::String
    output_names = join((String(output.output_name) for output in outputs), ", ")

    if length(outputs) == 1
        output_names *= ","
    end

    return "    return ($output_names)"
end

"""
    render_sequential_source(state)

Render the complete Julia-like source.
"""
function render_sequential_source(state::SequentialBuildState)::String
    n_inputs = length(state.model_architecture.inputs_types)
    input_names = join(("x$i" for i in 1:n_inputs), ", ")

    lines = String["function sequential_program($input_names)"]
    append!(lines, render_step_line.(state.steps))
    append!(lines, render_output_line.(state.outputs))
    push!(lines, render_return_line(state.outputs))
    push!(lines, "end")

    return join(lines, "\n")
end

"""
    render_sequential_source(seq)

Render source from the finalized IR. This keeps the public source view tied to
the same steps and outputs that an IR backend executes.
"""
function render_sequential_source(seq::SequentialProgram)::String
    input_names = join(("x$i" for i in eachindex(seq.input_types)), ", ")

    lines = String["function sequential_program($input_names)"]
    append!(lines, render_step_line.(seq.steps))
    append!(lines, render_output_line.(seq.outputs))
    push!(lines, render_return_line(seq.outputs))
    push!(lines, "end")

    return join(lines, "\n")
end

############################
# Finalization
############################

"""
    not_lowered_yet(args...)

Placeholder runtime for checkpoint 1.
"""
function not_lowered_yet(args...)
    throw(ErrorException("SequentialProgram has no lowered compiled backend. Use the `:ir` backend or inspect `sequential_source(seq)`, `steps`, and metadata fields."))
end

############################
# IR Interpreter
############################

"""
    read_sequential_ref(ref, args, tmp_values)

Read one reference from call-local storage. Input refs read function arguments;
tmp refs read the local tmp vector populated by previous steps.
"""
function read_sequential_ref(
        ref::SequentialProgramInputRef,
        args::Tuple,
        ::Vector{Any},
    )
    return args[ref.input_index]
end

function read_sequential_ref(
        ref::SequentialTmpRef,
        ::Tuple,
        tmp_values::Vector{Any},
    )
    return tmp_values[ref.tmp_index]
end

"""
    interpret_step(step, args, tmp_values)

Execute one IR step without mutating the original decoded program nodes.
"""
function interpret_step(
        step::SequentialConstantStep,
        ::Tuple,
        ::Vector{Any},
    )
    return step.value
end

function interpret_step(
        step::SequentialCallStep,
        args::Tuple,
        tmp_values::Vector{Any},
    )
    input_values = Any[
        read_sequential_ref(input, args, tmp_values) for input in step.inputs
    ]
    return safe_call(step.fn, input_values...; return_type = step.return_type_policy)
end

"""
    interpret_sequential_program(seq, args...)

Thread-safe IR interpreter. All intermediate values live in a fresh local
`tmp_values` vector, so evaluating one `SequentialProgram` never writes into the
original `IndividualPrograms` node value slots.
"""
function interpret_sequential_program(seq::SequentialProgram, args...)
    @assert length(args) == length(seq.input_types) "Expected $(length(seq.input_types)) inputs, got $(length(args))"

    tmp_values = Vector{Any}(undef, length(seq.steps))
    for (idx, step) in enumerate(seq.steps)
        tmp_values[idx] = interpret_step(step, args, tmp_values)
    end

    return Tuple(
        read_sequential_ref(output.source, args, tmp_values) for output in seq.outputs
    )
end

"""
    finalize_sequential_program(state)

Render source and return the public result object.
"""
function finalize_sequential_program(state::SequentialBuildState)::SequentialProgram
    input_types = Type[state.model_architecture.inputs_types...]
    output_types = Type[output.source.type for output in state.outputs]

    return SequentialProgram(
        not_lowered_yet,
        :ir,
        copy(state.steps),
        copy(state.outputs),
        copy(state.node_to_tmp),
        copy(state.skipped_duplicates),
        copy(state.operation_order),
        copy(state.notes),
        input_types,
        output_types,
    )
end

############################
# Public Compiler API
############################

"""
    build_trace_only_sequential_program(programs, model_architecture; safe=true)

Shared implementation for public compile methods.

`programs` is interpreted as one decoded `Program` per output. They are compiled
into one `SequentialProgram`, not one compiled function per output. A single
`SequentialBuildState` is intentionally shared across all programs so common
active nodes get one tmp assignment and all outputs can reuse it.
"""
function build_trace_only_sequential_program(
        programs::Vector{Program},
        model_architecture::modelArchitecture;
        safe::Bool = true,
    )::SequentialProgram
    state = SequentialBuildState(model_architecture; assert_return_types = safe)

    # Body first, with one shared state: this is what deduplicates computation across outputs.
    for program in programs
        append_body_steps!(state, program)
    end

    # Outputs second: output aliases can now look up any shared computed node in state.node_to_tmp.
    for (output_index, program) in enumerate(programs)
        append_output_step!(state, output_index, program)
    end

    return finalize_sequential_program(state)
end

"""
    compile_program(program, model_architecture, ml; safe=true)

Compile one decoded `Program` into trace-only sequential form. The `safe`
keyword controls whether generated `safe_call` lines request return-type
assertions.
"""
function compile_program(
        program::Program,
        model_architecture::modelArchitecture,
        ::MetaLibrary;
        safe::Bool = true,
    )::SequentialProgram
    return build_trace_only_sequential_program(Program[program], model_architecture; safe = safe)
end

"""
    compile_program(individual_programs, model_architecture, ml; safe=true)

Compile all outputs of one decoded `IndividualPrograms` object into one
trace-only sequential program.

This is the multi-output path. If an individual has N output nodes, decode gives
N `Program`s, but this method compiles them into a single source function that
returns `(out1, out2, ..., outN)`. Shared computation is emitted once.
"""
function compile_program(
        individual_programs::IndividualPrograms,
        model_architecture::modelArchitecture,
        ml::MetaLibrary;
        safe::Bool = true,
    )::SequentialProgram
    programs = Program[program for program in individual_programs]
    return compile_program(programs, model_architecture, ml; safe = safe)
end

"""
    compile_program(programs, model_architecture, ml; safe=true)

Compile an explicit vector of decoded programs into one trace-only sequential
program.
"""
function compile_program(
        programs::Vector{Program},
        model_architecture::modelArchitecture,
        ::MetaLibrary;
        safe::Bool = true,
    )::SequentialProgram
    return build_trace_only_sequential_program(programs, model_architecture; safe = safe)
end

"""
    sequential_source(seq)

Return the generated source text represented by a `SequentialProgram`.
"""
sequential_source(seq::SequentialProgram)::String = render_sequential_source(seq)

function Base.show(io::IO, seq::SequentialProgram)
    return print(io, sequential_source(seq))
end

function (seq::SequentialProgram)(args...)
    if seq.backend == :ir
        return interpret_sequential_program(seq, args...)
    end

    return seq.compiled(args...)
end
