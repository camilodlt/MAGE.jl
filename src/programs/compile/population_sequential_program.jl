############################
# Population Sequential IR
############################

"""
    AbstractPopulationSequentialRef

Reference used by a population-wide sequential graph. Unlike the local
`SequentialTmpRef`, a temporary reference identifies one computation shared by
any number of individuals.
"""
abstract type AbstractPopulationSequentialRef end

"""Reference to one common function argument."""
struct PopulationSequentialInputRef <: AbstractPopulationSequentialRef
    input_index::Int
    type::Type
end

"""Reference to one already-emitted population-wide graph step."""
struct PopulationSequentialTmpRef <: AbstractPopulationSequentialRef
    step_index::Int
    type::Type
end

############################
# Population Steps
############################

"""One executable step in the graph shared by all inserted programs."""
abstract type AbstractPopulationSequentialStep end

"""Population-wide equivalent of `SequentialCallStep`."""
struct PopulationSequentialCallStep <: AbstractPopulationSequentialStep
    fn::FunctionWrapper
    inputs::Vector{AbstractPopulationSequentialRef}
    return_type::Type
    return_type_policy::SequentialReturnTypePolicy
end

"""Population-wide constant assignment."""
struct PopulationSequentialConstantStep <: AbstractPopulationSequentialStep
    value::Any
    return_type::Type
end

############################
# Structural Keys
############################

"""Dictionary key used to reuse an existing population-wide step."""
abstract type AbstractPopulationSequentialKey end

"""
The wrapper object is part of the key. Programs compiled from one `MetaLibrary`
therefore share identical primitives, while independently rebuilt wrappers are
conservatively kept separate even when their names happen to match.
"""
struct PopulationSequentialCallKey <: AbstractPopulationSequentialKey
    fn::FunctionWrapper
    inputs::Tuple
    return_type::Type
    return_type_policy::SequentialReturnTypePolicy
end

"""Key for a constant step, including both its type and canonical value."""
struct PopulationSequentialConstantKey <: AbstractPopulationSequentialKey
    value_key::Any
    return_type::Type
end

############################
# Public Containers
############################

"""
    PopulationSequentialProgram()

Incrementally-built DAG that shares identical computations across one or more
`SequentialProgram`s. Insert programs with `push!`.

A call step is shared only when its exact `FunctionWrapper`, translated inputs,
return type, and return-type policy match an existing step. Equal function names
from separately rebuilt libraries are deliberately not considered identical.

`individual_outputs[i]` identifies the shared values that form program `i`'s
output tuple. `individual_step_ids[i]` identifies the shared steps used by
program `i`; it is used only to sum logical per-program runtimes.

`evaluate_population_sequential_program(population, args...)` returns a vector
in insertion order. Its `i`th value is the same output tuple as evaluating the
`i`th inserted `SequentialProgram` with `args...`.
"""
mutable struct PopulationSequentialProgram <: Function
    steps::Vector{AbstractPopulationSequentialStep}
    individual_outputs::Vector{Vector{AbstractPopulationSequentialRef}}
    individual_step_ids::Vector{Vector{Int}}
    input_types::Vector{Type}
    structural_key_to_step::Dict{AbstractPopulationSequentialKey, Int}
    has_input_layout::Bool
end

"""Reusable, thread-local storage for evaluating one sample.

`values` and `step_times` each have one slot per merged step. A workspace must
not be used concurrently by two threads; the batched evaluator creates one
workspace per Julia thread.
"""
mutable struct PopulationSequentialWorkspace
    values::Vector{Any}
    step_times::Vector{Float64}
end

function PopulationSequentialProgram()
    return PopulationSequentialProgram(
        AbstractPopulationSequentialStep[],
        Vector{Vector{AbstractPopulationSequentialRef}}(),
        Vector{Vector{Int}}(),
        Type[],
        Dict{AbstractPopulationSequentialKey, Int}(),
        false,
    )
end

function PopulationSequentialProgram(seq::SequentialProgram)
    population = PopulationSequentialProgram()
    push!(population, seq)
    return population
end


"""Build one merged graph from sequential programs in the given order."""
function PopulationSequentialProgram(sequences::AbstractVector{<:SequentialProgram})
    population = PopulationSequentialProgram()
    for sequence in sequences
        push!(population, sequence)
    end
    return population
end

function PopulationSequentialWorkspace(population::PopulationSequentialProgram)
    n_steps = length(population.steps)
    return PopulationSequentialWorkspace(Vector{Any}(undef, n_steps), zeros(n_steps))
end

Base.length(population::PopulationSequentialProgram) = length(population.individual_outputs)

############################
# Incremental Graph Building
############################

"""Make the first program's input layout the population-wide input contract."""
function _assert_population_input_layout!(
        population::PopulationSequentialProgram,
        seq::SequentialProgram,
    )::Nothing
    if !population.has_input_layout
        population.input_types = copy(seq.input_types)
        population.has_input_layout = true
        return nothing
    end

    @assert population.input_types == seq.input_types "All sequential programs in one population must have identical input types"
    return nothing
