# Tiled engine: scalar runs (e.g. symbolic regression).
#
# Steps are fully specialised (function, caster, fallback, input locations and
# value type are type parameters), so each step runs as compiled, allocation-free
# code. To pay the dynamic dispatch of the step loop once per tile instead of once
# per sample, every step runs over a tile of up to `batch_size` samples before
# the next step starts.
#
# Storage: one matrix per value type, rows = samples of the tile, columns = the
# steps of that type. A value's location is therefore (group, column), where the
# group is the index of its type. `TileRef{Group,T}` points to an input of the
# sample or to such a location; `Group` and `T` are type parameters so that reads
# are type-stable.
#
# Call tree:
#   _build_tiled_evaluator(graph, batch_size)                   from TypedEvaluator
#   ├── _tile_layout(graph)                                     group and column of every step
#   ├── per step: _build_tiled_step(graph, step, step_index, layout)
#   │   ├── _prove_step / _prove_constant                       typed_population.jl
#   │   └── _tile_ref(ref, layout)
#   ├── _tiled_output_refs(graph, layout)
#   └── _tile_matrices(layout, batch_size)
#
#   _evaluate_samples!(evaluator::TiledEvaluator, samples, outputs, step_values, individual_times)
#   └── per tile:
#       ├── per step: _process_tiled_step!(evaluator, step, step_index, samples, step_values, individual_times)
#       │   ├── _run_step_timed! → _run_step! → _run_on_tile!(step, matrices, samples, tile)
#       │   │                                    └── _call_tiled(step, args)
#       │   └── _record_step_column!(step_values, step, step_index, evaluator)
#       ├── _record_tile_outputs!(outputs, evaluator, samples)
#       └── _record_tile_times!(individual_times, evaluator)

"""Location of a value: an input of the sample (`from_input`), or column `index` of matrix `Group`."""
struct TileRef{Group,T}
    from_input::Bool
    index::Int
end

abstract type AbstractTiledStep end

"""A function call, specialised on everything so that `_run_on_tile!` compiles to direct code."""
struct TiledCall{F,C,B,N,T,Group,Inputs<:NTuple{N,TileRef}} <: AbstractTiledStep
    fn::F
    caster::C
    fallback::B
    inputs::Inputs
    column::Int
end

struct TiledConstant{T,Group} <: AbstractTiledStep
    value::T
    column::Int
end

"""The samples currently processed: `n_samples` samples from `first_sample` on."""
mutable struct Tile
    first_sample::Int
    n_samples::Int
end

"""Where every step's value is stored: the group (matrix) of each type and the (group, column) of each step."""
struct TileLayout
    group_of_type::Dict{Type,Int}
    value_types::Vector{Type}
    step_location::Vector{Tuple{Int,Int}}
    columns_per_group::Vector{Int}
end

"""
Tiled evaluator of one graph, for one task. Built by `TypedEvaluator` for runs
whose types are all bits types.

Declared `mutable` (its fields are never reassigned) so that it always lives on
the heap: the step loop's dynamic calls then pass a pointer to it, instead of
copying an unboxed evaluator into a new box at every call.
"""
mutable struct TiledEvaluator{Matrices,OutputRefs} <: TypedEvaluator
    graph::PopulationSequentialProgram
    steps::Vector{AbstractTiledStep}
    output_refs::OutputRefs          # per output position, the TileRef of each individual
    output_types::Vector{Type}
    matrices::Matrices               # Ref to the tuple of matrices, one per value type
    batch_size::Int
    tile::Tile
    step_seconds::Vector{Float64}    # per step, seconds per sample (with individual_times)
end

# ---------------------------------------------------------------------------
# Building
# ---------------------------------------------------------------------------

function _build_tiled_evaluator(graph::PopulationSequentialProgram, batch_size::Int)
    if batch_size < 1
        throw(ArgumentError("batch_size must be positive"))
    end
    layout = _tile_layout(graph)
    steps = AbstractTiledStep[]
    for (step_index, step) in enumerate(graph.steps)
        push!(steps, _build_tiled_step(graph, step, step_index, layout))
    end
    return TiledEvaluator(graph, steps, _tiled_output_refs(graph, layout), _output_types(graph),
        Ref(_tile_matrices(layout, batch_size)), batch_size, Tile(1, 0), zeros(length(steps)))
end

