# Typed evaluation of a population graph.
#
# A population graph (`PopulationSequentialProgram`) merges the steps of every
# individual of a generation. The generic interpreter evaluates it with untyped
# values. A `TypedEvaluator` evaluates it with every value's type proven by the
# compiler, using one of two engines:
#
#   tiled       scalar runs (e.g. symbolic regression). Fully specialised: runs one
#               step over a tile of samples, allocates nothing.
#               typed_population_tiled.jl
#   per_sample  runs with images (or any non-bits type). One sample at a time,
#               steps are not specialised (an image operation dwarfs a dynamic
#               call), sized outputs are written into preallocated buffers.
#               typed_population_per_sample.jl, typed_population_buffers.jl
#
# The engine is chosen from the run's types (the `BufferPool`), not from one
# graph, so a run is evaluated by the same engine in every generation.
#
# Types are guaranteed in two places only:
#   - when an evaluator is built, `_prove_step` checks with inference that every
#     step returns exactly its declared type (through its caster, and its
#     fallback too); otherwise building throws `TypedEvaluationError`;
#   - while evaluating, values are stored in typed storage (typed matrices for
#     the tiled engine, `ValueSlot{T}` for the per-sample engine).
#
# Public API (exported):
#   BufferPool(run_types)                    once per task, at the start of the run
#   TypedEvaluator(graph, pool)              once per task and generation
#   evaluate_population_into!(outputs, graph, samples; evaluator, individual_times, check)
#   evaluate_population_steps_into!(step_values, graph, samples; evaluator)
#   sequential_step_values(program, samples)
#
# An evaluator and its pool are used by one task at a time. With several threads
# (any scheduling: `:static`, `:greedy`, ...), each task takes a pool, builds its evaluator, evaluates
# its chunk of samples and gives the pool back (e.g. through a `Channel`).
#
# Call tree:
#   TypedEvaluator(graph, pool; engine, batch_size)
#   ├── _select_engine(engine, pool)
#   ├── _build_tiled_evaluator(graph, batch_size)            typed_population_tiled.jl
#   │   └── per step: _prove_step / _prove_constant
#   └── _build_per_sample_evaluator(graph, pool)             typed_population_per_sample.jl
#       └── per step: _prove_step / _prove_constant, _take_buffer!
#
#   evaluate_population_into!(outputs, graph, samples; evaluator, individual_times, check)
#   ├── _check_samples(graph, samples)
#   ├── _evaluator_for(evaluator, graph)                     given, or built with a fresh pool
#   ├── _check_output_shapes(outputs, individual_times, evaluator, samples)
#   ├── _evaluate_samples!(evaluator, samples, outputs, nothing, individual_times)   one method per engine
#   │   ├── per step: _run_step_timed!(evaluator, step, step_index, samples, individual_times)
#   │   │             └── _run_step!(evaluator, step, samples)                     engine files
#   │   ├── step values: _record_step_column! (tiled) / _record_step_value! (per-sample)
#   │   ├── outputs:     _record_tile_outputs! (tiled) / _record_sample_outputs! (per-sample)
#   │   └── _record_individual_times!(individual_times, graph, step_seconds, sample_index)
#   └── _assert_matches_generic(outputs, graph, samples)                           with check = true
#
#   evaluate_population_steps_into!(step_values, graph, samples; evaluator)
#   └── _evaluate_samples!(evaluator, samples, nothing, step_values, nothing)

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

"""
    TypedEvaluator(graph, pool = BufferPool(graph); engine = :auto, batch_size = 128)

Evaluator of `graph` with every value type proven. Throws `TypedEvaluationError`
when a step's type cannot be proven.

`engine = :auto` uses the per-sample engine when the pool has non-bits types
(images), the tiled engine otherwise; `:tiled` or `:per_sample` force one.
`batch_size` is the tile size of the tiled engine.

An evaluator and its pool must be used by one task at a time.
"""
abstract type TypedEvaluator end

function TypedEvaluator(graph::PopulationSequentialProgram, pool::BufferPool = BufferPool(graph);
        engine::Symbol = :auto, batch_size::Int = 128)
    _check_graph(graph)
    if _select_engine(engine, pool) === :tiled
        return _build_tiled_evaluator(graph, batch_size)
    end
    return _build_per_sample_evaluator(graph, pool)
end

