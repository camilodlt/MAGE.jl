@testset "Spatial RGB bundle contract" begin
    bundle = bundle_image3DIntensity_spatial_rgb_factory
    expected_names = Set([
        :sobel_magnitude_rgb,
        :laplacian_magnitude_rgb,
        :gaussian_blur_rgb,
        :difference_of_gaussians_rgb,
        :unsharp_mask_rgb,
        :local_contrast_normalize_rgb,
        :local_std_rgb,
        :gabor_energy_rgb,
    ])
    @test length(bundle) == 8
    @test Set(wrapper.name for wrapper in bundle) == expected_names
    @test bundle[:identity_rgb] === nothing
    @test bundle[:return_rgb] === nothing

    fresh = get_extension_spatial_rgbimg()
    @test length(fresh) == 1
    @test fresh[1] !== bundle
    @test fresh[1][:sobel_magnitude_rgb] !== bundle[:sobel_magnitude_rgb]

    basic = only(get_extension_rgbimg())
    @test basic[1].name == :identity_rgb
    @test basic[2].name == :return_rgb
    combined_names = [wrapper.name for b in (basic, only(fresh)) for wrapper in b]
    @test combined_names[1:2] == [:identity_rgb, :return_rgb]
    @test Set(combined_names[20:end]) == expected_names

    image2d = SImageND(IntensityPixel{N0f8}.(zeros(8, 8)))
    for wrapper in bundle
        @test_throws MethodError (@test_factory wrapper.fn(typeof(image2d)))
    end

    rgb = _rgb_test_image(
        fill(0.2, 8, 8), fill(0.4, 8, 8), fill(0.6, 8, 8),
    )
    specialized_bundles = [
        get_extension_rgbimg()...,
        get_extension_spatial_rgbimg()...,
    ]
    for factory_bundle in specialized_bundles
        for (index, wrapper) in enumerate(factory_bundle)
            specialized = (@test_factory wrapper.fn(typeof(rgb)))
            factory_bundle.functions[index] = FunctionWrapper(
                specialized,
                wrapper.name,
                wrapper.caster,
                wrapper.fallback;
                description = wrapper.description,
            )
        end
    end
    library = Library(specialized_bundles)
    meta_library = MetaLibrary([library])
    @test length(meta_library.libraries) == 1
    @test library[1].name == :identity_rgb
    @test library[2].name == :return_rgb
    @test length(library) == 27
    @test library[:sobel_magnitude_rgb].fn(rgb) isa typeof(rgb)
end

