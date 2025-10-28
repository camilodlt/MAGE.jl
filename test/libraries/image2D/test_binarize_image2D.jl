using ImageBinarization
using ImageCore
using Statistics

function generate_binarize_test_image(::Type{IntensityPixel{T}}, size = (10, 10)) where {T}
    # Create a gradient image for intensity
    img = [i / size[1] + j / size[2] for i in 1:size[1], j in 1:size[2]]
    img = img ./ maximum(img)  # Normalize to range [0, 1]
    return SImageND(IntensityPixel{T}.(img))
end

function generate_binarize_test_image(::Type{BinaryPixel{Bool}}, size = (10, 10))
    # Create a gradient image for intensity
    return SImageND(BinaryPixel{Bool}.(trues(10, 10)))
end

INTENSITY = IntensityPixel{N0f8}
BINARY = BinaryPixel{Bool}


#####################
# Adaptive Threshold #
#####################
@testset "Image2D Binarize: binarizeAdaptive(img, w, p) Default" begin
    Bundle = UTCGP.bundle_image2DBinary_binarize_factory
    @testset begin
        # Create a test image with a known pattern
        test_img = generate_binarize_test_image(INTENSITY)
        as_img = generate_binarize_test_image(BINARY)

        # Get the function for the specific image type
        fn = Bundle[:binarize_adaptive2D]
        fn = fn.fn(typeof(as_img)) # It's in the lib of BINARY img

        # Test with different combinations of parameters
        for (w, p) in [(9, 50), (10.5, 25), (15, 100), (20, 75)]
            res = fn(test_img, w, p)

            # Check that the result is of the correct type (BinaryPixel)
            @test eltype(res) == BinaryPixel{Bool}

            # Check that the result has the same size as the input image
            @test size(res) == size(test_img)

            # Check that the image is binarized (only 0 and 1 values)
            @test all(x -> x == 0 || x == 1, res)

            # Check that all values are clamped between 0 and 1
            @test all(0 .<= res .<= 1)
        end

        res1 = fn(test_img, 5, 30.0)
        res2 = fn(test_img, 5.0, 50)

        @test sum(float(res1) .== 0) > sum(float(res2) .== 0) # p = 30 is less restrictive so more background pixels than with p = 50
    end
end

@testset "Image2D Binarize: binarizeAdaptive(img, w) Default" begin
    Bundle = UTCGP.bundle_image2DBinary_binarize_factory
    @testset begin
        # Create a test image with a known pattern
        test_img = generate_binarize_test_image(INTENSITY)
        as_img = generate_binarize_test_image(BINARY)

        # Get the function for the specific image type
        fn = Bundle[:binarize_adaptive2D]
        fn = fn.fn(typeof(as_img)) # It's in the lib of BINARY img

        # Test with different window sizes
        for w in [5, 10.5, 15, 20]
            res = fn(test_img, w)

            # Check that the result is of the correct type (BinaryPixel)
            @test eltype(res) == BinaryPixel{Bool}

            # Check that the result has the same size as the input image
            @test size(res) == size(test_img)

            # Check that the image is binarized (only 0 and 1 values)
            @test all(x -> x == 0 || x == 1, res)

            # Check that all values are clamped between 0 and 1
            @test all(0 .<= res .<= 1)
        end

        res1 = fn(test_img, 100)
        res2 = fn(test_img, 3.0)

        @test sum(float(res1) .== 0) > sum(float(res2) .== 0) # p = 30 is less restrictive so more background pixels than with p = 50
    end
end

