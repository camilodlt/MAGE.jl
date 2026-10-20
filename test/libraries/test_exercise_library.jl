using Test, UTCGP, Random
using ImageCore: N0f8, N0f16

exercise_plus(x::Float64, y::Float64, args...) = x + y
exercise_plus(x::Int, args...) = x + 1
exercise_failure(x::Float64, args...) = error("expected workload error")
exercise_zero() = 0.0
exercise_number(x::Number, args...) = x + 1

@testset "Optional library exercise" begin
    Random.seed!(44)
    expected = rand()
    Random.seed!(44)
    examples = UTCGP.image_library_examples(16)
    @test rand() == expected
    repeated = UTCGP.image_library_examples(16)
    @test keys(examples) == keys(repeated)
    @test all(isequal(examples[T], repeated[T]) for T in keys(examples))
    bundle = UTCGP.FunctionBundle(exercise_zero)
    UTCGP.append_method!(bundle, exercise_plus, :plus)
    UTCGP.append_method!(bundle, exercise_failure, :failure)
    result = UTCGP.exercise_library([bundle], examples; extra_numbers = ())
    @test length(UTCGP._exercise_signatures(exercise_number, [Float64, Int])) == 2
    @test result.calls == 3
    @test length(result.errors) == 1
    @test isempty(result.uncovered)
    @test only(result.errors)[1] == :failure
    # Default extra numbers (-1.5, 2000.0) call every numeric signature twice more.
    extended = UTCGP.exercise_library([bundle], examples)
    @test extended.calls == 9
    @test length(extended.errors) == 3
    @test UTCGP._exercise_with_number((:image, 0.7, 3), -1.5) == (:image, -1.5, -2)
    @test UTCGP._exercise_with_number((:image, 0.7, 3), 2000.0) == (:image, 2000.0, 2000)
    @test_throws ArgumentError UTCGP.image_library_examples(0)
end

@testset "Factory names ignore caller imports" begin
    examples = UTCGP.image_library_examples(32)
    image_type = only(T for T in keys(examples) if T <: UTCGP.SizedImage && ndims(first(examples[T])) == 2 && eltype(first(examples[T])) <: UTCGP.IntensityPixel)
    before = UTCGP._factory_type_symbol(image_type)
    factory = UTCGP.get_image2Dintensity_factory_bundles()[1].functions[1].fn
    fn = factory(image_type)
    methods_before = collect(methods(fn))
    @eval Main using ImageCore, Images
    @test UTCGP._factory_type_symbol(image_type) == before
    @test factory(image_type) === fn
    @test collect(methods(fn)) == methods_before
    @test UTCGP._factory_type_symbol(Float64) == :Float64
    larger = UTCGP.image_library_examples(64)
    larger_type = only(T for (T, values) in larger if T <: UTCGP.SizedImage &&
        ndims(first(values)) == 2 && eltype(first(values)) <: UTCGP.IntensityPixel)
    @test UTCGP._factory_type_symbol(larger_type) != before
end

exercise_small(x::Float32, args...) = x
exercise_small(x::Int8, args...) = x
exercise_cast_one(x) = x + 1
exercise_cast_two(x) = x + 2
exercise_fallback_one() = 1
exercise_fallback_two() = 2

# Yield between definitions to expose premature reuse deterministically on one thread.
UTCGP.@serialized_factory function exercise_concurrent_factory()
    isdefined(@__MODULE__, :exercise_concurrent_operator) &&
        return Base.invokelatest(getfield, @__MODULE__, :exercise_concurrent_operator)
    operator = @eval exercise_concurrent_operator(x::Int) = x
    yield()
    @eval exercise_concurrent_operator(x::Float64) = x
    return operator
end

@testset "Complete factory publication and scalar reuse" begin
    tasks = [@async begin
        fn = exercise_concurrent_factory()
        (fn, collect(methods(fn)))
    end for _ in 1:8]
    results = fetch.(tasks)
    @test all(result -> result[1] === results[1][1], results)
    @test all(result -> length(result[2]) == 2, results)
    @test all(result -> result[2] == results[1][2], results)
    factory = UTCGP.element_conditional.if_else_multiplexer_factory
    functions = [factory(Float64) for _ in (32, 64, 224)]
    @test all(fn -> fn === first(functions), functions)
    @test Base.invokelatest(first(functions), 1, 2.0, 3.0) === 2.0
    @test Base.invokelatest(first(functions), 0, 2.0, 3.0) === 3.0
