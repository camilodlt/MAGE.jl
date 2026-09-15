using Random

_foreground_intensity(values, ::Type{T} = N0f8) where {T} =
    SImageND(IntensityPixel{T}.(clamp.(Float64.(values), 0.0, 1.0)))
_foreground_binary(values) = SImageND(BinaryPixel.(Bool.(values)))
_foreground_bits(image) = Bool.(reinterpret(image.img))

@testset "Image2D discrete foreground extraction: Boykov-Jolly" begin
    height, width = 64, 64
    object = falses(height, width)
    object[20:45, 24:41] .= true
    values = fill(0.15, height, width)
    values[object] .= 0.85
    saliency_values = zeros(Float64, height, width)
    saliency_values[object] .= 1.0
    image = _foreground_intensity(values)
    saliency = _foreground_intensity(saliency_values)
    output_example = _foreground_binary(falses(height, width))
    factory = bundle_image2DBinary_foreground_extraction_factory[
        :boykov_jolly_foreground
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
    result_bits = _foreground_bits(result)
    intersection = count(result_bits .& object)
    union_count = count(result_bits .| object)
    @test intersection / union_count >= 0.95
    @test !any(result_bits[1, :])
    @test !any(result_bits[end, :])
    @test !any(result_bits[:, 1])
    @test !any(result_bits[:, end])
    @test size(result) == size(image)
    @test eltype(result) == BinaryPixel{Bool}
    @test image.img == image_before
    @test saliency.img == saliency_before
    @test result.img == fn(image, saliency).img
    @test result.img == fn(image, saliency, 5.0).img
    @test fn(image, saliency, NaN).img == result.img
    @test fn(image, saliency, -2.0).img == fn(image, saliency, 0.0).img
    @test fn(image, saliency, 99.0).img == fn(image, saliency, 20.0).img
    @test fn(image, saliency, 5.0, :ignored).img == result.img

    automatic = fn(image)
    @test size(automatic) == size(image)
    @test eltype(automatic) == BinaryPixel{Bool}
    @test automatic.img == fn(image, 5.0).img
    @test automatic.img == fn(image, 5.0, 0.9).img
    @test fn(image, NaN, NaN).img == automatic.img
    @test fn(image, -2.0, 0.1).img == fn(image, 0.0, 0.5).img
    @test fn(image, 99.0, 1.2).img == fn(image, 20.0, 0.99).img
    @test fn(image, 5.0, 0.9, :ignored).img == automatic.img

    noisy_values = copy(values)
    noisy_values[8, 8] = 0.85
    noisy_values[55, 52] = 0.85
    noisy_image = _foreground_intensity(noisy_values)
    unsmoothed = _foreground_bits(fn(noisy_image, saliency, 0.0))
    regularized = _foreground_bits(fn(noisy_image, saliency, 15.0))
    @test count(regularized .& .!object) <= count(unsmoothed .& .!object)
    @test count(regularized .& object) >= round(Int, 0.9count(object))

    flat = _foreground_intensity(fill(0.4, 37, 53))
    flat_fn = factory.fn(typeof(_foreground_binary(falses(37, 53))))
    @test all(iszero, reinterpret(flat_fn(flat).img))

    tiny_values = reshape([0.0, 1.0, 0.0, 0.0, 1.0, 0.0], 2, 3)
    tiny = _foreground_intensity(tiny_values)
    tiny_saliency = _foreground_intensity(tiny_values)
    tiny_fn = factory.fn(typeof(_foreground_binary(falses(2, 3))))
    @test size(tiny_fn(tiny, tiny_saliency)) == (2, 3)

    image_16 = _foreground_intensity(values, N0f16)
    result_16 = fn(image_16, saliency)
    @test size(result_16) == size(image_16)
    @test eltype(result_16) == BinaryPixel{Bool}

    @test any(
        bundle -> bundle[:boykov_jolly_foreground] !== nothing,
        get_extension_foreground_binaryimg(),
    )
    @test all(
        bundle -> bundle[:boykov_jolly_foreground] === nothing,
        get_extension_intensityimg(),
    )

    graphcut_module = UTCGP.image2D_foreground_extraction_discrete
    oracle_rng = MersenneTwister(46)
    for _ in 1:20
        vertex_count = 6
        source_vertex = 1
        sink_vertex = vertex_count
        capacities = zeros(Float64, vertex_count, vertex_count)
        network = graphcut_module._FlowNetwork(vertex_count, 64)
        for from in 1:vertex_count, to in 1:vertex_count
            from == to && continue
            rand(oracle_rng) < 0.3 || continue
            capacity = 0.1 + 4.9rand(oracle_rng)
            capacities[from, to] += capacity
            graphcut_module._add_directed_edge!(network, from, to, capacity)
        end
        flow = graphcut_module._maximum_flow!(network, source_vertex, sink_vertex)
        brute_force_cut = Inf
        for labels in 0:(2^(vertex_count - 2) - 1)
            source_side = falses(vertex_count)
            source_side[source_vertex] = true
            for vertex in 2:(vertex_count - 1)
                source_side[vertex] = ((labels >> (vertex - 2)) & 1) == 1
            end
            cut = sum(
                capacities[from, to]
                for from in 1:vertex_count, to in 1:vertex_count
                if source_side[from] && !source_side[to]
            )
            brute_force_cut = min(brute_force_cut, cut)
        end
        @test flow ≈ brute_force_cut atol = 1.0e-8
    end

    rng = MersenneTwister(45)
    benchmark_values = rand(rng, 256, 256)
    benchmark_saliency_values = rand(rng, 256, 256)
    benchmark_image = _foreground_intensity(benchmark_values)
    benchmark_saliency = _foreground_intensity(benchmark_saliency_values)
    benchmark_fn = factory.fn(typeof(_foreground_binary(falses(256, 256))))
    benchmark_fn(benchmark_image, 2.0, 20.0)
    benchmark_fn(benchmark_image, benchmark_saliency, 20.0)
    automatic_elapsed = minimum(
        @elapsed benchmark_fn(benchmark_image, 2.0, 20.0)
        for _ in 1:3
    )
    supplied_elapsed = minimum(
        @elapsed benchmark_fn(benchmark_image, benchmark_saliency, 20.0)
        for _ in 1:3
    )
    @test automatic_elapsed <= 0.5
    @test supplied_elapsed <= 0.5
end

@testset "Image2D discrete foreground extraction: GrabCut" begin
    height, width = 64, 64
    object = falses(height, width)
    object[20:45, 24:41] .= true
    values = Matrix{Float64}(undef, height, width)
    @inbounds for row in 1:height, col in 1:width
        values[row, col] = isodd(row + col) ? 0.12 : 0.28
        object[row, col] &&
            (values[row, col] = isodd(row + col) ? 0.72 : 0.9)
    end
    saliency_values = zeros(Float64, height, width)
    saliency_values[object] .= 1.0
    image = _foreground_intensity(values)
    saliency = _foreground_intensity(saliency_values)
    output_example = _foreground_binary(falses(height, width))
    factory = bundle_image2DBinary_foreground_extraction_factory[
        :grabcut_foreground
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
    result_bits = _foreground_bits(result)
    intersection = count(result_bits .& object)
    union_count = count(result_bits .| object)
    @test intersection / union_count >= 0.95
    @test !any(result_bits[1, :])
    @test !any(result_bits[end, :])
    @test !any(result_bits[:, 1])
    @test !any(result_bits[:, end])
    @test size(result) == size(image)
    @test eltype(result) == BinaryPixel{Bool}
    @test image.img == image_before
    @test saliency.img == saliency_before
    @test result.img == fn(image, saliency).img
    @test result.img == fn(image, saliency, 2.0).img
    @test fn(image, saliency, NaN).img == result.img
    @test fn(image, saliency, -10.0).img == fn(image, saliency, 1.0).img
    @test fn(image, saliency, 99.0).img == fn(image, saliency, 2.0).img
    @test fn(image, saliency, 2.0, :ignored).img == result.img

    automatic = fn(image)
    @test size(automatic) == size(image)
    @test eltype(automatic) == BinaryPixel{Bool}
    @test automatic.img == fn(image, 2.0).img
    @test automatic.img == fn(image, 2.0, 5.0).img
    @test fn(image, NaN).img == automatic.img
    @test fn(image, -10.0).img == fn(image, 1.0).img
    @test fn(image, 99.0).img == fn(image, 2.0).img
    @test fn(image, 2.0, NaN).img == automatic.img
    @test fn(image, 2.0, -2.0).img == fn(image, 2.0, 0.0).img
    @test fn(image, 2.0, 99.0).img == fn(image, 2.0, 20.0).img
    @test fn(image, 2.0, 5.0, :ignored).img == automatic.img

    flat = _foreground_intensity(fill(0.4, 37, 53))
    flat_saliency = _foreground_intensity(fill(0.2, 37, 53))
    flat_fn = factory.fn(typeof(_foreground_binary(falses(37, 53))))
    @test all(iszero, reinterpret(flat_fn(flat).img))
    @test all(iszero, reinterpret(flat_fn(flat, flat_saliency).img))

    tiny_values = reshape([0.0, 1.0, 0.0, 0.0, 1.0, 0.0], 2, 3)
    tiny = _foreground_intensity(tiny_values)
    tiny_saliency = _foreground_intensity(tiny_values)
    tiny_fn = factory.fn(typeof(_foreground_binary(falses(2, 3))))
    @test size(tiny_fn(tiny, tiny_saliency)) == (2, 3)

    image_16 = _foreground_intensity(values, N0f16)
    result_16 = fn(image_16, saliency)
    @test size(result_16) == size(image_16)
    @test eltype(result_16) == BinaryPixel{Bool}

    @test any(
        bundle -> bundle[:grabcut_foreground] !== nothing,
        get_extension_foreground_binaryimg(),
    )
    @test all(
        bundle -> bundle[:grabcut_foreground] === nothing,
        get_extension_intensityimg(),
    )

    grabcut_module = UTCGP.image2D_foreground_extraction_discrete
    weights, means, variances = grabcut_module._fit_grabcut_gmm(
        vcat(fill(0.1, 20), fill(0.5, 20), fill(0.9, 20)),
    )
    @test length(weights) == 5
    @test length(means) == length(weights) == length(variances)
    @test sum(weights) ≈ 1.0
    @test all(isfinite, weights)
    @test all(isfinite, means)
    @test all(variance -> variance >= 1.0e-4, variances)
    @test isfinite(grabcut_module._gmm_cost(0.5, weights, means, variances))

    rng = MersenneTwister(47)
    benchmark_values = rand(rng, 256, 256)
    benchmark_saliency_values = rand(rng, 256, 256)
    benchmark_image = _foreground_intensity(benchmark_values)
    benchmark_saliency = _foreground_intensity(benchmark_saliency_values)
    benchmark_fn = factory.fn(typeof(_foreground_binary(falses(256, 256))))
    benchmark_fn(benchmark_image, 2.0, 20.0)
    benchmark_fn(benchmark_image, benchmark_saliency)
    automatic_elapsed = minimum(
        @elapsed benchmark_fn(benchmark_image, 2.0, 20.0)
        for _ in 1:3
    )
    supplied_elapsed = minimum(
        @elapsed benchmark_fn(benchmark_image, benchmark_saliency)
        for _ in 1:3
    )
    @test automatic_elapsed <= 0.5
    @test supplied_elapsed <= 0.5
end
