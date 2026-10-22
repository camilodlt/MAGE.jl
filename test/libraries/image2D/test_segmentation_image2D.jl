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
    fn = (@test_factory fac.fn(typeof(img_segment)))

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
        @test_throws MethodError begin # a different size has no method
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
    fn_to_binary = (@test_factory fac_to_binary.fn(typeof(img_binary)))
    res_binary = fn_to_binary(res)
    length(unique(reinterpret(res_binary.img))) == 2

    fac_to_intensity = bundle_image2DIntensity_basic_factory[:experimental_tointensity_image2D]
    fn_to_intensity = (@test_factory fac_to_intensity.fn(typeof(img_intensity)))
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
    fn = (@test_factory Bundle[:watershed_image2D].fn(typeof(img_segment)))

    @testset for p in [-30, -15, 0, 0.0, 0.5, 0.9, 2.0, NaN]
        res = fn(img, p)
        @test eltype(res) == SEGMENT
        @test size(res) == size(img)
        labels = Int.(reinterpret(res.img))
        @test all(iszero, labels[.!coins_mask])           # background stays 0
        @test all(>(0), labels[coins_mask])               # every object pixel is labelled
        @test_throws MethodError fn(img_intensity_bad1, p)
        @test_throws MethodError fn(img_binary_bad1, p)
    end

    count_labels(res) = length(setdiff(unique(Int.(reinterpret(res.img))), 0))
    # At 32 the touching coins merge into two coarse basins.
    @test count_labels(fn(img, 0.0)) == 1
    @test count_labels(fn(img, 0.7)) == 2
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
    fd = (@test_factory Bundle[:watershed_image2D].fn(typeof(SImageND(SegmentPixel{Int}.(zeros(Int, 40, 44))))))
    out = Int.(reinterpret(fd(D, 0.7, -1.0).img))
    @test out[20, 12] != out[20, 30] && out[20, 12] > 0 && out[20, 30] > 0
    @test count_labels(fd(D, 0.5)) == 1
end


@testset "Watershed sign selector and deterministic budget" begin
    library = MAGE.image2D_segmentation
    selectors = (-1, 0, 1, -1.0, 0.0, 1.0, -0.0, NaN, Inf, -Inf)
    for (height, width) in ((1, 1), (32, 32), (224, 100), (100, 224), (37, 500), (33, 32))
        foreground = [
            abs(row - height / 2) < height / 4 && abs(column - width / 2) < width / 4
            for row in 1:height, column in 1:width
        ]
        mask = SImageND(BinaryPixel{Bool}.(foreground))
        output = SImageND(SegmentPixel{Int}.(zeros(Int, height, width)))
        fn = (@test_factory bundle_image2DSegment_segmentation_factory[:watershed_image2D].fn(typeof(output)))
        @test fn(mask, 0.7).img == fn(mask, 0.7, NaN).img
        @test fn(mask, 0.7, 1).img == fn(mask, 0.7, Inf).img
        @test fn(mask, 0.7, 0).img == fn(mask, 0.7, -0.0).img
        longer_axis = max(height, width)
        for selector in selectors
            expected_limit = selector < 0 ? longer_axis : selector == 0 ? cld(longer_axis, 2) : 32
            @test library._watershed_resolution(longer_axis, selector) == expected_limit
            expected = copy(library._watershed_split(foreground, trues(height, width), 0.7, expected_limit))
            result = fn(mask, 0.7, selector)
            @test Int.(reinterpret(result.img)) == expected
            @test fn(mask, 0.7, selector; out = output) === output
            @test result.img == output.img
            tasks = [Threads.@spawn(fn(mask, 0.7, selector).img) for _ in 1:2]
            @test all(fetch(task) == result.img for task in tasks)
        end
        for selector in (-1, 0, 1)
            @test fn(mask, 0.7, selector).img == fn(mask, 0.7, Float64(selector)).img
        end
    end
    @test library._resolution_size(37, 500, library._watershed_resolution(500, 0)) == (18, 250)
    @test library._resolution_size(33, 32, library._watershed_resolution(33, 0)) == (17, 16)
    @test library._resolution_size(19, 7, library._watershed_resolution(19, 1)) == (19, 7)
    mask = SImageND(BinaryPixel{Bool}.(trues(225, 225)))
    output = SImageND(SegmentPixel{Int}.(zeros(Int, 225, 225)))
    fn = (@test_factory bundle_image2DSegment_segmentation_factory[:watershed_image2D].fn(typeof(output)))
    @test_throws ErrorException fn(mask, 0.7, -1)
    @test_throws ErrorException fn(mask, 0.7, -Inf)
    @test size(fn(mask, 0.7, 0).img) == (225, 225)
