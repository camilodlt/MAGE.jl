# Buffer pools: preallocated images and working arrays for the per-sample engine.
#
# A library function that returns a sized image (`SImageND`, whose size is part of
# its type) accepts `out`: it writes its result into `out` instead of allocating a
# new image. It may also accept working arrays of the size of `out`:
# `float_scratch` (two Array{Float32}) and `image_scratch` (two images of the same
# type as `out`), see libraries/image/image_buffers.jl. A `BufferPool` holds all of
# them for one evaluating task, for the whole run, so that no generation allocates
# them again:
#   - output buffers: one per step returning a sized image (steps keep their
#     outputs alive until the end of the sample, so they cannot share);
#   - working arrays: one set per image type, shared by every step of the task
#     (a working array is only used during one call, and a task makes one call at
#     a time).
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
#
#   _float_scratch!(pool, T) / _image_scratch!(pool, T) per step accepting them
#   └── _new_float_buffer(T) / _new_buffer(T)          first request for type T only

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
    buffers::Dict{DataType,Vector{Any}}  # sized type => its output buffers, in hand-out order
    float_scratch::Dict{DataType,Any}    # sized type => two Array{Float32} of its size
    image_scratch::Dict{DataType,Any}    # sized type => two images of that type
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
    return BufferPool(non_bits_types, buffers, Dict{DataType,Any}(), Dict{DataType,Any}())
end

BufferPool(graph::PopulationSequentialProgram) = BufferPool(_value_types(graph))

"""
    _has_static_size(T) -> Bool

Whether a value of type `T` can be allocated from its type alone. True for
`SImageND` and size-typed `SkiVector` (whose owned label map has fixed size,
while its value/id vectors grow and are reused); false otherwise, e.g. for vectors, whose length
is not part of their type. Values of such types are not pooled: their functions
are called without `out` and allocate as usual.
"""
_has_static_size(::Type) = false

"""
    _new_float_buffer(T) -> Array{Float32}

An uninitialised Float32 array of the size of the sized type `T` (methods in
image_utils.jl).
"""
function _new_float_buffer(T::Type)
    throw(ArgumentError("no buffer can be allocated for $T: its size is not part of its type"))
end

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

"""
    _float_scratch!(pool, T) -> (Array{Float32}, Array{Float32})

The two Float32 working arrays of the size of `T`, shared by all the steps of the
pool's task. Allocated on the first request for `T`, then kept for the run.
"""
function _float_scratch!(pool::BufferPool, T::DataType)
    return get!(pool.float_scratch, T) do
        (_new_float_buffer(T), _new_float_buffer(T))
    end
end

"""
    _image_scratch!(pool, T) -> (T, T)

The two working images of type `T`, shared by all the steps of the pool's task.
Allocated on the first request for `T`, then kept for the run.
"""
function _image_scratch!(pool::BufferPool, T::DataType)
    return get!(pool.image_scratch, T) do
        (_new_buffer(T), _new_buffer(T))
    end
end