"""
    evaluate_population_into!(outputs, graph, samples;
                              evaluator = nothing, individual_times = nothing, check = false)

Evaluate every individual of `graph` on every sample.

`outputs` holds one matrix per program output, `outputs[k][individual, sample]`
being the `k`th output of `individual` on `sample`; for single-output programs a
matrix can be passed instead of a one-matrix tuple. Image outputs are copies, so
they remain valid after the evaluation.

`samples` is a vector of input tuples. `evaluator` defaults to a new one with a
fresh pool. `individual_times[individual, sample]`, when given, receives the
time of the steps used by that individual (a step shared by several individuals
is timed once and counted for each). `check = true` also runs the generic
interpreter and throws if any output differs.
"""
function evaluate_population_into!(outputs::Tuple, graph::PopulationSequentialProgram,
        samples::AbstractVector{<:Tuple}; evaluator = nothing, individual_times = nothing, check::Bool = false)
    _check_samples(graph, samples)
    evaluator = _evaluator_for(evaluator, graph)
    _check_output_shapes(outputs, individual_times, evaluator, samples)
    _evaluate_samples!(evaluator, samples, outputs, nothing, individual_times)
    if check
        _assert_matches_generic(outputs, graph, samples)
    end
    return outputs
end

function evaluate_population_into!(outputs::Matrix, graph::PopulationSequentialProgram,
        samples::AbstractVector{<:Tuple}; kwargs...)
    evaluate_population_into!((outputs,), graph, samples; kwargs...)
    return outputs
end

"""
    evaluate_population_steps_into!(step_values, graph, samples; evaluator = nothing)

Write the value of every `Float64` step to `step_values[step, sample]` (NaN for
steps of other types). Used to score intermediate nodes (ISA-CGP).
"""
function evaluate_population_steps_into!(step_values::Matrix{Float64}, graph::PopulationSequentialProgram,
        samples; evaluator = nothing)
    if size(step_values) != (length(graph.steps), length(samples))
        throw(DimensionMismatch("step_values must be steps × samples"))
    end
    _check_samples(graph, samples)
    evaluator = _evaluator_for(evaluator, graph)
    fill!(step_values, NaN)
    _evaluate_samples!(evaluator, samples, nothing, step_values, nothing)
    return step_values
end

"""
    sequential_step_values(program::SequentialProgram, samples) -> (values, original_nodes)

Value of every step of one program on every sample, in the program's own step
order (repeated computations included), with each step's original node.
Non-Float64 steps are NaN.
"""
function sequential_step_values(program::SequentialProgram, samples)
    graph, graph_step_of = _single_program_graph(program)
    step_values = Matrix{Float64}(undef, length(graph.steps), length(samples))
    evaluate_population_steps_into!(step_values, graph, samples)
    original_nodes = [step.original_node for step in program.steps]
    return step_values[graph_step_of, :], original_nodes
end

# ---------------------------------------------------------------------------
# Errors
# ---------------------------------------------------------------------------

"""Thrown when a graph cannot be evaluated with proven types."""
struct TypedEvaluationError <: Exception
    message::String
end

Base.showerror(io::IO, error::TypedEvaluationError) = print(io, "TypedEvaluationError: ", error.message)

# ---------------------------------------------------------------------------
# Engine selection
# ---------------------------------------------------------------------------

"""
    _select_engine(engine, pool) -> :tiled or :per_sample

`:auto` chooses from the run's types, held by the pool, rather than from the
graph: a run with images always uses the per-sample engine, even for a graph
that happens to contain only numbers.
"""
function _select_engine(engine::Symbol, pool::BufferPool)
    if engine === :tiled || engine === :per_sample
        return engine
    end
    if engine !== :auto
        throw(ArgumentError("engine must be :auto, :tiled or :per_sample, got :$engine"))
    end
    if isempty(pool.non_bits_types)
        return :tiled
    end
    return :per_sample
end

# ---------------------------------------------------------------------------
# Proving types (used by both engines while they build their steps)
# ---------------------------------------------------------------------------

"""
    _prove_step(graph, step::PopulationSequentialCallStep, step_index) -> callable

Check that `step` returns exactly `step.return_type` on its declared input types,
and return the object to call (the step's function, or a native frame for an
ADF). Throws `TypedEvaluationError` naming the step otherwise.

Inference is sound: once proven, the step can only return its type or throw, and
a throw is replaced by the fallback, whose type is proven too.
"""
function _prove_step(graph::PopulationSequentialProgram, step::PopulationSequentialCallStep, step_index::Int)
    wrapper = step.fn
    _check_references(graph, step.inputs, step_index)
    if wrapper.cache !== nothing
        _not_proven(step, step_index, "cached functions are not supported")
    end
    input_types = [ref.type for ref in step.inputs]
    returned = _inferred_return_type(wrapper, input_types)
    if returned !== step.return_type
        _not_proven(step, step_index, "inferred to return $returned")
    end
    fallback_returned = Core.Compiler.return_type(wrapper.fallback, Tuple{})
    if fallback_returned !== step.return_type
        _not_proven(step, step_index, "its fallback is inferred to return $fallback_returned")
    end
    if !_satisfies_policy(step.return_type, step.return_type_policy)
        _not_proven(step, step_index, "the return-type policy $(step.return_type_policy) rejects it")
    end
    return _population_native_function(wrapper.fn)
