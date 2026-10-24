@testset "SkiVector and fixed region expectations" begin
    a = falses(8, 10)
    a[2:3, 6:8] .= true
    a[6, 2] = true
    img = mask(a)
    roi = mask(trues(size(a)))
    @test SK.ski_area(img) == [6.0, 1.0]
    @test SK.ski_centroid_row(img) == [1.5, 5.0]
    @test SK.ski_centroid_col(img) == [6.0, 1.0]
    @test SK.ski_bbox_max_row(img) == [3.0, 6.0]
    @test SK.ski_bbox_min_col(img) == [5.0, 1.0]
    @test SK.ski_axis_major_length(img) ≈ [4sqrt(2 / 3), 0.0]
    @test SK.ski_axis_minor_length(img) ≈ [2.0, 0.0]
    @test SK.ski_perimeter(img) ≈ [6.0, 0.0]
    @test SK.ski_area_convex(img) == [6.0, 1.0]
    @test SK.ski_feret_diameter_max(img) ≈ [sqrt(10), 1.0]
    @test SK.ski_area(img, roi) == SK.ski_area(img)
    @test isempty(SK.ski_area(img, mask(falses(size(a)))))
    @test_throws DimensionMismatch SK.ski_area(img, mask(trues(2, 2)))
    @test_throws DimensionMismatch SK.ski_intensity_mean(img, intensity(ones(2, 2)))
    ring = trues(5, 5)
    ring[2:4, 2:4] .= false
    @test SK.ski_area_filled(mask(ring)) == [25.0]
    @test SK.ski_euler_number(mask(ring)) == [0.0]
    # Diagonal opening: skimage fills with 8-connected background.
    ring[1, 1] = false
    @test SK.ski_area_filled(mask(ring)) == [15.0]
    @test SK.ski_euler_number(mask(ring)) == [0.0]
    @test all(isnan, SK.ski_centroid_weighted_row(img, intensity(zeros(size(a)))))
    saved = SK.ski_area(img)
    SK.ski_area(mask(trues(size(a))))
    @test saved == [6.0, 1.0]
    out = SkiVector{MAGE._get_image_tuple_size(typeof(img))}()
    @test SK.ski_area(img; out) === out
    @test out == [6.0, 1.0]
    @test fetch(@async SK.ski_area(img)) == saved
end

@testset "SkiVector transforms and reductions" begin
    a = SkiVector([3, 1, -2, 4, 1])
    b = SkiVector([2, 5])
    @test SK.ski_identity(a) === a
    @test SK.ski_one() == [1.0]
    @test SK.ski_two() == [2.0]
    @test SK.ski_relu(a) == [3, 1, 0, 4, 1]
    @test SK.ski_square(a) == [9, 1, 4, 16, 1]
    @test SK.ski_sort(a) == [-2, 1, 1, 3, 4]
    @test SK.ski_take_largest(a, 2) == [4, 3]
    @test SK.ski_drop_smallest(a, 2) == [1, 3, 4]
    @test isempty(SK.ski_take_largest(a, NaN))
    @test SK.ski_take_smallest(a, 1e300) == SK.ski_sort(a)
    @test SK.ski_filter_interval(a, 3, 1) == [3, 1, 1]
    @test SK.ski_filter_gt(a, 1) == [3, 4]
    @test SK.ski_pair_subtract(a, b) == [1, -4]
    @test SK.ski_concat(a, b) == [3, 1, -2, 4, 1, 2, 5]
    @test SK.ski_mean(a) ≈ mean(a)
    @test SK.ski_std(a) ≈ std(a; corrected = false)
    @test SK.ski_median(a) == 1
    @test SK.ski_mode(a) == 1
    @test SK.ski_percentile(a, 25) == 1
    @test SK.ski_sum_largest(a, 2) == 7
    @test SK.ski_count_gt(a, 1) == 2
    @test SK.ski_length_difference(a, b) == 3
    @test SK.ski_distance(a, b) ≈ sqrt(17)
    @test SK.ski_correlation(a, b) ≈ -1
    empty = SkiVector()
    @test SK.ski_sum(empty) == 0
    @test SK.ski_length(empty) == 0
    for f in (SK.ski_mean, SK.ski_min, SK.ski_max, SK.ski_std, SK.ski_median, SK.ski_mode)
        @test isnan(f(empty))
    end
    @test isnan(SK.ski_correlation(SkiVector([1, 1]), b))
    @test isnan(SK.ski_distance(empty, b))
    # Aliasing is supported by all vector out methods.
    c = copy(a)
    @test SK.ski_filter_gt(c, 1; out = c) == [3, 4]
    c = copy(a)
    @test SK.ski_concat(c, c; out = c) == vcat(a, a)
    c = copy(a)
    @test SK.ski_pair_add(c, b; out = c) == [5, 6]
    @test a == [3, 1, -2, 4, 1]
