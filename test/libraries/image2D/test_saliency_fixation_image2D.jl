using Random

function _saliency_test_image(values::AbstractMatrix{<:Real})
    return SImageND(IntensityPixel{N0f8}.(clamp.(Float64.(values), 0.0, 1.0)))
end

@testset "Image2D fixation saliency: Itti-Koch-Niebur" begin
    impulse = zeros(Float64, 128, 128)
    impulse[57:72, 57:72] .= 1.0
    image = _saliency_test_image(impulse)
    original = copy(image.img)
    factory = bundle_image2DIntensity_saliency_fixation_factory[:itti_koch_saliency]
    fn = factory.fn(typeof(image))
    @test which(fn, Tuple{typeof(image)}).nargs == 3
    @test which(fn, Tuple{typeof(image),Float64}).nargs == 4
    @test which(fn, Tuple{typeof(image),Float64,Float64}).nargs == 5

    default_result = fn(image)
    @test default_result.img == fn(image, 0.5).img
    @test default_result.img == fn(image, 0.5, 0.0).img

    intensity_only = fn(image, 0.0, 0.0)
    orientation_only = fn(image, 1.0, 0.0)
    smoothed = fn(image, 0.5, 3.0)
    @test intensity_only.img != orientation_only.img
    @test smoothed.img != default_result.img

    @test fn(image, -10.0, -10.0).img == intensity_only.img
    @test fn(image, 10.0, 10.0).img == fn(image, 1.0, 5.0).img
    @test fn(image, NaN, NaN).img == default_result.img
    @test fn(image, 0.5, 3.0, :ignored).img == smoothed.img


    result = fn(image)
    values = Float64.(reinterpret(result.img))

    @test size(result) == size(image)
    @test eltype(result) == eltype(image)
    @test all(isfinite, values)
    @test all(0.0 .<= values .<= 1.0)
    @test image.img == original
    @test maximum(values[49:80, 49:80]) > maximum(values[1:24, 1:24])
    @test result.img == fn(image).img

    flat = _saliency_test_image(fill(0.4, 37, 53))
    flat_fn = factory.fn(typeof(flat))
    @test all(iszero, reinterpret(flat_fn(flat).img))

    tiny = _saliency_test_image(reshape([0.0, 1.0, 0.0, 0.0, 1.0, 0.0], 2, 3))
    tiny_result = factory.fn(typeof(tiny))(tiny)
    @test size(tiny_result) == size(tiny)
    @test all(isfinite, Float64.(reinterpret(tiny_result.img)))

    float_image = SImageND(IntensityPixel{Float64}.(impulse))
    float_result = factory.fn(typeof(float_image))(float_image)
    @test eltype(float_result) == IntensityPixel{Float64}

    bundles = get_extension_saliency_intensityimg()
    @test any(bundle -> bundle[:itti_koch_saliency] !== nothing, bundles)

    rng = MersenneTwister(42)
    benchmark_image = _saliency_test_image(rand(rng, 256, 256))
    benchmark_fn = factory.fn(typeof(benchmark_image))
    benchmark_fn(benchmark_image, 1.0, 5.0)
    elapsed = minimum(
        @elapsed benchmark_fn(benchmark_image, 1.0, 5.0) for _ in 1:3
    )
    @test elapsed <= 0.5
end

@testset "Image2D fixation saliency: Spectral Residual" begin
    object = zeros(Float64, 128, 128)
    object[49:80, 57:72] .= 1.0
    image = _saliency_test_image(object)
    original = copy(image.img)
    factory = bundle_image2DIntensity_saliency_fixation_factory[:spectral_residual_saliency]
    fn = factory.fn(typeof(image))

    @test which(fn, Tuple{typeof(image)}).nargs == 3
    @test which(fn, Tuple{typeof(image),Float64}).nargs == 4
    @test which(fn, Tuple{typeof(image),Float64,Float64}).nargs == 5

    default_result = fn(image)
    @test default_result.img == fn(image, 1.0).img
    @test default_result.img == fn(image, 1.0, 2.0).img

    narrow_unsmoothed = fn(image, 1.0, 0.0)
    wide_unsmoothed = fn(image, 7.0, 0.0)
    smoothed = fn(image, 1.0, 5.0)
    @test narrow_unsmoothed.img != wide_unsmoothed.img
    @test narrow_unsmoothed.img != smoothed.img

    @test fn(image, -10.0, -10.0).img == narrow_unsmoothed.img
    @test fn(image, 100.0, 100.0).img == fn(image, 15.0, 5.0).img
    @test fn(image, NaN, NaN).img == default_result.img
    @test fn(image, 1.0, 5.0, :ignored).img == smoothed.img

    values = Float64.(reinterpret(default_result.img))
    @test size(default_result) == size(image)
    @test eltype(default_result) == eltype(image)
    @test all(isfinite, values)
    @test all(0.0 .<= values .<= 1.0)
    @test image.img == original
    impulse = zeros(Float64, 128, 128)
    impulse[64, 64] = 1.0
    impulse_result = fn(_saliency_test_image(impulse))
    impulse_values = Float64.(reinterpret(impulse_result.img))
    @test maximum(impulse_values[57:72, 57:72]) > maximum(impulse_values[1:24, 1:24])
    @test default_result.img == fn(image).img

    flat = _saliency_test_image(fill(0.4, 37, 53))
    flat_result = factory.fn(typeof(flat))(flat)
    @test all(iszero, reinterpret(flat_result.img))

    tiny = _saliency_test_image(reshape([0.0, 1.0, 0.0, 0.0, 1.0, 0.0], 2, 3))
    tiny_result = factory.fn(typeof(tiny))(tiny, 15.0, 2.0)
    @test size(tiny_result) == size(tiny)
    @test all(isfinite, Float64.(reinterpret(tiny_result.img)))

    float_image = SImageND(IntensityPixel{Float64}.(object))
    float_result = factory.fn(typeof(float_image))(float_image)
    @test eltype(float_result) == IntensityPixel{Float64}

    bundles = get_extension_saliency_intensityimg()
    @test any(bundle -> bundle[:spectral_residual_saliency] !== nothing, bundles)

    rng = MersenneTwister(43)
    benchmark_image = _saliency_test_image(rand(rng, 256, 256))
    benchmark_fn = factory.fn(typeof(benchmark_image))
    benchmark_fn(benchmark_image, 15.0, 5.0)
    elapsed = minimum(
        @elapsed benchmark_fn(benchmark_image, 15.0, 5.0) for _ in 1:3
    )
    @test elapsed <= 0.5
end
