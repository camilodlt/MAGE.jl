using ImageView
using ImageBinarization
using ImageCore
using Statistics

function generate_filter_test_image(::Type{IntensityPixel{T}}, size = (30, 30)) where {T}
    # Create a gradient image for intensity
    img = [i / size[1] + j / size[2] for i = 1:size[1], j = 1:size[2]]
    img = img ./ maximum(img)  # Normalize to range [0, 1]
    img[20:25, 20:25] .= 1.0
    img[10:13, 10:13] .= 0.0
    return SImageND(IntensityPixel{T}.(img))
end

function generate_filter_test_image(::Type{BinaryPixel{Bool}}, size = (30, 30))
    # Create a gradient image for intensity
    img = trues(size[1], size[2])
    img[10:13, 10:13] .= 0
    return SImageND(BinaryPixel{Bool}.(img))
end

INTENSITY = IntensityPixel{N0f8}
BINARY = BinaryPixel{Bool}

################################ INTENSITY ################################


######################
# Test Fns 2 kernels  #
######################

# API
@testset "Image2D filtering: kernels_X(img)" for KERNEL_METHOD in [
    :sobelx_image2D,
    :sobely_image2D,
    :sobelm_image2D,
    :ando3x_image2D,
    :ando3y_image2D,
    :ando3m_image2D,
    :ando4x_image2D,
    :ando4y_image2D,
    :ando4m_image2D,
    :ando5x_image2D,
    :ando5y_image2D,
    :ando5m_image2D,
    :bickleyx_image2D,
    :bickleyy_image2D,
    :bickleym_image2D,
    :prewittx_image2D,
    :prewitty_image2D,
    :prewittm_image2D,
    :scharrx_image2D,
    :scharry_image2D,
    :scharrm_image2D,
]
    Bundle = bundle_image2DIntensity_filtering_factory
    img_intensity = generate_filter_test_image(INTENSITY)
    img_intensity_bad1 = generate_filter_test_image(IntensityPixel{N0f16})
    img_intensity_bad2 = generate_filter_test_image(IntensityPixel{N0f8}, (50, 50))
    img_binary = generate_filter_test_image(BINARY)
    fac = Bundle[KERNEL_METHOD]
    fn = fac.fn(typeof(img_intensity))

    @testset for p in [-1, 0, 0.0, 2.0]
        res = fn(img_intensity, p)
        @test eltype(res) == INTENSITY
        @test size(res) == size(img_intensity)
        @test all(0 .<= res .<= 1)
        @test typeof(res) <: SImageND
        @test res != img_intensity

        @test begin
            fn(img_intensity_bad1)
            true
        end
        @test_throws MethodError begin #diff size is a pb
            fn(img_intensity_bad2)
        end
    end
    @testset for p in [-1, 0, 0.0, 2.0]
        res = fn(img_binary, p)
        @test eltype(res) == INTENSITY
        @test size(res) == size(img_intensity)
        @test all(0 .<= res .<= 1)
        @test typeof(res) <: SImageND
        @test res != img_binary
    end

    default = fn(img_intensity)
    expected = fn(img_intensity, 0)
    @test default == expected

    @test fn(img_intensity, 1) != fn(img_intensity, 0) # different border   
end
@testset "Image2D filtering: compare kernels" begin
    ks = [
        :sobelx_image2D,
        :sobely_image2D,
        :sobelm_image2D,
        :ando3x_image2D,
        :ando3y_image2D,
        :ando3m_image2D,
        :ando4x_image2D,
        :ando4y_image2D,
        :ando4m_image2D,
        :ando5x_image2D,
        :ando5y_image2D,
        :ando5m_image2D,
        :bickleyx_image2D,
        :bickleyy_image2D,
        :bickleym_image2D,
        :prewittx_image2D,
        :prewitty_image2D,
        :prewittm_image2D,
        :scharrx_image2D,
        :scharry_image2D,
        :scharrm_image2D,
    ]
    Bundle = bundle_image2DIntensity_filtering_factory
    img_intensity = generate_filter_test_image(INTENSITY)
    img_intensity_bad1 = generate_filter_test_image(IntensityPixel{N0f16})
    img_intensity_bad2 = generate_filter_test_image(IntensityPixel{N0f8}, (50, 50))
    img_binary = generate_filter_test_image(BINARY)
    fns = []
    for k in ks
        fac = Bundle[k]
        fn = fac.fn(typeof(img_intensity))
        push!(fns, fn)
    end

    @testset for p in [-1, 0, 0.0, 2.0]
        results = [fn(img_intensity, p) for fn in fns]
        @test img_intensity != results[1] != results[2] != results[3] != results[4] != results[5] != results[6] != results[7] != results[8] != results[9]
    end
