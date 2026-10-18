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
    # Two-pixel boundary quantization is expected on this 64→32 fixture.
    @test intersection / union_count >= 0.80
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
        # Capacities are stored as integers scaled by _FLOW_CAPACITY_SCALE (2^20), so each one
        # is rounded by at most 0.5 / 2^20; compare in the original units with that tolerance.
        scale = graphcut_module._FLOW_CAPACITY_SCALE
        @test flow / scale ≈ brute_force_cut atol = vertex_count^2 / scale
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
    # Two-pixel boundary quantization is expected on this 64→32 fixture.
    @test intersection / union_count >= 0.80
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

@testset "Discrete bounded resolution and rectangular determinism" begin
    for name in (:grabcut_foreground,:boykov_jolly_foreground), (h,w) in ((32,32),(224,100),(100,224),(37,500),(33,32))
        object=[abs(r-h/2)<h/4 && abs(c-w/2)<w/4 for r in 1:h,c in 1:w]
        image=SImageND(IntensityPixel{N0f8}.(0.1 .+ 0.8 .*object))
        aux=SImageND(IntensityPixel{N0f8}.(Float64.(object)))
        out=SImageND(BinaryPixel{Bool}.(falses(h,w)))
        fn=bundle_image2DBinary_foreground_extraction_factory[name].fn(typeof(out))
        result=fn(image,aux)
        @test fn(image,aux;out=out)===out
        @test result.img==out.img
        tasks=[Threads.@spawn(fn(image,aux).img) for _ in 1:2]
        @test all(fetch(t)==result.img for t in tasks)
    end
end

@testset "Discrete foreground linear max-flow work budget" begin
    flow = UTCGP.image2D_foreground_extraction_discrete
    # Zero/one unary costs with a sparse foreground seed leave excess circulating
    # under repeated global relabels. Keep the fixture procedural and reproducible.
    rng = MersenneTwister(1)
    values = rand(rng, 64, 64)
    background_cost = Float64.(rand(rng, Bool, 64, 64))
    foreground = falses(64, 64)
    background = falses(64, 64)
    foreground[32, 32] = true
    background[1, :] .= true
    cut() = flow._grabcut_graphcut(
        values, zeros(64, 64), background_cost, foreground, background, 5.0,
    )
    # The ordinary evaluator handles this same ErrorException as any failed call.
    # Check its message too: an unrelated solver error must not pass this test.
    failure = try
        cut()
        nothing
    catch exception
        exception
    end
    @test failure isa ErrorException
    @test occursin("exceeded its work budget", sprint(showerror, failure))
    wrapped = UTCGP.FunctionWrapper(cut, :budget_regression, nothing, flow.fallback)
    elapsed = @elapsed @test UTCGP.safe_call(wrapped, ()) == (nothing, true)
    @test elapsed < 3.0

    # With no pairwise cost, every non-background pixel prefers foreground.
    # This exact normal cut must survive the budget and keep its original pixels.
    normal = flow._grabcut_graphcut(
        values, zeros(64, 64), ones(64, 64), foreground, background, 0.0,
    )
    @test normal == .!background
end

@testset "Foreground evaluation does not define coarse methods" begin
    height, width = 43, 117
    image = _foreground_intensity(fill(0.5, height, width))
    auxiliary = _foreground_intensity(zeros(height, width))
    output = _foreground_binary(falses(height, width))
    library = UTCGP.image2D_foreground_extraction_discrete
    for name in (:boykov_jolly_foreground, :grabcut_foreground)
        fn = bundle_image2DBinary_foreground_extraction_factory[name].fn(typeof(output))
        bindings = names(library; all = true)
        fn(image, auxiliary; out = output)
        @test names(library; all = true) == bindings
        @test !haskey(task_local_storage(), :foreground_resolution_active)
    end
end

@testset "Sparse rough-mask evidence survives without component bridges" begin
    library = UTCGP.image2D_foreground_extraction_discrete
    # A connected sparse strip occupies 14/49 pixels per coarse box.
    sparse = falses(224, 224)
    sparse[100:101, 50:175] .= true
    hint = SImageND(BinaryPixel{Bool}.(sparse))
    pooled = fill(BinaryPixel(false), 32, 32)
    library._resolution_sparse_mask!(pooled, hint.img)
    @test any(Bool.(reinterpret(pooled)))
    @test !any(Bool.(reinterpret(library._resolution_pool!(similar(pooled), hint.img, Val(:majority)))))
    image = SImageND(IntensityPixel{N0f8}.(0.1 .+ 0.8 .* sparse))
    for name in (:grabcut_foreground, :boykov_jolly_foreground)
        output = SImageND(BinaryPixel{Bool}.(falses(224, 224)))
        fn = bundle_image2DBinary_foreground_extraction_factory[name].fn(typeof(output))
        result = fn(image, hint, 0)
        @test any(Bool.(reinterpret(result.img)))
        @test fn(image, hint, 0; out = output).img == result.img
        tasks = [Threads.@spawn(fn(image, hint, 0).img) for _ in 1:2]
        @test all(fetch(task) == result.img for task in tasks)
    end
    # Two coarse neighbor boxes with different provenance cannot form a bridge.
    separated = falses(14, 14)
    separated[2, 1:7] .= true
    separated[4, 8:14] .= true
    guarded = fill(BinaryPixel(false), 2, 2)
    library._resolution_sparse_mask!(guarded, BinaryPixel{Bool}.(separated))
    @test count(Bool.(reinterpret(guarded))) == 1
    # A box containing two full components is explicitly ambiguous.
    conflict = falses(7, 7)
    conflict[1:2, 1:2] .= true
    conflict[6:7, 6:7] .= true
    ambiguous = fill(BinaryPixel(false), 1, 1)
    library._resolution_sparse_mask!(ambiguous, BinaryPixel{Bool}.(conflict))
    @test !Bool(only(reinterpret(ambiguous)))
    for value in (false, true)
        constant = fill(BinaryPixel(value), 14, 14)
        library._resolution_sparse_mask!(guarded, constant)
        @test all(pixel -> Bool(pixel) == value, reinterpret(guarded))
    end
end

@testset "Cuts select quarter occupancy while matting retains eighth" begin
    library = UTCGP.image2D_foreground_extraction_discrete
    thin = falses(224, 224)
    thin[100, 50:175] .= true
    source = BinaryPixel{Bool}.(thin)
    eighth = copy(library._resolution_auxiliary(source, 32, 32, Val(:sparse)))
    quarter = library._resolution_auxiliary(source, 32, 32, Val(:sparse_quarter))
    @test any(reinterpret(eighth))
    @test !any(reinterpret(quarter))
end