end

@testset "Exercise preserves numeric types and wrapper policies" begin
    examples = Dict(Float32 => (0.7f0,), Int8 => (Int8(3),))
    bundle = UTCGP.FunctionBundle(exercise_zero)
    UTCGP.append_method!(bundle, exercise_small, :small)
    result = UTCGP.exercise_library([bundle], examples)
    @test result.calls == 6
    # Int8 cannot represent 2000: record the conversion error without aborting.
    @test length(result.errors) == 1
    @test only(result.errors)[3] isa InexactError
    @test UTCGP._exercise_with_number((0.7f0, Int8(3)), -1.5) === (-1.5f0, Int8(-2))
    @test isempty(result.uncovered)

    policies = UTCGP.FunctionBundle(exercise_zero)
    push!(policies.functions, UTCGP.FunctionWrapper(exercise_plus, :one, exercise_cast_one, exercise_fallback_one))
    push!(policies.functions, UTCGP.FunctionWrapper(exercise_plus, :two, exercise_cast_two, exercise_fallback_two))
    warmed = UTCGP.exercise_library([policies], Dict(Float64 => (0.7, 3.0)); extra_numbers = ())
    @test warmed.calls == 2
    @test isempty(warmed.errors)
end

@testset "Factory type separation and fresh-world exercise" begin
    pixels8 = UTCGP.IntensityPixel{N0f8}.(zeros(2, 2))
    pixels16 = UTCGP.IntensityPixel{N0f16}.(zeros(2, 2))
    images = (UTCGP.SImageND(pixels8), UTCGP.SImageND(pixels16), UTCGP.SImageND(view(pixels8, :, :)))
    @test length(Set(UTCGP._factory_type_symbol(typeof(image)) for image in images)) == 3
    factory = UTCGP.image2D_basic.identity_image2D_factory
    tasks = [Threads.@spawn factory(typeof(first(images))) for _ in 1:8]
    operators = fetch.(tasks)
    @test all(fn -> fn === first(operators), operators)
    for image in images
        fn = factory(typeof(image))
        @test Base.invokelatest(fn, image) === image
    end
    # Define and exercise in the same task world: the helper must use invokelatest.
    fn = UTCGP.element_conditional.if_else_multiplexer_factory(Int16)
    bundle = UTCGP.FunctionBundle(exercise_zero)
    UTCGP.append_method!(bundle, fn, :fresh)
    result = UTCGP.exercise_library([bundle], Dict(Int16 => (Int16(1), Int16(2))))
    @test result.calls == 3
    @test isempty(result.errors)
    @test isempty(result.uncovered)
end


module ExerciseDisplayTypes
    struct First end
    struct Second end
    Base.show(io::IO, ::Type{First}) = print(io, "SameType")
    Base.show(io::IO, ::Type{Second}) = print(io, "SameType")
end

@testset "Factory names do not use custom display" begin
    A, B = ExerciseDisplayTypes.First, ExerciseDisplayTypes.Second
    @test UTCGP._factory_type_symbol(A) != UTCGP._factory_type_symbol(B)
    factory = UTCGP.element_conditional.if_else_multiplexer_factory
    a, b = factory(A), factory(B)
    @test a !== b
    @test Base.invokelatest(a, 1, A(), A()) isa A
    @test Base.invokelatest(b, 1, B(), B()) isa B
    @test UTCGP._factory_type_symbol(Val{Int8(1)}) != UTCGP._factory_type_symbol(Val{1})
    @test UTCGP._factory_type_symbol(Val{0.0}) != UTCGP._factory_type_symbol(Val{-0.0})
    @test UTCGP._factory_type_symbol(Vector) == UTCGP._factory_type_symbol(Array{T,1} where T)
end

@testset "Unbounded tuple factory types" begin
    @test UTCGP._factory_type_symbol(Tuple{Vararg{Int}}) != UTCGP._factory_type_symbol(Tuple{Vararg{Float64}})
    factory = UTCGP.element_conditional.if_else_multiplexer_factory
    fn = factory(Tuple{Vararg{Int}})
    @test Base.invokelatest(fn, 1, (1, 2), (3, 4)) == (1, 2)
end
