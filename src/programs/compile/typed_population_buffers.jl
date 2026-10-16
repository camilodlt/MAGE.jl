# Buffer pools: preallocated output images for the per-sample engine.
#
# A library function that returns a sized image (`SImageND`, whose size is part of
# its type) accepts `out`: it writes its result into `out` instead of allocating a
# new image. A `BufferPool` holds those output images for one evaluating task, for
# the whole run, so that no generation allocates its step outputs again.
#
# Ownership: a pool is used by one task at a time (see `TypedEvaluator`). Pools
# are created once at the start of the run, typically one per thread, and handed
# from one generation's evaluator to the next.
#
# Keys are concrete types: a 224×224 binary image and a 112×112 binary image are
# different types, so they are kept in different lists.
#
# Call tree:
#   BufferPool(run_types)                              start of the run
#   └── _has_static_size(T)                            which types get buffers
#   (_select_engine, in typed_population.jl, reads pool.non_bits_types)
#
#   _take_buffer!(pool, next_buffer_index, T)          per step, when an evaluator is built
#   ├── _buffers_of_type!(pool, T)
#   └── _new_buffer(T)                                 only when the list is too short

"""
    BufferPool(run_types)
    BufferPool(graph::PopulationSequentialProgram)

Output storage for one evaluating task, reused for the whole run.

`run_types` are all the value types a run can produce: its input types and its
chromosome types. Bits types (numbers) need no storage. Non-bits types decide the
engine: a run with any of them is evaluated by the per-sample engine. Sized
non-bits types (images) get a list of preallocated buffers, which grows when a
generation needs more buffers of that type than any generation before.

The second form takes the types of one graph, for one-off evaluations.
"""
struct BufferPool
    non_bits_types::Vector{DataType}     # run types that are not bits types
    buffers::Dict{DataType,Vector{Any}}  # sized type => its buffers, in hand-out order
end

function BufferPool(run_types)
    non_bits_types = DataType[]
    buffers = Dict{DataType,Vector{Any}}()
    for T in unique(run_types)
        if isbitstype(T)
            continue
        end
        push!(non_bits_types, T)
        if _has_static_size(T)
            buffers[T] = Any[]
        end
    end
    return BufferPool(non_bits_types, buffers)
end

BufferPool(graph::PopulationSequentialProgram) = BufferPool(_value_types(graph))

"""
    _has_static_size(T) -> Bool

Whether a value of type `T` can be allocated from its type alone. True for
`SImageND` (see image_utils.jl); false otherwise, e.g. for vectors, whose length
is not part of their type. Values of such types are not pooled: their functions
are called without `out` and allocate as usual.
"""
_has_static_size(::Type) = false

"""
    _new_buffer(T) -> T

An uninitialised value of the sized type `T` (methods in image_utils.jl). Its
contents are garbage: a function given `out` overwrites all of it and never
reads it.
"""
function _new_buffer(T::Type)
    throw(ArgumentError("no buffer can be allocated for $T: its size is not part of its type"))
end

"""
    _take_buffer!(pool, next_buffer_index, T) -> T

The next buffer of type `T` for the evaluator being built.

`next_buffer_index[T]` counts the buffers of type `T` already given to earlier
steps of the same evaluator, so that no two steps share a buffer (two steps of
the same type can both be alive within one sample). The counter belongs to one
evaluator build: every build starts again at the first buffer, so generation
after generation the same images are reused. A list that is too short grows.
"""
function _take_buffer!(pool::BufferPool, next_buffer_index::Dict{DataType,Int}, T::DataType)
    index = get(next_buffer_index, T, 1)
    next_buffer_index[T] = index + 1
    buffers = _buffers_of_type!(pool, T)
    if index > length(buffers)
        push!(buffers, _new_buffer(T))
    end
    return buffers[index]::T
end

"""The buffer list of type `T`; created if the pool was not told about `T` at the start."""
function _buffers_of_type!(pool::BufferPool, T::DataType)
    return get!(pool.buffers, T) do
        Any[]
    end
end
