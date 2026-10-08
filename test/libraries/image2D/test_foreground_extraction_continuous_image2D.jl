using ImageCore: N0f8, N0f16
using Random
using Test

_continuous_intensity(values, ::Type{T} = N0f8) where {T} =
    SImageND(IntensityPixel{T}.(clamp.(Float64.(values), 0.0, 1.0)))
_continuous_values(image) = Float64.(reinterpret(image.img))

@testset "Image2D continuous foreground extraction: Random Walker" begin
    height, width = 64, 64
    object = falses(height, width)
    object[20:45, 24:41] .= true
    values = fill(0.15, height, width)
    values[object] .= 0.85
    saliency_values = zeros(Float64, height, width)
    saliency_values[object] .= 1.0

    image = _continuous_intensity(values)
    saliency = _continuous_intensity(saliency_values)
    output_example = _continuous_intensity(zeros(height, width))
    factory = bundle_image2DIntensity_foreground_extraction_factory[
        :random_walker_foreground
    ]
    fn = factory.fn(typeof(output_example))

    @test which(fn, Tuple{typeof(image)}).nargs == 3
    @test which(fn, Tuple{typeof(image),Float64}).nargs == 4
    @test which(fn, Tuple{typeof(image),Float64,Float64}).nargs == 5
    @test which(fn, Tuple{typeof(image),typeof(saliency)}).nargs == 4
    @test which(fn, Tuple{typeof(image),typeof(saliency),Float64}).nargs == 5
    @test all(method -> method.nargs <= 5, methods(fn))

    image_before = copy(image.img)
    saliency_before = copy(saliency.img)
    result = fn(image, saliency)
    result_values = _continuous_values(result)
    thresholded = result_values .>= 0.5
    intersection = count(thresholded .& object)
    union_count = count(thresholded .| object)

    @test intersection / union_count >= 0.95
    @test all(iszero, result_values[1, :])
    @test all(iszero, result_values[end, :])
    @test all(iszero, result_values[:, 1])
    @test all(iszero, result_values[:, end])
    @test minimum(result_values) >= 0.0
    @test maximum(result_values) <= 1.0
    @test all(isfinite, result_values)
    @test size(result) == size(image)
    @test eltype(result) == IntensityPixel{N0f8}
    @test image.img == image_before
    @test saliency.img == saliency_before
    @test result.img == fn(image, saliency).img
    @test result.img == fn(image, saliency, 90.0).img
    @test fn(image, saliency, NaN).img == result.img
    @test fn(image, saliency, -5.0).img == fn(image, saliency, 0.0).img
    @test fn(image, saliency, 5000.0).img == fn(image, saliency, 1000.0).img
    @test fn(image, saliency, 90.0, :ignored).img == result.img

    automatic = fn(image)
    @test size(automatic) == size(image)
    @test eltype(automatic) == IntensityPixel{N0f8}
    @test automatic.img == fn(image, 90.0).img
    @test automatic.img == fn(image, 90.0, 0.95).img
    @test fn(image, NaN, NaN).img == automatic.img
    @test fn(image, -5.0, 0.1).img == fn(image, 0.0, 0.5).img
    @test fn(image, 5000.0, 1.2).img == fn(image, 1000.0, 0.99).img
    @test fn(image, 90.0, 0.95, :ignored).img == automatic.img

    module_under_test = UTCGP.image2D_foreground_extraction_continuous
    chain = zeros(1, 5)
    foreground_seeds = falses(1, 5)
    background_seeds = falses(1, 5)
    foreground_seeds[1, 5] = true
    background_seeds[1, 1] = true
    chain_probabilities = module_under_test._solve_random_walker(
        chain,
        foreground_seeds,
        background_seeds,
        0.0,
    )
    @test chain_probabilities ≈ reshape(collect(0.0:0.25:1.0), 1, 5) atol = 1.0e-10
    @test chain_probabilities[1, 1] == 0.0
    @test chain_probabilities[1, 5] == 1.0
    @test all(value -> 0.0 <= value <= 1.0, chain_probabilities)
    @test module_under_test._solve_random_walker(
        chain,
        falses(1, 5),
        background_seeds,
        90.0,
    ) == zeros(1, 5)
    @test module_under_test._solve_random_walker(
        chain,
        trues(1, 5),
        falses(1, 5),
        90.0,
    ) == ones(1, 5)
    @test_throws DimensionMismatch module_under_test._solve_random_walker(
        zeros(2, 2),
        falses(2, 3),
        falses(2, 2),
        90.0,
    )

    flat = _continuous_intensity(fill(0.4, 37, 53))
    flat_saliency = _continuous_intensity(fill(0.2, 37, 53))
    flat_fn = factory.fn(typeof(flat))
    @test all(iszero, reinterpret(flat_fn(flat).img))
    @test all(iszero, reinterpret(flat_fn(flat, flat_saliency).img))

    tiny_values = reshape([0.0, 1.0, 0.0, 0.0, 1.0, 0.0], 2, 3)
    tiny = _continuous_intensity(tiny_values)
    tiny_saliency = _continuous_intensity(tiny_values)
    tiny_fn = factory.fn(typeof(tiny))
    tiny_result = tiny_fn(tiny, tiny_saliency)
    @test size(tiny_result) == (2, 3)
    @test all(isfinite, _continuous_values(tiny_result))

    output_16 = _continuous_intensity(zeros(height, width), N0f16)
    fn_16 = factory.fn(typeof(output_16))
    result_16 = fn_16(image, saliency)
    @test size(result_16) == size(image)
    @test eltype(result_16) == IntensityPixel{N0f16}

    @test any(
        bundle -> bundle[:random_walker_foreground] !== nothing,
        get_extension_foreground_intensityimg(),
    )
    @test all(
        bundle -> bundle[:random_walker_foreground] === nothing,
        get_extension_binaryimg(),
    )

    rng = MersenneTwister(48)
    benchmark_values = rand(rng, 256, 256)
    benchmark_saliency_values = rand(rng, 256, 256)
    benchmark_image = _continuous_intensity(benchmark_values)
    benchmark_saliency = _continuous_intensity(benchmark_saliency_values)
    benchmark_fn = factory.fn(typeof(benchmark_image))
    benchmark_fn(benchmark_image, 1000.0, 0.99)
    benchmark_fn(benchmark_image, benchmark_saliency, 1000.0)
    automatic_elapsed = minimum(
        @elapsed benchmark_fn(benchmark_image, 1000.0, 0.99)
        for _ in 1:3
    )
    supplied_elapsed = minimum(
        @elapsed benchmark_fn(benchmark_image, benchmark_saliency, 1000.0)
        for _ in 1:3
    )
    @test automatic_elapsed <= 0.5
    @test supplied_elapsed <= 0.5
