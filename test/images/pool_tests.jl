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

# Spec:
# The intensity pooling factory should preserve the image type and image size.
# The default method must match the explicit k=2 method, another k must also be checked.
# Numeric non-integer k must be accepted and converted internally.
@testset "Image Pool : avgpool_resize intensity" begin
    img = _dummy_intensity_pool_img()
    fn = bundle_image2DIntensity_pool_factory[:avgpool_resize]
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
@testset "Image Pool : avgpool_resize binary" begin
    img = _dummy_binary_pool_img()
    fn = bundle_image2DBinary_pool_factory[:avgpool_resize]
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
@testset "Image Pool : maxpool_resize intensity" begin
    img = _dummy_intensity_pool_img()
    fn = bundle_image2DIntensity_pool_factory[:maxpool_resize]
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
@testset "Image Pool : maxpool_resize binary" begin
    img = _dummy_binary_pool_img()
    fn = bundle_image2DBinary_pool_factory[:maxpool_resize]
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
@testset "Image Pool : maxpool_resize segment" begin
    img = _dummy_segment_pool_img()
    fn = bundle_image2DSegment_pool_factory[:maxpool_resize]
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
