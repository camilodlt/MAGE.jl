using Test, UTCGP
using ImageCore: N0f8
# Typed evaluation of image programs (per-sample engine): engine choice from the
# pool, buffers, several outputs, threads. Small images keep the tests fast.

# ---------------------------------------------------------------------------
# Library-like functions: images are returned through `out` when given
# ---------------------------------------------------------------------------

const ENGINE_CALLS = (with_out = Ref(0), without_out = Ref(0))

function count_call(out)
    if out === nothing
        ENGINE_CALLS.without_out[] += 1
    else
        ENGINE_CALLS.with_out[] += 1
    end
end

function reset_calls!()
    ENGINE_CALLS.with_out[] = 0
    ENGINE_CALLS.without_out[] = 0
end

intensity(value, side) = SImageND(IntensityPixel{N0f8}.(fill(value, side, side)))
binary(mask) = SImageND(BinaryPixel.(mask))
# With the size as a type, the result type is inferable (as in the libraries).
binary(mask, size::Type{<:Tuple}) = SImageND(BinaryPixel.(mask), size)

"""Binary image: pixels ≥ 0.5."""
function engine_threshold(img::SImageND{S}; out = nothing) where {S}
    count_call(out)
    mask = Float64.(img.img) .>= 0.5
    if out === nothing
        return binary(mask, S)
    end
    out.img .= BinaryPixel.(mask)
    return out
end

"""Binary 8×8 image from a 16×16 one (every other pixel)."""
function engine_halve(img::SImageND{Tuple{16,16}}; out = nothing)
    count_call(out)
    half = img.img[1:2:end, 1:2:end]
    if out === nothing
        return SImageND(half, Tuple{8,8})
    end
    out.img .= half
    return out
end

engine_mean(img) = Float64(sum(Float64, img.img) / length(img.img))

"""Writes garbage into `out`, then throws when `fail > 0`: the fallback must be used."""
function engine_partial_write(img::SImageND{S}, fail::Float64; out = nothing) where {S}
    if fail > 0
        if out !== nothing
            fill!(out.img, zero(eltype(out.img)))
        end
        error("partial write")
    end
    return engine_threshold(img; out)
end

"""Returns a sized image but accepts no `out`: not allowed in typed evaluation."""
engine_no_out(img::SImageND{S}) where {S} = binary(Float64.(img.img) .>= 0.5, S)

# ---------------------------------------------------------------------------
# Graph builder: steps are (function, inputs, return type); refs as below
# ---------------------------------------------------------------------------

input_ref(position, T) = UTCGP.PopulationSequentialInputRef(position, T)
step_ref(index, T) = UTCGP.PopulationSequentialTmpRef(index, T)

"""
A graph with `input_types`, the given steps, and per individual its output refs
and the steps it uses (for individual_times).
"""
function engine_graph(input_types, steps, individuals)
    graph = UTCGP.PopulationSequentialProgram()
    graph.input_types = Type[input_types...]
    graph.has_input_layout = true
    for (fn, inputs, T, fallback) in steps
        wrapper = FunctionWrapper(fn, nameof(fn), nothing, fallback)
        push!(graph.steps, UTCGP.PopulationSequentialCallStep(wrapper,
            UTCGP.AbstractPopulationSequentialRef[inputs...], T, T))
    end
    for (outputs, used_steps) in individuals
        push!(graph.individual_outputs, UTCGP.AbstractPopulationSequentialRef[outputs...])
        push!(graph.individual_step_ids, used_steps)
    end
    return graph
end

const I16 = typeof(intensity(0.0, 16))
const B16 = typeof(binary(falses(16, 16)))
const B8 = typeof(binary(falses(8, 8)))
# Fallbacks return constants, so their type is inferable too.
const FALSE16 = binary(falses(16, 16))
const FALSE8 = binary(falses(8, 8))

"""
threshold(R) → B16, halve(step 1) → B8, mean(step 2) → individual 1,
mean(R) → individual 2.
"""
function mixed_graph()
    return engine_graph([I16], [
            (engine_threshold, [input_ref(1, I16)], B16, () -> FALSE16),
            (engine_halve, [step_ref(1, B16)], B8, () -> FALSE8),
            (engine_mean, [step_ref(2, B8)], Float64, () -> 0.0),
            (engine_mean, [input_ref(1, I16)], Float64, () -> 0.0)],
        [([step_ref(3, Float64)], [1, 2, 3]), ([step_ref(4, Float64)], [4])])
