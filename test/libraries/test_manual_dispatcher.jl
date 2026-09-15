@testset "ManualDispatcher dispatch introspection" begin
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

    dispatcher = UTCGP.image2D_binarize.binarizeMinimumintermodes_image2D_factory(
        binary_image_type,
    )
    no_parameter_method = first(methods(dispatcher.functions[2]))
    parameter_method = first(methods(dispatcher.functions[1]))
    @test Base.which(dispatcher, Tuple{intensity_image_type}) === no_parameter_method
    @test Base.which(dispatcher, Tuple{intensity_image_type, Float64}) === parameter_method

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
        @test Base.hasmethod(dispatcher, signature)
        @test Base.which(dispatcher, signature) !== nothing
    end

    for signature in invalid_signatures
        @test !Base.hasmethod(dispatcher, signature)
        @test Base.which(dispatcher, signature) === nothing
    end

    @test_throws Exception dispatcher(1.0, 2.0)
end
