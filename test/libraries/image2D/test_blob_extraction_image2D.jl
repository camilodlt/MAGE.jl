using Random

_blob_intensity(values, ::Type{T} = N0f8) where {T} =
    SImageND(IntensityPixel{T}.(clamp.(Float64.(values), 0.0, 1.0)))
_blob_binary(values) = SImageND(BinaryPixel.(Bool.(values)))
_blob_bits(image) = Bool.(reinterpret(image.img))

function _masked_expected(image, mask)
    values = copy(reinterpret(image.img))
    values[.!mask] .= zero(eltype(values))
    return values
end

@testset "Image2D blob extraction" begin
    height, width = 10, 12
    blob_a = falses(height, width)
    blob_b = falses(height, width)
    blob_c = falses(height, width)
    blob_d = falses(height, width)
    blob_e = falses(height, width)
    blob_a[1:2, 1:2] .= true
    blob_b[1:3, 6:9] .= true
    blob_c[6:10, 2] .= true
    blob_d[8, 7:11] .= true
    blob_e[5, 12] = true

    main_mask_values = blob_a .| blob_b .| blob_c .| blob_d
    all_mask_values = main_mask_values .| blob_e
    main_mask = _blob_binary(main_mask_values)
    all_mask = _blob_binary(all_mask_values)

    saliency_values = zeros(Float64, height, width)
    saliency_values[main_mask_values] .= 0.8
    saliency_values[blob_e] .= 0.4
    saliency = _blob_intensity(saliency_values, N0f8)

    source_values = fill(0.05, height, width)
    source_values[blob_a] .= 0.1
    source_values[blob_b] .= 0.7
    source_values[blob_c] .= [0.2, 0.4, 0.6, 0.8, 1.0]
    source_values[blob_d] .= [0.3, 0.4, 0.5, 0.6, 0.7]
    source_values[blob_e] .= 0.9
    source = _blob_intensity(source_values, N0f16)

    binary_output_type = typeof(_blob_binary(falses(height, width)))
    intensity_output_type = typeof(source)
    binary_functions = Dict(
        wrapper.name => wrapper.fn(binary_output_type)
        for wrapper in bundle_image2DBinary_blob_extraction_factory
    )
    intensity_functions = Dict(
        wrapper.name => wrapper.fn(intensity_output_type)
        for wrapper in bundle_image2DIntensity_blob_extraction_factory
    )

    @test length(binary_functions) == 17
    @test length(intensity_functions) == 16
    @test all(fn -> all(method -> method.nargs <= 5, methods(fn)), values(binary_functions))
    @test all(fn -> all(method -> method.nargs <= 5, methods(fn)), values(intensity_functions))

    expected_geometry = Dict(
        :largest => blob_b,
        :smallest => blob_a,
        :longest_horizontally => blob_d,
        :shortest_horizontally => blob_c,
        :longest_vertically => blob_c,
        :shortest_vertically => blob_d,
    )
    for (selector, expected) in expected_geometry
        binary_fn = binary_functions[Symbol(:blob_extraction_, selector, :_blob)]
        intensity_fn = intensity_functions[Symbol(:blob_extraction_, selector)]

        binary_result = binary_fn(saliency)
        intensity_result = intensity_fn(source, saliency)
        @test size(binary_result) == (height, width)
        @test eltype(binary_result) == BinaryPixel{Bool}
        @test _blob_bits(binary_result) == expected
        @test size(intensity_result) == (height, width)
        @test eltype(intensity_result) == IntensityPixel{N0f16}
        @test reinterpret(intensity_result.img) == _masked_expected(source, expected)

        @test _blob_bits(binary_fn(all_mask, 2)) == expected
        @test reinterpret(intensity_fn(source, all_mask, 2).img) ==
              _masked_expected(source, expected)
    end

    smallest_blob = binary_functions[:blob_extraction_smallest_blob]
    smallest_image = intensity_functions[:blob_extraction_smallest]
    @test _blob_bits(smallest_blob(saliency, 0.3)) == blob_e
    @test _blob_bits(smallest_blob(saliency, 0.3, 2)) == blob_a
    @test _blob_bits(smallest_blob(saliency, NaN)) == blob_a
    @test _blob_bits(smallest_blob(all_mask)) == blob_e
    @test _blob_bits(smallest_blob(all_mask, 2)) == blob_a
    @test reinterpret(smallest_image(source, saliency, 0.3).img) ==
          _masked_expected(source, blob_e)
    @test reinterpret(smallest_image(source, all_mask).img) ==
          _masked_expected(source, blob_e)
    @test reinterpret(smallest_image(source, all_mask, 2).img) ==
          _masked_expected(source, blob_a)

    area_between = binary_functions[:blob_extraction_size_between_blob]
    expected_between = blob_a .| blob_c .| blob_d
    @test _blob_bits(area_between(all_mask, 4, 5)) == expected_between
    @test _blob_bits(area_between(all_mask, 5, 4)) == expected_between
    @test _blob_bits(area_between(saliency, 4, 5)) == expected_between
    @test _blob_bits(area_between(all_mask)) == all_mask_values

    expected_statistics = Dict(
        :max_mean => blob_b,
        :max_median => blob_b,
        :max_std => blob_c,
        :max_max => blob_c,
        :max_min => blob_b,
        :min_mean => blob_a,
        :min_median => blob_a,
        :min_std => blob_a,
        :min_max => blob_a,
        :min_min => blob_a,
    )
    for (selector, expected) in expected_statistics
        binary_fn = binary_functions[Symbol(:blob_extraction_, selector, :_blob)]
        intensity_fn = intensity_functions[Symbol(:blob_extraction_, selector)]

        binary_result = binary_fn(source, saliency)
        intensity_result = intensity_fn(source, saliency)
        @test eltype(binary_result) == BinaryPixel{Bool}
        @test eltype(intensity_result) == IntensityPixel{N0f16}
        @test size(binary_result) == size(source)
        @test size(intensity_result) == size(source)
        @test _blob_bits(binary_result) == expected
        @test reinterpret(intensity_result.img) == _masked_expected(source, expected)
        @test _blob_bits(binary_fn(source, main_mask)) == expected
        @test reinterpret(intensity_fn(source, main_mask).img) ==
              _masked_expected(source, expected)
    end

    empty_mask = _blob_binary(falses(height, width))
    empty_saliency = _blob_intensity(zeros(height, width), N0f8)
    largest_blob = binary_functions[:blob_extraction_largest_blob]
    largest_image = intensity_functions[:blob_extraction_largest]
    max_mean_blob = binary_functions[:blob_extraction_max_mean_blob]
    @test all(iszero, reinterpret(largest_blob(empty_mask).img))
    @test all(iszero, reinterpret(largest_blob(empty_saliency).img))
    @test all(iszero, reinterpret(largest_image(source, empty_mask).img))
    @test all(iszero, reinterpret(max_mean_blob(source, empty_mask).img))

    diagonal = falses(height, width)
    diagonal[2, 2] = true
    diagonal[3, 3] = true
    @test _blob_bits(largest_blob(_blob_binary(diagonal))) == diagonal

    tie_mask_values = falses(height, width)
    tie_first = falses(height, width)
    tie_second = falses(height, width)
    tie_first[1:2, 1:2] .= true
    tie_second[1:2, 9:10] .= true
    tie_mask_values .= tie_first .| tie_second
    @test _blob_bits(largest_blob(_blob_binary(tie_mask_values))) == tie_first

    source_before = copy(source.img)
    saliency_before = copy(saliency.img)
    all_mask_before = copy(all_mask.img)
    largest_image(source, saliency)
    largest_blob(all_mask)
    @test source.img == source_before
    @test saliency.img == saliency_before
    @test all_mask.img == all_mask_before

    @test any(
        bundle -> bundle[:blob_extraction_largest] !== nothing,
        get_extension_blob_intensityimg(),
    )
    @test any(
        bundle -> bundle[:blob_extraction_largest_blob] !== nothing,
        get_extension_blob_binaryimg(),
    )
    @test all(
        wrapper -> !endswith(String(wrapper.name), "_blob"),
        bundle_image2DIntensity_blob_extraction_factory,
    )
    @test all(
        wrapper -> endswith(String(wrapper.name), "_blob"),
        bundle_image2DBinary_blob_extraction_factory,
    )

    rng = MersenneTwister(44)
    benchmark_values = rand(rng, 256, 256)
    benchmark_source = _blob_intensity(benchmark_values, N0f8)
    many_blob_values = falses(256, 256)
    many_blob_values[1:3:end, 1:3:end] .= true
    many_blobs = _blob_binary(many_blob_values)
    benchmark_binary_type = typeof(_blob_binary(falses(256, 256)))
    benchmark_largest = bundle_image2DBinary_blob_extraction_factory[
        :blob_extraction_largest_blob
    ].fn(benchmark_binary_type)
    benchmark_median = bundle_image2DBinary_blob_extraction_factory[
        :blob_extraction_max_median_blob
    ].fn(benchmark_binary_type)
    benchmark_largest(many_blobs)
    benchmark_median(benchmark_source, many_blobs)
    geometry_elapsed = minimum(@elapsed benchmark_largest(many_blobs) for _ in 1:3)
    statistic_elapsed =
        minimum(@elapsed benchmark_median(benchmark_source, many_blobs) for _ in 1:3)
    @test geometry_elapsed <= 0.5
    @test statistic_elapsed <= 0.5
end