end

@testset "Image2D continuous foreground extraction: Closed-form matting" begin
    height, width = 64, 64
    gradient_values = repeat(
        reshape(collect(range(0.0, 1.0; length = width)), 1, :),
        height,
        1,
    )
    trimap_values = fill(0.5, height, width)
    trimap_values[:, 1:5] .= 0.0
    trimap_values[:, 60:64] .= 1.0

    image = _continuous_intensity(gradient_values)
    trimap = _continuous_intensity(trimap_values)
    output_example = _continuous_intensity(zeros(height, width))
    factory = bundle_image2DIntensity_foreground_extraction_factory[
        :closed_form_matting
    ]
    fn = factory.fn(typeof(output_example))

    @test which(fn, Tuple{typeof(image)}).nargs == 3
    @test which(fn, Tuple{typeof(image),Float64}).nargs == 4
    @test which(fn, Tuple{typeof(image),Float64,Float64}).nargs == 5
    @test which(fn, Tuple{typeof(image),typeof(trimap)}).nargs == 4
    @test which(fn, Tuple{typeof(image),typeof(trimap),Float64}).nargs == 5
    @test all(method -> method.nargs <= 5, methods(fn))

    image_before = copy(image.img)
    trimap_before = copy(trimap.img)
    alpha = fn(image, trimap)
    alpha_values = _continuous_values(alpha)

    @test size(alpha) == size(image)
    @test eltype(alpha) == IntensityPixel{N0f8}
    @test minimum(alpha_values) == 0.0
    @test maximum(alpha_values) == 1.0
    @test all(isfinite, alpha_values)
    @test count(value -> 0.0 < value < 1.0, alpha_values) > height * width ÷ 2
    @test all(iszero, alpha_values[:, 1:5])
    @test all(isone, alpha_values[:, 60:64])
    @test all(diff(alpha_values[height ÷ 2, :]) .>= -1 / 255)
    @test image.img == image_before
    @test trimap.img == trimap_before
    @test alpha.img == fn(image, trimap).img
    @test alpha.img == fn(image, trimap, 7.0).img
    @test fn(image, trimap, NaN).img == alpha.img
    @test fn(image, trimap, -10.0).img == fn(image, trimap, 2.0).img
    @test fn(image, trimap, 50.0).img == fn(image, trimap, 12.0).img
    @test fn(image, trimap, 7.0, :ignored).img == alpha.img

    object_values = fill(0.1, height, width)
    object_values[18:47, 20:45] .= 0.9
    object_image = _continuous_intensity(object_values)
    object_fn = factory.fn(typeof(object_image))
    automatic = object_fn(object_image)
    automatic_values = _continuous_values(automatic)
    @test size(automatic) == size(object_image)
    @test eltype(automatic) == IntensityPixel{N0f8}
    @test all(isfinite, automatic_values)
    @test minimum(automatic_values) >= 0.0
    @test maximum(automatic_values) <= 1.0
    @test automatic.img == object_fn(object_image, 7.0).img
    @test automatic.img == object_fn(object_image, 7.0, 0.95).img
    @test object_fn(object_image, NaN, NaN).img == automatic.img
    @test object_fn(object_image, -5.0, 0.1).img ==
          object_fn(object_image, 2.0, 0.5).img
    @test object_fn(object_image, 50.0, 1.2).img ==
          object_fn(object_image, 12.0, 0.99).img
    @test object_fn(object_image, 7.0, 0.95, :ignored).img == automatic.img

    @testset "Constant images use the empty-saliency branch" begin
        for level in (0.0, 0.5, 1.0)
            constant_image = _continuous_intensity(fill(level, height, width))
            constant_alpha = fn(constant_image)
            @test size(constant_alpha) == size(constant_image)
            @test eltype(constant_alpha) == IntensityPixel{N0f8}
            @test all(iszero, _continuous_values(constant_alpha))
            @test constant_alpha.img == fn(constant_image, 7.0, 0.95).img
        end
    end

    module_under_test = UTCGP.image2D_foreground_extraction_continuous
    raw_values = collect(reshape(range(0.0, 1.0; length = 35), 5, 7))
    raw_trimap = fill(0.5, 5, 7)
    raw_trimap[:, 1] .= 0.0
    raw_trimap[:, end] .= 1.0
    raw_alpha = module_under_test._solve_closed_form_matting(
        raw_values,
        raw_trimap,
        1.0e-7,
    )
    @test size(raw_alpha) == size(raw_values)
    @test all(iszero, raw_alpha[:, 1])
    @test all(isone, raw_alpha[:, end])
    @test any(value -> 0.0 < value < 1.0, raw_alpha)
    @test all(value -> isfinite(value) && 0.0 <= value <= 1.0, raw_alpha)
    @test_throws DimensionMismatch module_under_test._solve_closed_form_matting(
        zeros(2, 2),
        zeros(2, 3),
        1.0e-7,
    )

    all_unknown = fill(0.5, 5, 7)
    all_background = zeros(5, 7)
    all_foreground = ones(5, 7)
    @test module_under_test._closed_form_alpha(
        raw_values,
        all_unknown,
        7.0,
    ) == zeros(5, 7)
    @test module_under_test._closed_form_alpha(
        raw_values,
        all_background,
        7.0,
    ) == zeros(5, 7)
    @test module_under_test._closed_form_alpha(
        raw_values,
        all_foreground,
        7.0,
    ) == ones(5, 7)
    @test_throws DimensionMismatch module_under_test._closed_form_alpha(
        zeros(2, 2),
        zeros(2, 3),
        7.0,
    )

    threshold_trimap = fill(0.5, 5, 7)
    threshold_trimap[:, 1] .= 0.1
    threshold_trimap[:, end] .= 0.9
    threshold_foreground, threshold_background =
        module_under_test._closed_form_trimap_masks(threshold_trimap)
    @test all(threshold_background[:, 1])
    @test all(threshold_foreground[:, end])
    @test !any(threshold_foreground[:, 2:(end - 1)])
    @test !any(threshold_background[:, 2:(end - 1)])

    tiny_values = reshape([0.0, 0.25, 0.5, 0.75, 1.0], 1, 5)
    tiny_trimap_values = reshape([0.0, 0.5, 0.5, 0.5, 1.0], 1, 5)
    tiny = _continuous_intensity(tiny_values)
    tiny_trimap = _continuous_intensity(tiny_trimap_values)
    tiny_fn = factory.fn(typeof(tiny))
    tiny_alpha = _continuous_values(tiny_fn(tiny, tiny_trimap))
    @test size(tiny_alpha) == (1, 5)
    @test tiny_alpha[1, 1] == 0.0
    @test tiny_alpha[1, end] == 1.0
    @test all(isfinite, tiny_alpha)

    output_16 = _continuous_intensity(zeros(height, width), N0f16)
    fn_16 = factory.fn(typeof(output_16))
    alpha_16 = fn_16(image, trimap)
    @test size(alpha_16) == size(image)
    @test eltype(alpha_16) == IntensityPixel{N0f16}

    @test any(
        bundle -> bundle[:closed_form_matting] !== nothing,
        get_extension_foreground_intensityimg(),
    )
    @test all(
        bundle -> bundle[:closed_form_matting] === nothing,
        get_extension_binaryimg(),
    )

    @test module_under_test._closed_form_working_size(256, 256) == (96, 96)
    working_h, working_w =
        module_under_test._closed_form_working_size(200, 300)
    @test working_h * working_w <= 96 * 96

    rng = MersenneTwister(49)
    benchmark_values = rand(rng, 256, 256)
    benchmark_trimap_values = fill(0.5, 256, 256)
    benchmark_trimap_values[1:8, :] .= 0.0
    benchmark_trimap_values[end-7:end, :] .= 0.0
    benchmark_trimap_values[:, 1:8] .= 0.0
    benchmark_trimap_values[:, end-7:end] .= 0.0
    benchmark_trimap_values[104:152, 104:152] .= 1.0
    benchmark_image = _continuous_intensity(benchmark_values)
    benchmark_trimap = _continuous_intensity(benchmark_trimap_values)
    benchmark_fn = factory.fn(typeof(benchmark_image))
    benchmark_fn(benchmark_image, benchmark_trimap)
    benchmark_fn(benchmark_image)
    explicit_elapsed = minimum(
        @elapsed benchmark_fn(benchmark_image, benchmark_trimap)
        for _ in 1:3
    )
    automatic_elapsed = minimum(
        @elapsed benchmark_fn(benchmark_image)
        for _ in 1:3
    )
    @test explicit_elapsed <= 0.5
    @test automatic_elapsed <= 0.5
