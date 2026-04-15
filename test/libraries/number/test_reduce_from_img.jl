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

function region_test_image(::Type{IntensityPixel{T}}) where {T}
    img = Float64[
        1  2  3  4  5;
        6  7  8  9 10;
       11 12 13 14 15;
       16 17 18 19 20;
       21 22 23 24 25;
    ]
    img ./= maximum(img)
    return SImageND(IntensityPixel{T}.(img))
end

function region_test_image(::Type{BinaryPixel{Bool}})
    img = Bool[
        0 0 0 1 1;
        0 1 1 1 1;
        0 1 1 1 1;
        0 0 1 1 1;
        0 0 0 1 1;
    ]
    return SImageND(BinaryPixel{Bool}.(img))
end

function region_test_image(::Type{SegmentPixel{Int}})
    img = Int[
        1 1 2 2 2;
        1 1 2 3 3;
        1 2 2 3 3;
        4 4 2 3 3;
        4 4 4 3 3;
    ]
    return SImageND(SegmentPixel{Int}.(img))
end

function _normalized_index_for_test(coord::Number, n::Int)
    c = clamp(Float64(coord), 0.0, 1.0)
    return clamp(round(Int, c * (n - 1) + 1), 1, n)
end

function _patch_for_test(img::AbstractMatrix, cx, cy, half_size)
    h, w = size(img)
    center_col = _normalized_index_for_test(cx, w)
    center_row = _normalized_index_for_test(cy, h)
    row_lo = max(center_row - half_size, 1)
    row_hi = min(center_row + half_size, h)
    col_lo = max(center_col - half_size, 1)
    col_hi = min(center_col + half_size, w)
    return @view img[row_lo:row_hi, col_lo:col_hi]
end

function _region_entropy_expected(img::AbstractMatrix, cx, cy)
    patch = vec(Float64.(collect(_patch_for_test(img, cx, cy, 1))))
    minv = minimum(patch)
    maxv = maximum(patch)
    maxv == minv && return 0.0
    counts = zeros(Int, 8)
    for value in patch
        scaled = (value - minv) / (maxv - minv)
        idx = clamp(floor(Int, scaled * 8) + 1, 1, 8)
        counts[idx] += 1
    end
    total = length(patch)
    entropy = 0.0
    for count in counts
        count == 0 && continue
        p = count / total
        entropy -= p * log2(p)
    end
    return entropy
end

function _region_half_size_percent_for_test(img::AbstractMatrix, pct::Float64)
    max_side = min(size(img)...)
    kernel_size = max(round(Int, pct * max_side), 1)
    if iseven(kernel_size)
        kernel_size += 1
    end
    kernel_size = min(kernel_size, max_side)
    if iseven(kernel_size) && kernel_size > 1
        kernel_size -= 1
    end
    return fld(kernel_size - 1, 2)
end

function _region_contrast_expected(img::AbstractMatrix, cx, cy, half_size::Int)
    inner = _patch_for_test(img, cx, cy, half_size)
    outer_half_size = max(half_size + 1, min(2 * half_size + 1, fld(min(size(img)...) - 1, 2)))
    outer = _patch_for_test(img, cx, cy, outer_half_size)
    inner_h, inner_w = size(inner)
    outer_h, outer_w = size(outer)
    row_offset = fld(outer_h - inner_h, 2)
    col_offset = fld(outer_w - inner_w, 2)
    ring_mask = trues(size(outer))
    ring_mask[row_offset + 1:row_offset + inner_h, col_offset + 1:col_offset + inner_w] .= false
    return mean(inner) - mean(outer[ring_mask])
end

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

