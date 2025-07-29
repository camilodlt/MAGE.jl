using Test
using ImageCore
using UTCGP

# Helper function to generate a test image with a known pattern
function generate_erosion_test_image(::Type{BinaryPixel{T}}, size = (10, 10)) where {T}
    # Create a binary image with a known pattern
    img = ones(Bool, size)
    img[div(size[1], 2), div(size[2], 2)] = 0  # Set the central pixel to 0
    return SImageND(BinaryPixel.(img))
end

function generate_erosion_test_image(::Type{IntensityPixel{T}}, size = (10, 10)) where {T}
    # Create an intensity image with a known pattern
    img = ones(N0f8, size)
    img[div(size[1], 2), div(size[2], 2)] = 0  # Set the central pixel to 0
    return SImageND(IntensityPixel.(img))
end

BINARY = BinaryPixel{Bool}
INTENSITY = IntensityPixel{N0f8}

# EROSION
@testset "Image2D Morph: erosion(img) Default" begin
    # Create a test image with a known pattern
    test_img_binary = generate_erosion_test_image(BINARY)
    test_img_intensity = generate_erosion_test_image(INTENSITY)

    @testset for ImageType in [BINARY, INTENSITY]
        factory_for =
            ImageType == BINARY ? typeof(test_img_binary) : typeof(test_img_intensity)
        bundle =
            ImageType == BINARY ? bundle_image2DBinary_morph_factory :
            bundle_image2DIntensity_morph_factory
        # Get the function for the specific image type
        fn = bundle[:erosion_2D]
        fn = fn.fn(factory_for)

        # Test without k parameter
        res1 = fn(test_img_binary)
        res2 = fn(test_img_intensity)

        @test eltype(res1) == eltype(res2) # no matter the input, the output has to be of the same type
        @test typeof(res1) <: SImageND && typeof(res1) == typeof(res2)

        # Check that the result is of the correct type
        @test eltype(res1) == ImageType && eltype(res2) == ImageType

        # Check that the result has the same size as the input image
        @test size(res1) == size(test_img_binary)
        @test size(res2) == size(test_img_binary)

        @test sum(res1 .== 0) == 9 # bc Box SE
        @test sum(res2 .== 0) == 9 # bc Box SE

        # Check that all values are clamped between 0 and 1
        @test all(0 .<= res1 .<= 1)
        @test all(0 .<= res2 .<= 1)
    end
end

@testset "Image2D Morph: erosion(img, k) Default" begin
    # Create a test image with a known pattern
    test_img_binary = generate_erosion_test_image(BINARY)
    test_img_intensity = generate_erosion_test_image(INTENSITY)
    expected = [5, 5, 13, 13, 75, 75]
    ks = [-1, 3, 4, 5, 13, 100]
    @testset for ImageType in [BINARY, INTENSITY]
        factory_for =
            ImageType == BINARY ? typeof(test_img_binary) : typeof(test_img_intensity)
        bundle =
            ImageType == BINARY ? bundle_image2DBinary_morph_factory :
            bundle_image2DIntensity_morph_factory
        # Get the function for the specific image type
        fn = bundle[:erosion_2D]
        fn = fn.fn(factory_for)

        @testset for (k, expected) in zip(ks, expected)
            # Test without k parameter
            res1 = fn(test_img_binary, k)
            res2 = fn(test_img_intensity, k)

            @test eltype(res1) == eltype(res2) # no matter the input, the output has to be of the same type
            @test typeof(res1) <: SImageND && typeof(res1) == typeof(res2)

            # Check that the result is of the correct type
            @test eltype(res1) == ImageType && eltype(res2) == ImageType

            # Check that the result has the same size as the input image
            @test size(res1) == size(test_img_binary)
            @test size(res2) == size(test_img_binary)

            @test sum(res1 .== 0) == expected # bc Box SE
            @test sum(res2 .== 0) == expected # bc Box SE

            # Check that all values are clamped between 0 and 1
            @test all(0 .<= res1 .<= 1)
            @test all(0 .<= res2 .<= 1)
        end
    end
end


# DILATION
@testset "Image2D Morph: dilation(img) Default" begin
    # Create a test image with a known pattern
    test_img_binary = generate_erosion_test_image(BINARY)
    test_img_intensity = generate_erosion_test_image(INTENSITY)
    inverter1 =
        UTCGP.image2D_basic.experimental_invert_image2D_factory(typeof(test_img_binary))
    inverter2 =
        UTCGP.image2D_basic.experimental_invert_image2D_factory(typeof(test_img_intensity))
    test_img_binary = inverter1(test_img_binary)
    test_img_intensity = inverter2(test_img_intensity)

    @testset for ImageType in [BINARY, INTENSITY]
        factory_for =
            ImageType == BINARY ? typeof(test_img_binary) : typeof(test_img_intensity)
        bundle =
            ImageType == BINARY ? bundle_image2DBinary_morph_factory :
            bundle_image2DIntensity_morph_factory
        # Get the function for the specific image type
        fn = bundle[:dilation_2D]
        fn = fn.fn(factory_for)

        # Test without k parameter
        res1 = fn(test_img_binary)
        res2 = fn(test_img_intensity)

        @test eltype(res1) == eltype(res2) # no matter the input, the output has to be of the same type
        @test typeof(res1) <: SImageND && typeof(res1) == typeof(res2)

        # Check that the result is of the correct type
        @test eltype(res1) == ImageType && eltype(res2) == ImageType

        # Check that the result has the same size as the input image
        @test size(res1) == size(test_img_binary)
        @test size(res2) == size(test_img_binary)

        @test sum(res1 .== 1) == 9 # bc Box SE
        @test sum(res2 .== 1) == 9 # bc Box SE

        # Check that all values are clamped between 0 and 1
        @test all(0 .<= res1 .<= 1)
        @test all(0 .<= res2 .<= 1)
    end
