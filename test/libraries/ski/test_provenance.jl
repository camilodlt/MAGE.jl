@testset "Owned geometry and vector provenance" begin
    a = falses(8, 10)
    a[2:3, 6:8] .= true
    a[6, 2] = true
    img = mask(a)
    V = SkiVector{Tuple{8,10}}
    v = SK.ski_area(img)
    @test v isa V
    @test v.ids == Int32[1, 2]
    @test v.regions === v.own
    @test eltype(v.regions.labels) === Int32
    @test v.regions.image === img
    labels = copy(v.regions.labels)
    other = SK.ski_area(mask(trues(size(a))))
    @test v.regions !== other.regions
    @test v.regions.labels == labels
    for op in (SK.ski_square, SK.ski_neg, SK.ski_abs, SK.ski_identity)
        r = op(v)
        @test r.ids == v.ids
        @test r.regions === v.regions
    end
    @test SK.ski_sort(v).ids == [2, 1]
    @test SK.ski_take_smallest(v, 1).ids == [2]
    @test SK.ski_drop_smallest(v, 1).ids == [1]
    @test SK.ski_take_largest(v, 1).ids == [1]
    @test SK.ski_drop_largest(v, 1).ids == [2]
    @test SK.ski_filter_gt(v, 2).ids == [1]
    @test SK.ski_filter_interval(v, 0, 2).ids == [2]
    r = SK.ski_pair_add(v, other)
    @test r.ids == [1] && r.regions === v.regions
    @test SK.ski_concat(v, SK.ski_square(v)).ids == [1, 2, 1, 2]
    @test SK.ski_concat(v, other).ids == [1, 2, 0]
    c = copy(v)
    SK.ski_concat(c, other; out = c)
    @test c.ids == [1, 2, 0] && c.regions === v.regions
    c = copy(v)
    SK.ski_sort(c; out = c)
    @test c.ids == [2, 1] && c == [1.0, 6.0]
    c = copy(v)
    SK.ski_filter_gt(c, 2; out = c)
    @test c.ids == [1]
    out = V()
    own = out.own
    SK.ski_square(v; out)
    @test out.own === own && out.regions === v.regions
    for i in 2:4
        constant = Base.invokelatest(get_ski_bundles(V)[1][i].fn)
        @test all(iszero, constant.ids)
        @test constant.regions === constant.own
    end
end

@testset "Ski selectors use vector geometry and supplied/reference pixels" begin
    a = falses(8, 10)
    a[2:3, 6:8] .= true
    a[6, 2] = true
    img = mask(a)
    source = intensity(reshape(collect(1.0:80.0), 8, 10) ./ 80)
    v = SK.ski_area(img)
    w = SK.ski_intensity_mean(img, source)
    selected = a .& (reshape(1:8, 8, 1) .< 5)
    for (bundle, T) in (
        (bundle_image2DBinary_ski_factory, typeof(img)),
        (bundle_image2DIntensity_ski_factory, typeof(source)),
    )
        maxfn = bundle[:ski_keep_objects_max].fn(T)
        gt = bundle[:ski_keep_objects_gt].fn(T)
        ref = Base.invokelatest(maxfn, v)
        @test Float64.(ref.img) == Float64.(selected)
        explicit = Base.invokelatest(maxfn, source, v)
        want = T === typeof(img) ? Float64.(selected) : Float64.(source.img) .* selected
        @test Float64.(explicit.img) == want
        refweighted = Base.invokelatest(gt, w, 0.0)
        @test Float64.(refweighted.img) ==
              (T === typeof(img) ? Float64.(a) : Float64.(source.img) .* a)
        out = T === typeof(img) ? mask(falses(size(a))) : intensity(zeros(size(a)))
        @test Base.invokelatest(gt, source, v, 2.0; out) === out
        @test Float64.(out.img) == want
        if T === typeof(source)
            # A labeled intensity image is its own reference source.
            labeled = intensity(Float64.(a) .* 0.5 .+ 0.5 .* Float64.(a) .* (reshape(1:80, 8, 10) ./ 80))
            self = Base.invokelatest(gt, SK.ski_area(labeled), 0.0)
            @test Float64.(self.img) == Float64.(labeled.img) .* a
        end
        @test !hasmethod(gt, Tuple{typeof(v)})
        @test !hasmethod(gt, Tuple{typeof(img),typeof(v)})
        @test !hasmethod(gt, Tuple{typeof(mask(trues(2, 2))),typeof(v),Float64})
        # Multiple elements can refer to one region: any passing element selects it.
        duplicate = SK.ski_concat(v, SK.ski_neg(v))
        @test Float64.(Base.invokelatest(gt, duplicate, 2.0).img) == Float64.(selected)
        # Id-zero elements affect thresholds but can never identify a region.
        foreign = SK.ski_area(mask(trues(size(a))))
        foreign.values[1] = 1e6
        mixed = SK.ski_concat(v, foreign)
        @test all(iszero, Float64.(Base.invokelatest(maxfn, mixed).img))
    end
    # Bboxes fill the rectangle, including holes removed by a property ROI.
    roi = mask(trues(size(a)))
    roi.img[2, 6] = BinaryPixel(false)
    partial = SK.ski_area(img, roi)
    bbox = bundle_image2DBinary_ski_factory[:ski_keep_bbox_max].fn(typeof(img))
    @test (Float64.(Base.invokelatest(bbox, partial).img) .> 0) == selected
