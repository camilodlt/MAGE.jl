using ImageCore: N0f8
import ImageMorphology

# Call tree: exercise_library → _exercise_signatures → _exercise_arguments
#           image_library_examples → seeded planes, mask, labels and RGB

"""
    image_library_examples(side; seed=1)

Deterministic synthetic inputs for an image library: two textured intensity
planes, binary masks, connected-component labels and three-channel images.
Returns a dictionary from concrete type to a pair of values; it reads no files
and does not change the default RNG. For example,
`image_library_examples(32)[Float64] == (0.7, 3.0)`.
"""
function image_library_examples(side::Integer; seed::Integer = 1)
    side > 0 || throw(ArgumentError("image side must be positive"))
    rng = Random.Xoshiro(seed)
    examples = Dict{Type,Tuple}()
    planes = map(1:2) do variant
        values = rand(rng, Float64, side, side)
        for column in 1:side, row in 1:side
            texture = 0.12 * values[row, column]
            cell = exp(-((mod(row + variant, 12) - 6)^2 + (mod(column, 12) - 6)^2) / 10)
            values[row, column] = clamp(0.1 + texture + 0.7 * cell, 0, 1)
        end
        SImageND(IntensityPixel{N0f8}.(values))
    end
    masks = map(planes) do plane
        SImageND(BinaryPixel.(Float64.(plane.img) .> 0.45))
    end
    labels = map(masks) do mask
        SImageND(SegmentPixel{Int}.(ImageMorphology.label_components(reinterpret(mask.img))))
    end
    colors = map(planes) do plane
        red = plane.img
        green = circshift(red, (1, 2))
        blue = circshift(red, (2, 1))
        SImageND(cat(red, green, blue; dims = 3))
    end
    for pair in (planes, masks, labels, colors)
        examples[typeof(first(pair))] = Tuple(pair)
    end
    examples[Float64] = (0.7, 3.0)
    examples[Int] = (3, 1)
    return examples
end

"""
    _exercise_signatures(fn, candidates)

Enumerate concrete signatures of reachable fixed-arity methods, using the
example types and Julia dispatch (including dependent type variables). For
example a method `f(x::Number, args...)` gets a `Tuple{Float64}` signature
and `Tuple{Int}` when `candidates == [Float64, Int]`. Trailing varargs are left empty.
"""
function _exercise_signatures(fn, candidates)
    found = Vector{Type}[]
    arity = maximum((method.nargs - (method.isva ? 2 : 1) for method in methods(fn)); init = 0)
    for count in 0:arity
        for combination in Iterators.product(ntuple(_ -> candidates, count)...)
            signature = Tuple{combination...}
            hasmethod(fn, signature) || continue
            method = which(fn, signature)
            method.nargs - (method.isva ? 2 : 1) == count || continue
            push!(found, Type[combination...])
        end
    end
    return found
end

"""Choose successive examples for repeated types: `(T,T)` uses both images."""
function _exercise_arguments(types, examples)
    seen = Dict{Type,Int}()
    return map(types) do type
        index = get(seen, type, 0) + 1
        seen[type] = index
        values = examples[type]
        values[min(index, length(values))]
    end
end

"""Set every number of `arguments` to `value`; e.g. `(img, 0.7, 3)` with `-1.5` gives `(img, -1.5, -2)`."""
_exercise_with_number(arguments, value) = map(arguments) do argument
    argument isa Integer ? round(Int, value) : argument isa Real ? Float64(value) : argument
end

"""
    exercise_library(bundles, examples; with_out=true, extra_numbers=(-1.5, 2000.0))

Exercise specialised `FunctionBundle`s using a dictionary `Type => (value1,
value2, ...)`, such as `image_library_examples(32)`. Enumerate concrete
signatures by dispatch, extending the library profiler to every combination
of example types. A signature with numeric arguments is called again once per
value of `extra_numbers` (all its numbers set to that value, rounded for
integers), so negative and clamped branches are compiled too. Calls use
`invokelatest` because factories may just have defined the methods. Also warm
supported `out` calls, casters and fallbacks. Errors are collected per call;
no files are read or written and no failures are silently discarded.

Returns `(calls, errors, uncovered)`. `errors` holds `(name, types, exception)`;
`uncovered` lists methods for which no examples could be found. For example,
`exercise_library([specialised_bundle], image_library_examples(32)).calls > 0`.
This is an optional build workload, never run during normal package loading.
"""
function exercise_library(bundles, examples::AbstractDict; with_out::Bool = true, extra_numbers = (-1.5, 2000.0))
    candidates = collect(keys(examples))
    sort!(candidates; by = string)
    errors = []
    uncovered = []
    calls = 0
    seen = Set{Any}()
    for bundle in bundles, wrapper in bundle
        fn = wrapper.fn
        fn in seen && continue
        push!(seen, fn)
        signatures = _exercise_signatures(fn, candidates)
        reached = Set(which(fn, Tuple{types...}) for types in signatures)
        append!(uncovered, [(wrapper.name, method) for method in methods(fn) if !(method in reached)])
        for types in signatures
            arguments = _exercise_arguments(types, examples)
            variants = any(argument -> argument isa Real, arguments) ?
                       [arguments, (_exercise_with_number(arguments, value) for value in extra_numbers)...] : [arguments]
            for variant in variants
                calls += 1
                try
                    result = Base.invokelatest(fn, variant...)
                    if wrapper.caster !== nothing
                        Base.invokelatest(wrapper.caster, result)
                    end
                    if with_out && result isa SizedImage && hasmethod(fn, Tuple{types...}, (:out,))
                        Base.invokelatest(fn, variant...; out = deepcopy(result))
                    end
                catch exception
                    push!(errors, (wrapper.name, types, exception))
                end
            end
        end
        try
            Base.invokelatest(wrapper.fallback)
        catch exception
            push!(errors, (wrapper.name, Type[], exception))
        end
    end
    return (; calls, errors, uncovered)
end