end

@testset "Image2D Morph: dilation(img) with 0.8" begin
    # Create a test image with a known pattern
    test_img_binary = generate_erosion_test_image(BINARY)
    test_img_intensity = generate_erosion_test_image(INTENSITY)
    inverter1 =
        UTCGP.image2D_basic.experimental_invert_image2D_factory(typeof(test_img_binary))
    inverter2 =
        UTCGP.image2D_basic.experimental_invert_image2D_factory(typeof(test_img_intensity))
    test_img_binary = inverter1(test_img_binary)
    test_img_intensity = inverter2(test_img_intensity)
    test_img_intensity.img[test_img_intensity.==1] .= 0.8 # it should dilate 0.8s

    @testset for ImageType in [BINARY, INTENSITY]
        value_for_counting = ImageType == BINARY ? 1 : 0.8
        factory_for =
            ImageType == BINARY ? typeof(test_img_binary) : typeof(test_img_intensity)
        bundle =
            ImageType == BINARY ? bundle_image2DBinary_morph_factory :
            bundle_image2DIntensity_morph_factory
        # Get the function for the specific image type
        fn = bundle[:dilation_2D]
        fn = fn.fn(factory_for)

        # Test without k parameter
        res1 = fn(test_img_binary)
        res2 = fn(test_img_intensity)

        @test eltype(res1) == eltype(res2) # no matter the input, the output has to be of the same type
        @test typeof(res1) <: SImageND && typeof(res1) == typeof(res2)

        # Check that the result is of the correct type
        @test eltype(res1) == ImageType && eltype(res2) == ImageType

        # Check that the result has the same size as the input image
        @test size(res1) == size(test_img_binary)
        @test size(res2) == size(test_img_binary)

        @test sum(res1 .== 1) == 9 # bc Box SE # EXPLANATION: the binary img always dilates the 1s whether the fn is binary or not. and the 0.8 are rounded to 1. 
        @test sum(res2 .== value_for_counting) == 9 # bc Box SE # EXPLANATION: fn is binary then the dilated 0.8 => 1. Function is Intensity then the dilated 0.8 are 0.8.

        # Check that all values are clamped between 0 and 1
        @test all(0 .<= res1 .<= 1)
        @test all(0 .<= res2 .<= 1)
    end
end

# DILATION
@testset "Image2D Morph: dilation(img, k)" begin
    # Create a test image with a known pattern
    test_img_binary = generate_erosion_test_image(BINARY)
    test_img_intensity = generate_erosion_test_image(INTENSITY)
    inverter1 =
        UTCGP.image2D_basic.experimental_invert_image2D_factory(typeof(test_img_binary))
    inverter2 =
        UTCGP.image2D_basic.experimental_invert_image2D_factory(typeof(test_img_intensity))
    test_img_binary = inverter1(test_img_binary)
    test_img_intensity = inverter2(test_img_intensity)
    expected = [5, 5, 13, 13, 75, 75]
    ks = [-1, 3, 4, 5, 13, 100]
    @testset for ImageType in [BINARY, INTENSITY]
        factory_for =
            ImageType == BINARY ? typeof(test_img_binary) : typeof(test_img_intensity)
        bundle =
            ImageType == BINARY ? bundle_image2DBinary_morph_factory :
            bundle_image2DIntensity_morph_factory
        # Get the function for the specific image type
        fn = bundle[:dilation_2D]
        fn = fn.fn(factory_for)

        @testset for (k, expected) in zip(ks, expected)
            # Test without k parameter
            res1 = fn(test_img_binary, k)
            res2 = fn(test_img_intensity, k)

            @test eltype(res1) == eltype(res2) # no matter the input, the output has to be of the same type
            @test typeof(res1) <: SImageND && typeof(res1) == typeof(res2)

            # Check that the result is of the correct type
            @test eltype(res1) == ImageType && eltype(res2) == ImageType

            # Check that the result has the same size as the input image
            @test size(res1) == size(test_img_binary)
            @test size(res2) == size(test_img_binary)

            @test sum(res1 .== 1) == expected # bc Box SE
            @test sum(res2 .== 1) == expected # bc Box SE

            # Check that all values are clamped between 0 and 1
            @test all(0 .<= res1 .<= 1)
            @test all(0 .<= res2 .<= 1)
        end
    end
end


