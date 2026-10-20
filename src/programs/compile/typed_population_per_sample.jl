# Per-sample engine: runs with images (or any non-bits type).
#
# Samples are evaluated one at a time: every step runs on the current sample and
# stores its value in its slot, then the next sample starts. Only one sample's
# values are alive at a time.
#
# Steps are deliberately not specialised: every call step has the same concrete
# type, `PerSampleCall`, and calls its function dynamically. An image operation
# costs microseconds to seconds, so a dynamic call (~100 ns) does not matter,
# while specialising every (function, argument types) pair compiled several
# engine methods for each new pair, every generation. Here a new pair compiles
# only the library method itself.
#
# Types stay guaranteed: every step was proven by `_prove_step` when the
# evaluator was built, and the only way to write a value is `_store!`, which
# asserts the slot's type.
#
# Sized outputs (images) are written into buffers taken from the task's
# `BufferPool` and passed to the function as `out`, so evaluation allocates no
# output images. A function may also accept working arrays of the size of `out`
# (`float_scratch`, `image_scratch`, see libraries/image/image_buffers.jl); the
# pool's set for that image type is then passed too. Each step stores the keyword
# arguments its function accepts, once, when the evaluator is built.
#
# Call tree:
#   _build_per_sample_evaluator(graph, pool)                  from TypedEvaluator
#   ├── ValueSlot{T}() for every input and step
#   ├── per step: _build_per_sample_step(graph, step, step_index, slots, pool, next_buffer_index)
#   │   ├── _prove_step / _prove_constant                     typed_population.jl
#   │   ├── _output_buffer(fn, step, step_index, pool, next_buffer_index)
#   │   │   ├── _check_out_keyword(fn, step, step_index)
#   │   │   └── _take_buffer!(pool, next_buffer_index, T)    typed_population_buffers.jl
#   │   └── _step_keywords(fn, step, buffer, pool)            out, float_scratch, image_scratch
#   └── _per_sample_output_slots(graph, slots)
#
#   _evaluate_samples!(evaluator::PerSampleEvaluator, samples, outputs, step_values, individual_times)
#   └── per sample:
#       ├── _fill_inputs!(evaluator.input_slots, sample)
#       ├── per step:
#       │   ├── _run_step_timed! → _run_step!(evaluator, step, samples)
#       │   │   └── _store!(step.result, _call_step(step))
#       │   │       └── fn(_input_values(inputs)...; step.keywords...)
#       │   └── _record_step_value!(step_values, step_index, sample_index, value)
#       ├── _record_sample_outputs!(outputs, evaluator, sample_index)
#       └── _record_individual_times!(individual_times, ...)

"""
The value of one input or step for the current sample. Created empty: inputs are
filled before the steps run, and steps run in order, so an empty slot is never read.
"""
mutable struct ValueSlot{T}
    value::T
    ValueSlot{T}() where {T} = new{T}()
end

"""The only way to write a slot: the assertion is the run-time type guarantee."""
function _store!(slot::ValueSlot{T}, value) where {T}
    slot.value = value::T
    return nothing
end

"""A function call. Fields are untyped on purpose: one compiled engine for all steps."""
struct PerSampleCall
    fn::Any
    caster::Any
    fallback::Any
    inputs::Vector{ValueSlot}    # slots of the step's arguments (inputs or earlier steps)
    result::ValueSlot            # this step's slot
    buffer::Any                  # preallocated `out`, or nothing
    keywords::NamedTuple         # what the call passes: out and the working arrays it accepts
end

struct PerSampleConstant
    value::Any
    result::ValueSlot
end

"""
Per-sample evaluator of one graph, for one task. Built by `TypedEvaluator` for
runs with non-bits types.
"""
struct PerSampleEvaluator <: TypedEvaluator
    graph::PopulationSequentialProgram
    input_slots::Vector{ValueSlot}
    steps::Vector{Union{PerSampleCall,PerSampleConstant}}
    output_slots::Vector{Vector{ValueSlot}}   # per output position, the slot of each individual
    output_types::Vector{Type}
    pool::BufferPool
    step_seconds::Vector{Float64}             # per step, seconds on the last sample (with individual_times)
end

# ---------------------------------------------------------------------------
# Building
# ---------------------------------------------------------------------------

function _build_per_sample_evaluator(graph::PopulationSequentialProgram, pool::BufferPool)
    slots = (inputs = ValueSlot[ValueSlot{T}() for T in graph.input_types],
             steps = ValueSlot[ValueSlot{step.return_type}() for step in graph.steps])
    next_buffer_index = Dict{DataType,Int}()
    steps = Union{PerSampleCall,PerSampleConstant}[]
    for (step_index, step) in enumerate(graph.steps)
        push!(steps, _build_per_sample_step(graph, step, step_index, slots, pool, next_buffer_index))
    end
    return PerSampleEvaluator(graph, slots.inputs, steps, _per_sample_output_slots(graph, slots),
        _output_types(graph), pool, zeros(length(steps)))
end

function _build_per_sample_step(graph, step::PopulationSequentialCallStep, step_index, slots, pool, next_buffer_index)
    fn = _prove_step(graph, step, step_index)
    buffer = _output_buffer(fn, step, step_index, pool, next_buffer_index)
    keywords = _step_keywords(fn, step, buffer, pool)
    inputs = ValueSlot[_slot(ref, slots) for ref in step.inputs]
    return PerSampleCall(fn, step.fn.caster, step.fn.fallback, inputs, slots.steps[step_index], buffer, keywords)