@testset "Image2D Binarize: binarizeAdaptive(img) Default" begin
    Bundle = UTCGP.bundle_image2DBinary_binarize_factory
    @testset begin
        # Create a test image with a known pattern
        test_img = generate_binarize_test_image(INTENSITY)
        as_img = generate_binarize_test_image(BINARY)

        # Get the function for the specific image type
        fn = Bundle[:binarize_adaptive2D]
        fn = fn.fn(typeof(as_img)) # It's in the lib of BINARY img

        # Test without parameters
        res = fn(test_img)

        # Check that the result is of the correct type (BinaryPixel)
        @test eltype(res) == BinaryPixel{Bool}

        # Check that the result has the same size as the input image
        @test size(res) == size(test_img)

        # Check that the image is binarized (only 0 and 1 values)
        @test all(x -> x == 0 || x == 1, res)

        # Check that all values are clamped between 0 and 1
        @test all(0 .<= res .<= 1)
    end
end

# ####################
# # NIBLACK          #
# ####################

@testset "Image2D Binarize: binarizeNiblack(img, w, b) Default" begin
    Bundle = UTCGP.bundle_image2DBinary_binarize_factory
    @testset begin
        # Create a test image with a known pattern
        test_img = generate_binarize_test_image(INTENSITY)
        as_img = generate_binarize_test_image(BINARY)

        # Get the function for the specific image type
        fn = Bundle[:binarize_niblack2D]
        fn = fn.fn(typeof(as_img)) # It's in the lib of BINARY img

        # Test with different combinations of parameters
        for (w, b) in [(5, -0.2), (10.5, 0.5), (15, -1000), (20, 1000)]
            res = fn(test_img, w, b)

            # Check that the result is of the correct type (BinaryPixel)
            @test eltype(res) == BinaryPixel{Bool}

            # Check that the result has the same size as the input image
            @test size(res) == size(test_img)

            # Check that the image is binarized (only 0 and 1 values)
            @test all(x -> x == 0 || x == 1, res)

            # Check that all values are clamped between 0 and 1
            @test all(0 .<= res .<= 1)
        end
        res1 = fn(test_img, 5, 0.1)
        res2 = fn(test_img, 5, 0.9)
        @test res1 != res2
    end
end

@testset "Image2D Binarize: binarizeNiblack(img, w) Default" begin
    Bundle = UTCGP.bundle_image2DBinary_binarize_factory
    @testset begin
        # Create a test image with a known pattern
        test_img = generate_binarize_test_image(INTENSITY)
        as_img = generate_binarize_test_image(BINARY)

        # Get the function for the specific image type
        fn = Bundle[:binarize_niblack2D]
        fn = fn.fn(typeof(as_img)) # It's in the lib of BINARY img

        # Test with different window sizes
        for w in [5, 10.5, 15, 20]
            res = fn(test_img, w)

            # Check that the result is of the correct type (BinaryPixel)
            @test eltype(res) == BinaryPixel{Bool}

            # Check that the result has the same size as the input image
            @test size(res) == size(test_img)

            # Check that the image is binarized (only 0 and 1 values)
            @test all(x -> x == 0 || x == 1, res)

            # Check that all values are clamped between 0 and 1
            @test all(0 .<= res .<= 1)
        end

        res1 = fn(test_img, 5)
        res2 = fn(test_img, 100)
        @test res1 != res2
    end
end

@testset "Image2D Binarize: binarizeNiblack(img) Default" begin
    Bundle = UTCGP.bundle_image2DBinary_binarize_factory
    @testset begin
        # Create a test image with a known pattern
        test_img = generate_binarize_test_image(INTENSITY)
        as_img = generate_binarize_test_image(BINARY)

        # Get the function for the specific image type
        fn = Bundle[:binarize_niblack2D]
        fn = fn.fn(typeof(as_img)) # It's in the lib of BINARY img

        # Test without parameters
        res = fn(test_img)

        # Check that the result is of the correct type (BinaryPixel)
        @test eltype(res) == BinaryPixel{Bool}

        # Check that the result has the same size as the input image
        @test size(res) == size(test_img)

        # Check that the image is binarized (only 0 and 1 values)
        @test all(x -> x == 0 || x == 1, res)

        # Check that all values are clamped between 0 and 1
        @test all(0 .<= res .<= 1)
    end
