using UTCGP

function _dummy_intensity_pool_img()
    img = [
        0.0 0.2 0.8 1.0
        0.4 0.6 0.2 0.4
        0.9 0.7 0.1 0.3
        0.5 0.3 0.9 0.7
    ]
    return SImageND(IntensityPixel{Float64}.(img))
end

function _dummy_binary_pool_img()
    img = Bool[
        1 1 0 0
        1 0 0 0
        0 0 1 1
        0 0 1 0
    ]
    return SImageND(BinaryPixel{Bool}.(img))
end

function _dummy_segment_pool_img()
    img = [
        1 2 4 3
        0 3 1 2
        5 4 2 0
        2 1 6 7
    ]
    return SImageND(SegmentPixel{Int}.(img))
end

function _dummy_cross_pool_intensity_img()
    img = [
        1.0 9.0 1.0  2.0 8.0 2.0
        9.0 9.0 9.0  8.0 8.0 8.0
        1.0 9.0 1.0  2.0 8.0 2.0
        3.0 7.0 3.0  4.0 6.0 4.0
        7.0 7.0 7.0  6.0 6.0 6.0
        3.0 7.0 3.0  4.0 6.0 4.0
    ]
    return SImageND(IntensityPixel{Float64}.(img))
end

function _dummy_cross_pool_mixed_intensity_img()
    img = [
        0.0 1.0 0.0  0.0 6.0 0.0
        2.0 3.0 4.0  7.0 8.0 9.0
        0.0 5.0 0.0  0.0 1.0 0.0
        0.0 2.0 0.0  0.0 9.0 0.0
        3.0 4.0 5.0  8.0 7.0 6.0
        0.0 6.0 0.0  0.0 5.0 0.0
    ]
    return SImageND(IntensityPixel{Float64}.(img))
end

function _expected_avgpool_k2_intensity()
    expected = [
        0.3 0.3 0.6 0.6
        0.3 0.3 0.6 0.6
        0.6 0.6 0.5 0.5
        0.6 0.6 0.5 0.5
    ]
    return SImageND(IntensityPixel{Float64}.(expected))
end

function _expected_avgpool_k4_intensity()
    expected = fill(0.5, 4, 4)
    return SImageND(IntensityPixel{Float64}.(expected))
end

function _expected_avgpool_k2_binary()
    expected = Bool[
        1 1 0 0
        1 1 0 0
        0 0 1 1
        0 0 1 1
    ]
    return SImageND(BinaryPixel{Bool}.(expected))
end

function _expected_avgpool_k4_binary()
    expected = fill(false, 4, 4)
    return SImageND(BinaryPixel{Bool}.(expected))
end

function _expected_maxpool_k2_intensity()
    expected = [
        0.6 0.6 1.0 1.0
        0.6 0.6 1.0 1.0
        0.9 0.9 0.9 0.9
        0.9 0.9 0.9 0.9
    ]
    return SImageND(IntensityPixel{Float64}.(expected))
end

function _expected_maxpool_k4_intensity()
    expected = fill(1.0, 4, 4)
    return SImageND(IntensityPixel{Float64}.(expected))
end

function _expected_maxpool_k2_binary()
    expected = Bool[
        1 1 0 0
        1 1 0 0
        0 0 1 1
        0 0 1 1
    ]
    return SImageND(BinaryPixel{Bool}.(expected))
end

function _expected_maxpool_k4_binary()
    expected = fill(true, 4, 4)
    return SImageND(BinaryPixel{Bool}.(expected))
end

function _expected_maxpool_k2_segment()
    expected = [
        3 3 4 4
        3 3 4 4
        5 5 7 7
        5 5 7 7
    ]
    return SImageND(SegmentPixel{Int}.(expected))
end

function _expected_maxpool_k4_segment()
    expected = fill(7, 4, 4)
    return SImageND(SegmentPixel{Int}.(expected))
end

function _expected_minpool_k2_intensity()
    expected = [
        0.0 0.0 0.2 0.2
        0.0 0.0 0.2 0.2
        0.3 0.3 0.1 0.1
        0.3 0.3 0.1 0.1
    ]
    return SImageND(IntensityPixel{Float64}.(expected))
end

function _expected_minpool_k4_intensity()
    expected = fill(0.0, 4, 4)
    return SImageND(IntensityPixel{Float64}.(expected))
end

function _expected_minpool_k2_binary()
    expected = Bool[
        0 0 0 0
        0 0 0 0
        0 0 0 0
        0 0 0 0
    ]
    return SImageND(BinaryPixel{Bool}.(expected))
end

function _expected_minpool_k4_binary()
    expected = fill(false, 4, 4)
    return SImageND(BinaryPixel{Bool}.(expected))
end

