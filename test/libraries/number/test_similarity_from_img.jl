@testset "Image similarity and template matching" begin
    S = UTCGP.number_similarityFromImg
    _sim_intensity(values) = SImageND(IntensityPixel{N0f8}.(clamp.(values, 0.0, 1.0)))
    _sim_binary(values) = SImageND(BinaryPixel.(Bool.(values)))
    h, w = 24, 32
    rng = MersenneTwister(7)
    base = 0.1 .+ 0.1 .* rand(rng, h, w)
    base[6:11, 8:13] .= 0.9                          # square
    base[16:18, 18:28] .= 0.6                        # bar
    a = _sim_intensity(base)
    shifted_values = zeros(h, w)
    shifted_values[:, 4:end] .= base[:, 1:end-3]     # 3 px to the right
    shifted = _sim_intensity(shifted_values)
    inverted = _sim_intensity(1 .- base)
    mask_a = _sim_binary(base .> 0.5)
    mask_shifted = _sim_binary(shifted_values .> 0.5)
    empty = _sim_binary(falses(h, w))

    @testset "identity" begin
        @test S.sim_mse(a, a) == 0.0
        @test S.sim_mae(a, a) == 0.0
        @test S.sim_correlation(a, a) ≈ 1.0
        @test S.sim_ssim(a, a) ≈ 1.0
        @test S.sim_hist_intersection(a, a) ≈ 1.0
        @test S.sim_hist_bhattacharyya(a, a) ≈ 1.0
        @test S.sim_iou(a, a) == 1.0
        @test S.sim_dice(mask_a, mask_a) == 1.0
        @test S.sim_hamming(mask_a, mask_a) == 0.0
        @test S.sim_chamfer(mask_a, mask_a) == 0.0
        @test S.sim_shift_x(a, a) == 0.0
    end

    @testset "differences" begin
        @test S.sim_correlation(a, inverted) ≈ -1.0 atol = 1e-2
        @test S.sim_ssim(a, inverted) < 0.0
        @test S.sim_mse(a, inverted) > S.sim_mse(a, shifted) > 0.0
        @test 0.0 < S.sim_iou(mask_a, mask_shifted) < 1.0
        @test S.sim_dice(mask_a, mask_shifted) > S.sim_iou(mask_a, mask_shifted)
        @test S.sim_coverage(_sim_binary(base .> 0.8), mask_a) == 1.0          # square inside the full mask
        @test S.sim_coverage(mask_a, _sim_binary(base .> 0.8)) < 1.0
        far_values = zeros(h, w)
        far_values[:, 9:end] .= base[:, 1:end-8]
        mask_far = _sim_binary(far_values .> 0.5)
        @test 0.0 < S.sim_chamfer(mask_a, mask_shifted) < S.sim_chamfer(mask_a, mask_far)
        @test S.sim_iou(empty, empty) == 1.0
        @test S.sim_chamfer(mask_a, empty) == 1.0
        # The histogram ignores where things are: a shift barely changes it.
        @test S.sim_hist_intersection(a, shifted) > 0.85
    end

    @testset "shift estimation" begin
        @test S.sim_shift_x(a, shifted) ≈ 3 / w
        @test S.sim_shift_y(a, shifted) == 0.0
        down = zeros(h, w)
        down[3:end, :] .= base[1:end-2, :]
        @test S.sim_shift_y(a, _sim_intensity(down)) ≈ 2 / h
        @test S.sim_shift_x(shifted, a) ≈ -3 / w
    end

    @testset "masked comparisons" begin
        inside = _sim_binary(base .> 0.5)
        changed = copy(base)
        changed[1:3, 1:3] .= 1.0                     # outside the mask
        @test S.sim_mse(a, _sim_intensity(changed), inside) == 0.0
        @test S.sim_mse(a, _sim_intensity(changed)) > 0.0
    end

    @testset "template matching" begin
        # Reference: the square centred in the frame.
        ref_values = fill(0.15, h, w)
        ref_values[10:15, 14:19] .= 0.9
        ref_values[12:13, 16:17] .= 0.3              # texture so the template is not flat
        ref = _sim_intensity(ref_values)
        scene = fill(0.15, h, w)
        scene[4:9, 22:27] .= 0.9
        scene[6:7, 24:25] .= 0.3
        img = _sim_intensity(scene)
        @test S.match_x_30p(img, ref) ≈ (24.5 - 1) / (w - 1) atol = 0.04
        @test S.match_y_30p(img, ref) ≈ (6.5 - 1) / (h - 1) atol = 0.05
        @test S.match_score_30p(img, ref) > 0.95
        @test S.match_score_30p(_sim_intensity(fill(0.4, h, w)), ref) == 0.0
        @test S.match_x_10p(img, _sim_intensity(fill(0.4, h, w))) == 0.5
        # Template around a given point of the reference.
        @test S.match_x_20p(ref, ref, 0.5) ≈ 0.5 atol = 0.05
    end

    @testset "bundles" begin
        for bundle in (bundle_number_similarityFromImg, bundle_number_templateFromImg)
            for wrapper in bundle
                @test all(m -> m.nargs <= 5, methods(wrapper.fn))
                for inputs in ((a, shifted), (mask_a, mask_shifted), (a, mask_a), (a, shifted, 0.3), (a, shifted, mask_a))
                    hasmethod(wrapper.fn, typeof(inputs)) || continue
                    value = wrapper.fn(inputs...)
                    @test value isa Float64
                    @test isfinite(value)
                end
            end
        end
        @test_throws DimensionMismatch S.sim_mse(a, _sim_intensity(zeros(h, w + 1)))
    end
end
