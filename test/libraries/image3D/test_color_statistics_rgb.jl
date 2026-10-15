using Random

function _rgb_test_image(red, green, blue, ::Type{T}=N0f8) where {T}
    @assert size(red) == size(green) == size(blue)
    values = cat(Float64.(red), Float64.(green), Float64.(blue); dims = 3)
    return SImageND(IntensityPixel{T}.(values))
end

@testset "RGB SImage3D and color statistics" begin
    red = [1.0 0.0 0.5; 0.0 0.2 0.0]
    green = [0.0 1.0 0.5; 0.0 0.4 0.0]
    blue = [0.0 0.0 0.5; 1.0 0.8 0.0]
    rgb = _rgb_test_image(red, green, blue)
    original = copy(rgb.img)
    output_type = typeof(SImageND(IntensityPixel{N0f8}.(zeros(2, 3))))

    @test rgb isa SImage3D{2,3,3,IntensityPixel{N0f8}}
    @test rgb isa SizedImage3D{2,3,3,IntensityPixel{N0f8}}
    @test size(rgb) == (2, 3, 3)

    bundle = bundle_image2DIntensity_color_statistics_rgb_factory
    @test length(bundle) == 7
    expected_names = Set([
        :rgb_luminance,
        :red_green_opponency,
        :blue_yellow_opponency,
        :rgb_saturation,
        :normalized_red,
        :normalized_green,
        :normalized_blue,
    ])
    @test Set(wrapper.name for wrapper in bundle) == expected_names

    results = Dict{Symbol,Any}()
    for wrapper in bundle
        fn = wrapper.fn(output_type)
        @test hasmethod(fn, Tuple{typeof(rgb)})
        result = fn(rgb)
        results[wrapper.name] = Float64.(reinterpret(result.img))
        @test size(result) == (2, 3)
        @test eltype(result) == IntensityPixel{N0f8}
        @test all(isfinite, results[wrapper.name])
        @test all(0.0 .<= results[wrapper.name] .<= 1.0)
        @test fn(rgb, :ignored).img == result.img
    end

    quantization_tolerance = 1 / 255 + eps(Float64)
    @test results[:rgb_luminance][1, 1] ≈ 0.2126 atol = quantization_tolerance
    @test results[:rgb_luminance][1, 2] ≈ 0.7152 atol = quantization_tolerance
    @test results[:red_green_opponency][1, 1] ≈ 1.0 atol = quantization_tolerance
    @test results[:red_green_opponency][1, 2] ≈ 0.0 atol = quantization_tolerance
    @test results[:red_green_opponency][1, 3] ≈ 0.5 atol = quantization_tolerance
    @test results[:blue_yellow_opponency][2, 1] ≈ 1.0 atol = quantization_tolerance
    @test results[:rgb_saturation][1, 3] ≈ 0.0 atol = quantization_tolerance
    @test results[:rgb_saturation][2, 2] ≈ 0.6 atol = 2quantization_tolerance
    @test results[:normalized_red][1, 1] ≈ 1.0 atol = quantization_tolerance
    @test results[:normalized_green][1, 2] ≈ 1.0 atol = quantization_tolerance
    @test results[:normalized_blue][2, 1] ≈ 1.0 atol = quantization_tolerance
    @test results[:normalized_red][2, 3] == 0.0
    @test rgb.img == original

    output16 = SImageND(IntensityPixel{N0f16}.(zeros(2, 3)))
    result16 = bundle[:rgb_luminance].fn(typeof(output16))(rgb)
    @test eltype(result16) == IntensityPixel{N0f16}
    @test size(result16) == (2, 3)

    wrong_depth = SImageND(IntensityPixel{N0f8}.(zeros(2, 3, 4)))
    luminance = bundle[:rgb_luminance].fn(output_type)
    @test !hasmethod(luminance, Tuple{typeof(wrong_depth)})

    fresh = get_extension_color_statistics_rgb_intensityimg()
    @test length(fresh) == 1
    @test fresh[1] !== bundle
    @test fresh[1][:rgb_luminance] !== bundle[:rgb_luminance]

    rng = MersenneTwister(88)
    benchmark_rgb = _rgb_test_image(rand(rng, 256, 256), rand(rng, 256, 256), rand(rng, 256, 256))
    benchmark_output = typeof(SImageND(IntensityPixel{N0f8}.(zeros(256, 256))))
    for wrapper in bundle
        fn = wrapper.fn(benchmark_output)
        fn(benchmark_rgb)
        elapsed = minimum(@elapsed(fn(benchmark_rgb)) for _ in 1:3)
        @test elapsed <= 0.5
    end
end