end

function ski_graph(img; fork = false)
    I = typeof(img)
    V = SkiVector{MAGE._get_image_tuple_size(I)}
    fallback = get_ski_bundles(V)[1][1].fallback
    graph = MAGE.PopulationSequentialProgram()
    graph.input_types = Type[I, I]
    graph.has_input_layout = true
    input(i) = MAGE.PopulationSequentialInputRef(i, I)
    ref(i, T) = MAGE.PopulationSequentialTmpRef(i, T)
    function add(fn, inputs, T, fallback)
        wrapper = MAGE.FunctionWrapper(fn, nameof(fn), nothing, fallback)
        push!(
            graph.steps,
            MAGE.PopulationSequentialCallStep(
                wrapper,
                MAGE.AbstractPopulationSequentialRef[inputs...],
                T,
                T,
            ),
        )
    end
    add(SK.ski_area, [input(1)], V, fallback)
    add(SK.ski_square, [ref(1, V)], V, fallback)
    if fork
        add(SK.ski_area, [input(2)], V, fallback)
        selector = bundle_image2DBinary_ski_factory[:ski_keep_objects_max].fn(I)
        add(selector, [input(2), ref(2, V)], I, () -> img)
        add(ski_count_pixels, [ref(4, I)], Float64, () -> 0.0)
        final = 5
    else
        add(SK.ski_sum, [ref(2, V)], Float64, () -> 0.0)
        final = 3
    end
    push!(graph.individual_outputs, MAGE.AbstractPopulationSequentialRef[ref(final, Float64)])
    push!(graph.individual_step_ids, collect(1:final))
    graph
end
ski_count_pixels(img, args...) = Float64(count(x -> Bool(x.pixel), img.img))
function evaluation_bytes(outputs, graph, samples, evaluator)
    evaluate_population_into!(outputs, graph, samples; evaluator)
    evaluate_population_into!(outputs, graph, samples; evaluator)
    @allocated evaluate_population_into!(outputs, graph, samples; evaluator)
end
@testset "Pooled ski evaluation and in-evaluation reference lifetime" begin
    a = falses(8, 10)
    a[2:3, 6:8] .= true
    a[6, 2] = true
    img = mask(a)
    other = mask(trues(size(a)))
    graph = Base.invokelatest(ski_graph, img; fork = true)
    evaluator = TypedEvaluator(graph)
    values = zeros(1, 1)
    samples = [(img, other)]
    evaluate_population_into!(values, graph, samples; evaluator)
    @test values[1] == 6.0
    first = evaluator.steps[1].buffer
    derived = evaluator.steps[2].buffer
    second = evaluator.steps[3].buffer
    @test first !== derived && first !== second
    @test first.own !== derived.own && first.own !== second.own
    @test derived.regions === first.own
    @test second.regions === second.own
    @test first.regions.labels != second.regions.labels
    for step in evaluator.steps[1:3]
        @test step.keywords.out === step.buffer
        @test step.result.value === step.buffer
    end
    retained = copy(derived)
    before = copy(retained.regions.labels)
    evaluate_population_into!(values, graph, [(other, img)]; evaluator)
    @test retained.regions === first.own
    @test retained.regions.labels != before  # Explicitly documented cross-evaluation lifetime.
    @test values[1] == 80.0
    chain = Base.invokelatest(ski_graph, img)
    ev = TypedEvaluator(chain)
    results = zeros(1, 1)
    bytes = evaluation_bytes(results, chain, samples, ev)
    @test results[1] == 37.0
    @info "Warmed pooled ski property → square → sum allocation bytes per sample" bytes
    @test bytes <= 2048 # Bounded interpreter/boxing overhead, never an image-sized allocation.
    own_labels = ev.steps[1].buffer.own.labels
    own_values = ev.steps[1].buffer.values
    evaluate_population_into!(results, chain, samples; evaluator = ev)
    @test ev.steps[1].buffer.own.labels === own_labels
    @test ev.steps[1].buffer.values === own_values
    # Work/allocations, never wall-clock time: a much larger label map must not
    # turn warmed evaluation into an image-sized allocation.
    large_img = mask(rand(MersenneTwister(82), 64, 80) .> 0.8)
    large_graph = Base.invokelatest(ski_graph, large_img)
    large_ev = TypedEvaluator(large_graph)
    large_samples = [(large_img, large_img)]
    large_results = zeros(1, 1)
    large_bytes = evaluation_bytes(large_results, large_graph, large_samples, large_ev)
    @test large_bytes <= 2048
    @test large_bytes <= bytes + 256
    @test large_results[1] == sum(abs2, SK.ski_area(large_img))
    @info "Warmed pooled ski allocation bytes with a 64×80 label map" large_bytes