# OPENING
@testset "Image2D Morph: opening(img) Default" begin
    # Create a test image with a known pattern
    test_img_binary = generate_erosion_test_image(BINARY)
    test_img_intensity = generate_erosion_test_image(INTENSITY)

    @testset for ImageType in [BINARY, INTENSITY]
        factory_for =
            ImageType == BINARY ? typeof(test_img_binary) : typeof(test_img_intensity)
        bundle =
            ImageType == BINARY ? bundle_image2DBinary_morph_factory :
            bundle_image2DIntensity_morph_factory
        # Get the function for the specific image type
        fn = bundle[:opening_2D]
        fn = fn.fn(factory_for)

        # Test without k parameter
        res1 = fn(test_img_binary)
        res2 = fn(test_img_intensity)

        @test eltype(res1) == eltype(res2) # no matter the input, the output has to be of the same type
        @test typeof(res1) <: SImageND && typeof(res1) == typeof(res2)

        # Check that the result is of the correct type
        @test eltype(res1) == ImageType && eltype(res2) == ImageType

        # Check that the result has the same size as the input image
        @test size(res1) == size(test_img_binary)
        @test size(res2) == size(test_img_binary)

        @test sum(res1 .== 0) == 1 # bc Box SE
        @test sum(res2 .== 0) == 1 # bc Box SE

        # Check that all values are clamped between 0 and 1
        @test all(0 .<= res1 .<= 1)
        @test all(0 .<= res2 .<= 1)
    end
end

@testset "Image2D Morph: opening(img, k)" begin
    # Create a test image with a known pattern
    test_img_binary = generate_erosion_test_image(BINARY)
    test_img_intensity = generate_erosion_test_image(INTENSITY)

    expected = [1, 1, 1, 1, 1, 1]
    ks = [-1, 3, 4, 5, 13, 100]
    @testset for ImageType in [BINARY, INTENSITY]
        factory_for =
            ImageType == BINARY ? typeof(test_img_binary) : typeof(test_img_intensity)
        bundle =
            ImageType == BINARY ? bundle_image2DBinary_morph_factory :
            bundle_image2DIntensity_morph_factory
        # Get the function for the specific image type
        fn = bundle[:opening_2D]
        fn = fn.fn(factory_for)

        @testset for (k, expected) in zip(ks, expected)
            # Test without k parameter
            res1 = fn(test_img_binary, k)
            res2 = fn(test_img_intensity, k)

            @test eltype(res1) == eltype(res2) # no matter the input, the output has to be of the same type
            @test typeof(res1) <: SImageND && typeof(res1) == typeof(res2)

            # Check that the result is of the correct type
            @test eltype(res1) == ImageType && eltype(res2) == ImageType

            # Check that the result has the same size as the input image
            @test size(res1) == size(test_img_binary)
            @test size(res2) == size(test_img_binary)

            @test sum(res1 .== 0) == expected # bc Box SE
            @test sum(res2 .== 0) == expected # bc Box SE

            # Check that all values are clamped between 0 and 1
            @test all(0 .<= res1 .<= 1)
            @test all(0 .<= res2 .<= 1)
        end
    end
end


# CLOSING
@testset "Image2D Morph: closing(img) Default" begin
    # Create a test image with a known pattern
    test_img_binary = generate_erosion_test_image(BINARY)
    test_img_intensity = generate_erosion_test_image(INTENSITY)
    inverter1 =
        UTCGP.image2D_basic.experimental_invert_image2D_factory(typeof(test_img_binary))
    inverter2 =
        UTCGP.image2D_basic.experimental_invert_image2D_factory(typeof(test_img_intensity))
    test_img_binary = inverter1(test_img_binary)
    test_img_intensity = inverter2(test_img_intensity)

    @testset for ImageType in [BINARY, INTENSITY]
        factory_for =
            ImageType == BINARY ? typeof(test_img_binary) : typeof(test_img_intensity)
        bundle =
            ImageType == BINARY ? bundle_image2DBinary_morph_factory :
            bundle_image2DIntensity_morph_factory
        # Get the function for the specific image type
        fn = bundle[:closing_2D]
        fn = fn.fn(factory_for)

        # Test without k parameter
        res1 = fn(test_img_binary)
        res2 = fn(test_img_intensity)

        @test eltype(res1) == eltype(res2) # no matter the input, the output has to be of the same type
        @test typeof(res1) <: SImageND && typeof(res1) == typeof(res2)

        # Check that the result is of the correct type
        @test eltype(res1) == ImageType && eltype(res2) == ImageType

        # Check that the result has the same size as the input image
        @test size(res1) == size(test_img_binary)
        @test size(res2) == size(test_img_binary)

        @test sum(res1 .== 1) == 1 # bc Box SE
        @test sum(res2 .== 1) == 1 # bc Box SE

        # Check that all values are clamped between 0 and 1
        @test all(0 .<= res1 .<= 1)
        @test all(0 .<= res2 .<= 1)
    end
end