end


######################
# ONE KERNEL         #
######################
@testset "Image2D filtering: ONEKERNEL(img)" for KERNEL_METHOD in [
    :gaussian5_image2D,
    :gaussian9_image2D,
    :gaussian13_image2D,
    :gaussian17_image2D,
    :gaussian25_image2D,
    :laplacian3_image2D,
]
    Bundle = bundle_image2DIntensity_filtering_factory
    img_intensity = generate_filter_test_image(INTENSITY)
    img_intensity_bad1 = generate_filter_test_image(IntensityPixel{N0f16})
    img_intensity_bad2 = generate_filter_test_image(IntensityPixel{N0f8}, (50, 50))
    img_binary = generate_filter_test_image(BINARY)
    fac = Bundle[KERNEL_METHOD]
    fn = fac.fn(typeof(img_intensity))

    @testset for p in [-1, 0, 0.0, 2.0] # border type
        res = fn(img_intensity, p)
        @test eltype(res) == INTENSITY
        @test size(res) == size(img_intensity)
        @test all(0 .<= res .<= 1)
        @test typeof(res) <: SImageND
        @test res != img_intensity

        @test begin
            fn(img_intensity_bad1)
            true
        end
        @test_throws MethodError begin #diff size is a pb
            fn(img_intensity_bad2)
        end
    end
    @testset for p in [-1, 0, 0.0, 2.0]
        res = fn(img_binary, p)
        @test eltype(res) == INTENSITY
        @test size(res) == size(img_intensity)
        @test all(0 .<= res .<= 1)
        @test typeof(res) <: SImageND
        @test res != img_binary
    end

    default = fn(img_intensity)
    expected = fn(img_intensity, 0)
    @test default == expected

    @test fn(img_intensity, 1) != fn(img_intensity, 0) # different border   
end

@testset "Image2D filtering: compare kernels" begin
    ks = [
        :gaussian5_image2D,
        :gaussian9_image2D,
        :gaussian13_image2D,
        :gaussian17_image2D,
        :gaussian25_image2D,
        :laplacian3_image2D,
    ]
    Bundle = bundle_image2DIntensity_filtering_factory
    img_intensity = generate_filter_test_image(INTENSITY)
    img_intensity_bad1 = generate_filter_test_image(IntensityPixel{N0f16})
    img_intensity_bad2 = generate_filter_test_image(IntensityPixel{N0f8}, (50, 50))
    img_binary = generate_filter_test_image(BINARY)
    fns = []
    for k in ks
        fac = Bundle[k]
        fn = fac.fn(typeof(img_intensity))
        push!(fns, fn)
    end

    @testset for p in [-1, 0, 0.0, 2.0]
        results = [fn(img_intensity, p) for fn in fns]
        @test img_intensity != results[1] != results[2] != results[3] != results[4] != results[5] != results[6] 
    end
end


######################
# SPECIAL KERNEL     #
######################