end

mixed_samples() = [(intensity(0.2, 16),), (intensity(0.7, 16),), (intensity(0.5, 16),)]

# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

@testset "The engine is chosen from the run's types" begin
    @test TypedEvaluator(mixed_graph()) isa UTCGP.PerSampleEvaluator
    scalar_graph = engine_graph([Float64], [(identity, [input_ref(1, Float64)], Float64, () -> 0.0)],
        [([step_ref(1, Float64)], [1])])
    @test TypedEvaluator(scalar_graph) isa UTCGP.TiledEvaluator
    # An image run evaluates even an all-scalar graph with the per-sample engine.
    image_run_pool = BufferPool([I16, B16, Float64])
    @test TypedEvaluator(scalar_graph, image_run_pool) isa UTCGP.PerSampleEvaluator
    @test TypedEvaluator(scalar_graph, image_run_pool; engine=:tiled) isa UTCGP.TiledEvaluator
end

@testset "Image program: results, step values and times match the generic rule" begin
    graph = mixed_graph()
    samples = mixed_samples()
    evaluator = TypedEvaluator(graph)
    outputs = zeros(2, 3)
    individual_times = zeros(2, 3)
    evaluate_population_into!(outputs, graph, samples; evaluator, individual_times, check=true)
    @test outputs[2, :] ≈ [Float64(N0f8(0.2)), Float64(N0f8(0.7)), Float64(N0f8(0.5))]
    seconds = evaluator.step_seconds
    @test individual_times[1, end] === sum((seconds[i] for i in [1, 2, 3]); init = 0.0)
    @test individual_times[2, end] === seconds[4]
    step_values = zeros(4, 3)
    evaluate_population_steps_into!(step_values, graph, samples; evaluator)
    @test all(isnan, step_values[1:2, :])                 # images are not recorded
    @test step_values[3:4, :] == outputs[[1, 2], :]
end

@testset "Buffers are preallocated, per concrete type, and always passed as out" begin
    graph = mixed_graph()
    pool = BufferPool([I16, B16, B8, Float64])
    evaluator = TypedEvaluator(graph, pool)
    @test evaluator.steps[1].buffer isa B16
    @test evaluator.steps[2].buffer isa B8      # another size, another type, another list
    @test evaluator.steps[3].buffer === nothing # numbers need no buffer
    @test length(pool.buffers[B16]) == 1 && length(pool.buffers[B8]) == 1
    reset_calls!()
    evaluate_population_into!(zeros(2, 3), graph, mixed_samples(); evaluator)
    @test ENGINE_CALLS.without_out[] == 0
    @test ENGINE_CALLS.with_out[] == 6         # 2 image steps × 3 samples
    @test evaluator.steps[1].result.value === evaluator.steps[1].buffer
end

@testset "Steps of one type get distinct buffers, reused by the next generation" begin
    two_thresholds = engine_graph([I16, I16], [
            (engine_threshold, [input_ref(1, I16)], B16, () -> FALSE16),
            (engine_threshold, [input_ref(2, I16)], B16, () -> FALSE16),
            (engine_mean, [step_ref(1, B16)], Float64, () -> 0.0),
            (engine_mean, [step_ref(2, B16)], Float64, () -> 0.0)],
        [([step_ref(3, Float64)], [1, 3]), ([step_ref(4, Float64)], [2, 4])])
    pool = BufferPool([I16, B16, Float64])
    generation_1 = TypedEvaluator(mixed_graph(), pool)
    first_buffer = generation_1.steps[1].buffer
    generation_2 = TypedEvaluator(two_thresholds, pool)
    @test generation_2.steps[1].buffer === first_buffer        # reused, not allocated
    @test generation_2.steps[2].buffer !== first_buffer        # a second one was added
    @test length(pool.buffers[B16]) == 2
    samples = [(intensity(0.2, 16), intensity(0.9, 16))]
    outputs = zeros(2, 1)
    evaluate_population_into!(outputs, two_thresholds, samples; evaluator=generation_2, check=true)
    @test outputs[:, 1] == [0.0, 1.0]   # individual 1 sees the dark input, individual 2 the bright one