@testset "Image2D Morph: closing(img, k)" begin
    # Create a test image with a known pattern
    test_img_binary = generate_erosion_test_image(BINARY)
    test_img_intensity = generate_erosion_test_image(INTENSITY)
    inverter1 =
        UTCGP.image2D_basic.experimental_invert_image2D_factory(typeof(test_img_binary))
    inverter2 =
        UTCGP.image2D_basic.experimental_invert_image2D_factory(typeof(test_img_intensity))
    test_img_binary = inverter1(test_img_binary)
    test_img_intensity = inverter2(test_img_intensity)

    expected = [1, 1, 1, 1, 1, 1]
    ks = [-1, 3, 4, 5, 13, 100]
    @testset for ImageType in [BINARY, INTENSITY]
        factory_for =
            ImageType == BINARY ? typeof(test_img_binary) : typeof(test_img_intensity)
        bundle =
            ImageType == BINARY ? bundle_image2DBinary_morph_factory :
            bundle_image2DIntensity_morph_factory
        # Get the function for the specific image type
        fn = bundle[:closing_2D]
        fn = fn.fn(factory_for)

        @testset for (k, expected) in zip(ks, expected)
            # Test without k parameter
            res1 = fn(test_img_binary, k)
            res2 = fn(test_img_intensity, k)

            @test eltype(res1) == eltype(res2) # no matter the input, the output has to be of the same type
            @test typeof(res1) <: SImageND && typeof(res1) == typeof(res2)

            # Check that the result is of the correct type
            @test eltype(res1) == ImageType && eltype(res2) == ImageType

            # Check that the result has the same size as the input image
            @test size(res1) == size(test_img_binary)
            @test size(res2) == size(test_img_binary)

            @test sum(res1 .== 1) == expected # bc Box SE
            @test sum(res2 .== 1) == expected # bc Box SE

            # Check that all values are clamped between 0 and 1
            @test all(0 .<= res1 .<= 1)
            @test all(0 .<= res2 .<= 1)
        end
    end
end


# TOPHAT
@testset "Image2D Morph: tophat(img) Default" begin
    # Create a test image with a known pattern
    test_img_binary = generate_erosion_test_image(BINARY)
    test_img_intensity = generate_erosion_test_image(INTENSITY)

    @testset for ImageType in [BINARY, INTENSITY]
        factory_for =
            ImageType == BINARY ? typeof(test_img_binary) : typeof(test_img_intensity)
        bundle =
            ImageType == BINARY ? bundle_image2DBinary_morph_factory :
            bundle_image2DIntensity_morph_factory
        # Get the function for the specific image type
        fn = bundle[:tophat_2D]
        fn = fn.fn(factory_for)

        # Test without k parameter
        res1 = fn(test_img_binary)
        res2 = fn(test_img_intensity)

        @test eltype(res1) == eltype(res2) # no matter the input, the output has to be of the same type
        @test typeof(res1) <: SImageND && typeof(res1) == typeof(res2)

        # Check that the result is of the correct type
        @test eltype(res1) == ImageType && eltype(res2) == ImageType

        # Check that the result has the same size as the input image
        @test size(res1) == size(test_img_binary)
        @test size(res2) == size(test_img_binary)

        @test sum(res1 .== 1) == 0 # bc Box SE
        @test sum(res2 .== 1) == 0 # bc Box SE

        # Check that all values are clamped between 0 and 1
        @test all(0 .<= res1 .<= 1)
        @test all(0 .<= res2 .<= 1)
    end
end

@testset "Image2D Morph: tophat(img, k) Default" begin
    # Create a test image with a known pattern
    test_img_binary = generate_erosion_test_image(BINARY)
    test_img_intensity = generate_erosion_test_image(INTENSITY)
    expected = [5, 5, 13, 13, 75, 75]
    ks = [-1, 3, 4, 5, 13, 100]
    @testset for ImageType in [BINARY, INTENSITY]
        factory_for =
            ImageType == BINARY ? typeof(test_img_binary) : typeof(test_img_intensity)
        bundle =
            ImageType == BINARY ? bundle_image2DBinary_morph_factory :
            bundle_image2DIntensity_morph_factory
        # Get the function for the specific image type
        fn = bundle[:tophat_2D]
        fn = fn.fn(factory_for)

        @testset for (k, expected) in zip(ks, expected)
            # Test without k parameter
            res1 = fn(test_img_binary, k)
            res2 = fn(test_img_intensity, k)

            @test eltype(res1) == eltype(res2) # no matter the input, the output has to be of the same type
            @test typeof(res1) <: SImageND && typeof(res1) == typeof(res2)

            # Check that the result is of the correct type
            @test eltype(res1) == ImageType && eltype(res2) == ImageType

            # Check that the result has the same size as the input image
            @test size(res1) == size(test_img_binary)
            @test size(res2) == size(test_img_binary)

            @test sum(res1 .== 1) == 0 # bc Box SE
            @test sum(res2 .== 1) == 0 # bc Box SE

            # Check that all values are clamped between 0 and 1
            @test all(0 .<= res1 .<= 1)
            @test all(0 .<= res2 .<= 1)
        end
    end
end