end

# ####################
# # Polysegment      #
# ####################
@testset "Image2D Binarize: binarizePolysegment(img) Default" begin
    Bundle = UTCGP.bundle_image2DBinary_binarize_factory
    @testset begin
        # Create a test image with a known pattern
        test_img = generate_binarize_test_image(INTENSITY)
        as_img = generate_binarize_test_image(BINARY)

        # Get the function for the specific image type
        fn = Bundle[:binarize_polysegment2D]
        fn = fn.fn(typeof(as_img)) # It's in the lib of BINARY img

        # Test without parameters
        res = fn(test_img)

        # Check that the result is of the correct type (BinaryPixel)
        @test eltype(res) == BinaryPixel{Bool}

        # Check that the result has the same size as the input image
        @test size(res) == size(test_img)

        # Check that the image is binarized (only 0 and 1 values)
        @test all(x -> x == 0 || x == 1, res)

        # Check that all values are clamped between 0 and 1
        @test all(0 .<= res .<= 1)
    end
end

# ####################
# # SAUVOLA          #
# ####################
@testset "Image2D Binarize: binarizeSauvola(img, w, p) Default" begin
    Bundle = UTCGP.bundle_image2DBinary_binarize_factory
    @testset begin
        # Create a test image with a known pattern
        test_img = generate_binarize_test_image(INTENSITY)
        as_img = generate_binarize_test_image(BINARY)

        # Get the function for the specific image type
        fn = Bundle[:binarize_sauvola2D]
        fn = fn.fn(typeof(as_img)) # It's in the lib of BINARY img

        # Test with different combinations of parameters
        for (w, p) in [(5, -0.1), (10.5, 0.5), (15, 1.0)]
            res = fn(test_img, w, p)

            # Check that the result is of the correct type (BinaryPixel)
            @test eltype(res) == BinaryPixel{Bool}

            # Check that the result has the same size as the input image
            @test size(res) == size(test_img)

            # Check that the image is binarized (only 0 and 1 values)
            @test all(x -> x == 0 || x == 1, res)

            # Check that all values are clamped between 0 and 1
            @test all(0 .<= res .<= 1)
        end

        res1 = fn(test_img, 5, 0.1)
        res2 = fn(test_img, 5, 0.9)
        @test res1 != res2
    end
end

@testset "Image2D Binarize: binarizeSauvola(img, w) Default" begin
    Bundle = UTCGP.bundle_image2DBinary_binarize_factory
    @testset begin
        # Create a test image with a known pattern
        test_img = generate_binarize_test_image(INTENSITY)
        as_img = generate_binarize_test_image(BINARY)

        # Get the function for the specific image type
        fn = Bundle[:binarize_sauvola2D]
        fn = fn.fn(typeof(as_img)) # It's in the lib of BINARY img

        # Test with different window sizes
        for w in [5, 10.5, 15]
            res = fn(test_img, w)

            # Check that the result is of the correct type (BinaryPixel)
            @test eltype(res) == BinaryPixel{Bool}

            # Check that the result has the same size as the input image
            @test size(res) == size(test_img)

            # Check that the image is binarized (only 0 and 1 values)
            @test all(x -> x == 0 || x == 1, res)

            # Check that all values are clamped between 0 and 1
            @test all(0 .<= res .<= 1)
        end

        res1 = fn(test_img, 100)
        res2 = fn(test_img, 5)
        @test res1 != res2
    end
end

