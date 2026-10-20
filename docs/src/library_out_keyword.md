# Image library output buffers

Image-returning library operators accept an optional keyword `out=nothing`.
Scalar operators keep their existing API. Keywords leave positional dispatch
and the decoder's `which(fn, argtypes).nargs` calculation unchanged.

* With `out === nothing`, retain the original allocating behaviour and result.
* A supplied `out` has the **same concrete type** as the ordinary result.
  Overwrite the complete result, return that exact object (`result === out`),
  and preserve the ordinary return type and inference.
* Never read previous output contents or rely on zero-filled storage. Tests
  exercise both zero-filled and one-filled output buffers.
* Every early return must obey the contract, including identity, empty-image,
  and fallback paths. Copy an input into `out` instead of returning the input.
* Outputs owned by an evaluator are distinct from its inputs. Library authors
  need not support overlapping input/output storage unless documented otherwise.

## Working arrays

An image-returning function may also accept, as optional keywords, working
arrays of the size of `out`, provided by the per-sample evaluator from the
task's `BufferPool` (kept for the whole run):

* `float_scratch = (a, b)`: two `Array{Float32}` of the image's size;
* `image_scratch = (a, b)`: two images of the same concrete type as `out`.

Get them with `float_buffer(float_scratch, k, like_image, :key)` and
`image_buffer(image_scratch, k, like_image, :key)`: these return the caller's
`k`th array when given, and otherwise (generic interpreter, direct calls, or
`k > 2`) an array of the task's `scratch` storage, so the function behaves and
returns the same either way. Working arrays are valid during the call only:
overwrite them, never return them. Functions returning numbers do not get these
keywords; they use `scratch(key, T, dims...)` sized from their input images.

Write results with `output_pixels(out, src)` (where to write) and
`image_result(out, pixels, size_type)` (what to return).

## Example

A direct elementwise implementation looks like:

```julia
function invert(image::T; out=nothing) where {T<:SImageND}
    result = out === nothing ? deepcopy(image) : out
    result.img .= one.(image.img) .- image.img
    return result::T
end
```

For existing complex kernels, the internal `@image_out` adapter adds the keyword
and copies the original result into the supplied image. It preserves original
early returns by rewriting them in the original function scope, avoiding captured
mutable arguments that would degrade inference.
Such methods are marked `# out: copy`; these still allocate the original kernel
result and should not be described as allocation-free. Direct arithmetic,
constant-image, and inversion paths write into caller storage. Identity paths
copy their input directly. More complex filtering, segmentation, saliency,
foreground, blob, geometric, RGB and volume kernels initially retain their
original internal allocations. These are explicit future optimisation points.

The per-sample evaluator requires `out` for every step returning a sized image
(building the evaluator throws otherwise) and always calls such steps with a
preallocated buffer from the task's `BufferPool`, including on the first sample.
The buffer's previous contents are garbage, so a function must write all of it.
See [Typed population evaluation](typed_population_engines.md).

The exhaustive contract test `test/libraries/test_image_out_contract.jl`
discovers factory bundles, including unexported experimental image bundles,
instantiates their intensity/binary/segment/RGB/volume operators, and reports
missing keyword support or untested decoder-callable methods explicitly.

See the [complete allocating-kernel inventory](library_out_copy_inventory.md)
for every registered operator with a `# out: copy` path. Matching-storage 2D
morphology uses `erode!`, `dilate!`, and compound `!` operations; mixed-storage
morphology retains its original conversion path. Cheap RGB channel operations,
adjustments, statistics and masking, and volume arithmetic/logic/inversion/gamma
also write directly to the supplied storage.

During the contract audit, the unexported experimental mask operators needed
explicit output size parameters for concrete inference. Their segment-image
copies now copy pixel storage directly, avoiding an ambiguous constructor. The
experimental "mask around" operator now initialises its centre and bounds from
its positional arguments; it previously threw on undefined variables.