# BOTHAT
@testset "Image2D Morph: bothat(img) Default" begin
    # Create a test image with a known pattern
    test_img_binary = generate_erosion_test_image(BINARY)
    test_img_intensity = generate_erosion_test_image(INTENSITY)
    inverter1 =
        UTCGP.image2D_basic.experimental_invert_image2D_factory(typeof(test_img_binary))
    inverter2 =
        UTCGP.image2D_basic.experimental_invert_image2D_factory(typeof(test_img_intensity))
    test_img_binary = inverter1(test_img_binary)
    test_img_intensity = inverter2(test_img_intensity)

    @testset for ImageType in [BINARY, INTENSITY]
        factory_for =
            ImageType == BINARY ? typeof(test_img_binary) : typeof(test_img_intensity)
        bundle =
            ImageType == BINARY ? bundle_image2DBinary_morph_factory :
            bundle_image2DIntensity_morph_factory
        # Get the function for the specific image type
        fn = bundle[:bothat_2D]
        fn = fn.fn(factory_for)

        # Test without k parameter
        res1 = fn(test_img_binary)
        res2 = fn(test_img_intensity)

        @test eltype(res1) == eltype(res2) # no matter the input, the output has to be of the same type
        @test typeof(res1) <: SImageND && typeof(res1) == typeof(res2)

        # Check that the result is of the correct type
        @test eltype(res1) == ImageType && eltype(res2) == ImageType

        # Check that the result has the same size as the input image
        @test size(res1) == size(test_img_binary)
        @test size(res2) == size(test_img_binary)

        @test sum(res1 .== 1) == 0 # bc Box SE
        @test sum(res2 .== 1) == 0 # bc Box SE

        # Check that all values are clamped between 0 and 1
        @test all(0 .<= res1 .<= 1)
        @test all(0 .<= res2 .<= 1)
    end
end

@testset "Image2D Morph: bothat(img, k) Default" begin
    # Create a test image with a known pattern
    test_img_binary = generate_erosion_test_image(BINARY)
    test_img_intensity = generate_erosion_test_image(INTENSITY)
    inverter1 =
        UTCGP.image2D_basic.experimental_invert_image2D_factory(typeof(test_img_binary))
    inverter2 =
        UTCGP.image2D_basic.experimental_invert_image2D_factory(typeof(test_img_intensity))
    test_img_binary = inverter1(test_img_binary)
    test_img_intensity = inverter2(test_img_intensity)
    expected = [0, 0, 0, 0, 0, 0]
    ks = [-1, 3, 4, 5, 13, 100]
    @testset for ImageType in [BINARY, INTENSITY]
        factory_for =
            ImageType == BINARY ? typeof(test_img_binary) : typeof(test_img_intensity)
        bundle =
            ImageType == BINARY ? bundle_image2DBinary_morph_factory :
            bundle_image2DIntensity_morph_factory
        # Get the function for the specific image type
        fn = bundle[:bothat_2D]
        fn = fn.fn(factory_for)

        @testset for (k, expected) in zip(ks, expected)
            # Test without k parameter
            res1 = fn(test_img_binary, k)
            res2 = fn(test_img_intensity, k)

            @test eltype(res1) == eltype(res2) # no matter the input, the output has to be of the same type
            @test typeof(res1) <: SImageND && typeof(res1) == typeof(res2)

            # Check that the result is of the correct type
            @test eltype(res1) == ImageType && eltype(res2) == ImageType

            # Check that the result has the same size as the input image
            @test size(res1) == size(test_img_binary)
            @test size(res2) == size(test_img_binary)

            @test sum(res1 .== 1) == 0 # bc Box SE
            @test sum(res2 .== 1) == 0 # bc Box SE

            # Check that all values are clamped between 0 and 1
            @test all(0 .<= res1 .<= 1)
            @test all(0 .<= res2 .<= 1)
        end
    end
end



# MGRADIENT
@testset "Image2D Morph: morphogradient(img) Default" begin
    # Create a test image with a known pattern
    test_img_binary = generate_erosion_test_image(BINARY)
    test_img_intensity = generate_erosion_test_image(INTENSITY)
    test_img_intensity.img[test_img_intensity.==0] .= 0.8

    @testset for ImageType in [BINARY, INTENSITY]
        n_expected_1 = ImageType == BINARY ? 9 : 9
        n_expected_2 = ImageType == BINARY ? 10 * 10 : 9
        value_expected_1 = ImageType == BINARY ? 1 : 1
        value_expected_2 = ImageType == BINARY ? 0 : 0.2 # because 0.2 was rounded => 0

        factory_for =
            ImageType == BINARY ? typeof(test_img_binary) : typeof(test_img_intensity)
        bundle =
            ImageType == BINARY ? bundle_image2DBinary_morph_factory :
            bundle_image2DIntensity_morph_factory
        # Get the function for the specific image type
        fn = bundle[:morphogradient_2D]
        fn = fn.fn(factory_for)

        # Test without k parameter
        res1 = fn(test_img_binary)
        res2 = fn(test_img_intensity)

        @test eltype(res1) == eltype(res2) # no matter the input, the output has to be of the same type
        @test typeof(res1) <: SImageND && typeof(res1) == typeof(res2)

        # Check that the result is of the correct type
        @test eltype(res1) == ImageType && eltype(res2) == ImageType

        # Check that the result has the same size as the input image
        @test size(res1) == size(test_img_binary)
        @test size(res2) == size(test_img_binary)

        @test sum(res1 .== value_expected_1) == n_expected_1 # bc Box SE
        @test sum(res2 .== value_expected_2) == n_expected_2 # bc Box SE

        # Check that all values are clamped between 0 and 1
        @test all(0 .<= res1 .<= 1)
        @test all(0 .<= res2 .<= 1)
    end
end