@testset "Image2D Binarize: binarizeSauvola(img) Default" begin
    Bundle = UTCGP.bundle_image2DBinary_binarize_factory
    @testset begin
        # Create a test image with a known pattern
        test_img = generate_binarize_test_image(INTENSITY)
        as_img = generate_binarize_test_image(BINARY)

        # Get the function for the specific image type
        fn = Bundle[:binarize_sauvola2D]
        fn = fn.fn(typeof(as_img)) # It's in the lib of BINARY img

        # Test without parameters
        res = fn(test_img)

        # Check that the result is of the correct type (BinaryPixel)
        @test eltype(res) == BinaryPixel{Bool}

        # Check that the result has the same size as the input image
        @test size(res) == size(test_img)

        # Check that the image is binarized (only 0 and 1 values)
        @test all(x -> x == 0 || x == 1, res)

        # Check that all values are clamped between 0 and 1
        @test all(0 .<= res .<= 1)
    end
end


# ####################
# # OTSU             #
# ####################

@testset "Image2D Binarize: binarizeOtsu(img, nbins) Default" begin
    Bundle = UTCGP.bundle_image2DBinary_binarize_factory
    @testset begin
        # Create a test image with a known pattern
        test_img = generate_binarize_test_image(INTENSITY)
        as_img = generate_binarize_test_image(BINARY)

        # Get the function for the specific image type
        fn = Bundle[:binarize_otsu2D]
        fn = fn.fn(typeof(as_img)) # It's in the lib of BINARY img

        # Test with different number of bins
        for nbins in [-30, 100, 256, 500.189361]
            res = fn(test_img, nbins)

            # Check that the result is of the correct type (BinaryPixel)
            @test eltype(res) == BinaryPixel{Bool}

            # Check that the result has the same size as the input image
            @test size(res) == size(test_img)

            # Check that the image is binarized (only 0 and 1 values)
            @test all(x -> x == 0 || x == 1, res)

            # Check that all values are clamped between 0 and 1
            @test all(0 .<= res .<= 1)
        end
    end
end

@testset "Image2D Binarize: binarizeOtsu(img) Default" begin
    Bundle = UTCGP.bundle_image2DBinary_binarize_factory
    @testset begin
        # Create a test image with a known pattern
        test_img = generate_binarize_test_image(INTENSITY)
        as_img = generate_binarize_test_image(BINARY)

        # Get the function for the specific image type
        fn = Bundle[:binarize_otsu2D]
        fn = fn.fn(typeof(as_img)) # It's in the lib of BINARY img

        # Test without specifying the number of bins
        res = fn(test_img)

        # Check that the result is of the correct type (BinaryPixel)
        @test eltype(res) == BinaryPixel{Bool}

        # Check that the result has the same size as the input image
        @test size(res) == size(test_img)

        # Check that the image is binarized (only 0 and 1 values)
        @test all(x -> x == 0 || x == 1, res)

        # Check that all values are clamped between 0 and 1
        @test all(0 .<= res .<= 1)
        res1 = fn(test_img)
        res2 = fn(test_img, 256)
        @test res1 == res2
    end
end

# MINIMUM INTERMODES

@testset "Image2D Binarize: binarizeMinimumIntermodes(img, nbins) Default" begin
    Bundle = UTCGP.bundle_image2DBinary_binarize_factory
    @testset begin
        # Create a test image with a known pattern
        test_img = generate_binarize_test_image(INTENSITY)
        as_img = generate_binarize_test_image(BINARY)

        # Get the function for the specific image type
        fn = Bundle[:binarize_minimumintermodes2D]
        fn = fn.fn(typeof(as_img)) # It's in the lib of BINARY img

        # Test with different number of bins
        for nbins in [-30, 100, 256, 500.13]
            res = fn(test_img, nbins)
            # Check that the result is of the correct type (BinaryPixel)
            @test eltype(res) == BinaryPixel{Bool}
            # Check that the result has the same size as the input image
            @test size(res) == size(test_img)
            # Check that the image is binarized (only 0 and 1 values)
            @test all(x -> x == 0 || x == 1, res)
            # Check that all values are clamped between 0 and 1
            @test all(0 .<= res .<= 1)
        end
    end
end

