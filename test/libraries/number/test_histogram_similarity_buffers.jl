using Test, Random, MAGE
using ImageCore: N0f8, N0f16

# Keep the allocating pre-buffer formulas as an exact numerical reference.
function _hist_similarity_reference(pixels)
    counts = zeros(Int, 32)
    for pixel in pixels
        value = MAGE.image2D_object_common.pixel_value(pixel)
        bin = min(unsafe_trunc(Int, clamp(value, 0.0, 1.0) * 32), 31) + 1
        counts[bin] += 1
    end
    return counts ./ length(pixels)
end
_hist_similarity_expected(a, b) = (
    sum(min.(_hist_similarity_reference(a), _hist_similarity_reference(b))),
    clamp(sum(sqrt.(_hist_similarity_reference(a) .* _hist_similarity_reference(b))), 0.0, 1.0),
)
const _HIST_SIMILARITY_SINK = Ref(0.0)
function _hist_similarity_allocated(f::F, a::A, b::B) where {F,A,B}
    f(a, b)
    return @allocated (_HIST_SIMILARITY_SINK[] = f(a, b))
end

@testset "Task-local histogram similarity buffers" begin
    S = MAGE.number_similarityFromImg
    functions = (S.sim_hist_intersection, S.sim_hist_bhattacharyya)
    rng = MersenneTwister(20261022)
    @testset "Exact previous formulas across storage and layouts" begin
        for T in (N0f8, N0f16, Float32, Float64), dims in ((7, 11), (7, 11, 3), (7, 11, 5))
            a = IntensityPixel{T}.(rand(rng, dims...))
            # Histograms compare distributions even across different shapes.
            b = IntensityPixel{T}.(rand(rng, 9, 13))
            permutation = ndims(a) == 2 ? (2, 1) : (2, 1, 3)
            layouts = (a, view(a, ntuple(_ -> Colon(), ndims(a))...),
                PermutedDimsArray(permutedims(a, permutation), permutation))
            for layout in layouts
                expected = _hist_similarity_expected(layout, b)
                for (f, value) in zip(functions, expected)
                    @test isequal((@inferred f(SImageND(layout), SImageND(b))), value)
                end
            end
            @test S._histogram(a) == _hist_similarity_reference(a)
        end
    end
    @testset "Overwrite buffers and preserve boundaries and empty behavior" begin
        boundaries = vcat(0.0, 1.0, [k / 32 for k in 1:31],
            [prevfloat(k / 32) for k in 1:31], [nextfloat(k / 32) for k in 1:31], -0.1, 1.1)
        cases = (
            (IntensityPixel{Float64}.(reshape(boundaries, :, 1)), IntensityPixel{Float64}.(rand(rng, 13, 7))),
            (BinaryPixel.(trues(8, 9)), BinaryPixel.(falses(8, 9))),
            (IntensityPixel{N0f8}.(zeros(5, 7)), IntensityPixel{N0f8}.(zeros(9, 4))),
            (IntensityPixel{N0f8}.(ones(5, 7)), IntensityPixel{N0f8}.(zeros(9, 4))),
            (IntensityPixel{N0f8}.(zeros(0, 3)), IntensityPixel{N0f8}.(ones(5, 7))),
            (IntensityPixel{N0f8}.(zeros(0, 3)), IntensityPixel{N0f8}.(zeros(0, 3))),
        )
        for _ in 1:3, (a, b) in cases
            before_a, before_b = copy(a), copy(b)
            expected = _hist_similarity_expected(a, b)
            for (f, value) in zip(functions, expected)
                @test isequal((@inferred f(SImageND(a), SImageND(b))), value)
                @test isequal(f(SImageND(b), SImageND(a)), value)
            end
            @test a == before_a && b == before_b
        end
        # The allocating helper still returns an independently owned histogram.
        retained = S._histogram(cases[1][1])
        snapshot = copy(retained)
        S.sim_hist_intersection(SImageND(cases[2][1]), SImageND(cases[2][2]))
        @test retained == snapshot
    end
    @testset "Independent tasks and simultaneous live histograms" begin
        tasks = map(1:8) do k
            Threads.@spawn begin
                task_rng = MersenneTwister(k)
                a, b = IntensityPixel{N0f8}.(rand(task_rng, 17, 19)), IntensityPixel{N0f8}.(rand(task_rng, 11, 13))
                expected = _hist_similarity_expected(a, b)
                buffers = S._histogram_pair(a, b)
                snapshots = map(copy, buffers[1:2])
                yield()
                isolated = buffers[1] == snapshots[1] && buffers[2] == snapshots[2]
                correct = true
                for _ in 1:20
                    correct &= isequal(S.sim_hist_intersection(SImageND(a), SImageND(b)), expected[1])
                    yield()
                    correct &= isequal(S.sim_hist_bhattacharyya(SImageND(a), SImageND(b)), expected[2])
                end
                (buffers, isolated, correct)
            end
        end
        results = fetch.(tasks)
        @test all(r -> r[2] && r[3], results)
        @test all(r -> r[1][1] !== r[1][2] && r[1][1] !== r[1][3] && r[1][2] !== r[1][3], results)
        for i in 1:8, j in i+1:8, slot in 1:3
            @test results[i][1][slot] !== results[j][1][slot]
        end
    end
    @testset "No warmed temporary allocations" begin
        for T in (N0f8, N0f16, Float32, Float64), dims in ((8, 9), (224, 224, 3))
            a = SImageND(IntensityPixel{T}.(rand(rng, dims...)))
            b = SImageND(IntensityPixel{T}.(rand(rng, 11, 13)))
            for f in functions
                _hist_similarity_allocated(f, a, b) # warm helper as well as operator
                @test _hist_similarity_allocated(f, a, b) == 0
            end
        end
    end
end