end

@testset "Several outputs, including an image, are copies" begin
    graph = engine_graph([I16], [
            (engine_threshold, [input_ref(1, I16)], B16, () -> FALSE16),
            (engine_mean, [step_ref(1, B16)], Float64, () -> 0.0)],
        [([step_ref(1, B16), step_ref(2, Float64)], [1, 2])])
    samples = [(intensity(0.2, 16),), (intensity(0.9, 16),)]
    evaluator = TypedEvaluator(graph)
    outputs = (Matrix{B16}(undef, 1, 2), zeros(1, 2))
    evaluate_population_into!(outputs, graph, samples; evaluator, check=true)
    images, means = outputs
    @test images[1, 1] !== evaluator.steps[1].buffer
    @test images[1, 1].img == FALSE16.img                 # still sample 1's (dark) image
    @test images[1, 2].img == binary(trues(16, 16)).img
    @test means == [0.0 1.0]
end

@testset "Steps are not specialised: a reordered graph compiles no new runner" begin
    graph = mixed_graph()
    reordered = engine_graph([I16], [
            (engine_mean, [input_ref(1, I16)], Float64, () -> 0.0),
            (engine_threshold, [input_ref(1, I16)], B16, () -> FALSE16),
            (engine_halve, [step_ref(2, B16)], B8, () -> FALSE8),
            (engine_mean, [step_ref(3, B8)], Float64, () -> 0.0)],
        [([step_ref(4, Float64)], [2, 3, 4]), ([step_ref(1, Float64)], [1])])
    evaluator = TypedEvaluator(graph)
    @test all(step -> step isa UTCGP.PerSampleCall, evaluator.steps)
    evaluate_population_into!(zeros(2, 3), graph, mixed_samples(); evaluator)
    runner = which(UTCGP._run_step!, Tuple{UTCGP.PerSampleEvaluator,UTCGP.PerSampleCall,Any})
    specialisations = length(collect(Base.specializations(runner)))
    evaluate_population_into!(zeros(2, 3), reordered, mixed_samples(); check=true)
    @test length(collect(Base.specializations(runner))) == specialisations
end

@testset "A throwing step uses its fallback, even after writing into out" begin
    fallback = binary(trues(16, 16))
    graph = engine_graph([I16, Float64], [
            (engine_partial_write, [input_ref(1, I16), input_ref(2, Float64)], B16, () -> fallback),
            (engine_mean, [step_ref(1, B16)], Float64, () -> 0.0)],
        [([step_ref(2, Float64)], [1, 2])])
    samples = [(intensity(0.9, 16), 0.0), (intensity(0.1, 16), 1.0), (intensity(0.1, 16), 0.0)]
    outputs = zeros(1, 3)
    evaluate_population_into!(outputs, graph, samples; check=true)
    @test outputs == [1.0 1.0 0.0]
end

@testset "No buffer for casters and unsized types; out is required for sized images" begin
    vector_graph = engine_graph([Float64], [
            (x -> fill(x, 3), [input_ref(1, Float64)], Vector{Float64}, () -> zeros(3)),
            (sum, [step_ref(1, Vector{Float64})], Float64, () -> 0.0)],
        [([step_ref(2, Float64)], [1, 2])])
    evaluator = TypedEvaluator(vector_graph)
    @test evaluator isa UTCGP.PerSampleEvaluator && evaluator.steps[1].buffer === nothing
    outputs = zeros(1, 2)
    evaluate_population_into!(outputs, vector_graph, [(1.0,), (2.0,)]; evaluator, check=true)
    @test outputs == [3.0 6.0]
    no_out = engine_graph([I16], [(engine_no_out, [input_ref(1, I16)], B16, () -> FALSE16)],
        [([step_ref(1, B16)], [1])])
    @test_throws TypedEvaluationError TypedEvaluator(no_out)
end

