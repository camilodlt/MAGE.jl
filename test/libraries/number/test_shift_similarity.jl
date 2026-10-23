using Test, MAGE, ImageCore

@testset "Shift correlation: smooth profiles and translations" begin
    S = MAGE.number_similarityFromImg
    image(x) = SImageND(IntensityPixel{N0f8}.(x))
    n = 224
    # Translation with zeros outside the image, rather than circular wrapping.
    function translated(p, shift)
        [1 <= i - shift <= length(p) ? p[i - shift] : 0.0 for i in eachindex(p)]
    end
    for sigma in (10.0, 20.0), shift in (-112, -5, -1, 0, 1, 5, 112)
        p = Float64.(N0f8.(exp.(-0.5 .* (((1:n) .- 112.5) ./ sigma).^2)))
        q = translated(p, shift)
        horizontal_a = image(repeat(reshape(p, 1, n), 8, 1))
        horizontal_b = image(repeat(reshape(q, 1, n), 8, 1))
        vertical_a = image(repeat(reshape(p, n, 1), 1, 8))
        vertical_b = image(repeat(reshape(q, n, 1), 1, 8))
        @test (@inferred S.sim_shift_x(horizontal_a, horizontal_b)) == shift / n
        @test (@inferred S.sim_shift_y(vertical_a, vertical_b)) == shift / n
        @test S.sim_shift_y(horizontal_a, horizontal_b) === 0.0
        @test S.sim_shift_x(vertical_a, vertical_b) === 0.0
        @test S.sim_shift_x(horizontal_b, horizontal_a) == -shift / n
        @test S.sim_shift_y(vertical_b, vertical_a) == -shift / n
    end
    for shift in (-16, -5, 0, 5, 16)
        p = zeros(32)
        p[13:18] .= [0.2, 0.6, 1.0, 0.8, 0.4, 0.1]
        q = translated(p, shift)
        @test S._best_lag(p, q) == shift
    end
    p = [0.0, 0.2, 0.8, 0.5, 0.1, 0.0, 0.0, 0.0]
    @test S._best_lag(p, 2 .* p .+ 10) == 0
    @test S._best_lag(Float64[], Float64[]) == 0
    @test S._best_lag([1.0], [2.0]) == 0
    @test S._best_lag(zeros(16), ones(16)) == 0
    @test S._best_lag(zeros(16), collect(1.0:16.0)) == 0
    @test S._best_lag(collect(1.0:16.0), zeros(16)) == 0
    @test S._best_lag([1.0, 0.0, 1.0], [0.0, 1.0, 0.0]) == -1
    # Different offsets/brightness scales do not affect overlap correlation.
    @test S._best_lag(p, 3 .* translated(p, 1) .+ 5) == 1
end
