using Test, UTCGP, Random

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
