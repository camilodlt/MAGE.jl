# Temporary arrays for image library functions.
#
# Library functions often need working arrays the size of their image: float
# intermediates, or a second image. Allocating them on every call costs time and
# garbage collection, so they come from one of two places:
#
#   1. the caller's buffers. The per-sample engine of typed evaluation passes, to
#      the functions that accept them, the optional keywords
#        float_scratch = (a, b)   two Array{Float32} of the size of `out`
#        image_scratch = (a, b)   two images of the same type as `out`
#      taken from the evaluating task's BufferPool and kept for the whole run;
#   2. otherwise (generic interpreter, direct calls, or a function needing more
#      than two of a kind): the task's own storage, `scratch(key, T, dims...)`.
#
# `float_buffer` and `image_buffer` choose between the two, so a function reads
# the same either way and returns the same result with or without the keywords.
#
# Every temporary is valid during one call only: the next call (or the next
# request with the same key in the same task) overwrites it. Never return one.
#
# Reading the input:
#   pixel_values!(values, pixels) -> the pixels' values in a plain array (task scratch)
#
# Writing the result:
#   output_pixels(out, src) -> where to write: `out.img`, or a new array like `src.img`
#   output_pixels(out, src, P) -> same, for an output of another pixel type P
#   image_result(out, pixels, size_type) -> what to return: `out`, or the new pixels wrapped
#
# Call tree (from a library function):
#   float_buffer(float_scratch, k, like, key) -> Array{Float32}
#   ├── float_scratch[k]                                       when given
#   └── scratch(key_k, Float32, size(like.img)...)             otherwise
#   image_buffer(image_scratch, k, like, key) -> image of typeof(like)
#   ├── image_scratch[k]                                       when given
#   └── SImageND(scratch(key_k, pixel type, size...), size type) otherwise

"Key under which each task stores its scratch arrays in `task_local_storage()`."
const _SCRATCH_POOL_KEY = :utcgp_image_scratch

"Key of one scratch array: name, element type, and the requested size (`(0,)` for growable vectors)."
const _ScratchSlot = Tuple{Symbol,DataType,Any}

"""
    scratch(key, T, dims...) -> Array{T}

A working array reused across calls by the current task, so hot operators do
not allocate (and zero, and later garbage-collect) large temporaries on every
call.

- Each task has its own arrays, so this is thread-safe. They are freed with the
  task (a `Threads.@threads` loop creates new tasks on every call).
- The key includes the size: requests of two sizes under one name keep two
  arrays, instead of reallocating each time the size alternates.
- The contents are unspecified on return: callers overwrite or `fill!` it.
- The array is overwritten by the next request for the same key in the same
  task: use it only for temporaries that do not outlive the operator, never for
  returned images.
- `scratch(key, T, 0)` is a *growable* vector returned at whatever length it
  currently has; callers `empty!` or `resize!` it.

Example: `labels = scratch(:labels, Int32, 28, 28)` returns the same `28 × 28`
matrix on every call from this task.
"""
function scratch(key::Symbol, ::Type{T}, dims::Vararg{Int,N}) where {T,N}
    arrays = get!(Dict{_ScratchSlot,Any}, task_local_storage(), _SCRATCH_POOL_KEY)::Dict{_ScratchSlot,Any}
    # A growable vector is simply the one requested with length 0: its slot
    # `(key, T, (0,))` never changes, whatever length callers resize it to.
    # (One slot form for all requests keeps this type-stable: no allocation.)
    slot = (key, T, dims)
    buffer = get(arrays, slot, nothing)
    if buffer === nothing
        buffer = Array{T,N}(undef, dims...)
        arrays[slot] = buffer
    end
    return buffer::Array{T,N}
end

"""
    float_buffer(float_scratch, k, like, key) -> Array{Float32}

The `k`th Float32 working array of the size of the image `like`: from the
caller's `float_scratch` when given (and long enough), otherwise from the task's
`scratch` storage under `key`.
"""
float_buffer(::Nothing, k::Int, like::SImageND, key::Symbol) =
    scratch(Symbol(key, :_, k), Float32, size(like.img)...)

function float_buffer(float_scratch::Tuple, k::Int, like::SImageND, key::Symbol)
    if k > length(float_scratch)
        return float_buffer(nothing, k, like, key)
    end
    return float_scratch[k]
end

"""
    image_buffer(image_scratch, k, like, key) -> typeof(like)

The `k`th working image of the type (and so the size and pixel type) of
`like`: from the caller's `image_scratch` when given (and long enough),
otherwise wrapping an array of the task's `scratch` storage under `key`.
"""
function image_buffer(::Nothing, k::Int, like::I, key::Symbol) where {I<:SImageND}
    pixels = scratch(Symbol(key, :_, k), eltype(like.img), size(like.img)...)
    return SImageND(pixels, _get_image_tuple_size(I))::I
end

function image_buffer(image_scratch::Tuple, k::Int, like::I, key::Symbol) where {I<:SImageND}
    if k > length(image_scratch)
        return image_buffer(nothing, k, like, key)
    end
    return image_scratch[k]::I
end

"""
    output_pixels(out, src) -> pixel array

Where an image function writes its result: `out.img` when the caller gave `out`,
otherwise a new array like `src.img` (same pixel type and size).
"""
output_pixels(::Nothing, src::SImageND) = similar(src.img)
output_pixels(out::SImageND, src::SImageND) = out.img

"""
    output_pixels(out, src, P) -> pixel array

As `output_pixels(out, src)`, for an output whose pixel type `P` differs from
the input's (e.g. a mask computed from an intensity image): `out.img`, or a new
array of `P` of `src`'s size.
"""
output_pixels(::Nothing, src::SImageND, ::Type{P}) where {P} = similar(src.img, P)
output_pixels(out::SImageND, src::SImageND, ::Type{P}) where {P} = out.img

"""
    pixel_values!(values, pixels) -> values

Copy the values held by `pixels` (e.g. the `N0f8` inside each
`IntensityPixel{N0f8}`) into the plain array `values` of the same size,
converting to `eltype(values)` (e.g. `Float32`, as `float(img.img)`).

Kernels then read a plain array, which is fast; this is the same data as
`reinterpret(img.img)` (or `float(img.img)`) without allocating each call.

Example: pixels `[IntensityPixel(0.2N0f8) IntensityPixel(1.0N0f8)]` →
values `[0.2N0f8 1.0N0f8]`.
"""
function pixel_values!(values::AbstractArray, pixels::AbstractArray)
    @inbounds for index in eachindex(values, pixels)
        values[index] = pixels[index].pixel
    end
    return values
end

"""
    image_result(out, pixels, size_type) -> image

What an image function returns after writing `pixels` (from `output_pixels`):
`out` when the caller gave it, otherwise `pixels` wrapped into a new image.
"""
image_result(::Nothing, pixels::AbstractArray, size_type::Type{<:Tuple}) = SImageND(pixels, size_type)
image_result(out::SImageND, pixels::AbstractArray, size_type::Type{<:Tuple}) = out
