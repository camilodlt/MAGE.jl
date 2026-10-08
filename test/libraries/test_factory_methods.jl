@testset "Multi-signature factory functions: dispatch introspection" begin
    binary_image_type = SImage2D{
        10,
        10,
        BinaryPixel{Bool},
        Matrix{BinaryPixel{Bool}},
    }
    intensity_image_type = SImage2D{
        10,
        10,
        IntensityPixel{N0f8},
        Matrix{IntensityPixel{N0f8}},
    }
    wrong_size_intensity_type = SImage2D{
        20,
        20,
        IntensityPixel{N0f8},
        Matrix{IntensityPixel{N0f8}},
    }

    # Factories with several signatures build one named function with one method each.
    factory = UTCGP.image2D_binarize.binarizeMinimumintermodes_image2D_factory
    fn = factory(binary_image_type)
    @test fn isa Function && length(methods(fn)) == 2
    @test factory(binary_image_type) === fn                          # built once, then reused
    nparams(m) = m.nargs - 2                                          # without the function and the trailing args...
    @test nparams(Base.which(fn, Tuple{intensity_image_type})) == 1
    @test nparams(Base.which(fn, Tuple{intensity_image_type, Float64})) == 2

    valid_signatures = (
        Tuple{intensity_image_type},
        Tuple{intensity_image_type, Int},
        Tuple{intensity_image_type, Float32},
        Tuple{intensity_image_type, Float64},
        Tuple{intensity_image_type, Number},
        Tuple{intensity_image_type, String},
    )
    invalid_signatures = (
        Tuple{Float64},
        Tuple{Float64, Float64},
        Tuple{binary_image_type},
        Tuple{wrong_size_intensity_type},
    )

    for signature in valid_signatures
        @test Base.hasmethod(fn, signature)
        @test Base.which(fn, signature) isa Method
    end

    for signature in invalid_signatures
        @test !Base.hasmethod(fn, signature)
        @test_throws Exception Base.which(fn, signature)
    end

    @test_throws MethodError fn(1.0, 2.0)

    # The same factory specialised on two output types gives two distinct functions.
    erosion = UTCGP.image2D_morph.erosion_image2D_factory
    @test erosion(binary_image_type) !== erosion(intensity_image_type)
    @test erosion(binary_image_type) === erosion(binary_image_type)
end