end

function _build_per_sample_step(graph, step::PopulationSequentialConstantStep, step_index, slots, pool, next_buffer_index)
    _prove_constant(step, step_index)
    return PerSampleConstant(step.value, slots.steps[step_index])
end

_slot(ref::PopulationSequentialInputRef, slots) = slots.inputs[ref.input_index]
_slot(ref::PopulationSequentialTmpRef, slots) = slots.steps[ref.step_index]

"""
The `out` buffer of a step returning a sized image, or `nothing`. A step with a
caster, or an ADF, is called without `out`: what its function returns is not the
step's output type (the caster converts it) or is computed by a native frame.
"""
function _output_buffer(fn, step::PopulationSequentialCallStep, step_index, pool, next_buffer_index)
    T = step.return_type
    if !_has_static_size(T) || step.fn.caster !== nothing || step.fn.fn isa ADFSlotFunction
        return nothing
    end
    _check_out_keyword(fn, step, step_index)
    return _take_buffer!(pool, next_buffer_index, T)
end

"""Functions returning sized images must accept `out` (see docs/src/library_out_keyword.md)."""
function _check_out_keyword(fn, step::PopulationSequentialCallStep, step_index)
    input_types = Tuple{(ref.type for ref in step.inputs)...}
    if !hasmethod(fn, input_types, (:out,))
        throw(TypedEvaluationError("step $step_index: $(_step_signature(step)) returns the sized image $(step.return_type) but has no `out` keyword"))
    end
    return nothing
end

"""
    _step_keywords(fn, step, buffer, pool) -> NamedTuple

The keyword arguments of the step's calls: none without an `out` buffer;
otherwise `out`, plus `float_scratch` and `image_scratch` (the pool's working
arrays for the output type) when the function accepts them.
"""
function _step_keywords(fn, step::PopulationSequentialCallStep, buffer, pool::BufferPool)
    if buffer === nothing
        return NamedTuple()
    end
    T = step.return_type
    input_types = Tuple{(ref.type for ref in step.inputs)...}
    keywords = (out = buffer,)
    if hasmethod(fn, input_types, (:float_scratch,))
        keywords = merge(keywords, (float_scratch = _float_scratch!(pool, T),))
    end
    if hasmethod(fn, input_types, (:image_scratch,))
        keywords = merge(keywords, (image_scratch = _image_scratch!(pool, T),))
    end
    return keywords
end

"""For each output position, the slot holding every individual's output there."""
function _per_sample_output_slots(graph::PopulationSequentialProgram, slots)
    n_positions = length(_output_types(graph))
    return [ValueSlot[_slot(outputs[position], slots) for outputs in graph.individual_outputs]
            for position in 1:n_positions]
end

# ---------------------------------------------------------------------------
# Evaluating
# ---------------------------------------------------------------------------

function _evaluate_samples!(evaluator::PerSampleEvaluator, samples, outputs, step_values, individual_times)
    for (sample_index, sample) in enumerate(samples)
        _fill_inputs!(evaluator.input_slots, sample)
        for (step_index, step) in enumerate(evaluator.steps)
            _run_step_timed!(evaluator, step, step_index, samples, individual_times)
            _record_step_value!(step_values, step_index, sample_index, step.result.value)
        end
        _record_sample_outputs!(outputs, evaluator, sample_index)
        _record_individual_times!(individual_times, evaluator.graph, evaluator.step_seconds, sample_index)
    end
    return nothing
end

function _fill_inputs!(input_slots::Vector{ValueSlot}, sample::Tuple)
    for (position, slot) in enumerate(input_slots)
        _store!(slot, sample[position])
    end
    return nothing
end

_run_step!(evaluator::PerSampleEvaluator, step::PerSampleCall, samples) = _store!(step.result, _call_step(step))
_run_step!(evaluator::PerSampleEvaluator, step::PerSampleConstant, samples) = _store!(step.result, step.value)

_samples_per_run(evaluator::PerSampleEvaluator) = 1

"""The step's function through its caster, or its fallback if either throws (as `safe_call`)."""
function _call_step(step::PerSampleCall)
    value = try
        _apply_caster(step.caster, step.fn(_input_values(step.inputs)...; step.keywords...))
    catch
        step.fallback()
    end
    return value
end

_input_values(inputs::Vector{ValueSlot}) = Tuple(slot.value for slot in inputs)

# ---------------------------------------------------------------------------
# Recording
# ---------------------------------------------------------------------------

_record_sample_outputs!(::Nothing, evaluator::PerSampleEvaluator, sample_index) = nothing

function _record_sample_outputs!(outputs::Tuple, evaluator::PerSampleEvaluator, sample_index)
    for position in eachindex(evaluator.output_slots)
        _record_output_column!(outputs[position], evaluator.output_slots[position], sample_index)
    end
    return nothing
end

function _record_output_column!(matrix, slots::Vector{ValueSlot}, sample_index)
    for (individual, slot) in enumerate(slots)
        matrix[individual, sample_index] = _owned(slot.value)
    end
    return nothing
end

"""
Outputs leave the evaluator: an image may be a pool buffer that the next sample
overwrites, so non-bits values are copied.
"""
function _owned(value)
    if isbits(value)
        return value
    end
    return deepcopy(value)
end
