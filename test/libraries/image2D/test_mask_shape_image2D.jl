@testset "Mask shape clean-up" begin
    _ms_binary(values) = SImageND(BinaryPixel.(Bool.(values)))
    _ms_bits(img) = Bool.(reinterpret(img.img))
    h, w = 24, 30
    ring = falses(h, w)                  # 8x8 square with a 4x4 hole
    ring[3:10, 3:10] .= true
    ring[5:8, 5:8] .= false
    open_ring = copy(ring)               # same, but the hole leaks to the border
    open_ring[3:4, 6] .= false
    cshape = falses(h, w)                # concave "C"
    cshape[14:21, 3:4] .= true
    cshape[14:15, 3:10] .= true
    cshape[20:21, 3:10] .= true
    speck = falses(h, w)
    speck[2, 20] = true
    border_obj = falses(h, w)
    border_obj[10:14, w-1:w] .= true
    bar = falses(h, w)
    bar[18:19, 14:26] .= true
    scene = ring .| cshape .| speck .| border_obj .| bar
    mask = _ms_binary(scene)
    B = typeof(mask)
    saliency = SImageND(IntensityPixel{N0f8}.(0.8 .* scene))
    I = typeof(saliency)
    op(name) = bundle_image2DBinary_maskshape_factory[name].fn(B)
    iop(name) = bundle_image2DIntensity_maskshape_factory[name].fn(I)

    @testset "fill holes" begin
        filled = _ms_bits(op(:shape_fill_holes)(mask))
        @test all(filled[3:10, 3:10])
        @test count(filled) == count(scene) + 16
        @test _ms_bits(op(:shape_holes)(mask)) == (filled .& .!scene)
        # A hole open to the border is not a hole.
        @test _ms_bits(op(:shape_fill_holes)(_ms_binary(open_ring))) == open_ring
        # With a size limit, only small holes are filled.
        @test _ms_bits(op(:shape_fill_holes)(mask, 10 / (h * w))) == scene
        @test _ms_bits(op(:shape_fill_holes)(mask, 16 / (h * w))) == filled
        # Intensity input, thresholded.
        @test _ms_bits(op(:shape_fill_holes)(saliency)) == filled
        @test _ms_bits(op(:shape_fill_holes)(saliency, 0.9)) == falses(h, w)
    end

    @testset "hulls and boxes" begin
        c = _ms_binary(cshape)
        hull = _ms_bits(op(:shape_convex_hull)(c))
        @test all(hull[14:21, 3:10])
        @test count(hull) == 64
        objects = _ms_bits(op(:shape_convex_hull_objects)(mask))
        @test all(objects .>= scene)
        @test all(objects[14:21, 3:10])
        @test !objects[12, 12]                      # no hull bridging two objects
        whole = _ms_bits(op(:shape_convex_hull)(mask))
        @test whole[12, 12]
        boxes = _ms_bits(op(:shape_bbox_fill)(mask))
        @test all(boxes[14:21, 3:10]) && all(boxes[3:10, 3:10])
    end

    @testset "skeleton and boundary" begin
        skeleton = _ms_bits(op(:shape_skeleton)(_ms_binary(bar)))
        @test 0 < count(skeleton) <= 13
        @test all(skeleton .<= bar)
        boundary = _ms_bits(op(:shape_boundary)(_ms_binary(ring)))
        # A 2-px-thick ring is all boundary except its 4 inner corners, which touch
        # the hole only diagonally.
        @test count(boundary) == count(ring) - 4
        solid = falses(h, w)
        solid[5:12, 5:12] .= true
        @test count(_ms_bits(op(:shape_boundary)(_ms_binary(solid)))) == 28
    end

    @testset "size and border filters" begin
        @test !any(_ms_bits(op(:shape_remove_small)(mask, 2 / (h * w))) .& speck)
        @test _ms_bits(op(:shape_remove_small)(mask, 0.0)) == scene
        @test _ms_bits(op(:shape_remove_large)(mask, 12 / (h * w))) == (speck .| border_obj)
        cleared = _ms_bits(op(:shape_clear_border)(mask))
        @test cleared == (scene .& .!border_obj)
        @test _ms_bits(op(:shape_keep_border)(mask)) == border_obj
        noisy = copy(bar)
        noisy[5, 25] = true
        noisy[18, 20] = false
        @test _ms_bits(op(:shape_majority)(_ms_binary(noisy)))[5, 25] == false
        @test _ms_bits(op(:shape_majority)(_ms_binary(noisy)))[18, 20] == true
    end

    @testset "distance maps" begin
        solid = falses(h, w)
        solid[5:13, 5:13] .= true
        inside = Float64.(reinterpret(iop(:shape_distance_inside)(_ms_binary(solid)).img))
        @test maximum(inside) ≈ 1.0 atol = 0.01
        @test argmax(inside) == CartesianIndex(9, 9)
        @test all(inside[.!solid] .== 0.0)
        proximity = Float64.(reinterpret(iop(:shape_proximity)(_ms_binary(solid)).img))
        @test all(proximity[solid] .≈ 1.0)
        @test proximity[5, 20] > proximity[5, 28]
        @test all(Float64.(reinterpret(iop(:shape_proximity)(_ms_binary(falses(h, w))).img)) .== 0.0)
        @test typeof(iop(:shape_distance_inside)(saliency)) == I
    end

    @testset "bundles: every operator on every input form" begin
        empty = _ms_binary(falses(h, w))
        full = _ms_binary(trues(h, w))
        for (bundle, T) in ((bundle_image2DBinary_maskshape_factory, B), (bundle_image2DIntensity_maskshape_factory, I))
            for wrapper in bundle
                fn = wrapper.fn(T)
                @test all(m -> m.nargs <= 5, methods(fn))
                for inputs in ((mask,), (mask, 0.3), (saliency,), (saliency, 0.5), (saliency, 0.5, 0.2), (empty,), (full,), (mask, NaN))
                    @test typeof(fn(inputs...)) == T
                end
            end
        end
        @test length(bundle_image2DBinary_maskshape_factory) == 12
        @test length(bundle_image2DIntensity_maskshape_factory) == 2
    end
end
