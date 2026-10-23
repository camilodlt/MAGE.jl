using Test, MAGE, ImageCore, Statistics

@testset "Image correlation conventions and stability" begin
    correlation = MAGE.number_similarityFromImg.sim_correlation
    image(values, T=N0f8) = SImageND(IntensityPixel{T}.(values))
    for T in (N0f8, N0f16, Float32, Float64), side in (1, 32, 64, 224), value in (0.0, 0.1, 0.4, 0.5, 0.6, 1.0)
        a = image(fill(value, side, side), T)
        b = image(fill(value, side, side), T)
        different = image(fill(value == 0 ? 1.0 : 0.0, side, side), T)
        @test (@inferred correlation(a, b)) === 1.0
        @test (@inferred correlation(a, different)) === 0.0
    end
    for shape in ((8, 12), (8, 12, 3), (8, 12, 7)), T in (N0f8, N0f16, Float32, Float64)
        x = reshape([mod(i, 17) / 20 for i in 1:prod(shape)], shape)
        y = reverse(x)
        a, b = image(x, T), image(y, T)
        flat = image(fill(0.4, shape), T)
        @test (@inferred correlation(a, image(copy(x), T))) === 1.0
        @test correlation(flat, a) === 0.0
        @test correlation(a, flat) === 0.0
        @test (@inferred correlation(a, b)) ≈ cor(vec(Float64.(T.(x))), vec(Float64.(T.(y)))) atol=1e-12
    end
    a = image([0.4 0.4; 0.2 0.8])
    b = image([0.4 0.4; 0.7 0.1])
    mask(v) = SImageND(BinaryPixel.(v))
    @test (@inferred correlation(a, b, mask(Bool[1 1; 0 0]))) === 1.0
    @test correlation(a, b, mask(Bool[0 0; 1 0])) === 0.0
    @test correlation(a, b, mask(Bool[1 0; 0 0])) === 1.0
    @test correlation(a, b, mask(falses(2, 2))) === 0.0
    @test correlation(image(zeros(0, 0)), image(zeros(0, 0))) === 0.0
    for depth in (3, 7)
        volume = image(repeat(reshape([0.4, 0.2, 0.4, 0.8], 2, 2, 1), 1, 1, depth))
        plane = image([0.4 0.4; 0.2 0.8])
        @test (@inferred correlation(volume, plane)) === 1.0
        @test (@inferred correlation(volume, plane, mask(Bool[1 1; 0 0]))) === 1.0
        full_mask = mask(trues(2, 2, depth))
        @test (@inferred correlation(volume, plane, full_mask)) === 1.0
        @test correlation(volume, plane, mask(falses(2, 2, depth))) === 0.0
    end
    # Variance below the old absolute cutoff must still give Pearson's result.
    x = reshape([0.5 + i * 1e-9 for i in 1:12], 3, 4)
    @test correlation(image(x, Float64), image(1 .- x, Float64)) ≈ -1.0 atol=1e-12
    # A common offset should not destroy covariance through subtraction of squares.
    x = reshape([1e8 + i / 100 for i in 1:12], 3, 4)
    @test correlation(image(x, Float64), image(2 .* x .+ 1, Float64)) ≈ 1.0 atol=1e-12
end
