function generate_binarize_test_image(::Type{IntensityPixel{T}}, size = (10, 10)) where {T}
    # Create a gradient image for intensity
    img = [i / size[1] + j / size[2] for i = 1:size[1], j = 1:size[2]]
    img = img ./ maximum(img)  # Normalize to range [0, 1]
    return SImageND(IntensityPixel{T}.(img))
end

function generate_binarize_test_image(::Type{BinaryPixel{Bool}}, size = (10, 10))
    # Create a gradient image for intensity
    return SImageND(BinaryPixel{Bool}.(trues(10, 10)))
end

INTENSITY = IntensityPixel{N0f8}
BINARY = BinaryPixel{Bool}

@testset "Image2D Arithmetic: subtract_image2D" begin

    @testset "Binary Result" begin
        Bundle = bundle_image2DBinary_arithmetic_factory
        test_img1 = generate_binarize_test_image(BINARY)
        test_img2 = generate_binarize_test_image(BINARY)
        test_img3 = generate_binarize_test_image(INTENSITY)
        fn = Bundle[:subtract_img2D]
        fn = fn.fn(typeof(test_img1))

        @testset for (ith, pack) in enumerate([
            [test_img1, test_img2],
            [test_img1, test_img3],
            [test_img3, test_img1],
            [test_img3, test_img3],
        ])
            res = fn(pack[1], pack[2])
            @test eltype(res) == BinaryPixel{Bool}
            @test size(res) == size(test_img1)
            @test all(x -> x == 0 || x == 1, res)
            if ith == 1 || ith == 3 || ith == 4
                @test all(res .== 0) # all clamped to 0
            else # some values will be rounded to 1 even after sub
                @test sum(res .== 0) < 100
            end
        end
    end

    @testset "Intensity Result" begin
        Bundle = bundle_image2DBinary_arithmetic_factory
        test_img1 = generate_binarize_test_image(BINARY)
        test_img2 = generate_binarize_test_image(BINARY)
        test_img3 = generate_binarize_test_image(INTENSITY)
        fn = Bundle[:subtract_img2D]
        fn = fn.fn(typeof(test_img3))

        @testset for (ith, pack) in enumerate([
            [test_img1, test_img2],
            [test_img1, test_img3],
            [test_img3, test_img1],
            [test_img3, test_img3],
        ])
            res = fn(pack[1], pack[2])
            @test eltype(res) == INTENSITY
            @test size(res) == size(test_img1)
            @test all(0 .<= res .<= 1)
            if ith == 1 || ith == 3 || ith == 4
                @test all(res .== 0) # all clamped to 0
            else # not a single value can be 1 bc every pixel was subtracted an amount
                @test sum(res .== 1) == 0
            end
        end
    end
end

@testset "Image2D Arithmetic: add_image2D" begin

    @testset "Binary Result" begin
        Bundle = bundle_image2DBinary_arithmetic_factory
        test_img1 = generate_binarize_test_image(BINARY)
        test_img2 = generate_binarize_test_image(BINARY)
        test_img3 = generate_binarize_test_image(INTENSITY)
        fn = Bundle[:add_img2D]
        fn = fn.fn(typeof(test_img1))

        @testset for (ith, pack) in enumerate([
            [test_img1, test_img2],
            [test_img1, test_img3],
            [test_img3, test_img1],
            [test_img3, test_img3],
        ])
            res = fn(pack[1], pack[2])
            @test eltype(res) == BinaryPixel{Bool}
            @test size(res) == size(test_img1)
            @test all(x -> x == 0 || x == 1, res)
            if ith == 1 || ith == 2 || ith == 3
                @test all(res .== 1) # all clamped to 1
            else
                @test sum(float(res) .== 0) > 5 # some pixels even if added are rounded to 0
            end
        end
    end

    @testset "Intensity Result" begin
        Bundle = bundle_image2DBinary_arithmetic_factory
        test_img1 = generate_binarize_test_image(BINARY)
        test_img2 = generate_binarize_test_image(BINARY)
        test_img3 = generate_binarize_test_image(INTENSITY)
        fn = Bundle[:add_img2D]
        fn = fn.fn(typeof(test_img3))

        @testset for (ith, pack) in enumerate([
            [test_img1, test_img2],
            [test_img1, test_img3],
            [test_img3, test_img1],
            [test_img3, test_img3],
        ])
            res = fn(pack[1], pack[2])
            @test eltype(res) == IntensityPixel{N0f8}
            @test size(res) == size(test_img1)
            @test all(0 .<= res .<= 1)
            if ith == 1 || ith == 2 || ith == 3
                @test all(res .== 1) # all clamped to 1
            else
                @test sum(float(res) .<= 0.31) == 3 # some pixels even if added are less than 0.3
            end
        end
    end
end