end

"""Translate one local ref after its local temporary producers are resolved."""
function _population_ref(
        local_ref::SequentialProgramInputRef,
        ::Dict{Int, Int},
    )::PopulationSequentialInputRef
    return PopulationSequentialInputRef(local_ref.input_index, local_ref.type)
end

function _population_ref(
        local_ref::SequentialTmpRef,
        local_step_to_global::Dict{Int, Int},
    )::PopulationSequentialTmpRef
    global_step_index = get(local_step_to_global, local_ref.tmp_index, 0)
    @assert global_step_index > 0 "Sequential tmp $(local_ref.tmp_name) was used before its producing step was translated"
    return PopulationSequentialTmpRef(global_step_index, local_ref.type)
end

"""Mutable constants use identity; immutable constants use their actual value."""
function _constant_value_key(value)
    return ismutabletype(typeof(value)) ? objectid(value) : value
end

"""Build a key only after every local input was converted to a global ref."""
function _population_step_key(
        step::SequentialCallStep,
        translated_inputs::Vector{AbstractPopulationSequentialRef},
    )::PopulationSequentialCallKey
    return PopulationSequentialCallKey(
        step.fn,
        Tuple(translated_inputs),
        step.return_type,
        step.return_type_policy,
    )
end

function _population_step_key(
        step::SequentialConstantStep,
        ::Vector{AbstractPopulationSequentialRef},
    )::PopulationSequentialConstantKey
    return PopulationSequentialConstantKey(_constant_value_key(step.value), step.return_type)
end

"""Copy one local step into the population IR after it proved to be new."""
function _population_step(
        step::SequentialCallStep,
        translated_inputs::Vector{AbstractPopulationSequentialRef},
    )::PopulationSequentialCallStep
    return PopulationSequentialCallStep(
        step.fn,
        translated_inputs,
        step.return_type,
        step.return_type_policy,
    )
end

function _population_step(
        step::SequentialConstantStep,
        ::Vector{AbstractPopulationSequentialRef},
    )::PopulationSequentialConstantStep
    return PopulationSequentialConstantStep(
        step.value,
        step.return_type,
    )
end

"""
    push!(population, seq)

Insert one sequential program in topological order. Each local step is first
translated to global input references, then looked up by its complete
structural key. A hit reuses the existing global step; a miss appends exactly
one new global step. The key includes the exact `FunctionWrapper`, so programs
need to be compiled from the same `MetaLibrary` instance to share primitives.
"""
function Base.push!(
        population::PopulationSequentialProgram,
        seq::SequentialProgram,
    )::PopulationSequentialProgram
    _assert_population_input_layout!(population, seq)

    # Local tmp indices are sequential-step indices; mapped values are global-step indices.
    local_step_to_global = Dict{Int, Int}()

    # This becomes the individual's active graph for logical time accounting.
    individual_step_ids = Int[]

    for (local_step_index, local_step) in enumerate(seq.steps)
    # Phase 1: translate each local step's inputs into population-wide refs.
        translated_inputs = if local_step isa SequentialCallStep
            AbstractPopulationSequentialRef[
                _population_ref(local_input, local_step_to_global) for
                    local_input in local_step.inputs
            ]
        else
            AbstractPopulationSequentialRef[]
        end

        key = _population_step_key(local_step, translated_inputs)
        # Phase 2: reuse an equivalent global step or append one new step.
        global_step_index = get(population.structural_key_to_step, key, 0)

        if global_step_index == 0
            global_step_index = length(population.steps) + 1
            push!(population.steps, _population_step(local_step, translated_inputs))
            population.structural_key_to_step[key] = global_step_index
        end

        local_step_to_global[local_step_index] = global_step_index
        push!(individual_step_ids, global_step_index)
    end

    # Phase 3: translate outputs after all of their producers are known.
    output_refs = AbstractPopulationSequentialRef[
        _population_ref(output.source, local_step_to_global) for output in seq.outputs
    ]

    push!(population.individual_outputs, output_refs)
    push!(population.individual_step_ids, unique(individual_step_ids))
    return population
end

############################
# Population IR Interpreter
############################

"""Read one input argument or one already-evaluated global temporary."""
function _read_population_ref(
        ref::PopulationSequentialInputRef,
        args::Tuple,
        ::Vector{Any},
    )
    return args[ref.input_index]
end

function _read_population_ref(
        ref::PopulationSequentialTmpRef,
        ::Tuple,
        values::Vector{Any},
    )
    return values[ref.step_index]
end

"""Execute one global step with the same safe-call semantics as `SequentialProgram`."""
function _interpret_population_step(
        step::PopulationSequentialConstantStep,
        ::Tuple,
        ::Vector{Any},
    )
    return step.value
end