const FALSE128 = binary(falses(128, 128))
@testset "Images allocate no output: only small boxed values per step" begin
    side = 128
    I128 = typeof(intensity(0.0, side))
    B128 = typeof(FALSE128)
    graph = engine_graph([I128], [
            (engine_threshold, [input_ref(1, I128)], B128, () -> FALSE128),
            (engine_mean, [step_ref(1, B128)], Float64, () -> 0.0)],
        [([step_ref(2, Float64)], [1, 2])])
    samples = [(intensity(0.6, side),) for _ in 1:8]
    evaluator = TypedEvaluator(graph)
    outputs = zeros(1, 8)
    evaluate_population_into!(outputs, graph, samples; evaluator)
    bytes = @allocated evaluate_population_into!(outputs, graph, samples; evaluator)
    # engine_threshold allocates its Float64 mask itself (side² × 8 bytes per call):
    # anything beyond that would be an output image (side² bytes) per sample.
    mask_bytes = 8 * (side^2 * 8)
    @test bytes < mask_bytes + 8 * side^2 ÷ 2
end

@testset "One pool per task, with :static or :dynamic threads" begin
    graph = mixed_graph()
    samples = repeat(mixed_samples(), 4)
    expected = zeros(2, length(samples))
    evaluate_population_into!(expected, graph, samples)
    n_tasks = max(Threads.nthreads(), 2)
    chunks = collect(Iterators.partition(eachindex(samples), cld(length(samples), n_tasks)))
    for scheduling in (:static, :dynamic)
        pools = Channel{BufferPool}(n_tasks)
        for _ in 1:n_tasks
            put!(pools, BufferPool([I16, B16, B8, Float64]))
        end
        results = zeros(2, length(samples))
        evaluate_chunk(chunk) = begin
            pool = take!(pools)
            try
                evaluator = TypedEvaluator(graph, pool)
                chunk_outputs = zeros(2, length(chunk))
                evaluate_population_into!(chunk_outputs, graph, samples[chunk]; evaluator)
                results[:, chunk] = chunk_outputs
            finally
                put!(pools, pool)
            end
        end
        if scheduling === :static
            Threads.@threads :static for chunk in chunks
                evaluate_chunk(chunk)
            end
        else
            Threads.@threads :dynamic for chunk in chunks
                evaluate_chunk(chunk)
            end
        end
        @test results == expected
        all_pools = [take!(pools) for _ in 1:n_tasks]
        first_buffers = [pool.buffers[B16][1] for pool in all_pools if !isempty(pool.buffers[B16])]
        @test allunique(objectid.(first_buffers))   # no two pools share a buffer
    end
end

# ---------------------------------------------------------------------------
# Working arrays: float_scratch / image_scratch from the pool, else task storage
# ---------------------------------------------------------------------------

const SCRATCH_SEEN = (float = Any[], image = Any[])

"""Threshold through a Float32 working array and a working image (both overwritten)."""
function engine_threshold_with_scratch(img::SImageND{S}; out = nothing, float_scratch = nothing,
        image_scratch = nothing) where {S}
    values = UTCGP.float_buffer(float_scratch, 1, img, :engine_threshold)
    work = UTCGP.image_buffer(image_scratch, 1, FALSE16, :engine_threshold)
    push!(SCRATCH_SEEN.float, values)
    push!(SCRATCH_SEEN.image, work)
    values .= Float32.(img.img)
    work.img .= BinaryPixel.(values .>= 0.5f0)
    if out === nothing
        return SImageND(copy(work.img), S)
    end
    out.img .= work.img
    return out
end

@testset "Working arrays come from the pool, shared by steps and kept across generations" begin
    graph = engine_graph([I16, I16], [
            (engine_threshold_with_scratch, [input_ref(1, I16)], B16, () -> FALSE16),
            (engine_threshold_with_scratch, [input_ref(2, I16)], B16, () -> FALSE16),
            (engine_mean, [step_ref(1, B16)], Float64, () -> 0.0),
            (engine_mean, [step_ref(2, B16)], Float64, () -> 0.0)],
        [([step_ref(3, Float64)], [1, 3]), ([step_ref(4, Float64)], [2, 4])])
    samples = [(intensity(0.2, 16), intensity(0.9, 16)), (intensity(0.7, 16), intensity(0.1, 16))]
    pool = BufferPool([I16, B16, Float64])
    evaluator = TypedEvaluator(graph, pool)
    @test keys(evaluator.steps[1].keywords) == (:out, :float_scratch, :image_scratch)
    @test evaluator.steps[1].keywords.float_scratch === evaluator.steps[2].keywords.float_scratch
    @test evaluator.steps[1].keywords.image_scratch[1] isa B16
    @test size(evaluator.steps[1].keywords.float_scratch[1]) == (16, 16)
    empty!(SCRATCH_SEEN.float); empty!(SCRATCH_SEEN.image)
    outputs = zeros(2, 2)
    evaluate_population_into!(outputs, graph, samples; evaluator, check = true)
    @test outputs == [0.0 1.0; 1.0 0.0]
    pooled = pool.float_scratch[B16][1]
    @test SCRATCH_SEEN.float[1] === pooled            # the typed engine passes the pool's array
    next_generation = TypedEvaluator(graph, pool)
    @test next_generation.steps[1].keywords.float_scratch[1] === pooled
    # Without keywords (generic interpreter, direct calls): the task's storage, same result.
    direct = engine_threshold_with_scratch(intensity(0.9, 16))
    @test SCRATCH_SEEN.float[end] !== pooled
    @test direct.img == binary(trues(16, 16)).img