@testset "RGB arithmetic" begin
    rgb1 = _rgb_test_image(
        [0.8 0.1; 0.4 1.0],
        [0.2 0.9; 0.4 0.0],
        [0.5 0.3; 0.1 0.7],
    )
    rgb2 = _rgb_test_image(
        [0.4 0.3; 0.8 0.2],
        [0.9 0.2; 0.4 0.6],
        [0.5 0.8; 0.3 0.1],
    )
    original1 = copy(rgb1.img)
    original2 = copy(rgb2.img)
    left = Float64.(reinterpret(rgb1.img))
    right = Float64.(reinterpret(rgb2.img))
    bundle = bundle_image3DIntensity_rgb_factory
    operations = Dict(
        :add_img3D => +,
        :subtract_img3D => -,
        :mult_img3D => *,
        :max_img3D => max,
        :min_img3D => min,
    )

    @test length(bundle) == 19
    @test bundle[1].name == :identity_rgb
    @test bundle[2].name == :return_rgb
    @test Set(wrapper.name for wrapper in bundle) == union(
        Set(keys(operations)),
        Set([
            :identity_rgb,
            :return_rgb,
            :invert_rgb,
            :grayscale_rgb,
            :keep_red_rgb,
            :keep_green_rgb,
            :keep_blue_rgb,
            :rotate_channels_left_rgb,
            :rotate_channels_right_rgb,
            :adjust_brightness_rgb,
            :adjust_contrast_rgb,
            :adjust_saturation_rgb,
            :adjust_gamma_rgb,
            :mult_image3D,
        ]),
    )

    for (name, operation) in operations
        fn = bundle[name].fn(typeof(rgb1))
        @test hasmethod(fn, Tuple{typeof(rgb1),typeof(rgb2)})
        result = fn(rgb1, rgb2)
        expected = clamp.(operation.(left, right), 0.0, 1.0)
        @test result isa typeof(rgb1)
        @test size(result) == (2, 2, 3)
        @test reinterpret(result.img) == N0f8.(expected)
        @test fn(rgb1, rgb2, :ignored).img == result.img
    end

    wrong_size = _rgb_test_image(zeros(3, 2), zeros(3, 2), zeros(3, 2))
    add_rgb = bundle[:add_img3D].fn(typeof(rgb1))
    @test !hasmethod(add_rgb, Tuple{typeof(rgb1),typeof(wrong_size)})
    @test rgb1.img == original1
    @test rgb2.img == original2

    rgb16 = _rgb_test_image(fill(0.2, 2, 2), fill(0.3, 2, 2), fill(0.4, 2, 2), N0f16)
    result16 = bundle[:add_img3D].fn(typeof(rgb16))(rgb16, rgb16)
    @test result16 isa typeof(rgb16)
    @test eltype(result16) == IntensityPixel{N0f16}

    rng = MersenneTwister(89)
    benchmark1 = _rgb_test_image(
        rand(rng, 256, 256), rand(rng, 256, 256), rand(rng, 256, 256),
    )
    benchmark2 = _rgb_test_image(
        rand(rng, 256, 256), rand(rng, 256, 256), rand(rng, 256, 256),
    )
    for name in keys(operations)
        fn = bundle[name].fn(typeof(benchmark1))
        fn(benchmark1, benchmark2)
        elapsed = minimum(@elapsed(fn(benchmark1, benchmark2)) for _ in 1:3)
        @test elapsed <= 0.5
    end
end

@testset "RGB basic leading-function convention" begin
    rgb = _rgb_test_image(
        [0.8 0.1; 0.4 1.0],
        [0.2 0.9; 0.4 0.0],
        [0.5 0.3; 0.1 0.7],
    )
    bundle = bundle_image3DIntensity_rgb_factory

    identity_fn = bundle[1].fn(typeof(rgb))
    @test hasmethod(identity_fn, Tuple{typeof(rgb)})
    @test identity_fn(rgb) === rgb
    @test identity_fn(rgb, :ignored) === rgb

    return_fn = bundle[2].fn(typeof(rgb))
    @test hasmethod(return_fn, Tuple{})
    returned = return_fn()
    @test returned isa typeof(rgb)
    @test size(returned) == (2, 2, 3)
    @test all(isone, reinterpret(returned.img))
    @test return_fn(:ignored).img == returned.img

    rgb16 = _rgb_test_image(fill(0.2, 2, 2), fill(0.3, 2, 2), fill(0.4, 2, 2), N0f16)
    returned16 = bundle[:return_rgb].fn(typeof(rgb16))()
    @test returned16 isa typeof(rgb16)
    @test eltype(returned16) == IntensityPixel{N0f16}
    @test all(isone, reinterpret(returned16.img))

    fresh_bundle = only(get_extension_rgbimg())
    @test fresh_bundle[1].name == :identity_rgb
    @test fresh_bundle[2].name == :return_rgb
end

