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

@testset "Reduce Image" begin
    Bundle = bundle_number_reduceFromImg

    img_intensity = generate_filter_test_image(INTENSITY)
    img_intensity_bad1 = generate_filter_test_image(IntensityPixel{N0f16})
    img_intensity_bad2 = generate_filter_test_image(IntensityPixel{N0f8}, (50, 50))
    img_intensity_bad3 = generate_filter_test_image(IntensityPixel{N0f8}, (50, 60))
    img_binary = generate_filter_test_image(BINARY)
    img_segment = generate_filter_test_image(SEGMENT)

    # Reduce length --- 
    @testset "Reduce Length" begin
        fn = bundle_number_reduceFromImg[:reduce_length].fn
        @test fn(img_intensity_bad2) == 50 * 50
        @test fn(img_binary) == 30 * 30
        @test fn(img_segment) == 30 * 30
    end

    @testset "Reduce Big axis" begin
        fn = bundle_number_reduceFromImg[:reduce_biggestAxis].fn
        @test fn(img_intensity_bad2) == 50
        @test fn(img_intensity_bad3) == 60
        @test fn(img_binary) == 30
        @test fn(img_segment) == 30
    end

    @testset "Reduce Small axis" begin
        fn = bundle_number_reduceFromImg[:reduce_smallerAxis].fn
        @test fn(img_intensity_bad2) == 50
        @test fn(img_intensity_bad3) == 50
        @test fn(img_binary) == 30
        @test fn(img_segment) == 30
    end

    @testset "Reduce Image HistMode" begin
        fn = bundle_number_reduceFromImg[:reduce_histMode].fn
        @test begin
            res = fn(img_intensity)
            res == 1.0 && (res isa Float64)
        end

        @test begin
            res = fn(img_binary)
            res == 1.0 && (res isa Float64) # bc N0f16 binned it
        end
    end

    @testset "Reduce Image HistMode Count" begin
        fn = bundle_number_reduceFromImg[:reduce_histModeCount].fn
        @test begin
            res = fn(img_intensity)
            res == 37.0 && (res isa Float64)
        end

        @test begin
            res = fn(img_binary)
            res == 884.0 && (res isa Float64) # bc N0f16 binned it
        end
    end

    @testset "Reduce Prop White" begin
        fn = bundle_number_reduceFromImg[:reduce_propWhite].fn
        @test begin
            res = fn(img_binary)
            res ≈ 0.98222222 && (res isa Float64)
        end
        @test_throws MethodError begin
            fn(img_intensity)
        end
        @test_throws MethodError begin
            fn(img_segment)
        end
    end
    @testset "Reduce Prop Black" begin
        fn = bundle_number_reduceFromImg[:reduce_propBlack].fn
        @test begin
            res = fn(img_binary)
            res ≈ 0.017777777777777778 && (res isa Float64)
        end
        @test_throws MethodError begin
            fn(img_intensity)
        end
        @test_throws MethodError begin
            fn(img_segment)
        end
    end

    @testset "Reduce N Colors" begin
        fn = bundle_number_reduceFromImg[:reduce_nColors].fn
        @test begin
            res = fn(img_binary)
            res == 2.0 && (res isa Float64)
        end
        @test begin
            res = fn(img_intensity)
            res == 63 && (res isa Float64)
        end
        @test begin
            res = fn(img_segment)
            res == 3 && (res isa Float64)
        end
    end

    @testset "Reduce Mean" begin
        fn = bundle_number_reduceFromImg[:reduce_mean].fn
        @test begin
            res = fn(img_intensity)
            res ≈ mean(float(img_intensity)) && (res isa Float64)
        end
        @test begin
            res = fn(img_intensity_bad3)
            res ≈ mean(float(img_intensity_bad3)) && (res isa Float64)
        end
        @test_throws MethodError begin
            fn(img_binary)
        end
        @test_throws MethodError begin
            fn(img_segment)
        end
    end
    @testset "Reduce Median" begin
        fn = bundle_number_reduceFromImg[:reduce_median].fn
        @test begin
            res = fn(img_intensity)
            res ≈ median(float(img_intensity)) && (res isa Float64)
        end
        @test begin
            res = fn(img_intensity_bad3)
            res ≈ median(float(img_intensity_bad3)) && (res isa Float64)
        end
        @test_throws MethodError begin
            fn(img_binary)
        end
        @test_throws MethodError begin
            fn(img_segment)
        end
    end
    @testset "Reduce Std" begin
        fn = bundle_number_reduceFromImg[:reduce_std].fn
        @test begin
            res = fn(img_intensity)
            res ≈ std(float(img_intensity)) && (res isa Float64)
        end
        @test begin
            res = fn(img_intensity_bad3)
            res ≈ std(float(img_intensity_bad3)) && (res isa Float64)
        end
        @test_throws MethodError begin
            fn(img_binary)
        end
        @test_throws MethodError begin
            fn(img_segment)
        end
    end

    @testset "Reduce Maximum" begin
        fn = bundle_number_reduceFromImg[:reduce_maximum].fn
        @test begin
            res = fn(img_intensity)
            res ≈ 1.0 && (res isa Float64)
        end
        @test_throws MethodError begin
            fn(img_segment)
        end
        @test_throws MethodError begin
            fn(img_binary)
        end
    end
    @testset "Reduce Minimum" begin
        fn = bundle_number_reduceFromImg[:reduce_minimum].fn
        @test begin
            res = fn(img_intensity)
            res ≈ 0.0 && (res isa Float64)
        end
        @test_throws MethodError begin
            fn(img_segment)
        end
        @test_throws MethodError begin
            fn(img_binary)
        end
    end
end