function _interpret_population_step(
        step::PopulationSequentialCallStep,
        args::Tuple,
        values::Vector{Any},
    )
    input_values = Any[
        _read_population_ref(input, args, values) for input in step.inputs
    ]
    return safe_call(step.fn, input_values...; return_type = step.return_type_policy)
end

"""Recover one output tuple per individual from the completed shared workspace."""
function _population_outputs(
        population::PopulationSequentialProgram,
        args::Tuple,
        values::Vector{Any},
    )
    outputs = Vector{Any}(undef, length(population))
    for individual_index in eachindex(population.individual_outputs)
        output_refs = population.individual_outputs[individual_index]
        outputs[individual_index] = Tuple(
            _read_population_ref(output_ref, args, values) for output_ref in output_refs
        )
    end
    return outputs
end

"""
    evaluate_population_sequential_program(population, args...; workspace=nothing)

Evaluate every merged graph step once for one sample. The returned vector is in
insertion order, and result `i` equals the output tuple of the `i`th inserted
`SequentialProgram` evaluated on `args...`.

Pass a workspace only when the caller guarantees it is not shared by concurrent
evaluations; this avoids allocating temporary-value storage per sample.
"""
function evaluate_population_sequential_program(
        population::PopulationSequentialProgram,
        args...;
        workspace::Union{Nothing, PopulationSequentialWorkspace} = nothing,
    )
    @assert population.has_input_layout "Cannot evaluate an empty PopulationSequentialProgram"
    @assert length(args) == length(population.input_types) "Expected $(length(population.input_types)) inputs, got $(length(args))"

    active_workspace = isnothing(workspace) ? PopulationSequentialWorkspace(population) : workspace
    @assert length(active_workspace.values) == length(population.steps) "Workspace does not match the population graph size"

    argument_tuple = Tuple(args)
    for (step_index, step) in enumerate(population.steps)
        active_workspace.values[step_index] =
            _interpret_population_step(step, argument_tuple, active_workspace.values)
    end
    return _population_outputs(population, argument_tuple, active_workspace.values)
end

"""
    evaluate_population_sequential_program_with_time(population, args...; workspace=nothing)

Each shared step is timed once physically. The function returns the normal
population outputs and one logical runtime per individual, obtained by summing
the timings of the unique shared steps used by that individual.
"""
function evaluate_population_sequential_program_with_time(
        population::PopulationSequentialProgram,
        args...;
        workspace::Union{Nothing, PopulationSequentialWorkspace} = nothing,
    )
    @assert population.has_input_layout "Cannot evaluate an empty PopulationSequentialProgram"
    @assert length(args) == length(population.input_types) "Expected $(length(population.input_types)) inputs, got $(length(args))"

    active_workspace = isnothing(workspace) ? PopulationSequentialWorkspace(population) : workspace
    @assert length(active_workspace.values) == length(population.steps) "Workspace does not match the population graph size"

    argument_tuple = Tuple(args)
    for (step_index, step) in enumerate(population.steps)
        active_workspace.step_times[step_index] = @elapsed begin
            active_workspace.values[step_index] =
                _interpret_population_step(step, argument_tuple, active_workspace.values)
        end
    end

    individual_times = Float64[
        sum(active_workspace.step_times[step_index] for step_index in step_ids) for
            step_ids in population.individual_step_ids
    ]
    return _population_outputs(population, argument_tuple, active_workspace.values), individual_times
end

"""
    evaluate_population_sequential_program_on_samples(population, sample_args; measure_time=false)

Evaluate input tuples in parallel over samples. Every Julia thread owns one
workspace and every sample writes to an independent result slot. With timing,
the second returned value has shape `(n_individuals, n_samples)`.
"""
function evaluate_population_sequential_program_on_samples(
        population::PopulationSequentialProgram,
        sample_args::AbstractVector{<:Tuple};
        measure_time::Bool = false,
    )
    @assert population.has_input_layout "Cannot evaluate an empty PopulationSequentialProgram"

    sample_outputs = Vector{Any}(undef, length(sample_args))
    individual_times = measure_time ? zeros(length(population), length(sample_args)) : nothing

    # Workspaces are thread-local rather than sample-local to avoid races and repeated allocations.
    workspaces = [PopulationSequentialWorkspace(population) for _ in 1:Threads.nthreads()]

    Threads.@threads :static for sample_index in eachindex(sample_args)
        workspace = workspaces[Threads.threadid()]
        args = sample_args[sample_index]

        if measure_time
            outputs, times = evaluate_population_sequential_program_with_time(
                population,
                args...;
                workspace = workspace,
            )
            sample_outputs[sample_index] = outputs
            individual_times[:, sample_index] = times
        else
            sample_outputs[sample_index] = evaluate_population_sequential_program(
                population,
                args...;
                workspace = workspace,
            )
        end
    end
    return measure_time ? (sample_outputs, individual_times) : sample_outputs
end

function (population::PopulationSequentialProgram)(args...)
    return evaluate_population_sequential_program(population, args...)
end
