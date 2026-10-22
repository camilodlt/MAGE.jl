using Test, Random, Statistics, MAGE
using ImageCore: N0f8, N0f16

_streaming_inferred(f::F, args::A) where {F,A<:Tuple} = @inferred f(args...)
_streaming_reference(values) = isempty(values) ? 0.0 : mean(values)
const _STREAMING_MEAN_RESULT = Ref(0.0)

# A new task has no reusable scratch from earlier operators. Warm this helper
# before measuring so compilation and task creation are outside @allocated.
function _streaming_cold_allocations(f::F, args::A) where {F,A<:Tuple}
    return fetch(@async @allocated (_STREAMING_MEAN_RESULT[] = f(args...)))
end

@testset "Streaming image means" begin
    ST = MAGE.number_intensityStatsFromImg
    rng = MersenneTwister(20261022)

    @testset "Storage, layout and spatial/full ROI equivalence" begin
        @test length(bundle_number_intensityStatsFromImg) == 51
        for storage in (N0f8, N0f16, Float32, Float64), dims in ((5,7), (5,7,3), (5,7,4))
            pixels = IntensityPixel{storage}.(rand(rng, dims...))
            values = Float64.(pixels)
            permutation = ndims(pixels) == 2 ? (2,1) : (2,1,3)
            layouts = (pixels, view(pixels, ntuple(_ -> Colon(), ndims(pixels))...),
                PermutedDimsArray(permutedims(pixels, permutation), permutation))
            spatial = rand(rng, Bool, dims[1:2])
            bits = ndims(pixels) == 2 ? spatial : rand(rng, Bool, dims)
            regions = (
                SImageND(BinaryPixel.(spatial)),
                SImageND(IntensityPixel{Float32}.(ifelse.(spatial, 0.5f0, 0.49f0))),
                SImageND(BinaryPixel.(bits)),
                SImageND(IntensityPixel{Float64}.(Float64.(bits))),
                SImageND(BinaryPixel.(falses(dims[1:2]))),
                SImageND(BinaryPixel.(trues(dims[1:2]))),
            )
            for layout in layouts
                image = SImageND(layout)
                whole = _streaming_inferred(ST.stat_mean, (image,))
                @test whole ≈ mean(values)
                @test whole === ST._summary(layout, ST._All()).mean
                @test _streaming_inferred(ST.stat_mean, (image, 7.0, :unused)) === whole
                for roi in regions
                    selected = Float64.(roi.img) .>= 0.5
                    if ndims(pixels) == 3 && ndims(selected) == 2
                        selected = repeat(selected, 1, 1, dims[3])
                    end
                    expected_in = _streaming_reference(values[selected])
                    expected_out = _streaming_reference(values[.!selected])
                    inside = _streaming_inferred(ST.stat_mean, (image, roi))
                    outside = _streaming_inferred(ST.stat_mean_out, (image, roi))
                    difference = _streaming_inferred(ST.stat_mean_diff, (image, roi))
                    @test inside ≈ expected_in
                    @test outside ≈ expected_out
                    @test difference ≈ expected_in - expected_out atol=1e-14
                    # Compare bit-for-bit with the former summary-based mean.
                    mask, predicate = ST._roi(image, roi)
                    old_in = ST._summary(layout, ST._Inside(mask, predicate)).mean
                    old_out = ST._summary(layout, ST._Outside(mask, predicate)).mean
                    @test inside === old_in
                    @test outside === old_out
                    @test difference === old_in - old_out
                    @test _streaming_inferred(ST.stat_mean_diff, (image, roi, 7.0)) === difference
                end
            end
        end
    end

    @testset "Empty images and invalid ROI dispatch" begin
        for storage in (N0f8, N0f16, Float32, Float64), dims in ((0,7), (5,0,3))
            image = SImageND(Array{IntensityPixel{storage}}(undef, dims))
            roi = SImageND(BinaryPixel.(falses(dims[1:2])))
            @test _streaming_inferred(ST.stat_mean, (image,)) === 0.0
            for fn in (ST.stat_mean, ST.stat_mean_out, ST.stat_mean_diff)
                @test _streaming_inferred(fn, (image, roi)) === 0.0
            end
        end
        image = SImageND(IntensityPixel{Float64}.(zeros(2,3)))
        wrong = SImageND(BinaryPixel.(falses(3,2)))
        depth_roi = SImageND(BinaryPixel.(falses(2,3,3)))
        @test_throws DimensionMismatch ST.stat_mean(image, wrong)
        @test_throws DimensionMismatch ST.stat_mean(image, depth_roi)
        @test !hasmethod(ST.stat_mean_out, Tuple{typeof(image),typeof(wrong)})
        @test !hasmethod(ST.stat_mean_diff, Tuple{typeof(image),typeof(depth_roi)})
    end

    @testset "Separate sums and existing nonfinite behavior" begin
        image = SImageND(IntensityPixel{Float64}.(reshape([1e16,1.0,-1e16,3.0],2,2)))
        roi = SImageND(BinaryPixel.(reshape([true,false,true,false],2,2)))
        @test ST.stat_mean(image, roi) === 0.0
        @test ST.stat_mean_out(image, roi) === 2.0
        @test ST.stat_mean_diff(image, roi) === -2.0
        for value in (NaN, Inf, -Inf)
            pixels = IntensityPixel{Float64}.(reshape([value,0.2,0.4,0.6],2,2))
            image = SImageND(pixels)
            if isnan(value)
                @test_throws InexactError ST.stat_mean(image)
                @test_throws InexactError ST.stat_mean(image, roi)
                @test_throws InexactError ST.stat_mean_diff(image, roi)
            else
                @test ST.stat_mean(image) === value
                @test ST.stat_mean(image, roi) === value
                @test ST.stat_mean_diff(image, roi) === value
            end
            @test ST.stat_mean_out(image, roi) ≈ 0.4
        end
    end

    @testset "Fresh-task allocations do not grow with image size" begin
        @testset "$storage" for storage in (N0f8, N0f16, Float32, Float64)
            allocations = Int[]
            for side in (4,48)
                image = SImageND(IntensityPixel{storage}.(fill(0.3,side,side,side)))
                roi = SImageND(BinaryPixel.(falses(side,side)))
                for (fn,args) in ((ST.stat_mean,(image,)), (ST.stat_mean,(image,roi)),
                    (ST.stat_mean_out,(image,roi)), (ST.stat_mean_diff,(image,roi)))
                    _streaming_cold_allocations(fn,args)
                    push!(allocations, _streaming_cold_allocations(fn,args))
                end
            end
            for i in 1:4
                @test allocations[i+4] <= allocations[i] + 1024
            end
        end
    end
end