end

"""Check that a constant step holds a value of exactly its declared type."""
function _prove_constant(step::PopulationSequentialConstantStep, step_index::Int)
    if typeof(step.value) !== step.return_type
        throw(TypedEvaluationError("step $step_index: constant of type $(typeof(step.value)), declared $(step.return_type)"))
    end
    return nothing
end

"""
    _inferred_return_type(wrapper, input_types) -> Type

What the step's function returns on `input_types`, through its caster when it has
one. The caster must receive a concrete type, so that the function itself is
type-stable. An ADF slot declares its output type.
"""
function _inferred_return_type(wrapper::FunctionWrapper, input_types)
    if wrapper.fn isa ADFSlotFunction
        return wrapper.fn.output_type
    end
    returned = Core.Compiler.return_type(wrapper.fn, Tuple{input_types...})
    if wrapper.caster === nothing
        return returned
    end
    if !isconcretetype(returned)
        return returned
    end
    return Core.Compiler.return_type(wrapper.caster, Tuple{returned})
end

_satisfies_policy(::Type, ::NoTypeAssertion) = true
_satisfies_policy(T::Type, policy::Type) = T <: policy

"""Each reference must point to an input or an earlier step, with the right type."""
function _check_references(graph::PopulationSequentialProgram, references, step_index::Int)
    for ref in references
        if !_reference_is_valid(graph, ref, step_index)
            throw(TypedEvaluationError("step $step_index: invalid reference $ref"))
        end
    end
    return nothing
end

function _reference_is_valid(graph, ref::PopulationSequentialInputRef, step_index)
    return 1 <= ref.input_index <= length(graph.input_types) &&
           graph.input_types[ref.input_index] === ref.type
end

function _reference_is_valid(graph, ref::PopulationSequentialTmpRef, step_index)
    return 1 <= ref.step_index < step_index &&
           graph.steps[ref.step_index].return_type === ref.type
end

function _not_proven(step::PopulationSequentialCallStep, step_index::Int, reason::String)
    throw(TypedEvaluationError("step $step_index: $(_step_signature(step)) declared to return $(step.return_type), but $reason"))
end

"""`name(T1, T2)`: a step's function and input types, for error messages."""
_step_signature(step::PopulationSequentialCallStep) = "$(step.fn.name)($(join([ref.type for ref in step.inputs], ", ")))"

# ---------------------------------------------------------------------------
# Graph checks
# ---------------------------------------------------------------------------

"""Every input and step type of `graph`, each once."""
function _value_types(graph::PopulationSequentialProgram)
    return unique(Type[graph.input_types; [step.return_type for step in graph.steps]])
end

"""
The graph must have inputs, concrete value types, and the same number and types
of outputs for every individual (one output matrix per output position).
"""
function _check_graph(graph::PopulationSequentialProgram)
    if !graph.has_input_layout
        throw(ArgumentError("empty population graph"))
    end
    for T in _value_types(graph)
        if !isconcretetype(T)
            throw(TypedEvaluationError("the graph has the abstract value type $T"))
        end
    end
    _output_types(graph)
    for (individual, refs) in enumerate(graph.individual_outputs)
        _check_references(graph, refs, length(graph.steps) + 1)
    end
    return nothing
end

"""The type of each output position, which must be the same for every individual."""
function _output_types(graph::PopulationSequentialProgram)
    if isempty(graph.individual_outputs)
        return Type[]
    end
    types = Type[ref.type for ref in first(graph.individual_outputs)]
    for (individual, refs) in enumerate(graph.individual_outputs)
        if Type[ref.type for ref in refs] != types
            throw(TypedEvaluationError("individual $individual has outputs $([ref.type for ref in refs]), others have $types"))
        end
    end
    return types
end

"""
One matrix per output position, each individuals × samples, able to hold that
position's type. Uses the output types stored by the evaluator (no allocation).
"""
function _check_output_shapes(outputs::Tuple, individual_times, evaluator::TypedEvaluator, samples)
    output_types = evaluator.output_types
    if length(outputs) != length(output_types)
        throw(DimensionMismatch("$(length(outputs)) output matrices for $(length(output_types)) program outputs"))
    end
    expected_size = (length(evaluator.graph), length(samples))
    for (position, matrix) in enumerate(outputs)
        if size(matrix) != expected_size
            throw(DimensionMismatch("output $position must be individuals × samples = $expected_size"))
        end
        if !(output_types[position] <: eltype(matrix))
            throw(ArgumentError("output $position holds $(eltype(matrix)), the program returns $(output_types[position])"))
        end
    end
    if individual_times !== nothing && size(individual_times) != expected_size
        throw(DimensionMismatch("individual_times must be individuals × samples = $expected_size"))
    end
    return nothing