@testset "Spatial RGB values, arities, and typing" begin
    height, width = 16, 16
    constant = _rgb_test_image(
        fill(0.25, height, width),
        fill(0.5, height, width),
        fill(0.75, height, width),
    )
    edge_values = zeros(height, width)
    edge_values[:, 9:end] .= 1.0
    edge = _rgb_test_image(edge_values, reverse(edge_values; dims = 2), edge_values)
    impulse_values = zeros(height, width)
    impulse_values[8, 8] = 1.0
    impulse = _rgb_test_image(impulse_values, impulse_values, impulse_values)
    original_edge = copy(edge.img)
    bundle = bundle_image3DIntensity_spatial_rgb_factory

    calls = Dict{Symbol,Tuple}(
        :sobel_magnitude_rgb => (edge,),
        :laplacian_magnitude_rgb => (impulse,),
        :gaussian_blur_rgb => (edge, 1.2),
        :difference_of_gaussians_rgb => (impulse, 0.7, 1.5),
        :unsharp_mask_rgb => (edge, 1.0, 1.0),
        :local_contrast_normalize_rgb => (edge, 2.0),
        :local_std_rgb => (edge, 2.0),
        :gabor_energy_rgb => (edge, π / 4, 4.0),
    )
    for (name, arguments) in calls
        fn = (@test_factory bundle[name].fn(typeof(edge)))
        @test hasmethod(fn, Tuple{map(typeof, arguments)...})
        result = fn(arguments...)
        values = Float64.(reinterpret(result.img))
        @test result isa typeof(edge)
        @test size(result) == (height, width, 3)
        @test all(isfinite, values)
        @test all(0.0 .<= values .<= 1.0)
        @test fn(arguments..., :ignored).img == result.img
    end
    @test edge.img == original_edge

    sobel = (@test_factory bundle[:sobel_magnitude_rgb].fn(typeof(constant)))
    laplacian = (@test_factory bundle[:laplacian_magnitude_rgb].fn(typeof(constant)))
    gaussian = (@test_factory bundle[:gaussian_blur_rgb].fn(typeof(constant)))
    dog = (@test_factory bundle[:difference_of_gaussians_rgb].fn(typeof(constant)))
    unsharp = (@test_factory bundle[:unsharp_mask_rgb].fn(typeof(constant)))
    local_contrast = (@test_factory bundle[:local_contrast_normalize_rgb].fn(typeof(constant)))
    local_std = (@test_factory bundle[:local_std_rgb].fn(typeof(constant)))
    gabor = (@test_factory bundle[:gabor_energy_rgb].fn(typeof(constant)))

    @test all(iszero, reinterpret(sobel(constant).img))
    @test all(iszero, reinterpret(laplacian(constant).img))
    @test gaussian(constant, 1.0).img == constant.img
    @test all(iszero, reinterpret(dog(constant, 1.0, 1.0).img))
    @test unsharp(constant, 1.0, 0.0).img == constant.img
    @test all(reinterpret(local_contrast(constant, 3.0).img) .== N0f8(0.5))
    @test all(iszero, reinterpret(local_std(constant, 3.0).img))
    @test all(iszero, reinterpret(gabor(constant, 0.0, 4.0).img))

    @test maximum(reinterpret(sobel(edge).img)) == one(N0f8)
    @test maximum(reinterpret(laplacian(impulse).img)) == one(N0f8)
    @test maximum(reinterpret(dog(impulse, 0.7, 1.5).img)) == one(N0f8)
    @test maximum(reinterpret(local_std(edge, 2.0).img)) == one(N0f8)
    @test maximum(reinterpret(gabor(edge, 0.0, 4.0).img)) == one(N0f8)

    constant16 = _rgb_test_image(
        fill(0.25, height, width),
        fill(0.5, height, width),
        fill(0.75, height, width),
        N0f16,
    )
    result16 = (@test_factory bundle[:gaussian_blur_rgb].fn(typeof(constant16)))(constant16, 1.0)
    @test result16 isa typeof(constant16)
    @test eltype(result16) == IntensityPixel{N0f16}
end

# Called from top level after factory creation, so inference checks see the
# generated operator's methods without changing production dispatch.
function _check_constant_rgb_contrast(fn, image, ::Type{T}) where {T}
    destination = deepcopy(image)
    for radius in (1.0, 3.0, 5.0)
        result = @inferred fn(image, radius)
        @test all(==(T(0.5)), reinterpret(result.img))
        @test (@inferred fn(image, radius; out = destination)) === destination
        @test destination.img == result.img
    end
end

# Create operators at top level before the test block, so their methods are
# visible to direct calls and @inferred on Julia 1.12.
const _constant_rgb_contrast_cases = map((N0f8, N0f16, Float32, Float64)) do T
    image = _rgb_test_image(fill(0.1, 13, 17), fill(0.5, 13, 17), fill(0.9, 13, 17), T)
    fn = bundle_image3DIntensity_spatial_rgb_factory[:local_contrast_normalize_rgb].fn(typeof(image))
    (fn, image, T)
end

@testset "Constant RGB contrast is exactly neutral" begin
    spatial = MAGE.image3D_spatial_rgb
    # Test the working result as well as stored pixels: a quantized comparison
    # alone could hide residuals on one side of the rounding boundary.
    for value in (0.0, 0.1, 0.25, 0.5, 0.75, 1.0), radius in (1.0, 3.0, 5.0)
        source = fill(value, 13, 17, 3)
        result = similar(source)
        @test spatial._local_contrast_normalize!(result, source, radius) === result
        @test all(==(0.5), result)
    end
    for (fn, image, T) in _constant_rgb_contrast_cases
        _check_constant_rgb_contrast(fn, image, T)
    end

    # Flat channels may coexist with textured channels. Preserve the original
    # local-moments calculation on every nonconstant channel, even tiny contrast.
    source = fill(0.25, 13, 17, 3)
    source[7, 9, 2] += 1e-10
    source[:, 9:end, 3] .= 0.75
    original = copy(source)
    for radius in (1, 3, 5)
        result = similar(source)
        spatial._local_contrast_normalize!(result, source, radius)
        @test all(==(0.5), result[:, :, 1])
        for channel in (2, 3)
            plane = view(source, :, :, channel)
            local_mean, local_variance = similar(plane), similar(plane)
            spatial._local_moments!(local_mean, local_variance, plane, radius)
            expected = 0.5 .+ 0.2 .* ((plane .- local_mean) ./ sqrt.(local_variance .+ 1e-6))
            @test result[:, :, channel] == expected
        end
    end
    @test source == original