@testset "Image2D Binarize: binarizeMinimumIntermodes(img) Default" begin
    Bundle = UTCGP.bundle_image2DBinary_binarize_factory
    @testset begin
        # Create a test image with a known pattern
        test_img = generate_binarize_test_image(INTENSITY)
        as_img = generate_binarize_test_image(BINARY)

        # Get the function for the specific image type
        fn = Bundle[:binarize_minimumintermodes2D]
        fn = fn.fn(typeof(as_img)) # It's in the lib of BINARY img

        # Test without specifying the number of bins
        res = fn(test_img)

        # Check that the result is of the correct type (BinaryPixel)
        @test eltype(res) == BinaryPixel{Bool}

        # Check that the result has the same size as the input image
        @test size(res) == size(test_img)

        # Check that the image is binarized (only 0 and 1 values)
        @test all(x -> x == 0 || x == 1, res)

        # Check that all values are clamped between 0 and 1
        @test all(0 .<= res .<= 1)

        res1 = fn(test_img)
        res2 = fn(test_img, 256)
        @test res1 == res2
    end
end

# ####################
# # INTERMODES       #
# ####################
@testset "Image2D Binarize: binarizeIntermodes(img, nbins) Default" begin
    Bundle = UTCGP.bundle_image2DBinary_binarize_factory
    @testset begin
        # Create a test image with a known pattern
        test_img = generate_binarize_test_image(INTENSITY)
        as_img = generate_binarize_test_image(BINARY)

        # Get the function for the specific image type
        fn = Bundle[:binarize_intermodes2D]
        fn = fn.fn(typeof(as_img)) # It's in the lib of BINARY img

        # Test with different number of bins
        for nbins in [-30, 100, 256, 500.6]
            res = fn(test_img, nbins)

            # Check that the result is of the correct type (BinaryPixel)
            @test eltype(res) == BinaryPixel{Bool}

            # Check that the result has the same size as the input image
            @test size(res) == size(test_img)

            # Check that the image is binarized (only 0 and 1 values)
            @test all(x -> x == 0 || x == 1, res)

            # Check that all values are clamped between 0 and 1
            @test all(0 .<= res .<= 1)
        end
    end
end

@testset "Image2D Binarize: binarizeIntermodes(img) Default" begin
    Bundle = UTCGP.bundle_image2DBinary_binarize_factory
    @testset begin
        # Create a test image with a known pattern
        test_img = generate_binarize_test_image(INTENSITY)
        as_img = generate_binarize_test_image(BINARY)

        # Get the function for the specific image type
        fn = Bundle[:binarize_intermodes2D]
        fn = fn.fn(typeof(as_img)) # It's in the lib of BINARY img

        # Test without specifying the number of bins
        res = fn(test_img)

        # Check that the result is of the correct type (BinaryPixel)
        @test eltype(res) == BinaryPixel{Bool}

        # Check that the result has the same size as the input image
        @test size(res) == size(test_img)

        # Check that the image is binarized (only 0 and 1 values)
        @test all(x -> x == 0 || x == 1, res)

        # Check that all values are clamped between 0 and 1
        @test all(0 .<= res .<= 1)

        res1 = fn(test_img)
        res2 = fn(test_img, 256)
        @test res1 == res2
    end
end


# ####################
# # MINIMUM ERROR    #
# ####################
@testset "Image2D Binarize: binarizeMinimumError(img, nbins) Default" begin
    Bundle = UTCGP.bundle_image2DBinary_binarize_factory
    @testset begin
        # Create a test image with a known pattern
        test_img = generate_binarize_test_image(INTENSITY)
        as_img = generate_binarize_test_image(BINARY)

        # Get the function for the specific image type
        fn = Bundle[:binarize_minimumerror2D]
        fn = fn.fn(typeof(as_img)) # It's in the lib of BINARY img

        # Test with different number of bins
        for nbins in [-30, 100, 256.2, 500]
            res = fn(test_img, nbins)
            @test eltype(res) == BinaryPixel{Bool}
            @test size(res) == size(test_img)
            @test all(x -> x == 0 || x == 1, res)
            @test all(0 .<= res .<= 1)
        end
    end