@testset "Image2D filtering: moffatX(img)" for KERNEL_METHOD in [
    :moffat5_image2D,
    :moffat13_image2D,
    :moffat25_image2D,
]
    Bundle = bundle_image2DIntensity_filtering_factory
    img_intensity = generate_filter_test_image(INTENSITY)
    img_intensity_bad1 = generate_filter_test_image(IntensityPixel{N0f16})
    img_intensity_bad2 = generate_filter_test_image(IntensityPixel{N0f8}, (50, 50))
    img_binary = generate_filter_test_image(BINARY)
    fac = Bundle[KERNEL_METHOD]
    fn = fac.fn(typeof(img_intensity))

    @testset for (p1,p2) in zip(
                [-1, -0.5, 2., 101.],
                [-1, -0.5, 2., 101.],
            )
        res = fn(img_intensity, p1,p2)
        @test eltype(res) == INTENSITY
        @test size(res) == size(img_intensity)
        @test all(0 .<= res .<= 1)
        @test typeof(res) <: SImageND
        @test res != img_intensity

        @test begin
            fn(img_intensity_bad1, 1,1)
            true
        end
        @test_throws MethodError begin #diff size is a pb
            fn(img_intensity_bad2,1,1)
        end
    end
    @testset for (p1,p2) in zip(
                [-1, -0.5, 2., 101.],
                [-1, -0.5, 2., 101.],
            )
        res = fn(img_intensity, p1,p2)
        @test eltype(res) == INTENSITY
        @test size(res) == size(img_intensity)
        @test all(0 .<= res .<= 1)
        @test typeof(res) <: SImageND
        @test res != img_intensity
    end

    @testset begin
        res = fn(img_binary, 1., 1.)
        @test res != img_binary
        @test eltype(res) == INTENSITY
    end

    @test fn(img_intensity, 1,2) != fn(img_intensity, 100,100) # different values  
    @test fn(img_intensity, 100,100) == fn(img_intensity, 101,101.) # clamped   
end


@testset "Image2D filtering: DoGX(img)" for KERNEL_METHOD in [
    :dog_image2D,
]
    Bundle = bundle_image2DIntensity_filtering_factory
    img_intensity = generate_filter_test_image(INTENSITY)
    img_intensity_bad1 = generate_filter_test_image(IntensityPixel{N0f16})
    img_intensity_bad2 = generate_filter_test_image(IntensityPixel{N0f8}, (50, 50))
    img_binary = generate_filter_test_image(BINARY)
    fac = Bundle[KERNEL_METHOD]
    fn = fac.fn(typeof(img_intensity))

    @testset for (p1,p2) in zip(
                [-1, -0.5, 2., 101.],
                [-1, -0.5, 2., 101.],
            )
        res = fn(img_intensity, p1,p2)
        @test eltype(res) == INTENSITY
        @test size(res) == size(img_intensity)
        @test all(0 .<= res .<= 1)
        @test typeof(res) <: SImageND
        @test res != img_intensity

        @test begin
            fn(img_intensity_bad1, 1,1)
            true
        end
        @test_throws MethodError begin #diff size is a pb
            fn(img_intensity_bad2,1,1)
        end
    end
    @testset for p1 in [-1, -0.5, 2., 101.]
        res = fn(img_intensity, p1)
        @test eltype(res) == INTENSITY
        @test size(res) == size(img_intensity)
        @test all(0 .<= res .<= 1)
        @test typeof(res) <: SImageND
        @test res != img_intensity
    end

    @testset begin
        res = fn(img_binary,1.)
        @test res != img_binary
        @test eltype(res) == INTENSITY
    end

    @test fn(img_intensity, 1) == fn(img_intensity, 1,1) # same val 
    @test fn(img_binary, 1) == fn(img_binary, 1,1) # same val & for binary
    @test fn(img_intensity, 100,100) == fn(img_intensity, 101,101.) # clamped   
end


################################ BINARY ################################

######################
# Test Fns 2 kernels  #
######################