function _expected_minpool_k2_segment()
    expected = [
        0 0 1 1
        0 0 1 1
        1 1 0 0
        1 1 0 0
    ]
    return SImageND(SegmentPixel{Int}.(expected))
end

function _expected_minpool_k4_segment()
    expected = fill(0, 4, 4)
    return SImageND(SegmentPixel{Int}.(expected))
end

function _expected_avgpool_cross_k3_intensity()
    expected = [
        9.0 9.0 9.0  8.0 8.0 8.0
        9.0 9.0 9.0  8.0 8.0 8.0
        9.0 9.0 9.0  8.0 8.0 8.0
        7.0 7.0 7.0  6.0 6.0 6.0
        7.0 7.0 7.0  6.0 6.0 6.0
        7.0 7.0 7.0  6.0 6.0 6.0
    ]
    return SImageND(IntensityPixel{Float64}.(expected))
end

function _expected_avgpool_cross_k3_mixed_intensity()
    expected = [
        3.0 3.0 3.0   6.2 6.2 6.2
        3.0 3.0 3.0   6.2 6.2 6.2
        3.0 3.0 3.0   6.2 6.2 6.2
        4.0 4.0 4.0   7.0 7.0 7.0
        4.0 4.0 4.0   7.0 7.0 7.0
        4.0 4.0 4.0   7.0 7.0 7.0
    ]
    return SImageND(IntensityPixel{Float64}.(expected))
end

function _expected_maxpool_cross_k3_mixed_intensity()
    expected = [
        5.0 5.0 5.0   9.0 9.0 9.0
        5.0 5.0 5.0   9.0 9.0 9.0
        5.0 5.0 5.0   9.0 9.0 9.0
        6.0 6.0 6.0   9.0 9.0 9.0
        6.0 6.0 6.0   9.0 9.0 9.0
        6.0 6.0 6.0   9.0 9.0 9.0
    ]
    return SImageND(IntensityPixel{Float64}.(expected))
end

function _expected_minpool_cross_k3_mixed_intensity()
    expected = [
        1.0 1.0 1.0   1.0 1.0 1.0
        1.0 1.0 1.0   1.0 1.0 1.0
        1.0 1.0 1.0   1.0 1.0 1.0
        2.0 2.0 2.0   5.0 5.0 5.0
        2.0 2.0 2.0   5.0 5.0 5.0
        2.0 2.0 2.0   5.0 5.0 5.0
    ]
    return SImageND(IntensityPixel{Float64}.(expected))
end

# Spec:
# The intensity pooling factory should preserve the image type and image size.
# The default method must match the explicit k=2 method, another k must also be checked.
# Numeric non-integer k must be accepted and converted internally.
@testset "Image Pool : avgpool_blocks intensity" begin
    img = _dummy_intensity_pool_img()
    fn = bundle_image2DIntensity_pool_factory[:avgpool_blocks]
    fn = fn.fn(typeof(img))

    res_default = fn(img)
    res_k2 = fn(img, 2)
    res_k4 = fn(img, 4)
    expected_k2 = _expected_avgpool_k2_intensity()
    expected_k4 = _expected_avgpool_k4_intensity()

    @test eltype(res_default) == IntensityPixel{Float64}
    @test size(res_default) == size(img)
    @test res_default == res_k2
    @test all(isapprox.(float.(res_k2), float.(expected_k2); atol = 1.0e-12))
    @test all(isapprox.(float.(res_k4), float.(expected_k4); atol = 1.0e-12))
    @test all(isapprox.(float.(fn(img, 2.2)), float.(expected_k2); atol = 1.0e-12))
end

# Spec:
# The binary pooling factory should preserve the image type and image size.
# The default method must match the explicit k=2 method, another k must also be checked.
# Numeric non-integer k must be accepted and converted internally with binary casting preserved.
@testset "Image Pool : avgpool_blocks binary" begin
    img = _dummy_binary_pool_img()
    fn = bundle_image2DBinary_pool_factory[:avgpool_blocks]
    fn = fn.fn(typeof(img))

    res_default = fn(img)
    res_k2 = fn(img, 2)
    res_k4 = fn(img, 4)
    expected_k2 = _expected_avgpool_k2_binary()
    expected_k4 = _expected_avgpool_k4_binary()

    @test eltype(res_default) == BinaryPixel{Bool}
    @test size(res_default) == size(img)
    @test res_default == res_k2
    @test res_k2 == expected_k2
    @test res_k4 == expected_k4
    @test fn(img, 2.2) == expected_k2
end