end

@testset "Ski bundle contracts" begin
    V = SkiVector{Tuple{8,10}}
    for b in (bundle_ski_basic, bundle_ski_properties, bundle_ski_vector, bundle_float_ski)
        @test MAGE._unique_names_in_bundle(b)
        for w in b
            MAGE._verify_last_arg_is_vararg!(w.fn)
        end
    end
    bs = get_ski_bundles(V)
    for b in bs
        @test Core.Compiler.return_type(b[1].fallback, Tuple{}) === V
    end
    @test bs[1][1].name === :ski_identity
    @test bs[1][2].name === :ski_one
    @test Base.invokelatest(bs[1][2].fn) isa V
    @test all(b -> b[:ski_mean] === nothing, MAGE.get_float_bundles())
    @test get_extension_ski_float()[1][:ski_mean] !== nothing
    @test length(bundle_image2DBinary_ski_factory) == 16
    @test length(bundle_image2DIntensity_ski_factory) == 16
end

# Measured inside a function, warmed twice: no compilation in allocation counts.
function ski_allocations(img, v, out, image_out, f)
    SK.ski_area(img; out)
    SK.ski_square(v; out)
    f(img, out, 2.0; out = image_out)
    SK.ski_area(img; out)
    SK.ski_square(v; out)
    f(img, out, 2.0; out = image_out)
    (
        @allocated(SK.ski_area(img; out)),
        @allocated(SK.ski_square(v; out)),
        @allocated(f(img, out, 2.0; out = image_out))
    )
end
@testset "Ski warmed allocation budgets" begin
    img = mask(rand(MersenneTwister(6), 32, 40) .> 0.75)
    out = SkiVector{MAGE._get_image_tuple_size(typeof(img))}()
    v = typeof(out)([1.0, 2.0, 3.0])
    image_out = mask(falses(size(img)))
    f = bundle_image2DBinary_ski_factory[:ski_keep_objects_gt].fn(typeof(img))
    counts = Base.invokelatest(ski_allocations, img, v, out, image_out, f)
    @info "ski allocation bytes: extraction, transform, image selector" counts
    @test counts[1] <= 256
    @test counts[2] == 0
    @test counts[3] <= 256
end

function ski_property_bytes(f, img, source, out)
    if source === nothing
        f(img; out)
        f(img; out)
        return @allocated f(img; out)
    end
    f(img, source; out)
    f(img, source; out)
    @allocated f(img, source; out)
end
@testset "Ski geometry and intensity scratch allocation" begin
    rng = MersenneTwister(23)
    img = mask(rand(rng, 15, 19) .> 0.65)
    source = intensity(rand(rng, 15, 19))
    out = SkiVector{MAGE._get_image_tuple_size(typeof(img))}()
    for p in SK.SHAPE_PROPERTIES
        fn = getfield(SK, Symbol(:ski_, p))
        bytes = ski_property_bytes(fn, img, nothing, out)
        @testset "$p" begin
            @test bytes <= 256
        end
    end
    for p in SK.INTENSITY_PROPERTIES
        fn = getfield(SK, Symbol(:ski_, p))
        bytes = ski_property_bytes(fn, img, source, out)
        @testset "$p" begin
            @test bytes <= 256
        end
    end
end