"""Give each value type a matrix (its group) and each step a column in the matrix of its type."""
function _tile_layout(graph::PopulationSequentialProgram)
    value_types = _value_types(graph)
    group_of_type = Dict{Type,Int}(T => group for (group, T) in enumerate(value_types))
    columns_per_group = zeros(Int, length(value_types))
    step_location = Tuple{Int,Int}[]
    for step in graph.steps
        group = group_of_type[step.return_type]
        columns_per_group[group] += 1
        push!(step_location, (group, columns_per_group[group]))
    end
    return TileLayout(group_of_type, value_types, step_location, columns_per_group)
end

function _build_tiled_step(graph, step::PopulationSequentialCallStep, step_index, layout::TileLayout)
    fn = _prove_step(graph, step, step_index)
    inputs = Tuple(_tile_ref(ref, layout) for ref in step.inputs)
    group, column = layout.step_location[step_index]
    caster = step.fn.caster
    fallback = step.fn.fallback
    return TiledCall{typeof(fn),typeof(caster),typeof(fallback),length(inputs),step.return_type,group,typeof(inputs)}(
        fn, caster, fallback, inputs, column)
end

function _build_tiled_step(graph, step::PopulationSequentialConstantStep, step_index, layout::TileLayout)
    _prove_constant(step, step_index)
    group, column = layout.step_location[step_index]
    return TiledConstant{step.return_type,group}(step.value, column)
end

function _tile_ref(ref::PopulationSequentialInputRef, layout::TileLayout)
    return TileRef{layout.group_of_type[ref.type],ref.type}(true, ref.input_index)
end

function _tile_ref(ref::PopulationSequentialTmpRef, layout::TileLayout)
    group, column = layout.step_location[ref.step_index]
    return TileRef{group,ref.type}(false, column)
end

"""
For each output position, the location of every individual's output there. All
individuals' outputs at one position have the same type, hence the same
`TileRef` type: each vector is concrete and reading it is type-stable.
"""
function _tiled_output_refs(graph::PopulationSequentialProgram, layout::TileLayout)
    n_positions = length(_output_types(graph))
    return Tuple(_output_position_refs(graph, layout, position) for position in 1:n_positions)
end

function _output_position_refs(graph, layout, position)
    # A comprehension takes the type of its elements: all equal here, so concrete.
    return [_tile_ref(outputs[position], layout) for outputs in graph.individual_outputs]
end

function _tile_matrices(layout::TileLayout, batch_size::Int)
    return Tuple(Matrix{T}(undef, batch_size, layout.columns_per_group[group])
                 for (group, T) in enumerate(layout.value_types))
end

# ---------------------------------------------------------------------------
# Evaluating
# ---------------------------------------------------------------------------

function _evaluate_samples!(evaluator::TiledEvaluator, samples, outputs, step_values, individual_times)
    tile = evaluator.tile
    for first_sample in 1:evaluator.batch_size:length(samples)
        tile.first_sample = first_sample
        tile.n_samples = min(evaluator.batch_size, length(samples) - first_sample + 1)
        for (step_index, step) in enumerate(evaluator.steps)
            _process_tiled_step!(evaluator, step, step_index, samples, step_values, individual_times)
        end
        _record_tile_outputs!(outputs, evaluator, samples)
        _record_tile_times!(individual_times, evaluator)
    end
    return nothing
end

# Output-only evaluation needs one dynamic dispatch per step and tile. Do not
# pass step_index through that dispatch: Julia boxes Int arguments outside its
# small-integer cache, allocating once per step per tile even though the timing
# and step-recording methods discard the index. Keep their general path above.
function _evaluate_samples!(evaluator::TiledEvaluator, samples, outputs, ::Nothing, ::Nothing)
    tile = evaluator.tile
    matrices = evaluator.matrices
    steps = evaluator.steps
    batch_size = evaluator.batch_size
    for first_sample in 1:batch_size:length(samples)
        tile.first_sample = first_sample
        tile.n_samples = min(batch_size, length(samples) - first_sample + 1)
        for step in steps
            _run_on_tile!(step, matrices, samples, tile)
        end
        _record_tile_outputs!(outputs, evaluator, samples)
    end
    return nothing
end

"""
Function barrier: in the loop `step` has the abstract type `AbstractTiledStep`;
this call dispatches once per step and tile, and inside it `step` is concrete.
"""
function _process_tiled_step!(evaluator, step, step_index, samples, step_values, individual_times)
    _run_step_timed!(evaluator, step, step_index, samples, individual_times)
    _record_step_column!(step_values, step, step_index, evaluator)
    return nothing
end

_run_step!(evaluator::TiledEvaluator, step, samples) = _run_on_tile!(step, evaluator.matrices, samples, evaluator.tile)