@testset "Image2D Arithmetic: mult_image2D" begin

    @testset "Binary Result" begin
        Bundle = bundle_image2DBinary_arithmetic_factory
        test_img1 = generate_binarize_test_image(BINARY)
        test_img1.img[5, 5] = 0
        test_img2 = generate_binarize_test_image(BINARY)
        test_img3 = generate_binarize_test_image(INTENSITY)
        fn = Bundle[:mult_img2D]
        fn = fn.fn(typeof(test_img1))

        @testset for (ith, pack) in enumerate([
            [test_img1, test_img2],
            [test_img1, test_img3],
            [test_img3, test_img1],
            [test_img3, test_img3],
        ])
            res = fn(pack[1], pack[2])
            @test eltype(res) == BinaryPixel{Bool}
            @test size(res) == size(test_img1)
            @test all(x -> x == 0 || x == 1, res)
            if ith == 1 || ith == 2 || ith == 3
                @test res.img[5, 5] == 0 # Because * is like logical and.
            else
                @test res.img[5, 5] == 0 # bc rounded
                @test res.img[end-1] == 1  # bc rounded
            end
        end
    end

    @testset "Intensity Result" begin
        Bundle = bundle_image2DBinary_arithmetic_factory
        test_img1 = generate_binarize_test_image(BINARY)
        test_img1.img[5, 5] = 0
        test_img2 = generate_binarize_test_image(BINARY)
        test_img3 = generate_binarize_test_image(INTENSITY)
        fn = Bundle[:mult_img2D]
        fn = fn.fn(typeof(test_img3))

        @testset for (ith, pack) in enumerate([
            [test_img1, test_img2],
            [test_img1, test_img3],
            [test_img3, test_img1],
            [test_img3, test_img3],
        ])
            res = fn(pack[1], pack[2])
            @test eltype(res) == IntensityPixel{N0f8}
            @test size(res) == size(test_img1)
            @test all(0 .<= res .<= 1)
            if ith == 1 || ith == 2 || ith == 3
                @test res.img[5, 5] == 0 # Because * is like logical and.
            else
                @test res.img[5, 5] != 0 && res.img[5, 5] != test_img3.img[5, 5]
            end
        end
    end
end

# MAX
@testset "Image2D Arithmetic: max_image2D" begin
    Bundle = bundle_image2DBinary_arithmetic_factory
    test_img1 = generate_binarize_test_image(BINARY)
    test_img1.img[5, 5] = 0
    test_img2 = generate_binarize_test_image(BINARY)
    test_img3 = generate_binarize_test_image(INTENSITY)
    test_img3.img[5, 5] = 0.51

    @testset "Binary Result" begin
        fn = Bundle[:max_img2D]
        fn = fn.fn(typeof(test_img1))
        @testset for (ith, pack) in enumerate([
            [test_img1, test_img2],
            [test_img1, test_img3],
            [test_img3, test_img1],
            [test_img3, test_img3],
        ])
            res = fn(pack[1], pack[2])
            @test eltype(res) == BinaryPixel{Bool}
            @test size(res) == size(test_img1)
            @test all(x -> x == 0 || x == 1, res)
            if ith == 4
                @test sum(res .== 0) > 5 && sum(res .== 1) > 5
            else
                @test all(res .== 1) # All pixels should be 1 either by rounding or 1
            end
        end
    end

    test_img3.img[5, 5] = 0.51
    test_img1.img[5, 5] = 0
    @testset "Intensity Result" begin
        fn = Bundle[:max_img2D]
        fn = fn.fn(typeof(test_img3))
        @testset for (ith, pack) in enumerate([
            [test_img1, test_img2],
            [test_img1, test_img3],
            [test_img3, test_img1],
            [test_img3, test_img3],
        ])
            res = fn(pack[1], pack[2])
            @test eltype(res) == IntensityPixel{N0f8}
            @test size(res) == size(test_img1)
            @test all(0 .<= res .<= 1)
            if ith == 1
                @test all(res .== 1)
            elseif ith == 2 || ith == 3
                @test sum(res .== 1) == 99
                @test res.img[5, 5] == N0f8(0.51)
            else
                @test res.img[5, 5] == N0f8(0.51)
            end
        end
    end
end

@testset "Image2D Arithmetic: min_image2D" begin
    Bundle = bundle_image2DBinary_arithmetic_factory
    test_img1 = generate_binarize_test_image(BINARY)
    test_img1.img[5, 5] = 0
    test_img2 = generate_binarize_test_image(BINARY)
    test_img3 = generate_binarize_test_image(INTENSITY)
    test_img3.img[5, 5] = 0.51

    @testset "Binary Result" begin
        fn = Bundle[:min_img2D]
        fn = fn.fn(typeof(test_img1))
        @testset for (ith, pack) in enumerate([
            [test_img1, test_img2],
            [test_img1, test_img3],
            [test_img3, test_img1],
            [test_img3, test_img3],
        ])
            res = fn(pack[1], pack[2])
            @test eltype(res) == BinaryPixel{Bool}
            @test size(res) == size(test_img1)
            @test all(x -> x == 0 || x == 1, res)
            if ith == 4
                @test sum(res .== 0) > 5 && sum(res .== 1) > 5
            elseif ith == 1
                @test sum(res .== 0) == 1
            elseif ith == 2 || ith == 3
                @test sum(res .== 0) > 30
            end
        end
    end

    test_img3.img[5, 5] = 0.51
    test_img1.img[5, 5] = 0
    @testset "Intensity Result" begin
        fn = Bundle[:min_img2D]
        fn = fn.fn(typeof(test_img3))
        @testset for (ith, pack) in enumerate([
            [test_img1, test_img2],
            [test_img1, test_img3],
            [test_img3, test_img1],
            [test_img3, test_img3],
        ])
            res = fn(pack[1], pack[2])
            @test eltype(res) == IntensityPixel{N0f8}
            @test size(res) == size(test_img1)
            @test all(0 .<= res .<= 1)
            if ith == 1
                @test sum(res .== 0) == 1
            elseif ith == 2 || ith == 3
                @test res.img[5, 5] == N0f8(0) # the min with the binary with has 0
            else
                @test res.img[5, 5] == N0f8(0.51)
            end
        end
    end
end
