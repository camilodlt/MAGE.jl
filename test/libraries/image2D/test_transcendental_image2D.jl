#################
# Exponential   #
#################
@testset "Image2D Transcendental: exp_image2D" begin
    Bundle = bundle_image2DIntensity_transcendental_factory
    test_img = generate_binarize_test_image(INTENSITY)
    fn = Bundle[:exp_image2D]
    fn = fn.fn(typeof(test_img))

    c1 = sum(test_img .< 0.3)
    res = fn(test_img)
    @test eltype(res) == IntensityPixel{N0f8}
    @test size(res) == size(test_img)
    @test all(0 .<= res .<= 1)
    @test res !== test_img
    c2 = sum(res .< 0.3)
    @test c1 < c2 # more blacker pixels
end

# #################
# # LOG           #
# #################
@testset "Image2D Transcendental: loginv_image2D" begin
    Bundle = bundle_image2DIntensity_transcendental_factory
    test_img = generate_binarize_test_image(INTENSITY)
    fn = Bundle[:loginv_image2D]
    fn = fn.fn(typeof(test_img))

    res = fn(test_img)
    @test eltype(res) == IntensityPixel{N0f8}
    @test size(res) == size(test_img)
    @test all(0 .<= res .<= 1)
    @test res !== test_img

    count_white1 = sum(test_img .== 1)
    count_white2 = sum(res .== 1)
    @test count_white2 > count_white1
end

@testset "Image2D Transcendental: log_image2D" begin
    Bundle = bundle_image2DIntensity_transcendental_factory
    test_img = generate_binarize_test_image(INTENSITY)
    fn = Bundle[:log_image2D]
    fn = fn.fn(typeof(test_img))

    res = fn(test_img)
    
    @test eltype(res) == IntensityPixel{N0f8}
    @test size(res) == size(test_img)
    @test all(0 .<= res .<= 1)
    @test res !== test_img

    m1 = mean(test_img.img)
    m2 = mean(res.img)
    @test m2 > m1
end

# #################
# # Power Of      #
# #################

@testset "Image2D Transcendental: powerof_image2D" begin
    Bundle = bundle_image2DIntensity_transcendental_factory
    test_img = generate_binarize_test_image(INTENSITY)
    fn = Bundle[:powerof_image2D]
    fn = fn.fn(typeof(test_img))

    m1 = mean(test_img.img)
     
    res = fn(test_img, 1.)
    @test eltype(res) == IntensityPixel{N0f8}
    @test size(res) == size(test_img)
    @test all(0 .<= res .<= 1)
    @test res == test_img

    res = fn(test_img, 0)
    @test eltype(res) == IntensityPixel{N0f8}
    @test size(res) == size(test_img)
    @test all(0 .<= res .<= 1)
    @test all(res .== 1)

    res = fn(test_img, 0.5)
    m2 = mean(res.img)
    @test eltype(res) == IntensityPixel{N0f8}
    @test size(res) == size(test_img)
    @test all(0 .<= res .<= 1)
    @test m2 > m1 # image is brighter

    res = fn(test_img, 2.)
    m2 = mean(res.img)
    @test eltype(res) == IntensityPixel{N0f8}
    @test size(res) == size(test_img)
    @test all(0 .<= res .<= 1)
    @test m2 < m1 # image is way darker
    
end