end

@testset "New vision bundle getters remain explicit" begin
    legacy_intensity = get_extension_intensityimg()
    legacy_binary = get_extension_binaryimg()

    @test length(legacy_intensity) == 3
    @test length(legacy_binary) == 2

    new_intensity_names = (
        :itti_koch_saliency,
        :spectral_residual_saliency,
        :random_walker_foreground,
        :closed_form_matting,
        :blob_extraction_largest,
        :blob_extraction_max_mean,
    )
    new_binary_names = (
        :boykov_jolly_foreground,
        :grabcut_foreground,
        :blob_extraction_largest_blob,
        :blob_extraction_size_between_blob,
    )
    @test all(
        name -> all(bundle -> bundle[name] === nothing, legacy_intensity),
        new_intensity_names,
    )
    @test all(
        name -> all(bundle -> bundle[name] === nothing, legacy_binary),
        new_binary_names,
    )

    saliency_bundles = get_extension_saliency_intensityimg()
    continuous_bundles = get_extension_foreground_intensityimg()
    discrete_bundles = get_extension_foreground_binaryimg()
    intensity_blob_bundles = get_extension_blob_intensityimg()
    binary_blob_bundles = get_extension_blob_binaryimg()

    @test length(saliency_bundles) == 1
    @test length(continuous_bundles) == 1
    @test length(discrete_bundles) == 1
    @test length(intensity_blob_bundles) == 1
    @test length(binary_blob_bundles) == 1

    @test saliency_bundles[1][:itti_koch_saliency] !== nothing
    @test continuous_bundles[1][:closed_form_matting] !== nothing
    @test discrete_bundles[1][:grabcut_foreground] !== nothing
    @test intensity_blob_bundles[1][:blob_extraction_max_mean] !== nothing
    @test binary_blob_bundles[1][:blob_extraction_largest_blob] !== nothing

    @test saliency_bundles[1] !== get_extension_saliency_intensityimg()[1]
    @test continuous_bundles[1] !== get_extension_foreground_intensityimg()[1]
    @test discrete_bundles[1] !== get_extension_foreground_binaryimg()[1]
    @test intensity_blob_bundles[1] !== get_extension_blob_intensityimg()[1]
    @test binary_blob_bundles[1] !== get_extension_blob_binaryimg()[1]
end
