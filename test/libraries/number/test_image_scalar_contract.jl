# Contract checks call the actual registered function, without a library caster
# or a return annotation hiding a failure of inference in the operator itself.
using Random, Statistics
using ImageCore: N0f8, N0f16

_scalar_inferred(f::F, args::A) where {F,A<:Tuple} = @inferred f(args...)

@testset "Image-to-scalar dispatch and inference" begin
    ST = MAGE.number_intensityStatsFromImg
    SI = MAGE.number_similarityFromImg
    raw = reshape(collect(range(0.05, 0.95; length=120)), 4, 6, 5)
    roi_values = [isodd(r+c) for r in 1:4, c in 1:6]
    roi = SImageND(BinaryPixel.(roi_values))
    roi_intensity = SImageND(IntensityPixel{N0f8}.(Float64.(roi_values)))

    @testset "All 51 statistics: planar, RGB, volume; full and spatial ROIs" begin
        @test length(bundle_number_intensityStatsFromImg) == 51
        for storage in (N0f8, N0f16, Float32, Float64), depth in (1,3,5)
            array = IntensityPixel{storage}.(raw[:,:,1:depth])
            img = SImageND(array)
            spatial_bits = repeat(roi_values, 1, 1, depth)
            full_roi = SImageND(BinaryPixel.(spatial_bits))
            full_intensity_roi = SImageND(IntensityPixel{storage}.(Float64.(spatial_bits)))
            # Flatten the channels/slices into a 2D array as an independent
            # reference for which samples a spatial ROI includes/excludes.
            flattened = SImageND(reshape(copy(array), 4, :))
            flat_roi = SImageND(reshape(BinaryPixel.(spatial_bits), 4, :))
            for wrapper in bundle_number_intensityStatsFromImg
                f = wrapper.fn
                expected = _scalar_inferred(f, (flattened, flat_roi))
                @test expected isa Float64
                for region in (roi, roi_intensity, full_roi, full_intensity_roi)
                    @test _scalar_inferred(f, (img,region)) ≈ expected atol=1e-12
                end
                if !endswith(string(wrapper.name), "_out") && !endswith(string(wrapper.name), "_diff")
                    @test _scalar_inferred(f, (img,)) ≈ _scalar_inferred(f, (flattened,)) atol=1e-12
                end
                if startswith(string(wrapper.name), "stat_frac_above")
                    @test _scalar_inferred(f, (img,roi,0.7)) ≈ _scalar_inferred(f,(flattened,flat_roi,0.7))
                    @test _scalar_inferred(f, (img,roi,Float32(0.7))) isa Float64
                end
            end
            values = Float64.(array)
            @test _scalar_inferred(ST.stat_mean, (img,roi)) ≈ mean(values[spatial_bits])
            @test _scalar_inferred(ST.stat_std, (img,roi)) ≈ std(values[spatial_bits]; corrected=false)
            @test _scalar_inferred(ST.stat_q50, (img,roi)) ≈ median(values[spatial_bits])
            empty_roi = SImageND(BinaryPixel.(falses(4,6)))
            @test _scalar_inferred(ST.stat_mean,(img,empty_roi)) == 0.0
            @test _scalar_inferred(ST.stat_mean_diff,(img,empty_roi)) ≈ -mean(values)
            # A full-size intensity ROI remains supported, including RGB as its own ROI.
            selected = values[values .>= 0.5]
            @test _scalar_inferred(ST.stat_mean,(img,img)) ≈ (isempty(selected) ? 0.0 : mean(selected))
        end
        cartesian_values = PermutedDimsArray(permutedims(IntensityPixel{Float32}.(raw[:,:,1:3]),(2,1,3)),(2,1,3))
        cartesian_image = SImageND(cartesian_values)
        @test _scalar_inferred(ST.stat_mean,(cartesian_image,roi)) ≈ mean(Float64.(cartesian_values)[repeat(roi_values,1,1,3)])
        planar = SImageND(IntensityPixel{N0f8}.(raw[:,:,1]))
        bad_roi = SImageND(BinaryPixel.(falses(5,6)))
        rgb = SImageND(IntensityPixel{N0f8}.(raw[:,:,1:3]))
        @test !hasmethod(ST.stat_mean_out, Tuple{typeof(planar),typeof(bad_roi)})
        @test !hasmethod(ST.stat_mean_diff, Tuple{typeof(planar),typeof(rgb)})
        @test_throws DimensionMismatch ST.stat_mean(planar,bad_roi)
        @test_throws DimensionMismatch ST.stat_mean(planar,rgb)
        @test _scalar_inferred(ST.stat_mean, (planar,roi)) ≈ mean(Float64.(planar.img)[roi_values])
    end

    @testset "ND comparisons preserve the same operator and infer Float64" begin
        @test length(bundle_number_similarityNDFromImg) == 9
        @test length(bundle_number_similarity2DFromImg) == 4
        @test length(bundle_number_similarityFromImg) == 13
        for bundle in (bundle_number_similarityNDFromImg, bundle_number_similarity2DFromImg), wrapper in bundle
            @test wrapper.fn === bundle_number_similarityFromImg[wrapper.name].fn
        end
        for depth in (3,5), storage in (N0f8,N0f16,Float32,Float64)
            array = IntensityPixel{storage}.(raw[:,:,1:depth])
            a,b = SImageND(array), SImageND(reverse(array; dims=1))
            fa,fb = SImageND(reshape(copy(a.img),4,:)), SImageND(reshape(copy(b.img),4,:))
            full_roi = SImageND(BinaryPixel.(repeat(roi_values,1,1,depth)))
            flat_roi = SImageND(reshape(copy(full_roi.img),4,:))
            for w in bundle_number_similarityNDFromImg
                @test _scalar_inferred(w.fn,(a,b)) ≈ _scalar_inferred(w.fn,(fa,fb)) atol=1e-12
            end
            for f in (SI.sim_mse,SI.sim_mae,SI.sim_correlation)
                @test _scalar_inferred(f,(a,b,roi)) ≈ _scalar_inferred(f,(fa,fb,flat_roi)) atol=1e-12
                @test _scalar_inferred(f,(a,b,full_roi)) ≈ _scalar_inferred(f,(a,b,roi)) atol=1e-12
            end
            @test SI.sim_mse(a,b,roi) ≈ mean((Float64.(a.img)[repeat(roi_values,1,1,depth)] .- Float64.(b.img)[repeat(roi_values,1,1,depth)]).^2)
            for w in bundle_number_similarity2DFromImg
                @test !hasmethod(w.fn,Tuple{typeof(a),typeof(b)})
            end
        end
    end

    @testset "Mixed 2D/3D applications: every decoded call infers Float64 and runs" begin
        # Applications mix 2D planes with an RGB array (or a volume) of the same
        # height and width. A node connects to up to 3 inputs; MAGE's decoder
        # picks the method with `which` on all connection types and consumes only
        # its fixed arguments (`nargs - 2`). Every such decoded call must infer
        # exactly Float64 (no Union{}: no node that always throws) and run.
        # Nothing is skipped.
        rng = MersenneTwister(7)
        i2 = SImageND(IntensityPixel{N0f8}.(rand(rng,12,14)))
        b2 = SImageND(BinaryPixel.(rand(rng,Bool,12,14)))
        s2 = SImageND(SegmentPixel{Int}.(rand(rng,1:3,12,14)))
        rgb = SImageND(IntensityPixel{N0f8}.(rand(rng,12,14,3)))
        brgb = SImageND(BinaryPixel.(rand(rng,Bool,12,14,3)))
        i3 = SImageND(IntensityPixel{N0f8}.(rand(rng,12,14,5)))
        b3 = SImageND(BinaryPixel.(rand(rng,Bool,12,14,5)))
        bundles = (bundle_number_intensityStatsFromImg, bundle_number_similarityFromImg)
        for inputs in ((i2,b2,s2,rgb,brgb), (i2,b2,i3,b3)), bundle in bundles, w in bundle
            values = (inputs..., 0.4)
            for n in 1:3, connections in Iterators.product(ntuple(_ -> values, n)...)
                first(connections) isa SImageND || continue
                hasmethod(w.fn, typeof(connections)) || continue
                consumed = connections[1:(which(w.fn, typeof(connections)).nargs - 2)]
                rt = Core.Compiler.return_type(w.fn, typeof(consumed))
                @test rt === Float64 || (w.name, typeof.(consumed), rt)
                @test w.fn(consumed...) isa Float64
            end
        end
        # A 2D source facing a 3D image has no ROI method: the decoded node is
        # the one-input whole-image statistic.
        @test which(ST.stat_mean, typeof((i2, rgb))).nargs - 2 == 1
        @test !hasmethod(ST.stat_mean_diff, Tuple{typeof(i2),typeof(rgb)})
        # 3D vs 2D comparisons pool every channel against the 2D image, exactly
        # as against the 2D image stacked to the same depth.
        stacked = SImageND(cat(i2.img, i2.img, i2.img; dims=3))
        stacked_mask = SImageND(cat(b2.img, b2.img, b2.img; dims=3))
        for f in (SI.sim_mse, SI.sim_mae, SI.sim_correlation, SI.sim_iou, SI.sim_dice, SI.sim_coverage, SI.sim_hamming)
            @test _scalar_inferred(f,(rgb,i2)) ≈ _scalar_inferred(f,(rgb,stacked)) atol=1e-12
            @test _scalar_inferred(f,(i2,rgb)) ≈ _scalar_inferred(f,(stacked,rgb)) atol=1e-12
        end
        for f in (SI.sim_mse, SI.sim_mae, SI.sim_correlation)
            # 2D mask repeated through a 3D comparison, or a 3D mask of its size.
            @test _scalar_inferred(f,(rgb,i2,b2)) ≈ _scalar_inferred(f,(rgb,stacked,stacked_mask)) atol=1e-12
            @test _scalar_inferred(f,(rgb,i2,brgb)) ≈ _scalar_inferred(f,(rgb,stacked,brgb)) atol=1e-12
            # Masks are binary: an intensity image or a 3D mask for a 2D pair is
            # not a mask, so the decoded node is the unmasked pair.
            @test which(f, typeof((i2,i2,i2))).nargs - 2 == 2
            @test which(f, typeof((i2,i2,brgb))).nargs - 2 == 2
        end
        # Histograms are position-free: any two images, channels pooled.
        @test _scalar_inferred(SI.sim_hist_intersection,(rgb,i2)) ≈
              _scalar_inferred(SI.sim_hist_intersection,(SImageND(reshape(copy(rgb.img),12,:)),i2)) atol=1e-12
        @test _scalar_inferred(SI.sim_hist_intersection,(i2,i2)) ≈ 1.0
        # Planar operators stay 2D-only.
        for f in (SI.sim_ssim, SI.sim_chamfer, SI.sim_shift_x, SI.sim_shift_y)
            @test !hasmethod(f, Tuple{typeof(rgb),typeof(i2)})
            @test hasmethod(f, Tuple{typeof(i2),typeof(b2)})
        end
    end

    @testset "Every scalar bundle: valid methods infer real scalars" begin
        # Non-collinear, well-separated components give valid image graphs.
        i2 = SImageND(IntensityPixel{N0f8}.(rand(MersenneTwister(1),12,14)))
        b2 = SImageND(BinaryPixel.([r in (2,6,10) && c in (2,7,12) for r in 1:12,c in 1:14]))
        s2 = SImageND(SegmentPixel{Int}.(Int.(reinterpret(b2.img))))
        i3 = SImageND(IntensityPixel{N0f8}.(rand(MersenneTwister(2),12,14,5)))
        b3 = SImageND(BinaryPixel.(rand(MersenneTwister(3),Bool,12,14,5)))
        rgb = SImageND(IntensityPixel{N0f8}.(rand(MersenneTwister(4),12,14,3)))
        for (domain, images) in ((:image2D,(i2,b2,s2)),(:volume,(i3,b3)),(:rgb,(rgb,)))
            bundles = get_image_scalar_bundles([typeof.(images)...,Float64]; domain=domain,max_arity=3)
            @test !isempty(bundles)
            for bundle in bundles, w in bundle
                tested = false
                for image in images
                    pairs = domain === :image2D ? (image,b2) : domain === :volume ? (image,b3) : (image,)
                    # Test one valid tuple for every declared fixed-arity method.
                    for method in methods(w.fn)
                        options = ((image,), (image,0.4), (image,0.4,0.6),
                            (image,image), (image,image,0.4), (image,image,image),
                            ((image,p) for p in pairs)...)
                        for args in options
                            hasmethod(w.fn,typeof(args)) || continue
                            which(w.fn,typeof(args)) === method || continue
                            # SImageND encodes array sizes; skip tuples whose
                            # required full-size ROI is incompatible.
                            rt = Core.Compiler.return_type(w.fn,typeof(args))
                            rt === Union{} && continue
                            @test isconcretetype(rt) && rt <: Real
                            @test _scalar_inferred(w.fn,args) isa Real
                            tested = true
                            break
                        end
                    end
                end
                @test tested
            end
        end
        for w in bundle_float_imagegraph
            @test !hasmethod(w.fn,Tuple{typeof(i3)})
            @test !hasmethod(w.fn,Tuple{typeof(b3)})
        end
        for bundle in (bundle_number_coordinatesFromImg,bundle_number_relativeCoordinatesFromImg), w in bundle
            @test _scalar_inferred(w.fn,(i3,)) isa Float64
            @test _scalar_inferred(w.fn,(rgb,)) isa Float64
        end
        # A concrete 3D mask cannot accidentally select planar graph operators.
        @test isempty(get_image_scalar_bundles([typeof(b3)]; domain=:image2D))
        @test_throws ArgumentError get_image_scalar_bundles([typeof(i2)];domain=:unknown)
        @test_throws ArgumentError get_image_scalar_bundles([SImageND])
        @test_throws ArgumentError get_image_scalar_bundles([typeof(i2)];max_arity=0)
    end
end
