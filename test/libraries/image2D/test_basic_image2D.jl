using Images
using Statistics

function load_test_image()
    test_img = UTCGP._convert_image_to_channel_view(testimage("mandrill"))
    test_img = test_img[1, :, :]
    return SImageND(test_img)
end

types_and_bundles = [
    [IntensityPixel{N0f8}, BinaryPixel{Bool}, SegmentPixel{UInt8}],
    [
        bundle_image2DIntensity_basic_factory,
        bundle_image2DBinary_basic_factory,
        bundle_image2DSegment_basic_factory,
    ],
]
types_and_bundles2 = [
    [IntensityPixel{N0f8}, BinaryPixel{Bool}],
    [bundle_image2DIntensity_basic_factory, bundle_image2DBinary_basic_factory],
]

@testset "Image2D Basic : Identity Factory" begin
    @testset for (ImageType, Bundle) in zip(types_and_bundles...)
        test_img = UTCGP._generate_test_image(ImageType)
        fn = Bundle[:identity_image2D]
        fn = fn.fn(typeof(test_img))
        res = fn(test_img)
        @test res == test_img
    end
end

@testset "Image2D Basic : Ones Factory" begin
    @testset for (ImageType, Bundle) in zip(types_and_bundles...)
        test_img = UTCGP._generate_test_image(ImageType)
        fn = Bundle[:ones_2D]
        fn = fn.fn(typeof(test_img))
        res = fn(test_img)
        @test all(res .== 1)
    end
end

@testset "Image2D Basic : Zeros Factory" begin
    @testset for (ImageType, Bundle) in zip(types_and_bundles...)
        test_img = UTCGP._generate_test_image(ImageType)
        fn = Bundle[:zeros_2D]
        fn = fn.fn(typeof(test_img))
        res = fn(test_img)
        @test all(res .== 0)
    end
end

@testset "Image2D Basic : Invert Factory" begin
    @testset for (ImageType, Bundle) in zip(types_and_bundles2...)
        test_img = UTCGP._generate_test_image(ImageType)
        fn = Bundle[:experimental_invert_2D]
        fn = fn.fn(typeof(test_img))
        res = fn(test_img)

        # Convert test_img to float64 and apply the inversion and clamping
        expected_res = abs.(1.0 .- float64.(test_img))
        clamp01nan!(expected_res)
        expected_res = ImageType.(expected_res)

        # Compare the result with the expected result
        @test all(res .== expected_res)
    end
end

@testset "Image2D Basic : Normalize Factory" begin
    @testset begin
        test_img = UTCGP._generate_test_image(IntensityPixel{N0f8})
        fn = bundle_image2DIntensity_basic_factory[:experimental_normalize_2D]
        fn = fn.fn(typeof(test_img))
        res = fn(test_img)
        @test all(0 .<= res .<= 1)
    end
end

@testset "Image2D Basic : Standardize Factory" begin
    @testset begin
        test_img = UTCGP._generate_test_image(IntensityPixel{N0f8})
        fn = bundle_image2DIntensity_basic_factory[:experimental_standardize_2D]
        fn = fn.fn(typeof(test_img))
        res = fn(test_img)
        old_mean = mean(test_img)
        new_mean = mean(res)
        @test old_mean != new_mean
    end
end

@testset "Image2D Basic : ToBinary Factory" begin
    @testset for ImageType in [IntensityPixel{N0f8}, SegmentPixel{UInt8}]
        t = BinaryPixel{Bool}
        as_img = UTCGP._generate_test_image(t)
        test_img = UTCGP._generate_test_image(ImageType)
        fn = bundle_image2DBinary_basic_factory[:experimental_tobinary_image2D]
        fn = fn.fn(typeof(as_img))
        res = fn(test_img)
        if ImageType == IntensityPixel{N0f8}
            @test all(res .== BinaryPixel.(test_img .> 0))
        else
            @test all(res .== BinaryPixel.(test_img .!= 1))
        end
    end
end

@testset "Image2D Basic : ToIntensity Factory" begin
    @testset begin
        from = SegmentPixel{UInt8}
        to = IntensityPixel{N0f8}
        as_img = UTCGP._generate_test_image(to)
        test_img = UTCGP._generate_test_image(from)

        fn = bundle_image2DIntensity_basic_factory[:experimental_tointensity_image2D]
        fn = fn.fn(typeof(as_img))
        res = fn(test_img)

        # Calculate the expected result by normalizing the segment values
        r = float.(test_img)
        max_ = maximum(r)
        r .= r ./ max_
        expected_res = IntensityPixel{N0f8}.(r)

        # Compare the result with the expected normalized intensity values
        @test all(res .== expected_res)
    end
    @test begin
        from = BinaryPixel{Bool}
        to = IntensityPixel{N0f8}
        as_img = UTCGP._generate_test_image(to)
        test_img = UTCGP._generate_test_image(from)

        fn = bundle_image2DIntensity_basic_factory[:experimental_tointensity_image2D]
        fn = fn.fn(typeof(as_img))
        res = fn(test_img)

        # Check that the result is of the correct type
        @test eltype(res) == IntensityPixel{N0f8}

        # Check that all values in the result are either 0 or 1
        @test all(x -> x == 0 || x == 1, res)

        # Check that the binary structure is preserved
        @test all(res .=== IntensityPixel{N0f8}.(Int.(test_img)))
        true
    end
end

@testset "Image2D Basic : ToSegment Factory" begin
    @testset begin
        from = BinaryPixel{Bool}
        to = SegmentPixel{UInt8}
        as_img = UTCGP._generate_test_image(to)
        test_img = UTCGP._generate_test_image(from)

        fn = bundle_image2DSegment_basic_factory[:experimental_tosegment_image2D]
        fn = fn.fn(typeof(as_img))
        res = fn(test_img)

        # Check that the result is of the correct type
        @test eltype(res) == SegmentPixel{UInt8}

        # Check that all values in the result are either 0 or 1
        @test all(x -> x == 0 || x == 1, res)

        # Check that the binary structure is preserved
        @test all(res .=== SegmentPixel{UInt8}.(Int.(test_img)))
        true
    end
end