# Spec:
# The intensity max-pooling factory should preserve the image type and image size.
# The default method must match the explicit k=2 method, and larger windows should keep the same size.
# Numeric non-integer k must be accepted and converted internally.
@testset "Image Pool : maxpool_blocks intensity" begin
    img = _dummy_intensity_pool_img()
    fn = bundle_image2DIntensity_pool_factory[:maxpool_blocks]
    fn = fn.fn(typeof(img))

    res_default = fn(img)
    res_k2 = fn(img, 2)
    res_k4 = fn(img, 4)
    expected_k2 = _expected_maxpool_k2_intensity()
    expected_k4 = _expected_maxpool_k4_intensity()

    @test eltype(res_default) == IntensityPixel{Float64}
    @test size(res_default) == size(img)
    @test res_default == res_k2
    @test all(isapprox.(float.(res_k2), float.(expected_k2); atol = 1.0e-12))
    @test all(isapprox.(float.(res_k4), float.(expected_k4); atol = 1.0e-12))
    @test all(isapprox.(float.(fn(img, 2.2)), float.(expected_k2); atol = 1.0e-12))
end

# Spec:
# The binary max-pooling factory should preserve the image type and image size.
# The default method must match the explicit k=2 method, and larger windows should keep the same size.
# Numeric non-integer k must be accepted and converted internally with binary casting preserved.
@testset "Image Pool : maxpool_blocks binary" begin
    img = _dummy_binary_pool_img()
    fn = bundle_image2DBinary_pool_factory[:maxpool_blocks]
    fn = fn.fn(typeof(img))

    res_default = fn(img)
    res_k2 = fn(img, 2)
    res_k4 = fn(img, 4)
    expected_k2 = _expected_maxpool_k2_binary()
    expected_k4 = _expected_maxpool_k4_binary()

    @test eltype(res_default) == BinaryPixel{Bool}
    @test size(res_default) == size(img)
    @test res_default == res_k2
    @test res_k2 == expected_k2
    @test res_k4 == expected_k4
    @test fn(img, 2.2) == expected_k2
end

# Spec:
# The segmented max-pooling factory should preserve the image type and image size.
# The default method must match the explicit k=2 method, and larger windows should keep the same size.
# Numeric non-integer k must be accepted and converted internally while preserving segmented output.
@testset "Image Pool : maxpool_blocks segment" begin
    img = _dummy_segment_pool_img()
    fn = bundle_image2DSegment_pool_factory[:maxpool_blocks]
    fn = fn.fn(typeof(img))

    res_default = fn(img)
    res_k2 = fn(img, 2)
    res_k4 = fn(img, 4)
    expected_k2 = _expected_maxpool_k2_segment()
    expected_k4 = _expected_maxpool_k4_segment()

    @test eltype(res_default) == SegmentPixel{Int}
    @test size(res_default) == size(img)
    @test res_default == res_k2
    @test res_k2 == expected_k2
    @test res_k4 == expected_k4
    @test fn(img, 2.2) == expected_k2
end

# Spec:
# The intensity min-pooling factory should preserve the image type and image size.
# The default method must match the explicit k=2 method, and larger windows should keep the same size.
# Numeric non-integer k must be accepted and converted internally.
@testset "Image Pool : minpool_blocks intensity" begin
    img = _dummy_intensity_pool_img()
    fn = bundle_image2DIntensity_pool_factory[:minpool_blocks]
    fn = fn.fn(typeof(img))

    res_default = fn(img)
    res_k2 = fn(img, 2)
    res_k4 = fn(img, 4)
    expected_k2 = _expected_minpool_k2_intensity()
    expected_k4 = _expected_minpool_k4_intensity()

    @test eltype(res_default) == IntensityPixel{Float64}
    @test size(res_default) == size(img)
    @test res_default == res_k2
    @test all(isapprox.(float.(res_k2), float.(expected_k2); atol = 1.0e-12))
    @test all(isapprox.(float.(res_k4), float.(expected_k4); atol = 1.0e-12))
    @test all(isapprox.(float.(fn(img, 2.2)), float.(expected_k2); atol = 1.0e-12))
end

# Spec:
# The binary min-pooling factory should preserve the image type and image size.
# The default method must match the explicit k=2 method, and larger windows should keep the same size.
# Numeric non-integer k must be accepted and converted internally with binary casting preserved.
@testset "Image Pool : minpool_blocks binary" begin
    img = _dummy_binary_pool_img()
    fn = bundle_image2DBinary_pool_factory[:minpool_blocks]
    fn = fn.fn(typeof(img))

    res_default = fn(img)
    res_k2 = fn(img, 2)
    res_k4 = fn(img, 4)
    expected_k2 = _expected_minpool_k2_binary()
    expected_k4 = _expected_minpool_k4_binary()

    @test eltype(res_default) == BinaryPixel{Bool}
    @test size(res_default) == size(img)
    @test res_default == res_k2
    @test res_k2 == expected_k2
    @test res_k4 == expected_k4
    @test fn(img, 2.2) == expected_k2