@testset "Region From Image" begin
    img_intensity = region_test_image(INTENSITY)
    img_binary = region_test_image(BINARY)
    img_segment = region_test_image(SEGMENT)
    fn_bundle = bundle_number_regionFromImg

    base = Float64.(reinterpret(img_intensity.img))
    center_patch = _patch_for_test(base, 0.5, 0.5, 1)
    outer_patch = _patch_for_test(base, 0.5, 0.5, 2)
    ring_mask = trues(size(outer_patch))
    ring_mask[2:4, 2:4] .= false
    ring_vals = outer_patch[ring_mask]

    @testset "Region Mean" begin
        fn = fn_bundle[:region_mean].fn
        @test fn(img_intensity, 0.5, 0.5) ≈ mean(center_patch)
        @test fn(img_binary, 0.5, 0.5) ≈ mean(Float64.(reinterpret(img_binary.img)[2:4, 2:4]))
        @test fn(img_segment, 0.5, 0.5) ≈ mean(Float64.(reinterpret(img_segment.img)[2:4, 2:4]))
    end

    @testset "Region Std" begin
        fn = fn_bundle[:region_std].fn
        @test fn(img_intensity, 0.5, 0.5) ≈ std(center_patch)
        @test fn(img_intensity, 0.0, 0.0) ≈ std(_patch_for_test(base, 0.0, 0.0, 1))
    end

    @testset "Region Min" begin
        fn = fn_bundle[:region_min].fn
        @test fn(img_intensity, 0.5, 0.5) ≈ minimum(center_patch)
        @test fn(img_binary, 0.5, 0.5) == 0.0
    end

    @testset "Region Max" begin
        fn = fn_bundle[:region_max].fn
        @test fn(img_intensity, 0.5, 0.5) ≈ maximum(center_patch)
        @test fn(img_segment, 0.5, 0.5) ≈ maximum(Float64.(reinterpret(img_segment.img)[2:4, 2:4]))
    end

    @testset "Region Sum" begin
        fn = fn_bundle[:region_sum].fn
        @test fn(img_intensity, 0.5, 0.5) ≈ sum(center_patch)
        @test fn(img_binary, 0.5, 0.5) ≈ sum(Float64.(reinterpret(img_binary.img)[2:4, 2:4]))
    end

    @testset "Region Median" begin
        fn = fn_bundle[:region_median].fn
        @test fn(img_intensity, 0.5, 0.5) ≈ median(center_patch)
        @test fn(img_segment, 0.5, 0.5) ≈ median(Float64.(reinterpret(img_segment.img)[2:4, 2:4]))
    end

    @testset "Region Range" begin
        fn = fn_bundle[:region_range].fn
        @test fn(img_intensity, 0.5, 0.5) ≈ maximum(center_patch) - minimum(center_patch)
        @test fn(img_binary, 0.5, 0.5) == 1.0
    end

    @testset "Region Contrast" begin
        fn = fn_bundle[:region_contrast].fn
        @test fn(img_intensity, 0.5, 0.5) ≈ mean(center_patch) - mean(ring_vals)
        @test fn(img_intensity, 0.0, 0.0) isa Float64
    end

    @testset "Region Energy" begin
        fn = fn_bundle[:region_energy].fn
        @test fn(img_intensity, 0.5, 0.5) ≈ mean(abs2, center_patch)
        @test fn(img_binary, 0.5, 0.5) ≈ mean(abs2, Float64.(reinterpret(img_binary.img)[2:4, 2:4]))
    end

    @testset "Region Entropy" begin
        fn = fn_bundle[:region_entropy].fn
        @test fn(img_intensity, 0.5, 0.5) ≈ _region_entropy_expected(base, 0.5, 0.5)
        @test fn(img_intensity, 0.0, 0.0) ≈ _region_entropy_expected(base, 0.0, 0.0)
    end

    @testset "Region Percent Variants" begin
        percentages = Dict(
            :region_mean_5p => 0.05,
            :region_mean_10p => 0.10,
            :region_mean_20p => 0.20,
            :region_std_5p => 0.05,
            :region_std_10p => 0.10,
            :region_std_20p => 0.20,
            :region_min_5p => 0.05,
            :region_min_10p => 0.10,
            :region_min_20p => 0.20,
            :region_max_5p => 0.05,
            :region_max_10p => 0.10,
            :region_max_20p => 0.20,
            :region_sum_5p => 0.05,
            :region_sum_10p => 0.10,
            :region_sum_20p => 0.20,
            :region_median_5p => 0.05,
            :region_median_10p => 0.10,
            :region_median_20p => 0.20,
            :region_range_5p => 0.05,
            :region_range_10p => 0.10,
            :region_range_20p => 0.20,
            :region_contrast_5p => 0.05,
            :region_contrast_10p => 0.10,
            :region_contrast_20p => 0.20,
            :region_energy_5p => 0.05,
            :region_energy_10p => 0.10,
            :region_energy_20p => 0.20,
            :region_entropy_5p => 0.05,
            :region_entropy_10p => 0.10,
            :region_entropy_20p => 0.20,
        )

        for (name, pct) in percentages
            fn = fn_bundle[name].fn
            half_size = _region_half_size_percent_for_test(base, pct)
            patch = _patch_for_test(base, 0.5, 0.5, half_size)
            if occursin("mean", String(name))
                @test fn(img_intensity, 0.5, 0.5) ≈ mean(patch)
            elseif occursin("std", String(name))
                expected = std(patch)
                actual = fn(img_intensity, 0.5, 0.5)
                @test (isnan(expected) && isnan(actual)) || actual ≈ expected
            elseif occursin("min", String(name))
                @test fn(img_intensity, 0.5, 0.5) ≈ minimum(patch)
            elseif occursin("max", String(name))
                @test fn(img_intensity, 0.5, 0.5) ≈ maximum(patch)
            elseif occursin("sum", String(name))
                @test fn(img_intensity, 0.5, 0.5) ≈ sum(patch)
            elseif occursin("median", String(name))
                @test fn(img_intensity, 0.5, 0.5) ≈ median(patch)
            elseif occursin("range", String(name))
                @test fn(img_intensity, 0.5, 0.5) ≈ maximum(patch) - minimum(patch)
            elseif occursin("contrast", String(name))
                @test fn(img_intensity, 0.5, 0.5) ≈ _region_contrast_expected(base, 0.5, 0.5, half_size)
            elseif occursin("energy", String(name))
                @test fn(img_intensity, 0.5, 0.5) ≈ mean(abs2, patch)
            elseif occursin("entropy", String(name))
                @test fn(img_intensity, 0.5, 0.5) ≈ _region_entropy_expected(base, 0.5, 0.5)
            end
        end
    end
end
