using Images
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
function generate_filter_test_image(::Type{SegmentPixel{Int}}, size = (30, 30))
    # Create a gradient image for intensity
    img = zeros(size[1], size[2])
    img[20:23, 20:23] .= 1
    img[10:13, 10:13] .= 2
    return SImageND(SegmentPixel{Int}.(img))
end

INTENSITY = IntensityPixel{N0f8}
BINARY = BinaryPixel{Bool}
SEGMENT = SegmentPixel{Int}

################################ INTENSITY ################################

# FASTSCANNING

@testset "Image2D Segmentation: fastscanning(img)" begin
    Bundle = bundle_image2DSegment_segmentation_factory
    img_intensity = generate_filter_test_image(INTENSITY)
    img_intensity_bad1 = generate_filter_test_image(IntensityPixel{N0f16})
    img_intensity_bad2 = generate_filter_test_image(IntensityPixel{N0f8}, (50, 50))
    img_binary = generate_filter_test_image(BINARY)
    img_segment = generate_filter_test_image(SEGMENT)
    fac = Bundle[:fastscanning_image2D]
    fn = fac.fn(typeof(img_segment))

    @testset for p in [-1, 0, 0.0, 0.5, 0.9, 2.]
        res = fn(img_intensity, p)
        @test eltype(res) == SEGMENT
        @test size(res) == size(img_intensity)
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
    @testset for p in [-1, 0, 0.0, 0.5, 0.9, 2.]
        res = fn(img_binary, p)
        @test eltype(res) == SEGMENT
        @test size(res) == size(img_intensity)
        @test typeof(res) <: SImageND
        @test res != img_binary
    end
    
    res = fn(img_intensity, 0.1)
    @test length(unique(res)) == 8 # segments

    res = fn(img_binary, 0.1)
    @test length(unique(res)) == 2 # segments

    
    fac_to_binary = bundle_image2DBinary_basic_factory[:experimental_tobinary_image2D]
    fn_to_binary = fac_to_binary.fn(typeof(img_binary))
    res_binary = fn_to_binary(res)
    length(unique(reinterpret(res_binary.img))) == 2

    fac_to_intensity = bundle_image2DIntensity_basic_factory[:experimental_tointensity_image2D]
    fn_to_intensity = fac_to_intensity.fn(typeof(img_intensity))
    res_intensity = fn_to_intensity(res)
    length(unique(reinterpret(res_intensity.img))) == 2

end
 
@testset "Image2D Segmentation: watershed(img, mask, p)" begin
    Bundle = bundle_image2DSegment_segmentation_factory
    coins = load(download("http://docs.opencv.org/3.1.0/water_coins.jpg")); 
    coins_binary = Gray.(coins) .> 0.5 #coins black
    img = SImageND(BinaryPixel{Bool}.(coins_binary))
    s = size(coins_binary)

    img_intensity_bad1 = generate_filter_test_image(INTENSITY, s) # bad type
    img_binary_bad1 = generate_filter_test_image(BINARY, (50, 50)) # bad size
    img_binary = generate_filter_test_image(BINARY, s)
    img_segment = generate_filter_test_image(SEGMENT,s)
    fac = Bundle[:watershed_image2D]
    fn = fac.fn(typeof(img_segment))

    @testset for p in [-30, -15, 0, 0.0, 0.5, 0.9, 2.]
        res = fn(img, p)
        @test eltype(res) == SEGMENT
        @test size(res) == size(img)
        @test typeof(res) <: SImageND
        @test res != img

        @test_throws MethodError begin
            fn(img_intensity_bad1,p)
            true
        end
        @test_throws MethodError begin
            fn(img_binary_bad1,p)
        end
    end

    mask_all = SImageND(BinaryPixel{Bool}.(trues(s)))    
    mask_none = SImageND(BinaryPixel{Bool}.(falses(s)))    

    res = fn(img, mask_none, -15)
    @test length(unique(res)) > 1 # returns the markers

    res = fn(img, mask_all, -15)
    @test res == fn(img, -15) # default mask is all 

    @test fn(img) == fn(img, -15) == fn(img, mask_all, -15)

    mask = Gray.(coins) .< 0.5 #coins white
    mask = SImageND(BinaryPixel{Bool}.(mask ))
    res_cropped = fn(img, mask, -15)
    @test res_cropped != res
    @test length(unique(res_cropped)) == 25
end