end

# Spec:
# The segmented min-pooling factory should preserve the image type and image size.
# The default method must match the explicit k=2 method, and larger windows should keep the same size.
# Numeric non-integer k must be accepted and converted internally while preserving segmented output.
@testset "Image Pool : minpool_blocks segment" begin
    img = _dummy_segment_pool_img()
    fn = bundle_image2DSegment_pool_factory[:minpool_blocks]
    fn = fn.fn(typeof(img))

    res_default = fn(img)
    res_k2 = fn(img, 2)
    res_k4 = fn(img, 4)
    expected_k2 = _expected_minpool_k2_segment()
    expected_k4 = _expected_minpool_k4_segment()

    @test eltype(res_default) == SegmentPixel{Int}
    @test size(res_default) == size(img)
    @test res_default == res_k2
    @test res_k2 == expected_k2
    @test res_k4 == expected_k4
    @test fn(img, 2.2) == expected_k2
end

# Spec:
# Cross-shaped average pooling should use only the center row and center column inside each block.
# The returned image must keep the original type and size while producing a result different from plain avg pooling.
# A structured 6x6 test image makes the cross effect exact and easy to verify for k=3.
@testset "Image Pool : avgpool_cross_blocks intensity" begin
    img = _dummy_cross_pool_intensity_img()
    fn = bundle_image2DIntensity_pool_factory[:avgpool_cross_blocks]
    fn = fn.fn(typeof(img))
    plain_fn = bundle_image2DIntensity_pool_factory[:avgpool_blocks].fn(typeof(img))

    res_default = fn(img)
    res_k3 = fn(img, 3)
    expected_k3 = _expected_avgpool_cross_k3_intensity()

    @test eltype(res_default) == IntensityPixel{Float64}
    @test size(res_default) == size(img)
    @test res_default != res_k3
    @test all(isapprox.(float.(res_k3), float.(expected_k3); atol = 1.0e-12))
    @test res_k3 != plain_fn(img, 3)
    @test all(isapprox.(float.(fn(img, 3.2)), float.(expected_k3); atol = 1.0e-12))
end

# Spec:
# Cross-shaped max pooling should only consider the center row and center column inside each block.
# A mixed 6x6 image is used so avg, max, and min cross pooling produce different exact values for k=3.
# The returned image must keep the original intensity type and original size.
@testset "Image Pool : maxpool_cross_blocks intensity" begin
    img = _dummy_cross_pool_mixed_intensity_img()
    fn = bundle_image2DIntensity_pool_factory[:maxpool_cross_blocks]
    fn = fn.fn(typeof(img))
    avg_fn = bundle_image2DIntensity_pool_factory[:avgpool_cross_blocks].fn(typeof(img))
    min_fn = bundle_image2DIntensity_pool_factory[:minpool_cross_blocks].fn(typeof(img))

    res_default = fn(img)
    res_k3 = fn(img, 3)
    expected_k3 = _expected_maxpool_cross_k3_mixed_intensity()

    @test eltype(res_default) == IntensityPixel{Float64}
    @test size(res_default) == size(img)
    @test res_default != res_k3
    @test all(isapprox.(float.(res_k3), float.(expected_k3); atol = 1.0e-12))
    @test res_k3 != avg_fn(img, 3)
    @test res_k3 != min_fn(img, 3)
    @test all(isapprox.(float.(fn(img, 3.2)), float.(expected_k3); atol = 1.0e-12))
end

# Spec:
# Cross-shaped min pooling should only consider the center row and center column inside each block.
# A mixed 6x6 image is used so avg, max, and min cross pooling produce different exact values for k=3.
# The returned image must keep the original intensity type and original size.
@testset "Image Pool : minpool_cross_blocks intensity" begin
    img = _dummy_cross_pool_mixed_intensity_img()
    fn = bundle_image2DIntensity_pool_factory[:minpool_cross_blocks]
    fn = fn.fn(typeof(img))
    avg_fn = bundle_image2DIntensity_pool_factory[:avgpool_cross_blocks].fn(typeof(img))
    max_fn = bundle_image2DIntensity_pool_factory[:maxpool_cross_blocks].fn(typeof(img))

    res_default = fn(img)
    res_k3 = fn(img, 3)
    expected_k3 = _expected_minpool_cross_k3_mixed_intensity()

    @test eltype(res_default) == IntensityPixel{Float64}
    @test size(res_default) == size(img)
    @test res_default != res_k3
    @test all(isapprox.(float.(res_k3), float.(expected_k3); atol = 1.0e-12))
    @test res_k3 != avg_fn(img, 3)
    @test res_k3 != max_fn(img, 3)
    @test all(isapprox.(float.(fn(img, 3.2)), float.(expected_k3); atol = 1.0e-12))
end