@testset "Unary RGB transforms" begin
    rgb = _rgb_test_image(
        [0.8 0.1; 0.4 1.0],
        [0.2 0.9; 0.4 0.0],
        [0.5 0.3; 0.1 0.7],
    )
    original = copy(rgb.img)
    source = Float64.(reinterpret(rgb.img))
    luminance = 0.2126 .* source[:, :, 1] .+
        0.7152 .* source[:, :, 2] .+
        0.0722 .* source[:, :, 3]
    expected = Dict(
        :invert_rgb => 1.0 .- source,
        :grayscale_rgb => cat(luminance, luminance, luminance; dims = 3),
        :keep_red_rgb => cat(source[:, :, 1], zeros(2, 2), zeros(2, 2); dims = 3),
        :keep_green_rgb => cat(zeros(2, 2), source[:, :, 2], zeros(2, 2); dims = 3),
        :keep_blue_rgb => cat(zeros(2, 2), zeros(2, 2), source[:, :, 3]; dims = 3),
        :rotate_channels_left_rgb => cat(
            source[:, :, 2], source[:, :, 3], source[:, :, 1]; dims = 3,
        ),
        :rotate_channels_right_rgb => cat(
            source[:, :, 3], source[:, :, 1], source[:, :, 2]; dims = 3,
        ),
    )
    bundle = bundle_image3DIntensity_rgb_factory

    for (name, expected_values) in expected
        fn = bundle[name].fn(typeof(rgb))
        @test hasmethod(fn, Tuple{typeof(rgb)})
        result = fn(rgb)
        @test result isa typeof(rgb)
        @test size(result) == size(rgb)
        @test reinterpret(result.img) == N0f8.(expected_values)
        @test fn(rgb, :ignored).img == result.img
    end
    @test rgb.img == original
end

@testset "Parameterized RGB adjustments" begin
    rgb = _rgb_test_image(
        [0.8 0.1; 0.4 1.0],
        [0.2 0.9; 0.4 0.0],
        [0.5 0.3; 0.1 0.7],
    )
    original = copy(rgb.img)
    source = Float64.(reinterpret(rgb.img))
    bundle = bundle_image3DIntensity_rgb_factory

    brightness = bundle[:adjust_brightness_rgb].fn(typeof(rgb))
    @test reinterpret(brightness(rgb, 0.2).img) == N0f8.(clamp.(source .+ 0.2, 0.0, 1.0))
    @test all(isone, reinterpret(brightness(rgb, 2.0).img))
    @test all(iszero, reinterpret(brightness(rgb, -2.0).img))
    @test brightness(rgb, Inf).img == rgb.img

    contrast = bundle[:adjust_contrast_rgb].fn(typeof(rgb))
    @test all(reinterpret(contrast(rgb, 0.0).img) .== N0f8(0.5))
    @test contrast(rgb, 1.0).img == rgb.img
    @test contrast(rgb, NaN).img == rgb.img

    saturation = bundle[:adjust_saturation_rgb].fn(typeof(rgb))
    grayscale = Float64.(reinterpret(saturation(rgb, 0.0).img))
    @test grayscale[:, :, 1] == grayscale[:, :, 2] == grayscale[:, :, 3]
    @test saturation(rgb, 1.0).img == rgb.img
    @test saturation(rgb, -10.0).img == saturation(rgb, 0.0).img
    @test saturation(rgb, Inf).img == rgb.img

    gamma = bundle[:adjust_gamma_rgb].fn(typeof(rgb))
    @test reinterpret(gamma(rgb, 2.0).img) == N0f8.(source .^ 2.0)
    @test gamma(rgb, 1.0).img == rgb.img
    @test gamma(rgb, NaN).img == rgb.img

    for name in (
            :adjust_brightness_rgb,
            :adjust_contrast_rgb,
            :adjust_saturation_rgb,
            :adjust_gamma_rgb,
        )
        fn = bundle[name].fn(typeof(rgb))
        @test hasmethod(fn, Tuple{typeof(rgb),Float64})
        @test fn(rgb, 0.5, :ignored) isa typeof(rgb)
        @test !hasmethod(fn, Tuple{typeof(rgb),String})
    end
    @test rgb.img == original

    rng = MersenneTwister(90)
    benchmark = _rgb_test_image(
        rand(rng, 256, 256), rand(rng, 256, 256), rand(rng, 256, 256),
    )
    for name in keys(Dict(
            :invert_rgb => nothing,
            :grayscale_rgb => nothing,
            :keep_red_rgb => nothing,
            :keep_green_rgb => nothing,
            :keep_blue_rgb => nothing,
            :rotate_channels_left_rgb => nothing,
            :rotate_channels_right_rgb => nothing,
        ))
        fn = bundle[name].fn(typeof(benchmark))
        fn(benchmark)
        @test minimum(@elapsed(fn(benchmark)) for _ in 1:3) <= 0.5
    end
    for name in (
            :adjust_brightness_rgb,
            :adjust_contrast_rgb,
            :adjust_saturation_rgb,
            :adjust_gamma_rgb,
        )
        fn = bundle[name].fn(typeof(benchmark))
        fn(benchmark, 0.5)
        @test minimum(@elapsed(fn(benchmark, 0.5)) for _ in 1:3) <= 0.5
    end