@testset "Image2D Morph: morphogradient(img, k) Default" begin
    # Create a test image with a known pattern
    test_img_binary = generate_erosion_test_image(BINARY)
    test_img_intensity = generate_erosion_test_image(INTENSITY)
    test_img_intensity.img[test_img_intensity.==0] .= 0.8

    n_expected_intensity = [100, 100, 100, 100, 100, 100]
    n_expected_binary = [5, 5, 13, 13, 75, 75]
    value_expected_intensity = [0, 0, 0, 0, 0, 0]
    value_expected_binary = [1, 1, 1, 1, 1, 1]
    ks = [-1, 3, 4, 5, 13, 100]
    ImageType = BINARY
    factory_for = ImageType == BINARY ? typeof(test_img_binary) : typeof(test_img_intensity)
    bundle =
        ImageType == BINARY ? bundle_image2DBinary_morph_factory :
        bundle_image2DIntensity_morph_factory
    # Get the function for the specific image type
    fn = bundle[:morphogradient_2D]
    fn = fn.fn(factory_for)

    @testset for (k, n_expected_1, n_expected_2, value_expected_1, value_expected_2) in zip(
        ks,
        n_expected_binary,
        n_expected_intensity,
        value_expected_binary,
        value_expected_intensity,
    )
        # Test without k parameter
        res1 = fn(test_img_binary, k)
        res2 = fn(test_img_intensity, k)

        @test eltype(res1) == eltype(res2) # no matter the input, the output has to be of the same type
        @test typeof(res1) <: SImageND && typeof(res1) == typeof(res2)

        # Check that the result is of the correct type
        @test eltype(res1) == ImageType && eltype(res2) == ImageType

        # Check that the result has the same size as the input image
        @test size(res1) == size(test_img_binary)
        @test size(res2) == size(test_img_binary)

        @test sum(res1 .== value_expected_1) == n_expected_1
        @test sum(res2 .== value_expected_2) == n_expected_2

        # Check that all values are clamped between 0 and 1
        @test all(0 .<= res1 .<= 1)
        @test all(0 .<= res2 .<= 1)
    end

    n_expected_intensity = [5, 5, 13, 13, 75, 75]
    n_expected_binary = [5, 5, 13, 13, 75, 75]
    value_expected_intensity = [0.2, 0.2, 0.2, 0.2, 0.2, 0.2]
    value_expected_binary = [1, 1, 1, 1, 1, 1]
    ks = [-1, 3, 4, 5, 13, 100]
    ImageType = INTENSITY
    factory_for = ImageType == BINARY ? typeof(test_img_binary) : typeof(test_img_intensity)
    bundle =
        ImageType == BINARY ? bundle_image2DBinary_morph_factory :
        bundle_image2DIntensity_morph_factory
    # Get the function for the specific image type
    fn = bundle[:morphogradient_2D]
    fn = fn.fn(factory_for)

    @testset for (k, n_expected_1, n_expected_2, value_expected_1, value_expected_2) in zip(
        ks,
        n_expected_binary,
        n_expected_intensity,
        value_expected_binary,
        value_expected_intensity,
    )
        # Test without k parameter
        res1 = fn(test_img_binary, k)
        res2 = fn(test_img_intensity, k)

        @test eltype(res1) == eltype(res2) # no matter the input, the output has to be of the same type
        @test typeof(res1) <: SImageND && typeof(res1) == typeof(res2)

        # Check that the result is of the correct type
        @test eltype(res1) == ImageType && eltype(res2) == ImageType

        # Check that the result has the same size as the input image
        @test size(res1) == size(test_img_binary)
        @test size(res2) == size(test_img_binary)

        @test sum(res1 .== value_expected_1) == n_expected_1
        @test sum(res2 .== value_expected_2) == n_expected_2

        # Check that all values are clamped between 0 and 1
        @test all(0 .<= res1 .<= 1)
        @test all(0 .<= res2 .<= 1)
    end
end

