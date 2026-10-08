# Regression tests for the bugs found when reviewing the saliency, orientation,
# pooling, filtering, region and Haar libraries.
using Statistics: mean

@testset "Image library review fixes" begin
    call(f, args...) = Base.invokelatest(f, args...)
    v = [0.5 + 0.4 * sin(r / 3) * cos(c / 4) for r in 1:28, c in 1:28]
    img = SImageND(IntensityPixel{N0f8}.(v))
    I = typeof(img)
    mask = SImageND(BinaryPixel.(v .> 0.5))
    B = typeof(mask)
    labels = SImageND(SegmentPixel{Int}.([c <= 14 ? 1 : 3 for r in 1:28, c in 1:28]))
    Sg = typeof(labels)

    @testset "non-finite parameters never throw" begin
        for x in (NaN, Inf, -Inf, 1e30)
            @test call(bundle_image2DIntensity_pool_factory[:avgpool_blocks].fn(I), img, x) isa I
            @test call(bundle_image2DIntensity_pool_factory[:maxpool_cross_blocks].fn(I), img, x) isa I
            @test call(bundle_image2DIntensity_pooler_factory[:meanpool].fn(I), img, x, x) isa I
            @test call(bundle_image2DIntensity_morph_factory[:erosion_2D].fn(I), img, x) isa I
            @test call(bundle_image2DBinary_binarize_factory[:binarize_otsu2D].fn(B), img, x) isa B
            @test call(bundle_image2DBinary_binarize_factory[:binarize_sauvola2D].fn(B), img, x, x) isa B
            @test call(bundle_image2DBinary_filtering_factory[:findlocalmaxima_image2D].fn(B), img, x, x) isa B
            @test isfinite(UTCGP.number_regionFromImg.region_mean(img, x, 0.5))
            @test isfinite(UTCGP.number_haarFromImg.haar_lr(img, x, x))
            @test call(bundle_image2DIntensity_orientation_factory[:orientation_select].fn(I), img, x, x) isa I
        end
    end

    @testset "filter parameters are all used" begin
        dog = bundle_image2DIntensity_filtering_factory[:dog_image2D].fn(I)
        # σ along y and along x: swapping them changes the result on a non-symmetric image.
        @test call(dog, img, 1.0, 3.0).img != call(dog, img, 3.0, 1.0).img
        moffat5 = bundle_image2DIntensity_filtering_factory[:moffat5_image2D].fn(I)
        moffat25 = bundle_image2DIntensity_filtering_factory[:moffat25_image2D].fn(I)
        @test nameof(moffat5) != nameof(moffat25)                       # no longer one shared function
        @test call(moffat5, img, 2.0, 1.5).img != call(moffat25, img, 2.0, 1.5).img
        @test call(moffat5, img, 2.0, 1.5).img != call(moffat5, img, 2.0, 5.0).img   # β is used
        peaks = bundle_image2DBinary_filtering_factory[:findlocalmaxima_image2D].fn(B)
        noisy = SImageND(IntensityPixel{N0f8}.([mod(37r + 53c * r, 101) / 100 for r in 1:28, c in 1:28]))
        count_peaks(w1, w2) = count(Bool.(reinterpret(call(peaks, noisy, w1, w2).img)))
        @test count_peaks(3, 3) > count_peaks(3, 15)                              # second window size is used
    end

    @testset "label maps keep their labels" begin
        for (bundle, name) in ((bundle_image2DSegment_pool_factory, :avgpool_blocks),
                               (bundle_image2DSegment_pool_factory, :avgpool_cross_blocks),
                               (bundle_image2DSegment_pooler_factory, :meanpool))
            out = call(bundle[name].fn(Sg), labels, 10)
            @test issubset(unique(Int.(reinterpret(out.img))), (1, 3))       # never the invented label 2
        end
        zero_labels = SImageND(SegmentPixel{Int}.(zeros(Int, 28, 28)))
        as_intensity = call(bundle_image2DIntensity_basic_factory[:experimental_tointensity_image2D].fn(I), zero_labels)
        @test all(iszero, Float64.(reinterpret(as_intensity.img)))
    end

    @testset "region windows and contrast" begin
        R = UTCGP.number_regionFromImg
        @test isfinite(R.region_std_5p(img, 0.5, 0.5))                       # 5% of 28 px is a 3 px window, not 1 px
        w = zeros(28, 28)
        w[:, 27:28] .= 1.0
        edge = SImageND(IntensityPixel{N0f8}.(w))
        inner = mean(w[13:15, 27:28])                                        # centre (row 15, column 28), clipped
        ring = [w[r, c] for r in 13:17, c in 26:28 if !(14 <= r <= 16 && 27 <= c <= 28)]
        @test R.region_contrast(edge, 1.0, 0.5) ≈ mean(w[14:16, 27:28]) - mean(ring) atol = 1e-6
    end

    @testset "three-band Haar masks are centred" begin
        H = UTCGP.number_haarFromImg
        @test H._haar_weight_matrix(:haar_three_h, 1, 5) == [0.0 1.0 -1.0 1.0 0.0]
        @test H._haar_weight_matrix(:haar_three_v, 5, 1) == reshape([0.0, 1.0, -1.0, 1.0, 0.0], 5, 1)
        cs = H._haar_weight_matrix(:haar_center_surround, 5, 5)
        @test cs == reverse(cs, dims = 1) == reverse(cs, dims = 2)        # centre sits in the middle
        @test count(>(0), cs) == 9
        @test [H._centre_side(n) for n in 2:8] == [1, 1, 2, 3, 2, 3, 4]
    end

    @testset "orientation conventions agree" begin
        vertical = SImageND(IntensityPixel{N0f8}.([c > 14 ? 1.0 : 0.0 for r in 1:28, c in 1:28]))
        @test UTCGP.float_orientation.orientation_energy_90(vertical) ≈ 1.0 atol = 1e-9
        @test UTCGP.float_orientation.dominant_orientation(vertical) == 0.5
        select = bundle_image2DIntensity_orientation_factory[:orientation_select].fn(I)
        @test count(>(0), Float64.(reinterpret(call(select, vertical, 0.0, 0.1).img))) > 0   # gradient θ = 0: vertical edges
        @test count(>(0), Float64.(reinterpret(call(select, vertical, 0.5, 0.1).img))) == 0
        # flat areas carry ~1e-17 filter noise: it must not get an angle nor be rescaled to full range
        for θ in (0.25, 0.5, 0.75)
            @test count(>(0), Float64.(reinterpret(call(select, vertical, θ, 0.1).img))) == 0
        end
        grad_orientation = bundle_image2DIntensity_orientation_factory[:grad_orientation].fn(I)
        @test all(iszero, Float64.(reinterpret(call(grad_orientation, vertical).img))[:, 1:10])
    end
end