# API
@testset "Image2D filtering: kernels_X(img)" for KERNEL_METHOD in [
    :sobelx_image2D,
    :sobely_image2D,
    :sobelm_image2D,
    :ando3x_image2D,
    :ando3y_image2D,
    :ando3m_image2D,
    :ando4x_image2D,
    :ando4y_image2D,
    :ando4m_image2D,
    :ando5x_image2D,
    :ando5y_image2D,
    :ando5m_image2D,
    :bickleyx_image2D,
    :bickleyy_image2D,
    :bickleym_image2D,
    :prewittx_image2D,
    :prewitty_image2D,
    :prewittm_image2D,
    :scharrx_image2D,
    :scharry_image2D,
    :scharrm_image2D,
]
    Bundle = bundle_image2DBinary_filtering_factory
    img_intensity = generate_filter_test_image(INTENSITY)
    img_intensity_bad1 = generate_filter_test_image(IntensityPixel{N0f16})
    img_intensity_bad2 = generate_filter_test_image(IntensityPixel{N0f8}, (50, 50))
    img_binary = generate_filter_test_image(BINARY)
    fac = Bundle[KERNEL_METHOD]
    fn = fac.fn(typeof(img_binary))

    @testset for p in [-1, 0, 0.0, 2.0]
        res = fn(img_intensity, p)
        @test eltype(res) == BINARY
        @test size(res) == size(img_intensity)
        @test all(x -> x == 0 || x == 1, res)
        @test typeof(res) <: SImageND
        @test res != img_intensity

        @test begin
            fn(img_intensity_bad1)
            true
        end
        @test_throws MethodError begin #diff size is a pb
            fn(img_intensity_bad2)
        end
    end
    @testset for p in [-1, 0, 0.0, 2.0]
        res = fn(img_binary, p)
        @test eltype(res) == BINARY
        @test size(res) == size(img_intensity)
        @test all(x -> x == 0 || x == 1, res)
        @test typeof(res) <: SImageND
        @test res != img_binary
    end

    default = fn(img_intensity)
    expected = fn(img_intensity, 0)
    @test default == expected
end

@testset "Image2D filtering: compare kernels" begin
    ks = [
        :sobelx_image2D,
        :sobely_image2D,
        :sobelm_image2D,
        :ando3x_image2D,
        :ando3y_image2D,
        :ando3m_image2D,
        :ando4x_image2D,
        :ando4y_image2D,
        :ando4m_image2D,
        :ando5x_image2D,
        :ando5y_image2D,
        :ando5m_image2D,
        :bickleyx_image2D,
        :bickleyy_image2D,
        :bickleym_image2D,
        :prewittx_image2D,
        :prewitty_image2D,
        :prewittm_image2D,
        :scharrx_image2D,
        :scharry_image2D,
        :scharrm_image2D,
    ]
    Bundle = bundle_image2DBinary_filtering_factory
    img_intensity = generate_filter_test_image(INTENSITY)
    img_intensity_bad1 = generate_filter_test_image(IntensityPixel{N0f16})
    img_intensity_bad2 = generate_filter_test_image(IntensityPixel{N0f8}, (50, 50))
    img_binary = generate_filter_test_image(BINARY)
    fns = []
    for k in ks
        fac = Bundle[k]
        fn = fac.fn(typeof(img_binary ))
        push!(fns, fn)
    end

    @testset for p in [-1, 0, 0.0, 2.0]
        results = [fn(img_intensity, p) for fn in fns]
        @test img_intensity != results[1] != results[2] != results[3] != results[4] != results[5] != results[6] != results[7] != results[8] != results[9]
    end
end


######################
# ONE KERNEL         #
######################
@testset "Image2D filtering: ONEKERNEL(img)" for KERNEL_METHOD in [
    :gaussian5_image2D,
    :gaussian9_image2D,
    :gaussian13_image2D,
    :gaussian17_image2D,
    :gaussian25_image2D,
    :laplacian3_image2D,
]
    Bundle = bundle_image2DBinary_filtering_factory
    img_intensity = generate_filter_test_image(INTENSITY)
    img_intensity_bad1 = generate_filter_test_image(IntensityPixel{N0f16})
    img_intensity_bad2 = generate_filter_test_image(IntensityPixel{N0f8}, (50, 50))
    img_binary = generate_filter_test_image(BINARY)
    fac = Bundle[KERNEL_METHOD]
    fn = fac.fn(typeof(img_binary))

    @testset for p in [-1, 0, 0.0, 2.0] # border type
        res = fn(img_intensity, p)
        @test eltype(res) == BINARY
        @test size(res) == size(img_intensity)
        @test all(x -> x == 0 || x == 1, res)
        @test typeof(res) <: SImageND
        @test res != img_intensity

        @test begin
            fn(img_intensity_bad1)
            true
        end
        @test_throws MethodError begin #diff size is a pb
            fn(img_intensity_bad2)
        end
    end
    @testset for p in [-1, 0, 0.0, 2.0]
        res = fn(img_binary, p)
        @test eltype(res) == BINARY
        @test size(res) == size(img_intensity)
        @test all(x -> x == 0 || x == 1, res)
        @test typeof(res) <: SImageND
        @test res != img_intensity
    end

    default = fn(img_intensity)
    expected = fn(img_intensity, 0)
    @test default == expected