@testset "Image2D Morph: morphogradient(img, k, mode) Default" begin
    # Create a test image with a known pattern
    test_img_binary = generate_erosion_test_image(BINARY)
    test_img_intensity = generate_erosion_test_image(INTENSITY)
    test_img_intensity.img[test_img_intensity.==0] .= 0.8

    n_expected_intensity = [100, 100, 100, 100, 100, 100]
    n_expected_binary = [5, 5, 13, 13, 75, 75]
    value_expected_intensity = [0, 0, 0, 0, 0, 0]
    value_expected_binary = [1, 1, 1, 1, 1, 1]
    ks = [-1, 3, 4, 5, 13, 100]
    ImageType = BINARY
    factory_for = ImageType == BINARY ? typeof(test_img_binary) : typeof(test_img_intensity)
    bundle =
        ImageType == BINARY ? bundle_image2DBinary_morph_factory :
        bundle_image2DIntensity_morph_factory
    # Get the function for the specific image type
    fn = bundle[:morphogradient_2D]
    fn = fn.fn(factory_for)

    @testset for (k, n_expected_1, n_expected_2, value_expected_1, value_expected_2) in zip(
        ks,
        n_expected_binary,
        n_expected_intensity,
        value_expected_binary,
        value_expected_intensity,
    )
        # Test without k parameter
        res1 = fn(test_img_binary, k, -1) # default beucher
        res2 = fn(test_img_intensity, k, -1)

        tmp_res1_beucher = fn(test_img_binary, k, -1)
        tmp_res1_internal = fn(test_img_binary, k, 0)
        tmp_res1_external = fn(test_img_binary, k, 1.0)

        @test tmp_res1_beucher != tmp_res1_external &&
              tmp_res1_external != tmp_res1_internal

        tmp_res2_beucher = fn(test_img_intensity, k, -1)
        tmp_res2_internal = fn(test_img_intensity, k, 0.0)
        tmp_res2_external = fn(test_img_intensity, k, 1)

        @test tmp_res2_beucher == tmp_res2_external &&
              tmp_res2_external == tmp_res2_internal # because binary the img was rounded to 0. 

        @test eltype(res1) == eltype(res2) # no matter the input, the output has to be of the same type
        @test typeof(res1) <: SImageND && typeof(res1) == typeof(res2)

        # Check that the result is of the correct type
        @test eltype(res1) == ImageType && eltype(res2) == ImageType

        # Check that the result has the same size as the input image
        @test size(res1) == size(test_img_binary)
        @test size(res2) == size(test_img_binary)

        @test sum(res1 .== value_expected_1) == n_expected_1
        @test sum(res2 .== value_expected_2) == n_expected_2

        # Check that all values are clamped between 0 and 1
        @test all(0 .<= res1 .<= 1)
        @test all(0 .<= res2 .<= 1)
    end

    n_expected_intensity = [5, 5, 13, 13, 75, 75]
    n_expected_binary = [5, 5, 13, 13, 75, 75]
    value_expected_intensity = [0.2, 0.2, 0.2, 0.2, 0.2, 0.2]
    value_expected_binary = [1, 1, 1, 1, 1, 1]
    ks = [-1, 3, 4, 5, 13, 100]
    ImageType = INTENSITY
    factory_for = ImageType == BINARY ? typeof(test_img_binary) : typeof(test_img_intensity)
    bundle =
        ImageType == BINARY ? bundle_image2DBinary_morph_factory :
        bundle_image2DIntensity_morph_factory
    # Get the function for the specific image type
    fn = bundle[:morphogradient_2D]
    fn = fn.fn(factory_for)
    @testset for (k, n_expected_1, n_expected_2, value_expected_1, value_expected_2) in zip(
        ks,
        n_expected_binary,
        n_expected_intensity,
        value_expected_binary,
        value_expected_intensity,
    )
        # Test without k parameter
        res1 = fn(test_img_binary, k, -1) # default beucher
        res2 = fn(test_img_intensity, k, -1)

        tmp_res1_beucher = fn(test_img_binary, k, -1)
        tmp_res1_internal = fn(test_img_binary, k, 0)
        tmp_res1_external = fn(test_img_binary, k, 1.0)

        @test tmp_res1_beucher != tmp_res1_external &&
              tmp_res1_external != tmp_res1_internal

        tmp_res2_beucher = fn(test_img_intensity, k, -1)
        tmp_res2_internal = fn(test_img_intensity, k, 0.0)
        tmp_res2_external = fn(test_img_intensity, k, 1)

        @test tmp_res2_beucher != tmp_res2_external &&
              tmp_res2_external != tmp_res2_internal

        @test eltype(res1) == eltype(res2) # no matter the input, the output has to be of the same type
        @test typeof(res1) <: SImageND && typeof(res1) == typeof(res2)

        # Check that the result is of the correct type
        @test eltype(res1) == ImageType && eltype(res2) == ImageType

        # Check that the result has the same size as the input image
        @test size(res1) == size(test_img_binary)
        @test size(res2) == size(test_img_binary)

        @test sum(res1 .== value_expected_1) == n_expected_1
        @test sum(res2 .== value_expected_2) == n_expected_2

        # Check that all values are clamped between 0 and 1
        @test all(0 .<= res1 .<= 1)
        @test all(0 .<= res2 .<= 1)
    end
end

# MLAPLACE
@testset "Image2D Morph: morpholaplace(img) Default" begin
    # Create a test image with a known pattern
    test_img_binary = generate_erosion_test_image(BINARY)
    test_img_intensity = generate_erosion_test_image(INTENSITY)
    inverter1 =
        UTCGP.image2D_basic.experimental_invert_image2D_factory(typeof(test_img_binary))
    inverter2 =
        UTCGP.image2D_basic.experimental_invert_image2D_factory(typeof(test_img_intensity))
    test_img_binary = inverter1(test_img_binary)
    test_img_intensity = inverter2(test_img_intensity)

    @testset for ImageType in [BINARY, INTENSITY]
        n_expected_1 = ImageType == BINARY ? 8 : 8
        n_expected_2 = ImageType == BINARY ? 8 : 8
        value_expected_1 = ImageType == BINARY ? 1 : 1
        value_expected_2 = ImageType == BINARY ? 1.0 : 1.0

        factory_for =
            ImageType == BINARY ? typeof(test_img_binary) : typeof(test_img_intensity)
        bundle =
            ImageType == BINARY ? bundle_image2DBinary_morph_factory :
            bundle_image2DIntensity_morph_factory
        # Get the function for the specific image type
        fn = bundle[:morpholaplace_2D]
        fn = fn.fn(factory_for)

        # Test without k parameter
        res1 = fn(test_img_binary)
        res2 = fn(test_img_intensity)

        @test eltype(res1) == eltype(res2) # no matter the input, the output has to be of the same type
        @test typeof(res1) <: SImageND && typeof(res1) == typeof(res2)

        # Check that the result is of the correct type
        @test eltype(res1) == ImageType && eltype(res2) == ImageType

        # Check that the result has the same size as the input image
        @test size(res1) == size(test_img_binary)
        @test size(res2) == size(test_img_binary)

        @test sum(res1 .== value_expected_1) == n_expected_1 # bc Box SE
        @test sum(res2 .== value_expected_2) == n_expected_2 # bc Box SE

        # Check that all values are clamped between 0 and 1
        @test all(0 .<= res1 .<= 1)
        @test all(0 .<= res2 .<= 1)
    end