end

@testset "Reduced watershed allocations do not scale with full output size" begin
    allocations = Int[]
    for side in (224, 448)
        mask = SImageND(BinaryPixel{Bool}.([
            side ÷ 4 < row < 3side ÷ 4 && side ÷ 4 < column < 3side ÷ 4
            for row in 1:side, column in 1:side
        ]))
        output = SImageND(SegmentPixel{Int}.(zeros(Int, side, side)))
        fn = (@test_factory bundle_image2DSegment_segmentation_factory[:watershed_image2D].fn(typeof(output)))
        for _ in 1:3
            fn(mask, 0.7; out = output)
        end
        push!(allocations, @allocated fn(mask, 0.7; out = output))
    end
    @test allocations[2] <= allocations[1] + 4096
end

@testset "Reduced watershed preserves full-resolution component identities" begin
    library = MAGE.image2D_segmentation
    # The one-pixel gap disappears on both 32 and half grids.
    objects = falses(224, 224)
    objects[50:100, 50:100] .= true
    objects[50:100, 102:152] .= true
    mask = SImageND(BinaryPixel{Bool}.(objects))
    output = SImageND(SegmentPixel{Int}.(zeros(Int, size(objects))))
    fn = (@test_factory bundle_image2DSegment_segmentation_factory[:watershed_image2D].fn(typeof(output)))
    for selector in (1, 0)
        result = copy(reinterpret(fn(mask, 0.0, selector).img))
        @test result[75, 75] != result[75, 125]
        @test result[75, 75] > 0 && result[75, 125] > 0
        @test (result .> 0) == objects
        @test reinterpret(fn(mask, 0.0, selector; out = output).img) == result
        tasks = [Threads.@spawn(copy(reinterpret(fn(mask, 0.0, selector).img))) for _ in 1:2]
        @test all(fetch(task) == result for task in tasks)
    end
    # Restriction can disconnect a single foreground object too.
    foreground = SImageND(BinaryPixel{Bool}.(trues(224, 224)))
    @test length(unique(reinterpret(fn(foreground, mask, 0.0).img))) == 3
    # Four-neighbor convention: diagonal-only pixels are distinct components.
    diagonal = falses(64, 64)
    diagonal[10, 10] = diagonal[11, 11] = true
    diagonal_mask = SImageND(BinaryPixel{Bool}.(diagonal))
    small_output = SImageND(SegmentPixel{Int}.(zeros(Int, 64, 64)))
    diagonal_fn = (@test_factory bundle_image2DSegment_segmentation_factory[:watershed_image2D].fn(typeof(small_output)))
    labels = reinterpret(diagonal_fn(diagonal_mask, 0.0).img)
    @test labels[10, 10] != labels[11, 11]
    # Pair renumbering follows first occurrence, independent of coarse basin IDs.
    pairs = zeros(Int, 2, 3)
    library._watershed_component_pairs!(pairs, Bool[1 0 1; 0 0 1], fill(7, 1, 1))
    @test pairs == [1 0 2; 0 0 2]
    # More than 255 separate islands must not silently wrap UInt8 output labels.
    speckles = [isodd(row) && isodd(column) for row in 1:64, column in 1:64]
    narrow_output = SImageND(SegmentPixel{UInt8}.(zeros(UInt8, 64, 64)))
    narrow_fn = (@test_factory bundle_image2DSegment_segmentation_factory[:watershed_image2D].fn(typeof(narrow_output)))
    @test_throws OverflowError narrow_fn(SImageND(BinaryPixel{Bool}.(speckles)), 0.0)
end