end

@testset "Image2D filtering: compare kernels" begin
    ks = [
        :gaussian5_image2D,
        :gaussian9_image2D,
        :gaussian13_image2D,
        :gaussian17_image2D,
        :gaussian25_image2D,
        :laplacian3_image2D,
    ]

    Bundle = bundle_image2DBinary_filtering_factory
    img_intensity = generate_filter_test_image(INTENSITY)
    img_intensity_bad1 = generate_filter_test_image(IntensityPixel{N0f16})
    img_intensity_bad2 = generate_filter_test_image(IntensityPixel{N0f8}, (50, 50))
    img_binary = generate_filter_test_image(BINARY)
    fns = []
    for k in ks
        fac = Bundle[k]
        fn = fac.fn(typeof(img_binary))
        push!(fns, fn)
    end

    @testset for p in [-1, 0, 0.0, 2.0]
        results = [fn(img_intensity, p) for fn in fns]
        @test img_intensity != results[1]
        @test img_intensity != results[3]
        @test results[2] != results[4] 
        @test results[2] != results[5]
        @test results[2] != results[6]  
    end
end


######################
# SPECIAL KERNEL     #
######################

@testset "Image2D filtering: moffatX(img)" for KERNEL_METHOD in [
    :moffat5_image2D,
    :moffat13_image2D,
    :moffat25_image2D,
]
    Bundle = bundle_image2DBinary_filtering_factory
    img_intensity = generate_filter_test_image(INTENSITY)
    img_intensity_bad1 = generate_filter_test_image(IntensityPixel{N0f16})
    img_intensity_bad2 = generate_filter_test_image(IntensityPixel{N0f8}, (50, 50))
    img_binary = generate_filter_test_image(BINARY)
    fac = Bundle[KERNEL_METHOD]
    fn = fac.fn(typeof(img_binary))

    @testset for (p1,p2) in zip(
                [-1, -0.5, 2., 101.],
                [-1, -0.5, 2., 101.],
            )
        res = fn(img_intensity, p1,p2)
        @test eltype(res) == BINARY
        @test size(res) == size(img_intensity)
        @test all(x -> x == 0 || x == 1, res)
        @test typeof(res) <: SImageND
        @test res != img_intensity

        @test begin
            fn(img_intensity_bad1, 1,1)
            true
        end
        @test_throws MethodError begin #diff size is a pb
            fn(img_intensity_bad2,1,1)
        end
    end
    @testset for (p1,p2) in zip(
                [-1, -0.5, 2., 101.],
                [-1, -0.5, 2., 101.],
            )
        res = fn(img_intensity, p1,p2)
        @test eltype(res) == BINARY
        @test size(res) == size(img_intensity)
        @test all(x -> x == 0 || x == 1, res)
        @test typeof(res) <: SImageND
        @test res != img_intensity
    end

    @test fn(img_intensity, 1,2) != fn(img_intensity, 100,100) # different values  
    @test fn(img_intensity, 100,100) == fn(img_intensity, 101,101.) # clamped   
end


@testset "Image2D filtering: DoGX(img)" for KERNEL_METHOD in [
    :dog_image2D,
]
    Bundle = bundle_image2DBinary_filtering_factory
    img_intensity = generate_filter_test_image(INTENSITY)
    img_intensity_bad1 = generate_filter_test_image(IntensityPixel{N0f16})
    img_intensity_bad2 = generate_filter_test_image(IntensityPixel{N0f8}, (50, 50))
    img_binary = generate_filter_test_image(BINARY)
    fac = Bundle[KERNEL_METHOD]
    fn = fac.fn(typeof(img_binary))

    @testset for (p1,p2) in zip(
                [-1, -0.5, 2., 101.],
                [-1, -0.5, 2., 101.],
            )
        res = fn(img_intensity, p1,p2)
        @test eltype(res) == BINARY
        @test size(res) == size(img_intensity)
        @test all(x -> x == 0 || x == 1, res)
        @test typeof(res) <: SImageND
        @test res != img_intensity

        @test begin
            fn(img_intensity_bad1, 1,1)
            true
        end
        @test_throws MethodError begin #diff size is a pb
            fn(img_intensity_bad2,1,1)
        end
    end
    @testset for p1 in [-1, -0.5, 2., 101.]
        res = fn(img_intensity, p1)
        @test eltype(res) == BINARY
        @test size(res) == size(img_intensity)
        @test all(x -> x == 0 || x == 1, res)
        @test typeof(res) <: SImageND
        @test res != img_intensity
    end

    @test fn(img_intensity, 1) == fn(img_intensity, 1,1) # same val 
    @test fn(img_intensity, 100,100) == fn(img_intensity, 101,101.) # clamped   
