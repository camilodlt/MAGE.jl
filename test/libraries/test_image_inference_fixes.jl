@testset "Image factory inference changes preserve effects" begin
    # Factories create methods at run time. Enter the latest world, then check
    # inference of the method itself (not invokelatest, whose result is Any).
    check(f,args) = Base.invokelatest(_scalar_inferred,f,args)
    for dims in ((8,10),(13,9)), pixel in (IntensityPixel{N0f8},IntensityPixel{N0f16})
        source = SImageND(pixel.(reshape(collect(range(0.1,0.9; length=prod(dims))),dims)))
        I = typeof(source)
        for name in (:ones_2D,:zeros_2D)
            factory = bundle_image2DIntensity_basic_factory[name].fn
            f = factory(I)
            output = check(f,(source,))
            @test typeof(output) === I
            @test size(output) == dims
            @test all(p -> Float64(p) == (name == :ones_2D ? 1.0 : 0.0), output.img)
        end
        # Each changed cast alias is a constant binding to the same function.
        for (mod,bundle) in ((UTCGP.image2D_arithmetic,bundle_image2DIntensity_arithmetic_factory),
                            (UTCGP.image2D_barithmetic,bundle_image2DIntensity_barithmetic_factory),
                            (UTCGP.image2D_transcendental,bundle_image2DIntensity_transcendental_factory),
                            (UTCGP.image2D_filtering,bundle_image2DIntensity_filtering_factory))
            @test isconst(mod,:cast)
            @test mod.cast === UTCGP.image2D_morph.cast
            for w in bundle
                f = w.fn(I)
                args = hasmethod(f,Tuple{I,I}) && !(mod === UTCGP.image2D_barithmetic) ?
                    (source,source) : (source,0.5,0.7)
                @test check(f,args) isa I
            end
        end
        for w in bundle_image2DIntensity_pooler_factory
            f = w.fn(I)
            for args in ((source,),(source,3),(source,3,2))
                output = check(f,args)
                @test typeof(output) === I
                @test size(output) == dims
                @test all(p -> 0 <= Float64(p) <= 1, output.img)
            end
        end
        for w in experimental_bundle_float_glcm_factory
            for args in ((source,),(source,8),(source,1,8))
                @test _scalar_inferred(w.fn,args) isa Float64
            end
        end
    end
end

@testset "GLCM quantisation is bounded and preserves co-occurrence counts" begin
    G = UTCGP.experimental_GLCM
    img = SImageND(IntensityPixel{Float64}.([0.0 0.5; 1.0 0.5]))
    expected = zeros(Int,4,4)
    expected[1,2] = expected[2,1] = expected[4,2] = expected[2,4] = 1
    @test G.prep_glcm(img,1,4,[0.0]).glcm[1] == expected
    for storage in (N0f8,N0f16,Float32,Float64)
        zero_img = SImageND(IntensityPixel{storage}.(zeros(2,2)))
        counts = G.prep_glcm(zero_img,1,4,[0.0]).glcm[1]
        @test counts[1,1] == sum(counts) == 4
        sample = SImageND(IntensityPixel{storage}.(reshape(collect(range(0.05,0.95;length=168)),12,14)))
        for bins in (1,5,16,255), distance in (1,3)
            matrices = G.prep_glcm(sample,distance,bins,[0.0,pi/2]).glcm
            @test all(m -> size(m) == (clamp(bins,5,255),clamp(bins,5,255)),matrices)
            @test all(m -> m == m' && sum(m) > 0,matrices)
        end
        f = first(experimental_bundle_float_glcm_factory).fn
        for param in (NaN,Inf,-Inf,1e30,-1e30)
            @test _scalar_inferred(f,(sample,param,param)) isa Float64
        end
    end
end

@testset "Binary outputs also infer after cast bindings become constant" begin
    source = SImageND(IntensityPixel{N0f8}.([0.1 + 0.8*(r+c)/20 for r in 1:8,c in 1:10]))
    mask = SImageND(BinaryPixel.([isodd(r+c) for r in 1:8,c in 1:10]))
    B = typeof(mask)
    check(f,args) = Base.invokelatest(_scalar_inferred,f,args)
    for mod in (UTCGP.image2D_arithmetic,UTCGP.image2D_binarize,UTCGP.image2D_filtering)
        @test isconst(mod,:cast)
        @test mod.cast === UTCGP.image2D_morph.cast
    end
    for w in bundle_image2DBinary_arithmetic_factory
        @test check(w.fn(B),(mask,mask)) isa B
    end
    for bundle in (bundle_image2DBinary_binarize_factory,bundle_image2DBinary_filtering_factory), w in bundle
        f = w.fn(B)
        @test check(f,(source,)) isa B
        @test check(f,(source,0.5,0.7)) isa B
    end
    for bundle in (bundle_image2DBinary_pooler_factory,bundle_image2DSegment_pooler_factory)
        input = bundle === bundle_image2DBinary_pooler_factory ? mask : SImageND(SegmentPixel{Int}.([isodd(r+c) ? 2 : 7 for r in 1:8,c in 1:10]))
        for w in bundle
            @test check(w.fn(typeof(input)),(input,3,2)) isa typeof(input)
        end
    end
end
