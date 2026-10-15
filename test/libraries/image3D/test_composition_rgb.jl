using Random

function _composition_test_plane(values, ::Type{T}=N0f8) where {T}
    return SImageND(IntensityPixel{T}.(values))
end

function _composition_test_rgb(red, green, blue, ::Type{T}=N0f8) where {T}
    @assert size(red) == size(green) == size(blue)
    values = cat(Float64.(red), Float64.(green), Float64.(blue); dims = 3)
    return SImageND(IntensityPixel{T}.(values))
end

@testset "RGB composition bundle contract" begin
    bundle = bundle_image3DIntensity_rgb_composition_factory
    expected_names = Set([
        :compose_rgb,
        :gray_to_rgb,
        :replace_red_rgb,
        :replace_green_rgb,
        :replace_blue_rgb,
        :multiply_rgb_intensity,
        :alpha_blend_rgb,
        :set_luminance_rgb,
    ])
    @test length(bundle) == 8
    @test Set(wrapper.name for wrapper in bundle) == expected_names
    @test bundle[:identity_rgb] === nothing
    @test bundle[:return_rgb] === nothing

    fresh = get_extension_rgb_compositionimg()
    @test length(fresh) == 1
    @test fresh[1] !== bundle
    @test fresh[1][:compose_rgb] !== bundle[:compose_rgb]

    image2d = _composition_test_plane(zeros(8, 8))
    for wrapper in bundle
        @test_throws MethodError wrapper.fn(typeof(image2d))
    end

    rgb = _composition_test_rgb(
        fill(0.2, 8, 8), fill(0.4, 8, 8), fill(0.6, 8, 8),
    )
    specialized_bundles = [
        get_extension_rgbimg()...,
        get_extension_spatial_rgbimg()...,
        get_extension_rgb_compositionimg()...,
    ]
    for factory_bundle in specialized_bundles
        for (index, wrapper) in enumerate(factory_bundle)
            specialized = wrapper.fn(typeof(rgb))
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
    @test length(library) == 35
    @test library[:compose_rgb].fn(image2d, image2d, image2d) isa typeof(rgb)
    @test safe_call(
        library[:compose_rgb], image2d, image2d, image2d;
        return_type = typeof(rgb),
    ) isa typeof(rgb)
end

@testset "RGB composition values, arities, and typing" begin
    red = _composition_test_plane([0.0 0.2 0.4; 0.6 0.8 1.0])
    green = _composition_test_plane([1.0 0.8 0.6; 0.4 0.2 0.0], N0f16)
    blue = _composition_test_plane(fill(0.3, 2, 3))
    rgb = _composition_test_rgb(
        [0.1 0.2 0.3; 0.4 0.5 0.6],
        [0.2 0.3 0.4; 0.5 0.6 0.7],
        [0.3 0.4 0.5; 0.6 0.7 0.8],
    )
    other = _composition_test_rgb(
        [0.9 0.8 0.7; 0.6 0.5 0.4],
        [0.8 0.7 0.6; 0.5 0.4 0.3],
        [0.7 0.6 0.5; 0.4 0.3 0.2],
    )
    control = _composition_test_plane([0.0 0.25 0.5; 0.75 1.0 0.4])
    original_rgb = copy(rgb.img)
    original_other = copy(other.img)
    original_planes = (copy(red.img), copy(green.img), copy(blue.img), copy(control.img))
    bundle = bundle_image3DIntensity_rgb_composition_factory

    compose = bundle[:compose_rgb].fn(typeof(rgb))
    @test hasmethod(compose, Tuple{typeof(red),typeof(green),typeof(blue)})
    composed = compose(red, green, blue)
    expected_composed = cat(
        Float64.(reinterpret(red.img)),
        Float64.(reinterpret(green.img)),
        Float64.(reinterpret(blue.img));
        dims = 3,
    )
    @test composed isa typeof(rgb)
    @test reinterpret(composed.img) == N0f8.(expected_composed)
    @test compose(red, green, blue, :ignored).img == composed.img

    gray = bundle[:gray_to_rgb].fn(typeof(rgb))
    gray_result = gray(control)
    control_values = Float64.(reinterpret(control.img))
    @test reinterpret(gray_result.img) == N0f8.(cat(control_values, control_values, control_values; dims = 3))
    @test gray(control, :ignored).img == gray_result.img

    source = Float64.(reinterpret(rgb.img))
    for (name, channel, plane) in (
            (:replace_red_rgb, 1, red),
            (:replace_green_rgb, 2, green),
            (:replace_blue_rgb, 3, blue),
        )
        fn = bundle[name].fn(typeof(rgb))
        @test hasmethod(fn, Tuple{typeof(rgb),typeof(plane)})
        result = fn(rgb, plane)
        expected = copy(source)
        expected[:, :, channel] .= Float64.(reinterpret(plane.img))
        @test result isa typeof(rgb)
        @test reinterpret(result.img) == N0f8.(expected)
        @test fn(rgb, plane, :ignored).img == result.img
    end

    multiply = bundle[:multiply_rgb_intensity].fn(typeof(rgb))
    multiplied = multiply(rgb, control)
    expected_multiply = source .* reshape(control_values, 2, 3, 1)
    @test multiplied isa typeof(rgb)
    @test reinterpret(multiplied.img) == N0f8.(expected_multiply)
    @test multiply(rgb, control, :ignored).img == multiplied.img

    blend = bundle[:alpha_blend_rgb].fn(typeof(rgb))
    blended = blend(rgb, other, control)
    other_values = Float64.(reinterpret(other.img))
    weights = reshape(control_values, 2, 3, 1)
    expected_blend = weights .* source .+ (1.0 .- weights) .* other_values
    @test blended isa typeof(rgb)
    @test reinterpret(blended.img) == N0f8.(expected_blend)
    @test blend(rgb, other, control, :ignored).img == blended.img

    set_luminance = bundle[:set_luminance_rgb].fn(typeof(rgb))
    luminance_result = set_luminance(rgb, control)
    expected_luminance = similar(source)
    for col in axes(source, 2), row in axes(source, 1)
        current = 0.2126source[row, col, 1] +
            0.7152source[row, col, 2] + 0.0722source[row, col, 3]
        delta = control_values[row, col] - current
        expected_luminance[row, col, :] .= clamp.(source[row, col, :] .+ delta, 0.0, 1.0)
    end
    @test luminance_result isa typeof(rgb)
    @test reinterpret(luminance_result.img) == N0f8.(expected_luminance)
    @test set_luminance(rgb, control, :ignored).img == luminance_result.img

    @test rgb.img == original_rgb
    @test other.img == original_other
    @test (red.img, green.img, blue.img, control.img) == original_planes

    wrong_plane = _composition_test_plane(zeros(3, 2))
    wrong_rgb = _composition_test_rgb(zeros(3, 2), zeros(3, 2), zeros(3, 2))
    @test !hasmethod(compose, Tuple{typeof(red),typeof(green),typeof(wrong_plane)})
    @test !hasmethod(multiply, Tuple{typeof(rgb),typeof(wrong_plane)})
    @test !hasmethod(blend, Tuple{typeof(rgb),typeof(wrong_rgb),typeof(control)})

    rgb16 = _composition_test_rgb(zeros(2, 3), zeros(2, 3), zeros(2, 3), N0f16)
    composed16 = bundle[:compose_rgb].fn(typeof(rgb16))(red, green, blue)
    @test composed16 isa typeof(rgb16)
    @test eltype(composed16) == IntensityPixel{N0f16}