end

@testset "RGB masking" begin
    red = [1.0 0.2 0.3; 0.4 0.5 0.6]
    green = [0.1 1.0 0.3; 0.4 0.5 0.6]
    blue = [0.1 0.2 1.0; 0.4 0.5 0.6]
    rgb = _rgb_test_image(red, green, blue)
    original = copy(rgb.img)
    mask_values = Bool[true false true; false true false]
    mask = SImageND(BinaryPixel{Bool}.(mask_values))
    bundle = bundle_image3DIntensity_rgb_factory
    fn = bundle[:mult_image3D].fn(typeof(rgb))

    @test hasmethod(fn, Tuple{typeof(rgb),typeof(mask)})
    result = fn(rgb, mask)
    @test result isa typeof(rgb)
    @test size(result) == (2, 3, 3)
    result_values = Float64.(reinterpret(result.img))
    source_values = Float64.(reinterpret(rgb.img))
    for channel in 1:3
        @test result_values[:, :, channel] ≈ source_values[:, :, channel] .* mask_values
    end
    @test fn(rgb, mask, :ignored).img == result.img
    @test rgb.img == original

    black_mask = SImageND(BinaryPixel{Bool}.(falses(2, 3)))
    black_result = fn(rgb, black_mask)
    @test black_result isa typeof(rgb)
    @test size(black_result) == size(rgb)
    @test all(iszero, reinterpret(black_result.img))

    white_mask = SImageND(BinaryPixel{Bool}.(trues(2, 3)))
    @test fn(rgb, white_mask).img == rgb.img

    wrong_mask = SImageND(BinaryPixel{Bool}.(trues(3, 2)))
    @test !hasmethod(fn, Tuple{typeof(rgb),typeof(wrong_mask)})

    fresh = get_extension_rgbimg()
    @test length(fresh) == 1
    @test fresh[1] !== bundle
    @test fresh[1][:mult_image3D] !== bundle[:mult_image3D]
end

@testset "Dimension-generic image reducers accept RGB" begin
    red = [1.0 0.0; 0.0 0.0]
    rgb = _rgb_test_image(red, zeros(2, 2), zeros(2, 2))
    bundle = bundle_number_reduceFromImg

    @test bundle[:reduce_length].fn(rgb) == 12
    @test bundle[:reduce_biggestAxis].fn(rgb) == 3
    @test bundle[:reduce_smallerAxis].fn(rgb) == 2
    @test bundle[:reduce_mean].fn(rgb) ≈ mean(float(rgb))
    @test bundle[:reduce_median].fn(rgb) ≈ median(float(rgb))
    @test bundle[:reduce_std].fn(rgb) ≈ std(float(rgb))
    @test bundle[:reduce_maximum].fn(rgb) == 1.0
    @test bundle[:reduce_minimum].fn(rgb) == 0.0
    @test bundle[:reduce_nColors].fn(rgb) == 2.0
    @test bundle[:reduce_histMode].fn(rgb) == 0.0
    @test bundle[:reduce_histModeCount].fn(rgb) == 11.0

    @test bundle_number_coordinatesFromImg[:experimental_vertical_argmax].fn(rgb) == 1.0
    @test bundle_number_coordinatesFromImg[:experimental_horizontal_argmax].fn(rgb) == 1.0
    @test bundle_number_relativeCoordinatesFromImg[:experimental_vertical_relative_argmax].fn(rgb) == 0.5
    @test bundle_number_relativeCoordinatesFromImg[:experimental_horizontal_relative_argmax].fn(rgb) == 0.5
end

@testset "2D-only image-to-scalar bundles reject RGB" begin
    rgb = _rgb_test_image(ones(4, 5), zeros(4, 5), zeros(4, 5))

    for wrapper in bundle_number_regionFromImg
        @test !hasmethod(wrapper.fn, Tuple{typeof(rgb),Float64,Float64})
    end
    for wrapper in bundle_number_haarFromImg
        @test !hasmethod(wrapper.fn, Tuple{typeof(rgb),Float64,Float64})
    end
    for wrapper in bundle_float_orientation
        @test !hasmethod(wrapper.fn, Tuple{typeof(rgb)})
    end
    for wrapper in experimental_bundle_float_glcm_factory
        @test !hasmethod(wrapper.fn, Tuple{typeof(rgb)})
    end
    for wrapper in bundle_float_imagegraph
        @test !hasmethod(wrapper.fn, Tuple{typeof(rgb)})
    end
end