end

@testset "Image2D Binarize: binarizeMinimumError(img) Default" begin
    Bundle = UTCGP.bundle_image2DBinary_binarize_factory
    @testset begin
        # Create a test image with a known pattern
        test_img = generate_binarize_test_image(INTENSITY)
        as_img = generate_binarize_test_image(BINARY)

        # Get the function for the specific image type
        fn = Bundle[:binarize_minimumerror2D]
        fn = fn.fn(typeof(as_img)) # It's in the lib of BINARY img

        # Test without specifying the number of bins
        res = fn(test_img)

        # Check that the result is of the correct type (BinaryPixel)
        @test eltype(res) == BinaryPixel{Bool}

        # Check that the result has the same size as the input image
        @test size(res) == size(test_img)

        # Check that the image is binarized (only 0 and 1 values)
        @test all(x -> x == 0 || x == 1, res)

        # Check that all values are clamped between 0 and 1
        @test all(0 .<= res .<= 1)

        res1 = fn(test_img)
        res2 = fn(test_img, 256)
        @test res1 == res2
    end
end

# ####################
# # MANUAL BINARIZER #
# ####################
@testset "Image2D Binarize: binarizeMoments(img, nbins) Default" begin
    Bundle = UTCGP.bundle_image2DBinary_binarize_factory
    @testset begin
        test_img = generate_binarize_test_image(INTENSITY)
        as_img = generate_binarize_test_image(BINARY)
        fn = Bundle[:binarize_moments2D]
        fn = fn.fn(typeof(as_img))

        for nbins in [-30, 100, 256, 500.13]
            res = fn(test_img, nbins)
            @test eltype(res) == BinaryPixel{Bool}
            @test size(res) == size(test_img)
            @test all(x -> x == 0 || x == 1, res)
            @test all(0 .<= res .<= 1)
        end
    end
end

@testset "Image2D Binarize: binarizeMoments(img) Default" begin
    Bundle = UTCGP.bundle_image2DBinary_binarize_factory
    @testset begin
        test_img = generate_binarize_test_image(INTENSITY)
        as_img = generate_binarize_test_image(BINARY)
        fn = Bundle[:binarize_moments2D]
        fn = fn.fn(typeof(as_img))
        res = fn(test_img)
        @test eltype(res) == BinaryPixel{Bool}
        @test size(res) == size(test_img)
        @test all(x -> x == 0 || x == 1, res)
        @test all(0 .<= res .<= 1)

        res1 = fn(test_img)
        res2 = fn(test_img, 256)
        @test res1 == res2
    end
end

# ####################
# # UNIMODAL ROSIN   #
# ####################
@testset "Image2D Binarize: binarizeUnimodalRosin(img, nbins) Default" begin
    Bundle = UTCGP.bundle_image2DBinary_binarize_factory
    @testset begin
        test_img = generate_binarize_test_image(INTENSITY)
        as_img = generate_binarize_test_image(BINARY)
        fn = Bundle[:binarize_unimodalrosin2D]
        fn = fn.fn(typeof(as_img))

        for nbins in [30, 100, -256, 500.1783]
            res = fn(test_img, nbins)
            @test eltype(res) == BinaryPixel{Bool}
            @test size(res) == size(test_img)
            @test all(x -> x == 0 || x == 1, res)
            @test all(0 .<= res .<= 1)
        end
    end
end