end

@testset "scratch keeps one array per size" begin
    a224 = UTCGP.scratch(:engine_test, Float64, 224, 224)
    a112 = UTCGP.scratch(:engine_test, Float64, 112, 112)
    @test UTCGP.scratch(:engine_test, Float64, 224, 224) === a224
    @test UTCGP.scratch(:engine_test, Float64, 112, 112) === a112
    @test UTCGP.scratch(:engine_test, Float32, 224, 224) !== a224   # another element type, another array
    growable = UTCGP.scratch(:engine_growable, Int, 0)
    push!(growable, 1, 2, 3)
    @test UTCGP.scratch(:engine_growable, Int, 0) === growable && length(growable) == 3
end

"""Deliberately faulty out path: plain threshold is correct, buffered pixels invert."""
function engine_faulty_threshold(img::SImageND{S}; out = nothing) where {S}
    result = engine_threshold(img; out)
    if out !== nothing
        result.img .= BinaryPixel.(Float64.(result.img) .< 0.5)
    end
    return result
end

@testset "Checked evaluation localises a faulty image call" begin
    graph = engine_graph([I16], [
            (engine_faulty_threshold, [input_ref(1, I16)], B16, () -> FALSE16),
            (engine_mean, [step_ref(1, B16)], Float64, () -> 0.0)],
        [([step_ref(2, Float64)], [1, 2])])
    error = try
        evaluate_population_into!(zeros(1, 1), graph, [(intensity(0.2, 16),)]; check=true)
        nothing
    catch caught
        caught
    end
    @test error isa AssertionError
    message = sprint(showerror, error)
    for text in ("MISMATCH DIAGNOSIS", "first differing step: 1", "function: engine_faulty_threshold",
            "input types:", "all inputs identical: true", "plain vs out identical: false",
            "plain vs out + scratch identical: false", "plain reproduces generic: true",
            "out + scratch reproduces typed: true")
        @test occursin(text, message)
    end
end

const ENGINE_LUMINANCE = UTCGP.image3D_color_statistics_rgb.rgb_luminance_image2D_factory(I16)
const ENGINE_LUMINANCE_FALLBACK = intensity(0.0, 16)

@testset "RGB luminance preserves the generic Float64 rounding boundary" begin
    P = IntensityPixel{N0f8}
    pixels = Array{P}(undef, 16, 16, 3)
    for (channel, byte) in enumerate((110, 123, 2))
        pixels[:, :, channel] .= P(reinterpret(N0f8, UInt8(byte)))
    end
    rgb = SImageND(pixels)
    plain = ENGINE_LUMINANCE(rgb)
    out = intensity(0.9, 16)
    @test ENGINE_LUMINANCE(rgb; out) === out
    @test UTCGP._identical(plain, out)
    @test all(pixel -> pixel.pixel === reinterpret(N0f8, UInt8(112)), out.img)
    T = typeof(rgb)
    graph = engine_graph([T], [
            (ENGINE_LUMINANCE, [input_ref(1, T)], I16, () -> ENGINE_LUMINANCE_FALLBACK),
            (engine_mean, [step_ref(1, I16)], Float64, () -> 0.0)],
        [([step_ref(2, Float64)], [1, 2])])
    evaluate_population_into!(zeros(1, 2), graph, [(rgb,), (rgb,)]; check=true)
end