end

function reuse_graph(input_type, fn, V)
    g = MAGE.PopulationSequentialProgram()
    g.input_types = Type[input_type]
    g.has_input_layout = true
    input = MAGE.PopulationSequentialInputRef(1, input_type)
    first = MAGE.PopulationSequentialTmpRef(1, V)
    final = MAGE.PopulationSequentialTmpRef(2, Float64)
    for (op, refs, T, fallback) in
        ((fn, [input], V, get_ski_bundles(V)[1][1].fallback), (SK.ski_sum, [first], Float64, () -> 0.0))
        wrapper = MAGE.FunctionWrapper(op, nameof(op), nothing, fallback)
        push!(
            g.steps,
            MAGE.PopulationSequentialCallStep(
                wrapper,
                MAGE.AbstractPopulationSequentialRef[refs...],
                T,
                T,
            ),
        )
    end
    push!(g.individual_outputs, MAGE.AbstractPopulationSequentialRef[final])
    push!(g.individual_step_ids, [1, 2])
    g
end
@testset "Pool slots reused across programs, larger/smaller and unrelated provenance" begin
    S = Tuple{8,10}
    V = SkiVector{S}
    many = falses(8, 10)
    many[1:3:8, 1:3:10] .= true
    few = falses(8, 10)
    few[2:3, 6:8] .= true
    few[6, 2] = true
    large = mask(many)
    small = mask(few)
    blank = mask(falses(8, 10))
    pool = BufferPool([typeof(large), V, Float64])
    property_graph = reuse_graph(typeof(large), SK.ski_area, V)
    derived_graph = reuse_graph(V, SK.ski_sort, V)
    # Each new evaluator starts handing buffers out from the same pool index.
    function property_generation(img)
        ev = TypedEvaluator(property_graph, pool)
        evaluate_population_into!(zeros(1, 1), property_graph, [(img,)]; evaluator = ev)
        ev.steps[1].buffer
    end
    function derived_generation(v)
        ev = TypedEvaluator(derived_graph, pool)
        evaluate_population_into!(zeros(1, 1), derived_graph, [(v,)]; evaluator = ev)
        ev.steps[1].buffer
    end
    first = property_generation(large)
    @test length(first) == 12
    @test isempty(MAGE._new_buffer(V).values) && isempty(MAGE._new_buffer(V).ids)
    @test isempty(MAGE._new_buffer(V).own.boxes) && isempty(MAGE._new_buffer(V).own.counts)
    for img in (small, large, blank, large, small)
        expected = SK.ski_area(img)
        reused = property_generation(img)
        @test reused === first
        @test reused == expected && reused.ids == expected.ids
        @test reused.regions === reused.own
        @test reused.own.labels == expected.regions.labels
        @test reused.own.boxes == expected.regions.boxes
        @test reused.own.counts == expected.regions.counts
        @test reused.own.n == length(expected)
        @test reused.own.image === img && reused.own.intensity === nothing
        fresh = SK.ski_area(img)
        sorted = derived_generation(fresh)
        want = SK.ski_sort(fresh)
        @test sorted === first
        @test sorted == want && sorted.ids == want.ids
        @test sorted.regions === fresh.regions
        # Previously shared references are overwritten by the next property step.
        @test property_generation(img).regions === first.own
    end
    # Reuse the same slot for a derived output larger and smaller than its prior data.
    for input in (SK.ski_area(large), SK.ski_area(small), SK.ski_area(blank), SK.ski_area(large))
        out = derived_generation(input)
        @test out === first
        @test out == SK.ski_sort(input)
        @test out.ids == SK.ski_sort(input).ids
        @test out.regions === input.regions
    end
    # An intensity reference must also be cleared on later shape-only extraction.
    src = intensity(ones(8, 10))
    SK.ski_intensity_mean(small, src; out = first)
    @test first.own.intensity === src
    SK.ski_area(blank; out = first)
    @test first.own.intensity === nothing && first.own.n == 0
    @test isempty(first.values) && isempty(first.ids)
    @test isempty(first.own.boxes) && isempty(first.own.counts)
    @test all(iszero, first.own.labels)
    SK.ski_area(large; out = first)
    SK.ski_one(; out = first)
    @test first.values == [1.0] && first.ids == [0]
    @test first.regions === first.own && first.own.n == 0
    @test isempty(first.own.boxes) && isempty(first.own.counts)
    @test first.own.image === nothing && first.own.intensity === nothing
    # Stale labels are unreachable with n = 0: no selector keeps any pixel.
    keep_all = bundle_image2DBinary_ski_factory[:ski_keep_objects_gte].fn(typeof(large))
    @test !any(Float64.(Base.invokelatest(keep_all, large, first, -Inf).img) .> 0)
    SK.ski_empty(; out = first)
    @test isempty(first.values) && isempty(first.ids)
end
