#################
# bsubtract_img #
#################

@testset "Image2D BArithmetic: bsubtract_image2D" begin
    Bundle = bundle_image2DIntensity_barithmetic_factory
    test_img = generate_binarize_test_image(INTENSITY)
    another_img = SImageND(BinaryPixel{Bool}.(zeros(10,10)))
    fn = Bundle[:bsubtract_image2D]
    fn = fn.fn(typeof(test_img))

    @testset "Intensity Result" begin
        for (ith, p) in enumerate([0.0, 0.3, 0.5, 0.8])
            res = fn(test_img, p)
            @test eltype(res) == IntensityPixel{N0f8}
            @test size(res) == size(test_img)
            @test all(0 .<= res .<= 1)
            if ith == 1
                @test all(res .== test_img)
            else
                @test res !== test_img
            end
        end
    end
    @testset begin
        p = -2.0
        res = fn(test_img, p)
        @test eltype(res) == IntensityPixel{N0f8}
        @test size(res) == size(test_img)
        @test all(res .== 1) # everything clamped to 1. 
    end
    @testset begin
        p = +2.0
        res = fn(test_img, p)
        @test eltype(res) == IntensityPixel{N0f8}
        @test size(res) == size(test_img)
        @test all(res .== 0) # everything clamped to 0. 
    end

    @test_throws MethodError begin 
        fn(another_img, 0.1) # because wrong type
    end
end

#################
#  badd_img     #
#################

@testset "Image2D BArithmetic: badd_image2D" begin
    Bundle = bundle_image2DIntensity_barithmetic_factory
    test_img = generate_binarize_test_image(INTENSITY)
    another_img = SImageND(IntensityPixel{N0f16}.(zeros(10,10)))
    fn = Bundle[:badd_image2D]
    fn = fn.fn(typeof(test_img))

    @testset "Intensity Result" begin
        for (ith, p) in enumerate([0.0, 0.3, 0.5, 0.8])
            res = fn(test_img, p)
            @test eltype(res) == IntensityPixel{N0f8}
            @test size(res) == size(test_img)
            @test all(0 .<= res .<= 1)
            if ith == 1
                @test all(res .== test_img)
            else
                @test res !== test_img
            end
        end
    end
    @testset begin
        p = -2.0
        res = fn(test_img, p)
        @test eltype(res) == IntensityPixel{N0f8}
        @test size(res) == size(test_img)
        @test all(res .== 0) # everything clamped to 0. 
    end
    @testset begin
        p = +2.0
        res = fn(test_img, p)
        @test eltype(res) == IntensityPixel{N0f8}
        @test size(res) == size(test_img)
        @test all(res .== 1) # everything clamped to 1 
    end

    @test_throws MethodError begin 
        fn(another_img, 0.1) # because wrong type
    end
end

# #####################
# #  bmult_image2D     #
# #####################

@testset "Image2D BArithmetic: bmult_image2D" begin
    Bundle = bundle_image2DIntensity_barithmetic_factory
    test_img = generate_binarize_test_image(INTENSITY)
    another_img = SImageND(IntensityPixel{N0f8}.(zeros(12,12))) # wrong size
    fn = Bundle[:bmult_image2D]
    fn = fn.fn(typeof(test_img))

    @testset "Intensity Result" begin
        for (ith, p) in enumerate([0.0, 0.3, 0.5, 0.8, 1])
            res = fn(test_img, p)
            @test eltype(res) == IntensityPixel{N0f8}
            @test size(res) == size(test_img)
            @test all(0 .<= res .<= 1)
            if ith == 1
                @test all(res .== 0)
            elseif ith == 5
                @test res == test_img
            else
                @test res !== test_img
            end
        end
    end
    @testset begin
        p = -2.0
        res = fn(test_img, p)
        @test eltype(res) == IntensityPixel{N0f8}
        @test size(res) == size(test_img)
        @test all(res .== 0) # everything clamped to 0. 
    end
    @test_throws MethodError begin 
        fn(another_img, 0.1) # because wrong size
    end
end