end


# FIND LOCAL
@testset "Image2D filtering: findlocal_minima(img)" begin 
    Bundle = bundle_image2DBinary_filtering_factory
    img_intensity = generate_filter_test_image(INTENSITY)
    img_intensity_bad1 = generate_filter_test_image(IntensityPixel{N0f16})
    img_intensity_bad2 = generate_filter_test_image(IntensityPixel{N0f8}, (50, 50))
    img_binary = generate_filter_test_image(BINARY)
    fac = Bundle[:findlocalminima_image2D]
    fn = fac.fn(typeof(img_binary))

    @testset for (p1,p2) in zip(
                [-1, 3, 25., 26],
                [-1, 3, 25., 26],
            )
        res = fn(img_intensity, p1,p2)
        @test eltype(res) == BINARY
        @test size(res) == size(img_intensity)
        @test all(x -> x == 0 || x == 1, res)
        @test typeof(res) <: SImageND
        @test res != img_intensity

        @test begin
            fn(img_intensity_bad1, 1,1)
            true
        end
        @test_throws MethodError begin #diff size is a pb
            fn(img_intensity_bad2,1,1)
        end
    end
    @testset for p1 in [-1, 3, 25., 26]
        res = fn(img_intensity, p1)
        @test eltype(res) == BINARY
        @test size(res) == size(img_intensity)
        @test all(x -> x == 0 || x == 1, res)
        @test typeof(res) <: SImageND
        @test res != img_intensity
    end
    @testset begin 
        res = fn(img_intensity)
        @test eltype(res) == BINARY
        @test size(res) == size(img_intensity)
        @test all(x -> x == 0 || x == 1, res)
        @test typeof(res) <: SImageND
        @test res != img_intensity
    end
end
@testset "Image2D filtering: findlocal_maxima(img)" begin 

    Bundle = bundle_image2DBinary_filtering_factory
    img_intensity = generate_filter_test_image(INTENSITY)
    img_intensity_bad1 = generate_filter_test_image(IntensityPixel{N0f16})
    img_intensity_bad2 = generate_filter_test_image(IntensityPixel{N0f8}, (50, 50))
    img_binary = generate_filter_test_image(BINARY)
    fac = Bundle[:findlocalmaxima_image2D]
    fn = fac.fn(typeof(img_binary))

    @testset for (p1,p2) in zip(
                [-1, 3, 25., 26],
                [-1, 3, 25., 26],
            )
        res = fn(img_intensity, p1,p2)
        @test eltype(res) == BINARY
        @test size(res) == size(img_intensity)
        @test all(x -> x == 0 || x == 1, res)
        @test typeof(res) <: SImageND
        @test res != img_intensity

        @test begin
            fn(img_intensity_bad1, 1,1)
            true
        end
        @test_throws MethodError begin #diff size is a pb
            fn(img_intensity_bad2,1,1)
        end
    end
    @testset for p1 in [-1, 3, 25., 26]
        res = fn(img_intensity, p1)
        @test eltype(res) == BINARY
        @test size(res) == size(img_intensity)
        @test all(x -> x == 0 || x == 1, res)
        @test typeof(res) <: SImageND
        @test res != img_intensity
    end
    @testset begin 
        res = fn(img_intensity)
        @test eltype(res) == BINARY
        @test size(res) == size(img_intensity)
        @test all(x -> x == 0 || x == 1, res)
        @test typeof(res) <: SImageND
        @test res != img_intensity
    end
end