end

"""Every sample must hold exactly the graph's input types."""
function _check_samples(graph::PopulationSequentialProgram, samples)
    for (sample_index, sample) in enumerate(samples)
        if !_has_types(sample, graph.input_types)
            throw(ArgumentError("sample $sample_index has types $(map(typeof, sample)), the graph expects $(Tuple(graph.input_types))"))
        end
    end
    return nothing
end

function _has_types(sample::Tuple, types::Vector{Type})
    if length(sample) != length(types)
        return false
    end
    for position in eachindex(types)
        if typeof(sample[position]) !== types[position]
            return false
        end
    end
    return true
end

"""The given evaluator (which must have been built for `graph`), or a new one."""
_evaluator_for(::Nothing, graph) = TypedEvaluator(graph)

function _evaluator_for(evaluator::TypedEvaluator, graph)
    if evaluator.graph !== graph || length(evaluator.steps) != length(graph.steps)
        throw(ArgumentError("the evaluator was built for another graph"))
    end
    return evaluator
end

# ---------------------------------------------------------------------------
# Running and recording (shared by both engines)
# ---------------------------------------------------------------------------

"""The raw result through the step's caster, when it has one."""
_apply_caster(::Nothing, value) = value
_apply_caster(caster, value) = caster(value)

"""Run one step; with `individual_times`, also store its time per sample."""
_run_step_timed!(evaluator, step, step_index, samples, ::Nothing) = _run_step!(evaluator, step, samples)

function _run_step_timed!(evaluator, step, step_index, samples, ::Matrix{Float64})
    seconds = @elapsed _run_step!(evaluator, step, samples)
    evaluator.step_seconds[step_index] = seconds / _samples_per_run(evaluator)
    return nothing
end

"""Each individual's time on one sample: the sum of the times of its steps."""
_record_individual_times!(::Nothing, graph, step_seconds, sample_index) = nothing

function _record_individual_times!(individual_times::Matrix{Float64}, graph, step_seconds, sample_index)
    for (individual, step_ids) in enumerate(graph.individual_step_ids)
        individual_times[individual, sample_index] = sum((step_seconds[id] for id in step_ids); init = 0.0)
    end
    return nothing
end

"""A step value goes to `step_values` only when requested and only for Float64 steps."""
_record_step_value!(::Nothing, step_index, sample_index, value) = nothing
_record_step_value!(::Matrix{Float64}, step_index, sample_index, value) = nothing

function _record_step_value!(step_values::Matrix{Float64}, step_index, sample_index, value::Float64)
    step_values[step_index, sample_index] = value
    return nothing
end

# ---------------------------------------------------------------------------
# check = true: comparison with the generic interpreter
# ---------------------------------------------------------------------------

function _assert_matches_generic(outputs::Tuple, graph::PopulationSequentialProgram, samples)
    workspace = PopulationSequentialWorkspace(graph)
    for (sample_index, sample) in enumerate(samples)
        expected = evaluate_population_sequential_program(graph, sample...; workspace = workspace)
        for individual in eachindex(expected), position in eachindex(outputs)
            typed_value = outputs[position][individual, sample_index]
            if !_identical(typed_value, expected[individual][position])
                throw(AssertionError("typed and generic evaluation differ: individual $individual, output $position, sample $sample_index"))
            end
        end
    end
    return nothing
end

"""Exact equality: `===` for numbers (NaN and signed zeros included); pixelwise for images (image_utils.jl)."""
_identical(a, b) = a === b

# ---------------------------------------------------------------------------
# sequential_step_values helper
# ---------------------------------------------------------------------------

"""
A graph holding one program, merging its repeated computations, and for each of
the program's steps the graph step that computes it.
"""
function _single_program_graph(program::SequentialProgram)
    graph = PopulationSequentialProgram()
    _assert_population_input_layout!(graph, program)
    graph_step_of_program_step = Dict{Int,Int}()
    graph_step_of = Int[]
    for (program_step_index, step) in enumerate(program.steps)
        refs = AbstractPopulationSequentialRef[]
        if step isa SequentialCallStep
            refs = AbstractPopulationSequentialRef[_population_ref(ref, graph_step_of_program_step) for ref in step.inputs]
        end
        key = _population_step_key(step, refs)
        graph_step = get(graph.structural_key_to_step, key, 0)
        if graph_step == 0
            push!(graph.steps, _population_step(step, refs))
            graph_step = length(graph.steps)
            graph.structural_key_to_step[key] = graph_step
        end
        graph_step_of_program_step[program_step_index] = graph_step
        push!(graph_step_of, graph_step)
    end
    return graph, graph_step_of
end