end

@testset "RGB composition sanitization and degenerate maps" begin
    rgb = _composition_test_rgb(
        [0.2 0.4; 0.6 0.8],
        [0.3 0.5; 0.7 0.9],
        [0.4 0.6; 0.8 1.0],
    )
    other = _composition_test_rgb(
        [0.8 0.6; 0.4 0.2],
        [0.7 0.5; 0.3 0.1],
        [0.6 0.4; 0.2 0.0],
    )
    zero_map = _composition_test_plane(zeros(2, 2))
    one_map = _composition_test_plane(ones(2, 2))
    unsafe_map = _composition_test_plane([-1.0 2.0; NaN Inf], Float64)
    sanitized = [0.0 1.0; 0.0 0.0]
    bundle = bundle_image3DIntensity_rgb_composition_factory

    compose = bundle[:compose_rgb].fn(typeof(rgb))
    unsafe_result = Float64.(reinterpret(compose(unsafe_map, unsafe_map, unsafe_map).img))
    @test all(isfinite, unsafe_result)
    @test unsafe_result == Float64.(N0f8.(cat(sanitized, sanitized, sanitized; dims = 3)))

    gray = bundle[:gray_to_rgb].fn(typeof(rgb))
    @test all(isfinite, Float64.(reinterpret(gray(unsafe_map).img)))

    multiply = bundle[:multiply_rgb_intensity].fn(typeof(rgb))
    @test all(iszero, reinterpret(multiply(rgb, zero_map).img))
    @test multiply(rgb, one_map).img == rgb.img
    expected_masked = Float64.(reinterpret(rgb.img)) .* reshape(sanitized, 2, 2, 1)
    @test reinterpret(multiply(rgb, unsafe_map).img) == N0f8.(expected_masked)

    blend = bundle[:alpha_blend_rgb].fn(typeof(rgb))
    @test blend(rgb, other, zero_map).img == other.img
    @test blend(rgb, other, one_map).img == rgb.img
    unsafe_blend = Float64.(reinterpret(blend(rgb, other, unsafe_map).img))
    @test all(isfinite, unsafe_blend)

    black = _composition_test_rgb(zeros(2, 2), zeros(2, 2), zeros(2, 2))
    half = _composition_test_plane(fill(0.5, 2, 2))
    set_luminance = bundle[:set_luminance_rgb].fn(typeof(rgb))
    relit_black = set_luminance(black, half)
    @test all(reinterpret(relit_black.img) .== N0f8(0.5))
    @test all(isfinite, Float64.(reinterpret(set_luminance(rgb, unsafe_map).img)))
end

@testset "RGB composition performance" begin
    rng = MersenneTwister(93)
    rgb = _composition_test_rgb(
        rand(rng, 256, 256), rand(rng, 256, 256), rand(rng, 256, 256),
    )
    other = _composition_test_rgb(
        rand(rng, 256, 256), rand(rng, 256, 256), rand(rng, 256, 256),
    )
    red = _composition_test_plane(rand(rng, 256, 256))
    green = _composition_test_plane(rand(rng, 256, 256))
    blue = _composition_test_plane(rand(rng, 256, 256))
    bundle = bundle_image3DIntensity_rgb_composition_factory
    calls = Dict{Symbol,Tuple}(
        :compose_rgb => (red, green, blue),
        :gray_to_rgb => (red,),
        :replace_red_rgb => (rgb, red),
        :replace_green_rgb => (rgb, green),
        :replace_blue_rgb => (rgb, blue),
        :multiply_rgb_intensity => (rgb, red),
        :alpha_blend_rgb => (rgb, other, green),
        :set_luminance_rgb => (rgb, blue),
    )
    for (name, arguments) in calls
        fn = bundle[name].fn(typeof(rgb))
        fn(arguments...)
        elapsed = minimum(@elapsed(fn(arguments...)) for _ in 1:3)
        @test elapsed <= 0.5
    end
end