@testset "Image2D Binarize: binarizeUnimodalRosin(img) Default" begin
    Bundle = UTCGP.bundle_image2DBinary_binarize_factory
    @testset begin
        test_img = generate_binarize_test_image(INTENSITY)
        as_img = generate_binarize_test_image(BINARY)
        fn = Bundle[:binarize_unimodalrosin2D]
        fn = fn.fn(typeof(as_img))
        res = fn(test_img)
        @test eltype(res) == BinaryPixel{Bool}
        @test size(res) == size(test_img)
        @test all(x -> x == 0 || x == 1, res)
        @test all(0 .<= res .<= 1)

        res1 = fn(test_img)
        res2 = fn(test_img, 256)
        @test res1 == res2
    end
end

# ####################
# # ENTROPY          #
# ####################
@testset "Image2D Binarize: binarizeEntropy(img, nbins) Default" begin
    Bundle = UTCGP.bundle_image2DBinary_binarize_factory
    @testset begin
        test_img = generate_binarize_test_image(INTENSITY)
        as_img = generate_binarize_test_image(BINARY)
        fn = Bundle[:binarize_entropy2D]
        fn = fn.fn(typeof(as_img))

        for nbins in [30, 100, 256, 500.1]
            res = fn(test_img, nbins)
            @test eltype(res) == BinaryPixel{Bool}
            @test size(res) == size(test_img)
            @test all(x -> x == 0 || x == 1, res)
            @test all(0 .<= res .<= 1)
        end
    end
end

@testset "Image2D Binarize: binarizeEntropy(img) Default" begin
    Bundle = UTCGP.bundle_image2DBinary_binarize_factory
    @testset begin
        test_img = generate_binarize_test_image(INTENSITY)
        as_img = generate_binarize_test_image(BINARY)
        fn = Bundle[:binarize_entropy2D]
        fn = fn.fn(typeof(as_img))
        res = fn(test_img)
        @test eltype(res) == BinaryPixel{Bool}
        @test size(res) == size(test_img)
        @test all(x -> x == 0 || x == 1, res)
        @test all(0 .<= res .<= 1)

        res1 = fn(test_img)
        res2 = fn(test_img, 256)
        @test res1 == res2
    end
end

# ####################
# # BALANCED         #
# ####################
@testset "Image2D Binarize: binarizeBalanced(img, nbins) Default" begin
    Bundle = UTCGP.bundle_image2DBinary_binarize_factory
    @testset begin
        test_img = generate_binarize_test_image(INTENSITY)
        as_img = generate_binarize_test_image(BINARY)
        fn = Bundle[:binarize_balanced2D]
        fn = fn.fn(typeof(as_img))

        for nbins in [30, 100, 256, 500]
            res = fn(test_img, nbins)
            @test eltype(res) == BinaryPixel{Bool}
            @test size(res) == size(test_img)
            @test all(x -> x == 0 || x == 1, res)
            @test all(0 .<= res .<= 1)
        end
    end
end

@testset "Image2D Binarize: binarizeBalanced(img) Default" begin
    Bundle = UTCGP.bundle_image2DBinary_binarize_factory
    @testset begin
        test_img = generate_binarize_test_image(INTENSITY)
        as_img = generate_binarize_test_image(BINARY)
        fn = Bundle[:binarize_balanced2D]
        fn = fn.fn(typeof(as_img))
        res = fn(test_img)
        @test eltype(res) == BinaryPixel{Bool}
        @test size(res) == size(test_img)
        @test all(x -> x == 0 || x == 1, res)
        @test all(0 .<= res .<= 1)
    end
end

# ####################
# # YEN              #
# ####################
@testset "Image2D Binarize: binarizeYen(img, nbins) Default" begin
    Bundle = UTCGP.bundle_image2DBinary_binarize_factory
    @testset begin
        test_img = generate_binarize_test_image(INTENSITY)
        as_img = generate_binarize_test_image(BINARY)
        fn = Bundle[:binarize_yen2D]
        fn = fn.fn(typeof(as_img))

        for nbins in [30, 100, 256, 500]
            res = fn(test_img, nbins)
            @test eltype(res) == BinaryPixel{Bool}
            @test size(res) == size(test_img)
            @test all(x -> x == 0 || x == 1, res)
            @test all(0 .<= res .<= 1)
        end
    end