_samples_per_run(evaluator::TiledEvaluator) = evaluator.tile.n_samples

function _run_on_tile!(step::TiledCall{F,C,B,N,T,Group}, matrices, samples, tile::Tile) where {F,C,B,N,T,Group}
    matrix = matrices[][Group]
    # Only storage accesses are unchecked; the primitive retains its own bounds
    # checks and exception/fallback semantics, including when it is inlined.
    for row in 1:tile.n_samples
        sample = @inbounds samples[tile.first_sample + row - 1]
        args = ntuple(position -> (@inbounds _read(step.inputs[position], sample, matrices, row)), Val(N))
        value = _call_tiled(step, args)
        @inbounds matrix[row, step.column] = value
    end
    return nothing
end

function _run_on_tile!(step::TiledConstant{T,Group}, matrices, samples, tile::Tile) where {T,Group}
    matrix = matrices[][Group]
    # References and sample types/shapes were checked before entering the engine.
    @inbounds for row in 1:tile.n_samples
        matrix[row, step.column] = step.value
    end
    return nothing
end

"""The step's function through its caster, or its fallback if either throws (as `safe_call`)."""
@inline function _call_tiled(step::TiledCall{F,C,B,N,T}, args) where {F,C,B,N,T}
    value = try
        _apply_caster(step.caster, step.fn(args...))
    catch
        step.fallback()
    end
    return value::T
end

# Internal storage only: graph references and tile/sample bounds are validated
# before execution. Keep the primitive itself outside this unchecked helper.
@inline function _read(ref::TileRef{Group,T}, sample, matrices, row) where {Group,T}
    if ref.from_input
        return (@inbounds sample[ref.index])::T
    end
    return (@inbounds matrices[][Group][row, ref.index])::T
end

# ---------------------------------------------------------------------------
# Recording
# ---------------------------------------------------------------------------

_record_tile_outputs!(::Nothing, evaluator::TiledEvaluator, samples) = nothing

function _record_tile_outputs!(outputs::Tuple, evaluator::TiledEvaluator, samples)
    # `map` over two tuples is unrolled at compile time: each output matrix is
    # written by a call specialised on its own type.
    map(outputs, evaluator.output_refs) do matrix, refs
        _record_output_matrix!(matrix, refs, evaluator, samples)
    end
    return nothing
end

function _record_output_matrix!(matrix, refs, evaluator::TiledEvaluator, samples)
    # Snapshot the tile and storage once. In particular, load the sample outside
    # the individual loop: eagerly reloading its tuple for every output dominated
    # large populations, even when most references point to temporary values.
    matrices = evaluator.matrices
    first_sample = evaluator.tile.first_sample
    n_samples = evaluator.tile.n_samples
    @inbounds for row in 1:n_samples
        sample_index = first_sample + row - 1
        sample = samples[sample_index]
        for (individual, ref) in enumerate(refs)
            matrix[individual, sample_index] = _read(ref, sample, matrices, row)
        end
    end
    return nothing
end

"""Steps of every type but Float64 are not recorded (their `step_values` rows stay NaN)."""
_record_step_column!(::Nothing, step, step_index, evaluator) = nothing
_record_step_column!(::Matrix{Float64}, step, step_index, evaluator) = nothing

const FloatTiledStep = Union{TiledCall{<:Any,<:Any,<:Any,<:Any,Float64},TiledConstant{Float64}}

function _record_step_column!(step_values::Matrix{Float64}, step::FloatTiledStep, step_index, evaluator::TiledEvaluator)
    tile = evaluator.tile
    @inbounds for row in 1:tile.n_samples
        step_values[step_index, tile.first_sample + row - 1] = _step_value(step, evaluator.matrices, row)
    end
    return nothing
end

_step_value(step::TiledCall{F,C,B,N,T,Group}, matrices, row) where {F,C,B,N,T,Group} = matrices[][Group][row, step.column]
_step_value(step::TiledConstant{T,Group}, matrices, row) where {T,Group} = matrices[][Group][row, step.column]

"""Every sample of the tile gets the same per-sample step times (the tile time divided by its size)."""
_record_tile_times!(::Nothing, evaluator::TiledEvaluator) = nothing

function _record_tile_times!(individual_times::Matrix{Float64}, evaluator::TiledEvaluator)
    tile = evaluator.tile
    for row in 1:tile.n_samples
        _record_individual_times!(individual_times, evaluator.graph, evaluator.step_seconds, tile.first_sample + row - 1)
    end
    return nothing
end