end

@testset "Spatial RGB parameter sanitization" begin
    rng = MersenneTwister(91)
    rgb = _rgb_test_image(
        rand(rng, 18, 17), rand(rng, 18, 17), rand(rng, 18, 17),
    )
    bundle = bundle_image3DIntensity_spatial_rgb_factory

    gaussian = (@test_factory bundle[:gaussian_blur_rgb].fn(typeof(rgb)))
    @test gaussian(rgb, -100.0).img == gaussian(rgb, 0.3).img
    @test gaussian(rgb, 100.0).img == gaussian(rgb, 4.0).img
    @test gaussian(rgb, NaN).img == gaussian(rgb, 1.0).img

    dog = (@test_factory bundle[:difference_of_gaussians_rgb].fn(typeof(rgb)))
    @test dog(rgb, -100.0, 100.0).img == dog(rgb, 0.3, 4.0).img
    @test dog(rgb, NaN, Inf).img == dog(rgb, 0.8, 1.6).img
    @test dog(rgb, 0.7, 1.5).img == dog(rgb, 1.5, 0.7).img

    unsharp = (@test_factory bundle[:unsharp_mask_rgb].fn(typeof(rgb)))
    @test unsharp(rgb, -100.0, -100.0).img == unsharp(rgb, 0.3, 0.0).img
    @test unsharp(rgb, Inf, NaN).img == unsharp(rgb, 1.0, 1.0).img

    local_contrast = (@test_factory bundle[:local_contrast_normalize_rgb].fn(typeof(rgb)))
    local_std = (@test_factory bundle[:local_std_rgb].fn(typeof(rgb)))
    @test local_contrast(rgb, -100.0).img == local_contrast(rgb, 1.0).img
    @test local_contrast(rgb, Inf).img == local_contrast(rgb, 3.0).img
    @test local_std(rgb, 100.0).img == local_std(rgb, 5.0).img
    @test local_std(rgb, NaN).img == local_std(rgb, 3.0).img

    gabor = (@test_factory bundle[:gabor_energy_rgb].fn(typeof(rgb)))
    @test gabor(rgb, π, 4.0).img == gabor(rgb, 0.0, 4.0).img
    @test gabor(rgb, 0.0, -100.0).img == gabor(rgb, 0.0, 2.0).img
    @test gabor(rgb, Inf, NaN).img == gabor(rgb, 0.0, 4.0).img

    for name in (:gaussian_blur_rgb, :local_contrast_normalize_rgb, :local_std_rgb)
        fn = (@test_factory bundle[name].fn(typeof(rgb)))
        @test hasmethod(fn, Tuple{typeof(rgb),Float64})
        @test !hasmethod(fn, Tuple{typeof(rgb),String})
    end
    for name in (:difference_of_gaussians_rgb, :unsharp_mask_rgb, :gabor_energy_rgb)
        fn = (@test_factory bundle[name].fn(typeof(rgb)))
        @test hasmethod(fn, Tuple{typeof(rgb),Float64,Float64})
        @test !hasmethod(fn, Tuple{typeof(rgb),String,String})
    end
end

@testset "Spatial RGB performance" begin
    rng = MersenneTwister(92)
    rgb = _rgb_test_image(
        rand(rng, 256, 256), rand(rng, 256, 256), rand(rng, 256, 256),
    )
    bundle = bundle_image3DIntensity_spatial_rgb_factory
    calls = Dict{Symbol,Tuple}(
        :sobel_magnitude_rgb => (rgb,),
        :laplacian_magnitude_rgb => (rgb,),
        :gaussian_blur_rgb => (rgb, 1.0),
        :difference_of_gaussians_rgb => (rgb, 0.7, 1.5),
        :unsharp_mask_rgb => (rgb, 1.0, 1.0),
        :local_contrast_normalize_rgb => (rgb, 3.0),
        :local_std_rgb => (rgb, 3.0),
        :gabor_energy_rgb => (rgb, π / 4, 4.0),
    )
    for (name, arguments) in calls
        fn = (@test_factory bundle[name].fn(typeof(rgb)))
        fn(arguments...)
        elapsed = minimum(@elapsed(fn(arguments...)) for _ in 1:3)
        @test elapsed <= 0.5
    end
end