end

@testset "Image2D Binarize: binarizeYen(img) Default" begin
    Bundle = UTCGP.bundle_image2DBinary_binarize_factory
    @testset begin
        test_img = generate_binarize_test_image(INTENSITY)
        as_img = generate_binarize_test_image(BINARY)
        fn = Bundle[:binarize_yen2D]
        fn = fn.fn(typeof(as_img))
        res = fn(test_img)
        @test eltype(res) == BinaryPixel{Bool}
        @test size(res) == size(test_img)
        @test all(x -> x == 0 || x == 1, res)
        @test all(0 .<= res .<= 1)
    end
end

# ####################
# # MANUAL BINARIZER #
# ####################

@testset "Image2D Binarize: binarizeManual(img, t) with Number" begin
    Bundle = UTCGP.bundle_image2DBinary_binarize_factory
    @testset begin
        test_img = generate_binarize_test_image(INTENSITY)
        as_img = generate_binarize_test_image(BINARY)
        fn = Bundle[:binarize_manual2D]
        fn = fn.fn(typeof(as_img))

        for t in [0, 128, 200, 255]
            res = fn(test_img, t)
            @test eltype(res) == BinaryPixel{Bool}
            @test size(res) == size(test_img)
            @test all(x -> x == 0 || x == 1, res)
            @test all(0 .<= res .<= 1)
            if t == 255 # none is gr
                sum(float(res.img)) == 0
            end
        end
    end
end

@testset "Image2D Binarize: binarizeManual(img, t) with Float64" begin
    Bundle = UTCGP.bundle_image2DBinary_binarize_factory
    @testset begin
        test_img = generate_binarize_test_image(INTENSITY)
        as_img = generate_binarize_test_image(BINARY)
        fn = Bundle[:binarize_manual2D]
        fn = fn.fn(typeof(as_img))

        for t in [0.0, 0.3, 0.5, 0.8, 1.0]
            res = fn(test_img, t)
            @test eltype(res) == BinaryPixel{Bool}
            @test size(res) == size(test_img)
            @test all(x -> x == 0 || x == 1, res)
            @test all(0 .<= res .<= 1)
            if t == 1.0 # none is gr
                sum(float(res.img)) == 0
            end
            if t == 0.0 # all are gr
                sum(float(res.img)) == 10 * 10
            end
        end
    end
end

@testset "Image2D Binarize: binarizeManual(img1, img2)" begin
    Bundle = UTCGP.bundle_image2DBinary_binarize_factory
    @testset begin
        test_img1 = generate_binarize_test_image(INTENSITY)
        test_img2 = generate_binarize_test_image(INTENSITY)
        as_img = generate_binarize_test_image(BINARY)
        fn = Bundle[:binarize_manual2D]
        fn = fn.fn(typeof(as_img))

        res = fn(test_img1, test_img2)
        @test eltype(res) == BinaryPixel{Bool}
        @test size(res) == size(test_img1)
        @test all(x -> x == 0 || x == 1, res)
        @test all(0 .<= res .<= 1)


        mean_img = mean(float(test_img2))
        res2 = fn(test_img1, mean_img)
        @test res == res2
    end
end

@testset "Image2D Binarize: binarizeManual(img)" begin
    Bundle = UTCGP.bundle_image2DBinary_binarize_factory
    @testset begin
        test_img = generate_binarize_test_image(INTENSITY)
        as_img = generate_binarize_test_image(BINARY)
        fn = Bundle[:binarize_manual2D]
        fn = fn.fn(typeof(as_img))

        res = fn(test_img)
        @test eltype(res) == BinaryPixel{Bool}
        @test size(res) == size(test_img)
        @test all(x -> x == 0 || x == 1, res)
        @test all(0 .<= res .<= 1)
    end
end
