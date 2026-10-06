using Statistics: quantile, mean, std, var

@testset "Classification descriptors" begin
    I = UTCGP.number_intensityStatsFromImg
    Sh = UTCGP.number_shapeFromImg
    G = UTCGP.number_granulometryFromImg
    _d_intensity(values, ::Type{T} = N0f8) where {T} = SImageND(IntensityPixel{T}.(clamp.(values, 0.0, 1.0)))
    _d_binary(values) = SImageND(BinaryPixel.(Bool.(values)))
    _d_values(img) = Float64.(reinterpret(img.img))

    rng = MersenneTwister(4)
    raw = rand(rng, 40, 50) .^ 2
    img8 = _d_intensity(raw)
    img16 = _d_intensity(raw, N0f16)
    roi_bits = [(r - 20)^2 + (c - 25)^2 < 150 for r in 1:40, c in 1:50]
    roi = _d_binary(roi_bits)

    @testset "intensity statistics match Statistics" begin
        for img in (img8, img16)
            v = _d_values(img)
            inside, outside = v[roi_bits], v[.!roi_bits]
            for (p, name) in ((0.05, :q05), (0.25, :q25), (0.5, :q50), (0.75, :q75), (0.95, :q95))
                f = getfield(I, Symbol(:stat_, name))
                @test f(img) ≈ quantile(vec(v), p)
                @test f(img, roi) ≈ quantile(inside, p)
                @test getfield(I, Symbol(:stat_, name, :_out))(img, roi) ≈ quantile(outside, p)
            end
            @test I.stat_iqr(img) ≈ quantile(vec(v), 0.75) - quantile(vec(v), 0.25)
            @test I.stat_mean_diff(img, roi) ≈ mean(inside) - mean(outside)
            @test I.stat_std(img) ≈ std(vec(v); corrected = false)
            @test I.stat_mad(img, roi) ≈ mean(abs.(inside .- mean(inside)))
            m = mean(outside)
            m2 = mean((outside .- m) .^ 2)
            @test I.stat_skewness_out(img, roi) ≈ mean((outside .- m) .^ 3) / m2^1.5
            @test I.stat_kurtosis_out(img, roi) ≈ mean((outside .- m) .^ 4) / m2^2 - 3
            @test I.stat_frac_above(img, roi, 0.3) ≈ mean(inside .>= 0.3)
        end
        # Intensity map as ROI (thresholded at 0.5) gives the same as the binary mask.
        @test I.stat_q75(img8, _d_intensity(Float64.(roi_bits))) == I.stat_q75(img8, roi)
    end

    @testset "entropy, uniformity, bimodality, Otsu" begin
        flat = _d_intensity(fill(0.4, 30, 30))
        @test I.stat_entropy(flat) == 0.0
        @test I.stat_uniformity(flat) == 1.0
        @test I.stat_std(flat) == 0.0
        @test I.stat_bimodality(flat) == 0.0
        @test I.stat_otsu_separability(flat) == 0.0
        two_level = _d_intensity([c <= 15 ? 0.2 : 0.8 for r in 1:30, c in 1:30])
        @test I.stat_entropy(two_level) ≈ 1 / 5                 # 1 bit out of log2(32)
        @test I.stat_uniformity(two_level) ≈ 0.5
        @test I.stat_otsu_separability(two_level) ≈ 1.0
        @test 0.2 <= I.stat_otsu_threshold(two_level) < 0.8
        @test I.stat_bimodality(two_level) > 5 / 9
        @test I.stat_bimodality(img8) < I.stat_bimodality(two_level)
        # Otsu against a brute-force search over the 256 levels.
        v = _d_values(img8)
        levels = round.(Int, v .* 255)
        best, best_t = -1.0, 0
        for t in 0:254
            a, b = v[levels .<= t], v[levels .> t]
            (isempty(a) || isempty(b)) && continue
            between = length(a) * length(b) / length(v)^2 * (mean(a) - mean(b))^2
            between > best && ((best, best_t) = (between, t))
        end
        @test I.stat_otsu_threshold(img8) ≈ best_t / 255
        @test I.stat_otsu_separability(img8) ≈ best / var(vec(v); corrected = false)
    end

    @testset "empty selections" begin
        empty = _d_binary(falses(40, 50))
        @test I.stat_mean(img8, empty) == 0.0
        @test I.stat_q50_out(img8, _d_binary(trues(40, 50))) == 0.0
        @test I.stat_mean_diff(img8, empty) == -I.stat_mean(img8)
        @test Sh.shape_solidity(empty) == 0.0
        @test Sh.shape_hu1(empty) == 0.0
        @test UTCGP.number_shapeFromImg.objs_area_mean(empty) == 0.0
        @test G.gran_open_r2(empty) == 0.0
        @test G.gran_thickness_max(empty) == 0.0
    end

    shape = falses(41, 41)
    for r in 1:41, c in 1:41
        ((r - 21) / 14)^2 + ((c - 21) / 6)^2 <= 1 && (shape[r, c] = true)
    end
    shape[8:14, 21:30] .= true

    @testset "Hu invariants" begin
        m = _d_binary(shape)
        rotated = _d_binary(rotl90(shape))
        mirrored = _d_binary(shape[:, end:-1:1])
        shifted = _d_binary(circshift(shape, (0, 0)) .& false .| [c > 5 && shape[r, c - 5] for r in 1:41, c in 1:41])
        for k in 1:7
            f = getfield(Sh, Symbol(:shape_hu, k))
            @test f(m) ≈ f(rotated)
            k < 7 && @test f(m) ≈ f(mirrored)
        end
        @test Sh.shape_hu7(m) ≈ -Sh.shape_hu7(mirrored)            # hu7 flips under mirroring
        @test Sh.shape_hu1(m) ≈ Sh.shape_hu1(_d_binary(repeat(shape, inner = (2, 2)))) atol = 0.01
        @test Sh.shape_hu2(m) ≈ Sh.shape_hu2(shifted) atol = 1e-9
        # Weighted Hu on a constant image equals the mask Hu.
        @test Sh.shape_hu1_weighted(_d_intensity(0.7 .* shape)) ≈ Sh.shape_hu1(m)
        @test Sh.shape_hu3_weighted(_d_intensity(fill(0.5, 41, 41)), m) ≈ Sh.shape_hu3(m)
    end

    @testset "whole-foreground descriptors" begin
        m = _d_binary(shape)
        hull_fn = bundle_image2DBinary_maskshape_factory[:shape_convex_hull].fn(typeof(m))
        hull_pixels = count(p -> p == true, Base.invokelatest(hull_fn, m).img)
        @test Sh.shape_solidity(m) ≈ count(shape) / hull_pixels
        square = falses(30, 30)
        square[5:20, 8:23] .= true
        @test Sh.shape_solidity(_d_binary(square)) == 1.0
        @test Sh.shape_extent(_d_binary(square)) == 1.0
        @test Sh.shape_fill(_d_binary(square)) ≈ 256 / 900
        ring = [36 < (r - 20)^2 + (c - 20)^2 <= 100 for r in 1:40, c in 1:40]
        @test Sh.shape_euler(_d_binary(ring)) == 0.0                # one object, one hole
        @test Sh.shape_euler(_d_binary(square)) == 1.0
        @test Sh.shape_euler(_d_binary(ring .| [r == 2 && c == 2 for r in 1:40, c in 1:40])) == 1.0
        @test 0.0 < Sh.shape_hole_fraction(_d_binary(ring)) < 1.0
        @test Sh.shape_hole_fraction(_d_binary(square)) == 0.0
        @test Sh.shape_elongation(_d_binary(square)) ≈ 0.0 atol = 1e-9
        # ROI: only the foreground inside it.
        left = _d_binary([c <= 20 for r in 1:30, c in 1:30])
        @test Sh.shape_fill(_d_binary(square), left) ≈ count(square[:, 1:20]) / 900
    end

    @testset "object aggregates" begin
        population = falses(60, 80)
        areas = Int[]
        for (k, (r, c, s)) in enumerate(((5, 5, 3), (5, 30, 5), (30, 10, 7), (30, 50, 4), (45, 65, 9)))
            population[r:r+s-1, c:c+s-1] .= true
            push!(areas, s * s)
        end
        m = _d_binary(population)
        fractions = areas ./ (60 * 80)
        @test UTCGP.number_shapeFromImg.objs_area_mean(m) ≈ mean(fractions)
        @test UTCGP.number_shapeFromImg.objs_area_max(m) ≈ maximum(fractions)
        @test UTCGP.number_shapeFromImg.objs_area_std(m) ≈ std(fractions; corrected = false)
        @test UTCGP.number_shapeFromImg.objs_area_median(m) ≈ sort(fractions)[3]
        @test UTCGP.number_shapeFromImg.objs_area_cv(m) ≈ std(fractions; corrected = false) / mean(fractions)
        @test UTCGP.number_shapeFromImg.objs_solidity_min(m) == 1.0
        @test UTCGP.number_shapeFromImg.objs_extent_mean(m) == 1.0
        sorted = sort(Float64.(areas))
        n = length(sorted)
        @test UTCGP.number_shapeFromImg.objs_area_gini(m) ≈ sum((2i - n - 1) * sorted[i] for i in 1:n) / (n * sum(sorted))
        @test UTCGP.number_shapeFromImg.objs_nn_distance_min(m) > 0.0
        # ROI: objects whose centroid lies in the top half.
        top = _d_binary([r <= 20 for r in 1:60, c in 1:80])
        @test UTCGP.number_shapeFromImg.objs_area_mean(m, top) ≈ mean(fractions[1:2])
        # Mean intensity per object, aggregated.
        values = zeros(60, 80)
        values[population] .= 0.5
        values[45:53, 65:73] .= 0.9
        img = _d_intensity(values)
        @test UTCGP.number_shapeFromImg.objs_intensity_max(img, m) ≈ Float64(N0f8(0.9))
        @test UTCGP.number_shapeFromImg.objs_intensity_min(img, m) ≈ Float64(N0f8(0.5))
        @test UTCGP.number_shapeFromImg.objs_intensity_mean(img, img, 0.3) ≈ (4 * Float64(N0f8(0.5)) + Float64(N0f8(0.9))) / 5
    end

    @testset "granulometry" begin
        function naive_open(fg, r)
            h, w = size(fg)
            disk = [(dr, dc) for dr in -r:r, dc in -r:r if dr^2 + dc^2 <= r^2]
            eroded = [fg[i, j] && all(!(1 <= i + dr <= h && 1 <= j + dc <= w) || fg[i+dr, j+dc] for (dr, dc) in disk) for i in 1:h, j in 1:w]
            return [any(1 <= i + dr <= h && 1 <= j + dc <= w && eroded[i+dr, j+dc] for (dr, dc) in disk) for i in 1:h, j in 1:w]
        end
        blobs = (rand(MersenneTwister(9), 40, 50) .< 0.45)
        blobs[10:25, 10:30] .= true
        m = _d_binary(blobs)
        for r in (1, 2, 3, 4)
            @test getfield(G, Symbol(:gran_open_r, r))(m) ≈ count(naive_open(blobs, r) .& blobs) / count(blobs)
            @test getfield(G, Symbol(:gran_open_bg_r, r))(m) ≈ count(naive_open(.!blobs, r) .& .!blobs) / count(.!blobs)
        end
        @test G.gran_open(m, 0.0) == G.gran_open_r1(m)
        # The size distribution decreases with the radius.
        fractions = [getfield(G, Symbol(:gran_open_r, r))(m) for r in (1, 2, 3, 4, 6, 8)]
        @test issorted(fractions; rev = true)
        disk = [(r - 20)^2 + (c - 20)^2 <= 64 for r in 1:40, c in 1:40]
        @test G.gran_thickness_max(_d_binary(disk)) ≈ sqrt(65) / 20      # nearest background at √65 px, over half-side 20
        @test G.gran_open_r8(_d_binary(disk)) == 1.0                    # a radius-8 disk survives radius 8
        @test G.gran_open_r6(_d_binary(disk)) > 0.9                     # digital disks do not tile it exactly
        @test G.gran_open(_d_binary(disk), 9 / 15) == 0.0               # radius 10: nothing left

        function naive_filter(v, k, f)
            h, w = size(v)
            return [f(v[max(i-k, 1):min(i+k, h), max(j-k, 1):min(j+k, w)]) for i in 1:h, j in 1:w]
        end
        v = _d_values(img8)
        for k in (1, 2, 4, 8)
            opened = naive_filter(naive_filter(v, k, minimum), k, maximum)
            closed = naive_filter(naive_filter(v, k, maximum), k, minimum)
            @test getfield(G, Symbol(:gran_grey_open_r, k))(img8) ≈ sum(opened) / sum(v)
            @test getfield(G, Symbol(:gran_grey_close_r, k))(img8) ≈ sum(1 .- closed) / sum(1 .- v)
            @test getfield(G, Symbol(:gran_grey_open_r, k))(img8, roi) ≈ sum(opened[roi_bits]) / sum(v[roi_bits])
        end
    end

    @testset "bundles: arity, finite Float64 on every input form" begin
        mask = _d_binary(shape)
        img = _d_intensity(0.3 .+ 0.5 .* shape)
        @test length(bundle_number_intensityStatsFromImg) == 51
        @test length(bundle_number_shapeFromImg) == 21
        @test length(bundle_number_objectStatsFromImg) == 43
        @test length(bundle_number_granulometryFromImg) == 27
        for bundle in (bundle_number_intensityStatsFromImg, bundle_number_shapeFromImg,
                bundle_number_objectStatsFromImg, bundle_number_granulometryFromImg)
            for wrapper in bundle
                @test all(m -> m.nargs <= 5, methods(wrapper.fn))
                called = 0
                for inputs in ((img,), (mask,), (img, mask), (img, img), (img, 0.4), (mask, mask),
                        (img, mask, 0.3), (img, img, 0.7), (mask, NaN))
                    hasmethod(wrapper.fn, typeof(inputs)) || continue
                    value = wrapper.fn(inputs...)
                    called += 1
                    @test value isa Float64
                    @test isfinite(value)
                end
                @test called > 0
            end
        end
    end
end
