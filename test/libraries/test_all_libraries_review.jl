# Regression tests for the bugs found by fuzzing every image / float / int bundle.
using Statistics: mean

@testset "All-libraries review fixes" begin
    call(f, args...) = Base.invokelatest(f, args...)
    v = [0.15 + 0.1 * sin(r / 3) * cos(c / 4) for r in 1:32, c in 1:28]
    v[6:12, 5:11] .= 0.85
    img = SImageND(IntensityPixel{N0f8}.(v))
    I = typeof(img)
    B = typeof(SImageND(BinaryPixel.(falses(32, 28))))
    pixels(x) = Float64.(reinterpret(x.img))

    @testset "stdpool with a 1-pixel window" begin
        # k < 1.5 gives a 1-pixel window, whose std was NaN and could not be stored.
        for (bundle, T, input) in ((bundle_image2DIntensity_pooler_factory, I, img),
                                   (bundle_image2DBinary_pooler_factory, B, SImageND(BinaryPixel.(v .> 0.5))),
                                   (bundle_image2DSegment_pooler_factory, typeof(SImageND(SegmentPixel{Int}.(zeros(Int, 32, 28)))),
                                    SImageND(SegmentPixel{Int}.(Int.(v .> 0.5)))))
            out = call(bundle[:stdpool].fn(T), input, 1.0, 1.0)
            @test all(iszero, pixels(out))
        end
    end

    @testset "thresholding a constant image" begin
        for value in (0.0, 0.4, 1.0)
            flat = SImageND(IntensityPixel{N0f8}.(fill(value, 32, 28)))
            for name in (:binarize_moments2D, :binarize_polysegment2D)
                out = call(bundle_image2DBinary_binarize_factory[name].fn(B), flat)
                @test !any(Bool.(reinterpret(out.img)))          # empty, like the histogram methods
            end
        end
    end

    @testset "saliency with extreme parameters" begin
        for name in (:itti_koch_saliency, :spectral_residual_saliency)
            f = bundle_image2DIntensity_saliency_fixation_factory[name].fn(I)
            for x in (1e-300, 1e30, -1e30)
                @test call(f, img, 2.0, x) isa I                    # vanishing σ gave a NaN kernel
                @test call(f, img, x, 1.0) isa I                    # huge radius overflowed round(Int, ·)
            end
        end
    end

    @testset "filters do not amplify floating-point noise" begin
        vertical = SImageND(IntensityPixel{N0f8}.([c > 14 ? 1.0 : 0.0 for r in 1:32, c in 1:28]))
        sobely = bundle_image2DIntensity_filtering_factory[:sobely_image2D].fn(I)
        @test all(iszero, pixels(call(sobely, vertical)))           # no horizontal edge anywhere
        sobelx = bundle_image2DIntensity_filtering_factory[:sobelx_image2D].fn(I)
        out = pixels(call(sobelx, vertical))
        @test out[16, 14] == 0.0 && out[16, 3] == 1.0               # brightening edge dark, flat bright
    end

    @testset "image graph descriptors run" begin
        m = falses(40, 40)
        for (r, c) in ((5, 5), (5, 30), (20, 15), (33, 8), (30, 32), (15, 36))
            m[r:r+3, c:c+3] .= true
        end
        mask = SImageND(BinaryPixel.(m))
        for w in bundle_float_imagegraph
            @test isfinite(Float64(call(w.fn, mask)))               # every operator threw UndefVarError
        end
    end

    @testset "image graph coordinates: x is the column" begin
        m = falses(40, 50)
        for (r, c) in ((2, 2), (2, 45), (36, 2), (36, 45), (12, 30))   # four corners + an inner hub
            m[r:r+2, c:c+2] .= true
        end
        mask = SImageND(BinaryPixel.(m))
        x = call(bundle_float_imagegraph[:xcoorargmaxdegreecentrality].fn, mask)
        y = call(bundle_float_imagegraph[:ycoorargmaxdegreecentrality].fn, mask)
        @test (x, y) == (31.0, 13.0)                                   # hub centroid: column 31, row 13
    end

    @testset "foreground extraction from a rough mask" begin
        D = UTCGP.image2D_foreground_extraction_discrete
        square = falses(30, 30); square[6:25, 6:25] .= true
        fg, bg = D._mask_band_seeds(square, 2)
        @test count(fg) == 16^2 && fg[8, 8] && !fg[7, 7]               # 20-px square shrunk by 2 on each side
        @test !bg[4, 10] && bg[3, 10] && count(bg .& square) == 0      # background from 3 px outside (row 3)
        thin = falses(30, 30); thin[10:11, 5:25] .= true                # 2 px thick, thinner than the band
        @test any(D._mask_band_seeds(thin, 4)[1])                       # still seeded

        n = 64
        disk = [(r - 30)^2 + (c - 36)^2 <= 14^2 for r in 1:n, c in 1:n]
        noise = [0.05 * sin(7r) * cos(5c) for r in 1:n, c in 1:n]
        image = SImageND(IntensityPixel{N0f8}.(clamp.(0.2 .+ 0.5 .* disk .+ noise, 0, 1)))
        Iim, Bim = typeof(image), typeof(SImageND(BinaryPixel.(falses(n, n))))
        blocky = SImageND(BinaryPixel.([disk[8 * cld(r, 8) - 4, 8 * cld(c, 8) - 4] for r in 1:n, c in 1:n]))
        empty = SImageND(BinaryPixel.(falses(n, n)))
        iou(m) = count(m .& disk) / count(m .| disk)
        for (bundle, name, T) in ((bundle_image2DBinary_foreground_extraction_factory, :boykov_jolly_foreground, Bim),
                                  (bundle_image2DBinary_foreground_extraction_factory, :grabcut_foreground, Bim),
                                  (bundle_image2DIntensity_foreground_extraction_factory, :random_walker_foreground, Iim),
                                  (bundle_image2DIntensity_foreground_extraction_factory, :closed_form_matting, Iim))
            f = bundle[name].fn(T)
            mask_of(out) = pixels(out) .> 0.5
            @test iou(mask_of(call(f, image, blocky, 5.0))) >= 0.95        # the blocky mask alone: 0.79
            @test call(f, image, blocky) == call(f, image, blocky, 4.0)    # default band 4
            @test call(f, image, blocky, NaN) == call(f, image, blocky, 4.0)
            @test !any(mask_of(call(f, image, empty, 4.0)))                # empty mask, empty result
            @test call(f, image) isa T                                     # the saliency mode is still there
        end
    end

    @testset "number_div throws an instance" begin
        @test_throws DivideError UTCGP.number_arithmetic.number_div(1, 0)
    end
end
