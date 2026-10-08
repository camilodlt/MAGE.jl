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
        @test_throws ErrorException begin # diff size is rejected by ManualDispatcher
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
    coins = load(joinpath(@__DIR__, "../../../assets/water_coins.jpg"))
    coins_mask = Gray.(coins) .< 0.5 # coins are the objects (true)
    img = SImageND(BinaryPixel{Bool}.(coins_mask))
    s = size(coins_mask)

    img_intensity_bad1 = generate_filter_test_image(INTENSITY, s) # bad type
    img_binary_bad1 = generate_filter_test_image(BINARY, (50, 50)) # bad size
    img_segment = generate_filter_test_image(SEGMENT, s)
    fn = Bundle[:watershed_image2D].fn(typeof(img_segment))

    @testset for p in [-30, -15, 0, 0.0, 0.5, 0.9, 2.0, NaN]
        res = fn(img, p)
        @test eltype(res) == SEGMENT
        @test size(res) == size(img)
        labels = Int.(reinterpret(res.img))
        @test all(iszero, labels[.!coins_mask])           # background stays 0
        @test all(>(0), labels[coins_mask])               # every object pixel is labelled
        @test_throws ErrorException fn(img_intensity_bad1, p)
        @test_throws ErrorException fn(img_binary_bad1, p)
    end

    count_labels(res) = length(setdiff(unique(Int.(reinterpret(res.img))), 0))
    # The coins touch each other: one connected blob, split into the 24 coins.
    @test count_labels(fn(img, 0.0)) == 1
    @test count_labels(fn(img, 0.7)) == 24
    @test fn(img) == fn(img, 0.7)

    mask_all = SImageND(BinaryPixel{Bool}.(trues(s)))
    mask_none = SImageND(BinaryPixel{Bool}.(falses(s)))
    @test fn(img, mask_all, 0.7) == fn(img, 0.7)          # restrict to everything = no restriction
    @test count_labels(fn(img, mask_none, 0.7)) == 0
    left = SImageND(BinaryPixel{Bool}.([c <= s[2] ÷ 2 for r in 1:s[1], c in 1:s[2]]))
    cropped = Int.(reinterpret(fn(img, left, 0.7).img))
    @test all(iszero, cropped[:, s[2]÷2+1:end])

    # Two touching disks are cut at their neck (depth ratio ≈ 0.62).
    disks = [((r - 20)^2 + (c - 14)^2 <= 81) || ((r - 20)^2 + (c - 28)^2 <= 81) for r in 1:40, c in 1:44]
    D = SImageND(BinaryPixel{Bool}.(disks))
    fd = Bundle[:watershed_image2D].fn(typeof(SImageND(SegmentPixel{Int}.(zeros(Int, 40, 44)))))
    out = Int.(reinterpret(fd(D, 0.7).img))
    @test out[20, 12] != out[20, 30] && out[20, 12] > 0 && out[20, 30] > 0
    @test count_labels(fd(D, 0.5)) == 1
end

