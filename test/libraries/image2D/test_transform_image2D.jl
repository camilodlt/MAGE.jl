@testset "Geometric transforms" begin
    O = UTCGP.number_objectFromImg
    _tr_intensity(values) = SImageND(IntensityPixel{N0f8}.(clamp.(values, 0.0, 1.0)))
    _tr_binary(values) = SImageND(BinaryPixel.(Bool.(values)))
    _tr_values(img) = Float64.(reinterpret(img.img))
    h, w = 20, 30
    values = zeros(h, w)
    values[3:6, 4:9] .= 1.0                                       # top-left block
    values[15, 20] = 0.6
    img = _tr_intensity(values)
    I = typeof(img)
    mask = _tr_binary(values .> 0.5)
    B = typeof(mask)
    segment = SImageND(SegmentPixel.(Int.(round.(3 .* values))))
    G = typeof(segment)
    op(bundle, name, T) = bundle[name].fn(T)
    iop(name) = op(bundle_image2DIntensity_transform_factory, name, I)
    bop(name) = op(bundle_image2DBinary_transform_factory, name, B)

    @testset "flips and quarter turns" begin
        @test _tr_values(iop(:transform_flip_h)(img)) == values[:, end:-1:1]
        @test _tr_values(iop(:transform_flip_v)(img)) == values[end:-1:1, :]
        @test _tr_values(iop(:transform_rotate_180)(img)) == values[end:-1:1, end:-1:1]
        square_values = zeros(10, 10)
        square_values[1:2, 8:10] .= 1.0                           # top-right corner
        square = _tr_binary(square_values .> 0.5)
        S = typeof(square)
        r90 = Bool.(reinterpret(op(bundle_image2DBinary_transform_factory, :transform_rotate_90, S)(square).img))
        r270 = Bool.(reinterpret(op(bundle_image2DBinary_transform_factory, :transform_rotate_270, S)(square).img))
        @test r90 == rotl90(square_values .> 0.5)                 # counter-clockwise on screen
        @test r270 == rotr90(square_values .> 0.5)
        @test typeof(iop(:transform_rotate_90)(img)) == I          # rectangular: stretched back
    end

    @testset "rotate" begin
        @test _tr_values(iop(:transform_rotate)(img, 0.0)) ≈ values atol = 1e-2
        @test _tr_values(iop(:transform_rotate)(img, 0.5)) ≈ values[end:-1:1, end:-1:1] atol = 0.02
        # A quarter turn counter-clockwise moves the right side of a square image to the top.
        sq = zeros(21, 21)
        sq[11, 15:19] .= 1.0
        rotated = _tr_values(op(bundle_image2DIntensity_transform_factory, :transform_rotate,
            typeof(_tr_intensity(sq)))(_tr_intensity(sq), 0.25))
        @test argmax(vec(sum(rotated; dims = 2))) < 11
        @test argmax(vec(sum(rotated; dims = 1))) == 11
    end

    @testset "shifts" begin
        right = bop(:transform_shift)(mask, 0.6, 0.5)              # +3 columns
        @test Bool.(reinterpret(right.img))[3:6, 7:12] == trues(4, 6)
        @test !any(Bool.(reinterpret(right.img))[:, 1:3])
        @test bop(:transform_shift)(mask, 0.5).img == mask.img
        wrapped = _tr_values(iop(:transform_shift_wrap)(img, 1.0, 0.5)) # +15 columns, wraps
        @test wrapped == circshift(values, (0, 15))
        @test _tr_values(iop(:transform_shift)(img, 0.5, 0.0))[1:2, :] == values[11:12, :]
    end

    @testset "mask-driven poses" begin
        @test iop(:transform_flip_h_if_right)(img, mask).img == img.img     # block already left
        mirrored = iop(:transform_flip_h)(img)
        @test _tr_values(iop(:transform_flip_h_if_right)(mirrored)) == values
        @test _tr_values(iop(:transform_flip_v_if_bottom)(iop(:transform_flip_v)(img))) == values

        diagonal = zeros(31, 31)
        for k in -8:8
            diagonal[16 + k, 16 + k] = 1.0
            diagonal[16 + k, 17 + k] = 1.0
        end
        D = _tr_binary(diagonal .> 0.5)
        DT = typeof(D)
        aligned = op(bundle_image2DBinary_transform_factory, :transform_align_axis, DT)(D)
        @test O.obj_orientation_largest(aligned) ≈ 0.5 atol = 0.05      # horizontal
        @test O.obj_elongation_largest(aligned) > 0.8

        offset = zeros(31, 31)
        offset[4:5, 4:14] .= 1.0
        posed = op(bundle_image2DBinary_transform_factory, :transform_canonical_pose, DT)(_tr_binary(offset .> 0.5))
        @test O.obj_x_largest(posed) ≈ 0.5 atol = 0.04
        @test O.obj_y_largest(posed) ≈ 0.5 atol = 0.04
        @test O.obj_orientation_largest(posed) ≈ 0.5 atol = 0.05
        # Empty masks leave the image unchanged.
        @test iop(:transform_align_axis)(img, _tr_binary(falses(h, w))).img == img.img
    end

    @testset "bundles: every operator on every kind" begin
        cases = (
            (bundle_image2DIntensity_transform_factory, img, ((img,), (img, 0.3), (img, 0.3, 0.8), (img, mask), (img, img))),
            (bundle_image2DBinary_transform_factory, mask, ((mask,), (mask, 0.3), (mask, 0.3, 0.8), (mask, mask), (mask, img))),
            (bundle_image2DSegment_transform_factory, segment, ((segment,), (segment, 0.3), (segment, 0.3, 0.8), (segment, mask), (segment, img))),
        )
        for (bundle, prototype, input_sets) in cases
            T = typeof(prototype)
            @test length(bundle) == 12
            for wrapper in bundle
                fn = wrapper.fn(T)
                @test all(m -> m.nargs <= 5, methods(fn))
                called = 0
                for inputs in input_sets
                    hasmethod(fn, typeof(inputs)) || continue
                    called += 1
                    @test typeof(fn(inputs...)) == T
                end
                @test called > 0
            end
        end
        rotated_segment = op(bundle_image2DSegment_transform_factory, :transform_rotate, G)(segment, 0.1)
        @test Set(Int.(reinterpret(rotated_segment.img))) ⊆ Set(Int.(reinterpret(segment.img)))
    end
end