end

@testset "Image2D Morph: morpholaplace(img, k) Default" begin
    # Create a test image with a known pattern
    test_img_binary = generate_erosion_test_image(BINARY)
    test_img_intensity = generate_erosion_test_image(INTENSITY)
    inverter1 =
        UTCGP.image2D_basic.experimental_invert_image2D_factory(typeof(test_img_binary))
    inverter2 =
        UTCGP.image2D_basic.experimental_invert_image2D_factory(typeof(test_img_intensity))
    test_img_binary = inverter1(test_img_binary)
    test_img_intensity = inverter2(test_img_intensity)
    test_img_intensity.img[5, 5] = 0.8

    n_expected_intensity = [4, 4, 12, 12, 74, 74]
    n_expected_binary = [4, 4, 12, 12, 74, 74]
    value_expected_intensity = [1, 1, 1, 1, 1, 1]
    value_expected_binary = [1, 1, 1, 1, 1, 1]
    ks = [-1, 3, 4, 5, 13, 100]
    ImageType = BINARY
    factory_for = ImageType == BINARY ? typeof(test_img_binary) : typeof(test_img_intensity)
    bundle =
        ImageType == BINARY ? bundle_image2DBinary_morph_factory :
        bundle_image2DIntensity_morph_factory
    # Get the function for the specific image type
    fn = bundle[:morpholaplace_2D]
    fn = fn.fn(factory_for)

    @testset for (k, n_expected_1, n_expected_2, value_expected_1, value_expected_2) in zip(
        ks,
        n_expected_binary,
        n_expected_intensity,
        value_expected_binary,
        value_expected_intensity,
    )
        # Test without k parameter
        res1 = fn(test_img_binary, k)
        res2 = fn(test_img_intensity, k)

        @test eltype(res1) == eltype(res2) # no matter the input, the output has to be of the same type
        @test typeof(res1) <: SImageND && typeof(res1) == typeof(res2)

        # Check that the result is of the correct type
        @test eltype(res1) == ImageType && eltype(res2) == ImageType

        # Check that the result has the same size as the input image
        @test size(res1) == size(test_img_binary)
        @test size(res2) == size(test_img_binary)

        @test sum(res1 .== value_expected_1) == n_expected_1
        @test sum(res2 .== value_expected_2) == n_expected_2

        # Check that all values are clamped between 0 and 1
        @test all(0 .<= res1 .<= 1)
        @test all(0 .<= res2 .<= 1)
    end

    n_expected_intensity = [4, 4, 12, 12, 74, 74]
    n_expected_binary = [4, 4, 12, 12, 74, 74]
    value_expected_intensity = [1, 1, 1, 1, 1, 1]
    value_expected_binary = [1, 1, 1, 1, 1, 1]
    ks = [-1, 3, 4, 5, 13, 100]
    ImageType = INTENSITY
    factory_for = ImageType == BINARY ? typeof(test_img_binary) : typeof(test_img_intensity)
    bundle =
        ImageType == BINARY ? bundle_image2DBinary_morph_factory :
        bundle_image2DIntensity_morph_factory
    # Get the function for the specific image type
    fn = bundle[:morpholaplace_2D]
    fn = fn.fn(factory_for)

    @testset for (k, n_expected_1, n_expected_2, value_expected_1, value_expected_2) in zip(
        ks,
        n_expected_binary,
        n_expected_intensity,
        value_expected_binary,
        value_expected_intensity,
    )
        # Test without k parameter
        res1 = fn(test_img_binary, k)
        res2 = fn(test_img_intensity, k)

        @test eltype(res1) == eltype(res2) # no matter the input, the output has to be of the same type
        @test typeof(res1) <: SImageND && typeof(res1) == typeof(res2)

        # Check that the result is of the correct type
        @test eltype(res1) == ImageType && eltype(res2) == ImageType

        # Check that the result has the same size as the input image
        @test size(res1) == size(test_img_binary)
        @test size(res2) == size(test_img_binary)
        @test sum(float(res1)) > 0
        @test sum(float(res2)) > 0

        @test sum(res1 .== value_expected_1) == n_expected_1
        @test sum(res2 .== value_expected_2) == n_expected_2

        # Check that all values are clamped between 0 and 1
        @test all(0 .<= res1 .<= 1)
        @test all(0 .<= res2 .<= 1)
    end
end
