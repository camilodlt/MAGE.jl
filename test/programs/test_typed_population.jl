using Test, MAGE
# Typed evaluation of scalar programs: both engines agree with the generic
# interpreter, the tiled engine allocates nothing, and a step whose type cannot be
# proven makes building the evaluator throw.

"""One-step graph: input x::Float64, output fn(x)."""
function typed_fixture(fn; caster=nothing, fallback=()->0.0, return_type=Float64, policy=return_type)
    graph = MAGE.PopulationSequentialProgram()
    graph.input_types = Type[Float64]
    graph.has_input_layout = true
    wrapper = MAGE.FunctionWrapper(fn, :typed_test, caster, fallback)
    push!(graph.steps, MAGE.PopulationSequentialCallStep(wrapper,
        MAGE.AbstractPopulationSequentialRef[MAGE.PopulationSequentialInputRef(1, Float64)], return_type, policy))
    push!(graph.individual_outputs, MAGE.AbstractPopulationSequentialRef[MAGE.PopulationSequentialTmpRef(1, return_type)])
    push!(graph.individual_step_ids, [1])
    return graph
end

typed_allocations(outputs, graph, samples, evaluator) =
    @allocated evaluate_population_into!(outputs, graph, samples; evaluator)

@testset "Scalar programs: both engines match the generic interpreter" begin
    samples = [(0.0,), (-0.0,), (NaN,), (Inf,), (-10001.0,), (2.0,)]
    graphs = (typed_fixture(identity),
              typed_fixture(x -> x; caster=x -> clamp(x, -10000.0, 10000.0)),
              typed_fixture(x -> x == 2.0 ? error("domain") : x; fallback=() -> -0.0),
              typed_fixture(x -> (1.0,)[Int(x)]; fallback=() -> -0.0))
    for graph in graphs, engine in (:tiled, :per_sample), batch_size in (1, 2, 128)
        evaluator = TypedEvaluator(graph; engine, batch_size)
        outputs = zeros(1, length(samples))
        @test evaluate_population_into!(outputs, graph, samples; evaluator, check=true) === outputs
    end
end

@testset "The tiled engine allocates nothing" begin
    graph = typed_fixture(identity)
    for n_samples in (3, 750), batch_size in (1, 2, 128)
        samples = fill((2.0,), n_samples)
        outputs = zeros(1, n_samples)
        evaluator = TypedEvaluator(graph; batch_size)
        @test evaluator isa MAGE.TiledEvaluator
        evaluate_population_into!(outputs, graph, samples; evaluator)
        @test typed_allocations(outputs, graph, samples, evaluator) == 0
    end
end

@testset "Constants, mixed scalar types and three arguments" begin
    graph = typed_fixture(x -> round(Int, x); fallback=() -> 0, return_type=Int)
    three = MAGE.FunctionWrapper((a, b, c) -> Float64(a) + b + c, :three_args, nothing, () -> 0.0)
    push!(graph.steps, MAGE.PopulationSequentialConstantStep(0.5, Float64))
    push!(graph.steps, MAGE.PopulationSequentialCallStep(three, MAGE.AbstractPopulationSequentialRef[
        MAGE.PopulationSequentialTmpRef(1, Int), MAGE.PopulationSequentialTmpRef(2, Float64),
        MAGE.PopulationSequentialInputRef(1, Float64)], Float64, Float64))
    graph.individual_outputs[1] = MAGE.AbstractPopulationSequentialRef[MAGE.PopulationSequentialTmpRef(3, Float64)]
    samples = [(1.0,), (2.0,), (-0.0,)]
    for engine in (:tiled, :per_sample)
        evaluator = TypedEvaluator(graph; engine, batch_size=2)
        outputs = zeros(1, 3)
        evaluate_population_into!(outputs, graph, samples; evaluator, check=true)
        @test outputs == [2.5 4.5 0.5]
    end
    tiled = TypedEvaluator(graph; batch_size=2)
    @test length(tiled.matrices[]) == 2   # one matrix per value type: Float64 and Int
    outputs = zeros(1, 3)
    evaluate_population_into!(outputs, graph, samples; evaluator=tiled)
    @test typed_allocations(outputs, graph, samples, tiled) == 0
end

@testset "Unproven types throw when the evaluator is built" begin
    uncertain = typed_fixture(x -> x == 2.0 ? x : "bad")
    @test_throws TypedEvaluationError TypedEvaluator(uncertain)
    @test_throws TypedEvaluationError evaluate_population_into!(zeros(1, 1), uncertain, [(2.0,)])
    bad_fallback = typed_fixture(identity; fallback=() -> "fallback")
    @test_throws TypedEvaluationError TypedEvaluator(bad_fallback)
    wrong_policy = typed_fixture(identity; policy=Int)
    @test_throws TypedEvaluationError TypedEvaluator(wrong_policy)
    abstract_type = typed_fixture(identity; return_type=Any, policy=MAGE.NoTypeAssertion())
    @test_throws TypedEvaluationError TypedEvaluator(abstract_type)
    # The message names the step and its signature.
    message = try
        TypedEvaluator(uncertain)
        ""
    catch error
        sprint(showerror, error)
    end
    @test occursin("step 1", message) && occursin("typed_test(Float64)", message)
end

@testset "Shape and sample checks" begin
    graph = typed_fixture(identity)
    samples = [(1.0,), (2.0,)]
    @test_throws DimensionMismatch evaluate_population_into!(zeros(2, 2), graph, samples)
    @test_throws DimensionMismatch evaluate_population_into!((zeros(1, 2), zeros(1, 2)), graph, samples)
    @test_throws ArgumentError evaluate_population_into!(zeros(1, 1), graph, [(1,)])
    @test_throws ArgumentError TypedEvaluator(graph; engine=:unknown)
    other = typed_fixture(identity)
    @test_throws ArgumentError evaluate_population_into!(zeros(1, 2), graph, samples; evaluator=TypedEvaluator(other))
end

@testset "Tiled output-only dispatch does not box large step indices" begin
    # Indices 512+ used to allocate at the abstract-step dispatch for every tile.
    graph = typed_fixture(identity)
    append!(graph.steps, fill(first(graph.steps), 649))
    graph.individual_outputs[1][1] = UTCGP.PopulationSequentialTmpRef(650, Float64)
    graph.individual_step_ids[1] = collect(1:650)
    samples = fill((-0.0,), 257) # two full tiles and a partial tile
    outputs = zeros(1, length(samples))
    evaluator = TypedEvaluator(graph)
    evaluate_population_into!(outputs, graph, samples; evaluator, check=true)
    typed_allocations(outputs, graph, samples, evaluator)
    @test typed_allocations(outputs, graph, samples, evaluator) == 0
    @test all(x -> x === -0.0, outputs)
end
