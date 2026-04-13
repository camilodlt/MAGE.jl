using UTCGP: IntensityPixel, BinaryPixel, SegmentPixel

function _dummy_pooler_intensity_img()
    img = Float64[
        1 2 3
        4 4 6
        7 8 9
    ]
    return SImageND(IntensityPixel{Float64}.(img))
end

function _dummy_pooler_binary_img()
    img = Bool[
        0 1 1
        1 0 1
        0 0 1
    ]
    return SImageND(BinaryPixel{Bool}.(img))
end

function _dummy_pooler_segment_img()
    img = Int[
        1 1 2
        2 3 3
        4 4 5
    ]
    return SImageND(SegmentPixel{Int}.(img))
end

function _pooler_windows()
    return [
        Float64[1 2; 4 4],
        Float64[2 3; 4 6],
        Float64[4 4; 7 8],
        Float64[4 6; 8 9],
    ]
end

function _resize_2x2_to_3x3(vals::AbstractMatrix)
    out = Matrix{Float64}(undef, 3, 3)
    row_map = (1, 2, 2)
    col_map = (1, 2, 2)
    for i in 1:3
        for j in 1:3
            out[i, j] = vals[row_map[i], col_map[j]]
        end
    end
    return out
end

function _expected_pooler_intensity(reducer::Function)
    wins = _pooler_windows()
    small = Float64[
        reducer(wins[1]) reducer(wins[2])
        reducer(wins[3]) reducer(wins[4])
    ]
    return SImageND(IntensityPixel{Float64}.(_resize_2x2_to_3x3(small)))
end

function _normalize_expected(img)
    vals = float.(img)
    minv = minimum(vals)
    maxv = maximum(vals)
    if maxv == minv
        return SImageND(IntensityPixel{Float64}.(zeros(size(vals))))
    end
    return SImageND(IntensityPixel{Float64}.((vals .- minv) ./ (maxv - minv)))
end

const _POOLER_INTENSITY_EXPECTED = Dict(
    :meanpool => _expected_pooler_intensity(mean),
    :maxpool => _expected_pooler_intensity(maximum),
    :minpool => _expected_pooler_intensity(minimum),
    :stdpool => _expected_pooler_intensity(std),
    :medianpool => _expected_pooler_intensity(median),
    :uniquecountpool => _normalize_expected(_expected_pooler_intensity(w -> length(unique(w)))),
    :argmaxcountpool => _normalize_expected(_expected_pooler_intensity(w -> count(==(maximum(w)), w))),
    :argmincountpool => _normalize_expected(_expected_pooler_intensity(w -> count(==(minimum(w)), w))),
    :iqrpool => _expected_pooler_intensity(w -> begin
        vals = Float64.(vec(collect(w)))
        quantile(vals, 0.75) - quantile(vals, 0.25)
    end),
)

const _POOLER_NAMES = (
    :meanpool,
    :maxpool,
    :minpool,
    :stdpool,
    :medianpool,
    :uniquecountpool,
    :argmaxcountpool,
    :argmincountpool,
    :iqrpool,
)

for name in _POOLER_NAMES
    @eval begin
        # Spec:
        # The $(string($name)) intensity pooler should apply a no-padding sliding-window reducer, then resize back to the original size.
        # The default call must match k=2, stride=1 and numeric inputs must be converted internally.
        # A 3x3 image gives an exact expected result after the 2x2 reduced map is resized back to 3x3.
        @testset $(string("Image Pooler : ", name, " intensity")) begin
            img = _dummy_pooler_intensity_img()
            fn = bundle_image2DIntensity_pooler_factory[$(QuoteNode(name))].fn(typeof(img))
            expected = _POOLER_INTENSITY_EXPECTED[$(QuoteNode(name))]

            res_default = fn(img)
            res_explicit = fn(img, 2, 1)
            res_numeric = fn(img, 2.2, 1.2)

            @test eltype(res_default) == IntensityPixel{Float64}
            @test size(res_default) == size(img)
            @test all(isapprox.(float.(res_default), float.(expected); atol = 1.0e-12))
            @test all(isapprox.(float.(res_explicit), float.(expected); atol = 1.0e-12))
            @test all(isapprox.(float.(res_numeric), float.(expected); atol = 1.0e-12))
        end
    end
end

# Spec:
# The binary sliding-window poolers should preserve the binary image type after resizing back to the original size.
# All poolers must accept explicit k and stride values and keep the original image size.
# The test checks type and size across the full binary pooler bundle.
@testset "Image Pooler : binary bundle typing" begin
    img = _dummy_pooler_binary_img()
    for name in _POOLER_NAMES
        fn = bundle_image2DBinary_pooler_factory[name].fn(typeof(img))
        res = fn(img, 2, 1)
        @test eltype(res) == BinaryPixel{Bool}
        @test size(res) == size(img)
    end
end

# Spec:
# The segmented sliding-window poolers should preserve the segmented image type after resizing back to the original size.
# All poolers must accept explicit k and stride values and keep the original image size.
# The test checks type and size across the full segmented pooler bundle.
@testset "Image Pooler : segment bundle typing" begin
    img = _dummy_pooler_segment_img()
    for name in _POOLER_NAMES
        fn = bundle_image2DSegment_pooler_factory[name].fn(typeof(img))
        res = fn(img, 2, 1)
        @test eltype(res) == SegmentPixel{Int}
        @test size(res) == size(img)
    end
end
