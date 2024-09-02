@testset "Reduce Image" begin
    @test begin
        # bundle import
        using UTCGP: bundle_number_reduceFromImg
        length(bundle_number_reduceFromImg) == 12 &&
            _unique_names_in_bundle(bundle_number_reduceFromImg)
    end

    # Reduce length --- 
    @test begin
        fn = bundle_number_reduceFromImg[:reduce_length].fn
        fn(SImageND(ones(10, 10))) == 10 * 10
    end
    @test begin
        fn = bundle_number_reduceFromImg[:reduce_length].fn
        fn(SImageND(ones(2, 10))) == 20
    end

    # Reduce Biggest Axis --- 
    @test begin
        fn = bundle_number_reduceFromImg[:reduce_biggestAxis].fn
        fn(SImageND(ones(10, 10))) == 10
    end
    @test begin
        fn = bundle_number_reduceFromImg[:reduce_biggestAxis].fn
        fn(SImageND(ones(2, 10))) == 10
    end
    @test begin
        fn = bundle_number_reduceFromImg[:reduce_biggestAxis].fn
        fn(SImageND(ones(10, 11))) == 11
    end

    # Reduce Biggest Axis --- 
    @test begin
        fn = bundle_number_reduceFromImg[:reduce_smallerAxis].fn
        fn(SImageND(ones(10, 10, 10))) == 10
    end
    @test begin
        fn = bundle_number_reduceFromImg[:reduce_smallerAxis].fn
        fn(SImageND(ones(2, 10))) == 2
    end
    @test begin
        fn = bundle_number_reduceFromImg[:reduce_smallerAxis].fn
        fn(SImageND(ones(10, 11))) == 10
    end
end

@testset "Reduce Image HistMode" begin
    sample_img = [
        0.33 0.33 0.12
        0.12 0.10 0.11
        0.9 0.8 0.33
    ]
    sample_img_n0f8 = SImageND(N0f8.(sample_img))
    @test begin
        fn = bundle_number_reduceFromImg[:reduce_histMode].fn
        res = fn(sample_img_n0f8)
        res ≈ 0.329411764 && (res isa Float64) # bc N0f8 binned it
    end
    sample_img_n0f16 = SImageND(N0f16.(sample_img))
    @test begin
        fn = bundle_number_reduceFromImg[:reduce_histMode].fn
        res = fn(sample_img_n0f16)
        res ≈ 0.330006866559 && (res isa Float64) # bc N0f16 binned it
    end

end

@testset "Reduce Prop White" begin
    sample_img = [
        0.0 0.33 0.12
        0.12 0.10 0.11
        0.9 0.8 0.33
    ] # prop white is 1/9
    sample_img = SImageND(N0f8.(sample_img))
    @test begin
        fn = bundle_number_reduceFromImg[:reduce_propWhite].fn
        res = fn(sample_img)
        res ≈ (1 / 9) && (res isa Float64)
    end
    sample_img = [
        0.0 0.0 0.0
        0.12 0.10 0.11
        0.9 0.8 0.33
    ] # prop white is 1/9
    sample_img = SImageND(N0f8.(sample_img))
    @test begin
        fn = bundle_number_reduceFromImg[:reduce_propWhite].fn
        res = fn(sample_img)
        res ≈ (1 / 3) && (res isa Float64)
    end

end

@testset "Reduce Prop Black" begin
    sample_img = [
        1.0 0.33 0.12
        0.12 0.10 0.11
        0.9 0.8 0.33
    ] # prop black is 1/9
    sample_img = SImageND(N0f8.(sample_img))
    @test begin
        fn = bundle_number_reduceFromImg[:reduce_propBlack].fn
        res = fn(sample_img)
        res ≈ (1 / 9) && (res isa Float64)
    end
    sample_img = [
        1.0 1.0 1.0
        0.12 0.10 0.11
        0.9 0.8 0.33
    ] # prop black is 1/3
    sample_img = SImageND(N0f8.(sample_img))
    @test begin
        fn = bundle_number_reduceFromImg[:reduce_propBlack].fn
        res = fn(sample_img)
        res ≈ (1 / 3) && (res isa Float64)
    end

end

@testset "Reduce N Colors" begin
    sample_img = [
        1 1 1
        2 2 2
    ]
    to_normed = reinterpret(N0f8, UInt8.(sample_img))
    sample_img = SImageND(to_normed)
    @test begin
        fn = bundle_number_reduceFromImg[:reduce_nColors].fn
        res = fn(sample_img)
        res ≈ 2.0 && (res isa Float64)
    end
end

@testset "Reduce Mean" begin
    sample_img = [
        0 0 0
        255 255 255
    ]
    to_normed = reinterpret(N0f8, UInt8.(sample_img))
    sample_img = SImageND(to_normed)
    @test begin
        fn = bundle_number_reduceFromImg[:reduce_mean].fn
        res = fn(sample_img)
        res ≈ 0.5 && (res isa Float64)
    end
end

@testset "Reduce median" begin
    sample_img = [
        0.1 0.1 0.2
        0.3 0.3 0.9
    ]
    sample_img = SImageND(N0f8.(sample_img))
    @test begin
        fn = bundle_number_reduceFromImg[:reduce_median].fn
        res = fn(sample_img)
        res ≈ 0.249019607843 && (res isa Float64)
    end
end

@testset "Reduce std" begin
    sample_img = [
        0.1 0.1 0.2
        0.3 0.3 0.9
    ]
    sample_img = SImageND(N0f8.(sample_img))
    @test begin
        fn = bundle_number_reduceFromImg[:reduce_std].fn
        res = fn(sample_img)
        res ≈ 0.299690130027 && (res isa Float64)
    end
end

@testset "Reduce Maximum" begin
    sample_img = [
        0.1 0.1 0.2
        0.3 0.3 0.9
    ]
    sample_img = SImageND(N0f8.(sample_img))
    @test begin
        fn = bundle_number_reduceFromImg[:reduce_maximum].fn
        res = fn(sample_img)
        res ≈ 0.901960784 && (res isa Float64)
    end
end

@testset "Reduce minimum" begin
    sample_img = [
        0.1 0.1 0.2
        0.3 0.3 0.9
    ]
    sample_img = SImageND(N0f8.(sample_img))
    @test begin
        fn = bundle_number_reduceFromImg[:reduce_minimum].fn
        res = fn(sample_img)
        res ≈ 0.10196078431 && (res isa Float64)
    end
end
