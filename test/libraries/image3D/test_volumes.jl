using Random
using Statistics: quantile, mean, std

@testset "Volumes: 3D → 3D, 3D → 2D, 3D → scalar" begin
    VC = UTCGP.image3D_volume_common
    V = UTCGP.number_volumeFromImg
    ST = UTCGP.number_intensityStatsFromImg
    _v_intensity(values) = SImageND(IntensityPixel{N0f8}.(clamp.(values, 0.0, 1.0)))
    _v_binary(values) = SImageND(BinaryPixel.(Bool.(values)))
    _v_bits(img) = Bool.(reinterpret(img.img))
    _v_values(img) = Float64.(reinterpret(img.img))
    _v_call(f, args...) = Base.invokelatest(f, args...)
    _v_close(a, b, tol) = maximum(abs.(a .- b)) <= tol          # element-wise, unlike ≈ on arrays

    function brute_labels(m, offsets)
        dims = size(m)
        L = zeros(Int, dims)
        n = 0
        for idx in CartesianIndices(m)
            (m[idx] && L[idx] == 0) || continue
            n += 1
            L[idx] = n
            stack = [idx]
            while !isempty(stack)
                p = pop!(stack)
                for o in offsets
                    q = p + o
                    checkbounds(Bool, m, q) || continue
                    (m[q] && L[q] == 0) || continue
                    L[q] = n
                    push!(stack, q)
                end
            end
        end
        return L, n
    end
    offsets26 = [CartesianIndex(a, b, c) for a in -1:1, b in -1:1, c in -1:1 if (a, b, c) != (0, 0, 0)]
    offsets6 = [CartesianIndex(1, 0, 0), CartesianIndex(-1, 0, 0), CartesianIndex(0, 1, 0),
                CartesianIndex(0, -1, 0), CartesianIndex(0, 0, 1), CartesianIndex(0, 0, -1)]

    @testset "core: labelling, cavities, distance transforms, filters" begin
        rng = MersenneTwister(11)
        for trial in 1:40
            dims = (rand(rng, 3:9), rand(rng, 3:9), rand(rng, 3:9))
            m = rand(rng, dims...) .< rand(rng, 0.15:0.05:0.6)
            t = VC.volume_table(m, identity)
            L, n = brute_labels(m, offsets26)
            @test t.n == n
            @test Int.(t.labels) == L
            @test sum(t.area) == count(m)
            # Cavities: background components (6-connected) away from the border.
            Lb, nb = brute_labels(.!m, offsets6)
            border = Set{Int}()
            for idx in CartesianIndices(m)
                any(idx[k] == 1 || idx[k] == dims[k] for k in 1:3) && Lb[idx] > 0 && push!(border, Lb[idx])
            end
            holes = Array{Bool,3}(undef, dims)
            count_, voxels = VC.volume_holes!(holes, m)
            @test count_ == nb - length(border)
            @test holes == [Lb[idx] > 0 && !(Lb[idx] in border) for idx in CartesianIndices(m)]
            @test voxels == count(holes)
        end
        for trial in 1:10
            dims = (rand(rng, 4:9), rand(rng, 4:9), rand(rng, 4:9))
            f = rand(rng, dims...) .< 0.08
            any(f) || (f[1] = true)
            points = findall(f)
            brute = [minimum(sum(abs2, Tuple(i) .- Tuple(p)) for p in points) for i in CartesianIndices(f)]
            @test VC.volume_distance_map!(zeros(dims), f) == brute
            for radius in (1, 2, 3)
                bounded = VC.volume_distance_map_upto!(zeros(dims), f, radius)
                @test all((brute .<= radius^2) .== (bounded .<= radius^2))
                @test bounded[brute .<= radius^2] == brute[brute .<= radius^2]
            end
        end
        v = rand(rng, 7, 8, 6)
        for r in (1, 2)
            naive_min = [minimum(v[max(i-r,1):min(i+r,7), max(j-r,1):min(j+r,8), max(k-r,1):min(k+r,6)]) for i in 1:7, j in 1:8, k in 1:6]
            @test VC.box_extremum!(zeros(size(v)), v, r, VC.fmin) == naive_min
        end
        cross = [minimum([v[i, j, k]; [v[(CartesianIndex(i, j, k) + o)] for o in offsets6 if checkbounds(Bool, v, CartesianIndex(i, j, k) + o)]]) for i in 1:7, j in 1:8, k in 1:6]
        @test VC.cross_extremum!(zeros(size(v)), v, VC.fmin) == cross
        kernel, radius = VC.gaussian_kernel(1.0)
        @test sum(kernel) ≈ 1.0
        @test VC.separable_convolve!(zeros(5, 5, 5), fill(0.4, 5, 5, 5), kernel, radius) ≈ fill(0.4, 5, 5, 5)
    end

    # A test volume: hollow ball (cavity), a rod, a speck, on a dim background.
    dims = (20, 24, 16)
    values = fill(0.1, dims)
    ball = falses(dims)
    for idx in CartesianIndices(values)
        r, c, s = Tuple(idx)
        if (r - 10)^2 + (c - 9)^2 + (s - 8)^2 <= 25
            values[idx] = 0.8
            ball[idx] = true
        end
    end
    values[9:11, 8:10, 7:9] .= 0.1                    # cavity
    ball[9:11, 8:10, 7:9] .= false
    rod = falses(dims)
    rod[3:4, 18:22, 2:14] .= true
    values[rod] .= 0.6
    values[18, 1, 2] = 0.95                            # speck on the border (x = 1)
    vol = _v_intensity(values)
    mask = _v_binary(values .> 0.5)
    I = typeof(vol)
    B = typeof(mask)
    iop(name) = bundle_image3DIntensity_volume_factory[name].fn(I)
    bop(name) = bundle_image3DBinary_volume_factory[name].fn(B)

    @testset "Basic volume bundles" begin
        for (bundle, T, proto) in ((bundle_image3DIntensity_volume_basic_factory, I, vol),
                                   (bundle_image3DBinary_volume_basic_factory, B, mask))
            # Search convention: identity first, then a constant taking no input.
            @test bundle[1].name == :vol_identity
            @test bundle[2].name == :vol_ones
            @test _v_call(bundle[1].fn(T), proto) === proto
            ones_vol = _v_call(bundle[2].fn(T))
            @test ones_vol isa T
            @test all(isone, _v_values(ones_vol))
            @test _v_call(bundle[2].fn(T), proto, 0.3) isa T          # extra inputs are ignored
            @test !any(!iszero, _v_values(_v_call(bundle[:vol_zeros].fn(T))))
        end
        as_intensity = _v_call(bundle_image3DIntensity_volume_basic_factory[:vol_from_mask].fn(I), mask)
        @test as_intensity isa I
        @test _v_values(as_intensity) == Float64.(_v_bits(mask))
        # The 3D → 3D getters put the basic bundle first.
        for getter in (UTCGP.get_extension_volume_intensityimg, UTCGP.get_extension_volume_binaryimg)
            basic = first(getter())
            @test basic[1].name == :vol_identity && basic[2].name == :vol_ones
        end
    end

    @testset "3D → 3D intensity" begin
        v = _v_values(vol)
        @test _v_close(_v_values(_v_call(iop(:vol_invert), vol)), 1 .- v, 0.003)
        normalized = _v_values(_v_call(iop(:vol_normalize), vol))
        @test extrema(normalized) == (0.0, 1.0)
        windowed = _v_values(_v_call(iop(:vol_window), vol, 0.7, 0.2))
        @test all(windowed[v .<= 0.6] .== 0.0) && all(windowed[v .>= 0.8] .== 1.0)
        @test _v_values(_v_call(iop(:vol_threshold_zero), vol, 0.5)) == ifelse.(v .>= 0.5, v, 0.0)
        eroded = _v_values(_v_call(iop(:vol_erode), vol))
        naive = [minimum(v[max(i-1,1):min(i+1,20), max(j-1,1):min(j+1,24), max(k-1,1):min(k+1,16)]) for i in 1:20, j in 1:24, k in 1:16]
        @test _v_close(eroded, naive, 0.003)
        opened = _v_call(iop(:vol_open), vol)
        @test all(_v_values(opened) .<= v .+ 1e-9)
        @test _v_close(_v_values(_v_call(iop(:vol_open), opened)), _v_values(opened), 0.003)    # idempotent
        @test sum(_v_values(_v_call(iop(:vol_gaussian_s1), vol))) ≈ sum(v) rtol = 0.02
        @test all(_v_values(_v_call(iop(:vol_gradient), _v_intensity(fill(0.4, dims)))) .== 0.0)
        @test _v_values(_v_call(iop(:vol_mask_keep), vol, mask)) == ifelse.(_v_bits(mask), v, 0.0)
        @test _v_values(_v_call(iop(:vol_absdiff), vol, vol)) == zeros(dims)
        inside = _v_values(_v_call(iop(:vol_distance_inside), mask))
        @test maximum(inside) ≈ 1.0 && all(inside[.!_v_bits(mask)] .== 0.0)
        @test all(_v_values(_v_call(iop(:vol_proximity), mask))[_v_bits(mask)] .≈ 1.0)
    end

    @testset "3D → 3D binary" begin
        m = _v_bits(mask)
        @test _v_bits(_v_call(bop(:vol_threshold), vol, 0.5)) == (values .>= 0.5)
        @test count(_v_bits(_v_call(bop(:vol_top_fraction), vol, 0.05))) >= 0.05 * prod(dims)
        otsu = _v_bits(_v_call(bop(:vol_otsu), vol))
        @test otsu == m
        filled = _v_bits(_v_call(bop(:vol_fill_holes), mask))
        @test count(filled) == count(m) + 27
        @test _v_bits(_v_call(bop(:vol_holes), mask)) == (filled .& .!m)
        @test _v_bits(_v_call(bop(:vol_largest_component), mask)) == ball
        @test _v_bits(_v_call(bop(:vol_central_component), mask)) == ball
        @test !(_v_bits(_v_call(bop(:vol_remove_small), mask, 2 / prod(dims)))[18, 1, 2])
        @test !(_v_bits(_v_call(bop(:vol_clear_border), mask))[18, 1, 2])
        @test _v_bits(_v_call(bop(:vol_clear_border), mask))[ball] |> all
        dilated = _v_bits(_v_call(bop(:vol_dilate), mask))
        naive = [any(m[max(i-1,1):min(i+1,20), max(j-1,1):min(j+1,24), max(k-1,1):min(k+1,16)]) for i in 1:20, j in 1:24, k in 1:16]
        @test dilated == naive
        @test _v_bits(_v_call(bop(:vol_not), mask)) == .!m
        @test _v_bits(_v_call(bop(:vol_xor), mask, mask)) == falses(dims)
        @test count(_v_bits(_v_call(bop(:vol_bbox_fill), mask))) >= count(m)
    end

    @testset "geometry and 2D → 3D" begin
        m = _v_bits(mask)
        @test _v_bits(_v_call(bop(:vol_flip_x), mask)) == reverse(m; dims = 2)
        @test _v_values(_v_call(iop(:vol_flip_z), vol)) == reverse(_v_values(vol); dims = 3)
        cube = rand(MersenneTwister(2), 9, 9, 9) .> 0.5
        C = _v_binary(cube)
        rot = bundle_image3DBinary_volume_factory[:vol_rot90_xy].fn(typeof(C))
        once = _v_bits(_v_call(rot, C))
        @test all(once[:, :, k] == rotl90(cube[:, :, k]) for k in 1:9)
        @test _v_bits(_v_call(rot, _v_call(rot, _v_call(rot, _v_call(rot, C))))) == cube
        @test _v_bits(_v_call(bop(:vol_rot90_xy), mask)) == m           # non-square plane: identity
        shifted = _v_bits(_v_call(bop(:vol_shift_z), mask, 0.5 + 2 / 16))
        @test shifted[:, :, 3:end] == m[:, :, 1:end-2]
        cropped = _v_values(_v_call(iop(:vol_crop_bbox_largest), vol, mask, 0.0))
        @test minimum(cropped) >= 0.09 && maximum(cropped) <= 0.81
        recentred = _v_bits(_v_call(bop(:vol_recenter_largest), mask, mask))
        t = UTCGP.image3D_volume_common.volume_table(recentred, identity)
        largest = argmax(t.area)
        @test all(abs.(UTCGP.image3D_volume_common.centroid(t, largest) .- (dims .+ 1) ./ 2) .<= 1.0)
        plane = rand(MersenneTwister(3), 20, 24) .> 0.5
        extruded = _v_bits(_v_call(bop(:vol_extrude_z), _v_binary(plane)))
        @test all(extruded[:, :, k] == plane for k in 1:16)
        applied = _v_values(_v_call(iop(:vol_mask2d_z), vol, _v_binary(plane)))
        @test applied == _v_values(vol) .* plane
        side = rand(MersenneTwister(4), 24, 16) .> 0.5          # (x, z) plane for the y axis
        @test all(_v_bits(_v_call(bop(:vol_extrude_y), _v_binary(side)))[k, :, :] == side for k in 1:20)
        # Each operator has only its own methods: mask2d needs a volume, extrude takes the 2D image alone.
        @test !_v_call(hasmethod, bop(:vol_mask2d_z), Tuple{typeof(_v_binary(plane))})
        @test !_v_call(hasmethod, bop(:vol_extrude_z), Tuple{typeof(mask),typeof(_v_binary(plane))})
        # Segment images have no method (the kernels only read intensity or binary pixels).
        segments = SImageND(SegmentPixel{UInt8}.(rand(MersenneTwister(5), UInt8(1):UInt8(3), 20, 24)))
        @test !_v_call(hasmethod, bop(:vol_extrude_z), Tuple{typeof(segments)})
        @test !_v_call(hasmethod, iop(:vol_mask2d_z), Tuple{typeof(vol),typeof(segments)})
    end

    @testset "3D → 2D" begin
        v = _v_values(vol)
        m = _v_bits(mask)
        out_dims = Dict(:z => (20, 24), :y => (24, 16), :x => (20, 16))
        axis_of = Dict(:y => 1, :x => 2, :z => 3)
        for letter in (:y, :x, :z)
            a = axis_of[letter]
            T = typeof(_v_intensity(zeros(out_dims[letter])))
            TB = typeof(_v_binary(falses(out_dims[letter])))
            f(stem) = bundle_image2DIntensity_fromVolume_factory[Symbol(stem, :_, letter)].fn(T)
            g(stem) = bundle_image2DBinary_fromVolume_factory[Symbol(stem, :_, letter)].fn(TB)
            @test _v_values(_v_call(f(:proj_max), vol)) == dropdims(maximum(v; dims = a); dims = a)
            @test _v_values(_v_call(f(:proj_min), vol)) == dropdims(minimum(v; dims = a); dims = a)
            @test _v_close(_v_values(_v_call(f(:proj_mean), vol)), dropdims(mean(v; dims = a); dims = a), 0.003)
            @test _v_close(_v_values(_v_call(f(:proj_std), vol)), min.(1.0, 2 .* dropdims(std(v; dims = a, corrected = false); dims = a)), 0.003)
            depth = _v_values(_v_call(f(:proj_argmax), vol))
            expected = (dropdims(map(i -> i[a], argmax(v; dims = a)); dims = a) .- 1) ./ (size(v, a) - 1)
            @test _v_close(depth, expected, 0.003)
            k = cld(size(v, a), 2)
            @test _v_values(_v_call(f(:slice_center), vol)) == selectdim(v, a, k)
            @test _v_values(_v_call(f(:slice_at), vol, 0.0)) == selectdim(v, a, 1)
            counts = [count(selectdim(m, a, j)) for j in 1:size(m, a)]
            @test _v_values(_v_call(f(:slice_largest), vol, mask)) == selectdim(v, a, argmax(counts))
            masked = _v_values(_v_call(f(:proj_max_masked), vol, mask))
            @test masked == dropdims(maximum(ifelse.(m, v, -Inf); dims = a); dims = a) |> x -> ifelse.(isinf.(x), 0.0, x)
            @test _v_bits(_v_call(g(:proj_any), mask)) == dropdims(any(m; dims = a); dims = a)
            @test _v_bits(_v_call(g(:proj_any), vol, 0.7)) == dropdims(any(v .>= 0.7; dims = a); dims = a)
            @test _v_bits(_v_call(g(:proj_all), mask)) == dropdims(all(m; dims = a); dims = a)
            @test _v_bits(_v_call(g(:slice_largest), mask)) == selectdim(m, a, argmax(counts))
            # Operators keep their own methods: slice_largest ignores a scalar (it once ran proj_any's).
            @test _v_bits(_v_call(g(:slice_largest), vol, 0.7)) == _v_bits(_v_call(g(:slice_largest), vol))
            @test _v_bits(_v_call(g(:proj_any), vol, 0.7)) == dropdims(any(v .>= 0.7; dims = a); dims = a)
        end
    end

    @testset "3D → scalar" begin
        v = _v_values(vol)
        m = _v_bits(mask)
        for (p, name) in ((0.05, :stat_q05), (0.5, :stat_q50), (0.95, :stat_q95))
            @test getfield(ST, name)(vol) ≈ quantile(vec(v), p)
            @test getfield(ST, name)(vol, mask) ≈ quantile(v[m], p)
        end
        @test ST.stat_mean_diff(vol, mask) ≈ mean(v[m]) - mean(v[.!m])
        cube = falses(12, 12, 12)
        cube[3:8, 3:8, 3:8] .= true
        @test V.vshape_sphericity(_v_binary(cube)) ≈ π^(1 / 3) * 6^(2 / 3) / 6
        @test V.vshape_fill(_v_binary(cube)) ≈ 216 / 12^3
        @test V.vshape_extent(_v_binary(cube)) == 1.0
        @test V.vshape_elongation(_v_binary(cube)) ≈ 0.0 atol = 1e-9
        bar = falses(12, 12, 12)
        bar[5:6, 2:11, 5:6] .= true
        @test V.vshape_elongation(_v_binary(bar)) ≈ 1 - sqrt(((4 - 1) / 12 + 1 / 12) / ((100 - 1) / 12 + 1 / 12))   # 0.8
        @test V.vshape_components(mask) == 3.0
        @test V.vshape_cavities(mask) == 1.0
        @test V.vshape_cavity_fraction(mask) ≈ 27 / (count(m) + 27)
        @test V.vshape_largest_fraction(mask) ≈ count(ball) / count(m)
        @test V.vshape_centroid_z(_v_binary(cube)) ≈ (5.5 - 1) / 11
        @test V.vobjs_volume_max(mask) ≈ count(ball) / prod(dims)
        @test V.vobjs_extent_min(mask) <= V.vobjs_extent_max(mask) == 1.0
        @test V.vshape_fill(mask, _v_binary(ball)) ≈ count(ball) / prod(dims)

        function naive_open(fg, r)
            ballr = [CartesianIndex(a, b, c) for a in -r:r, b in -r:r, c in -r:r if a^2 + b^2 + c^2 <= r^2]
            eroded = [fg[i] && all(!checkbounds(Bool, fg, i + o) || fg[i+o] for o in ballr) for i in CartesianIndices(fg)]
            return [any(checkbounds(Bool, fg, i + o) && eroded[i+o] for o in ballr) for i in CartesianIndices(fg)]
        end
        blob = falses(14, 14, 14)
        blob[3:10, 3:10, 3:10] .= true
        blob[11:12, 5:6, 5:6] .= true
        for r in (1, 2, 3)
            @test getfield(V, Symbol(:vgran_open_r, r))(_v_binary(blob)) ≈ count(naive_open(blob, r) .& blob) / count(blob)
        end
        small = rand(MersenneTwister(6), 8, 9, 7)
        naive = [minimum(small[max(i-1,1):min(i+1,8), max(j-1,1):min(j+1,9), max(k-1,1):min(k+1,7)]) for i in 1:8, j in 1:9, k in 1:7]
        opened = [maximum(naive[max(i-1,1):min(i+1,8), max(j-1,1):min(j+1,9), max(k-1,1):min(k+1,7)]) for i in 1:8, j in 1:9, k in 1:7]
        sv = _v_intensity(small)
        sraw = _v_values(sv)
        naive = [minimum(sraw[max(i-1,1):min(i+1,8), max(j-1,1):min(j+1,9), max(k-1,1):min(k+1,7)]) for i in 1:8, j in 1:9, k in 1:7]
        opened = [maximum(naive[max(i-1,1):min(i+1,8), max(j-1,1):min(j+1,9), max(k-1,1):min(k+1,7)]) for i in 1:8, j in 1:9, k in 1:7]
        @test V.vgran_grey_open_r1(sv) ≈ sum(opened) / sum(sraw)

        symmetric = _v_intensity([0.2 + 0.5 * exp(-((r - 6.5)^2 + (c - 6.5)^2 + (s - 6.5)^2) / 8) for r in 1:12, c in 1:12, s in 1:12])
        @test V.vprof_symmetry_x(symmetric) ≈ 1.0
        @test V.vprof_com_z(symmetric) ≈ 0.5 atol = 1e-6
        @test V.vprof_center_contrast(symmetric) > 0.2
        @test V.vprof_shell_inner(symmetric) > V.vprof_shell_middle(symmetric) > V.vprof_shell_outer(symmetric)
        @test V.vprof_slab_z_low(symmetric) ≈ V.vprof_slab_z_high(symmetric)
        @test V.vprof_shell_inner(vol, mask) > V.vprof_shell_outer(vol, mask)
    end

    @testset "bundles: arity, types, finite values" begin
        for (bundle, T, inputs) in (
                (bundle_image3DIntensity_volume_factory, I, ((vol,), (vol, 0.3), (vol, 0.3, 0.6), (vol, vol), (vol, mask), (vol, mask, 0.2), (mask,), (mask, 0.4))),
                (bundle_image3DBinary_volume_factory, B, ((mask,), (mask, 0.3), (mask, mask), (mask, vol), (vol,), (vol, 0.4), (mask, mask, 0.2))),
            )
            for wrapper in bundle
                fn = wrapper.fn(T)
                @test all(m -> m.nargs <= 5, methods(fn))
                for args in inputs
                    Base.invokelatest(hasmethod, fn, typeof(args)) || continue
                    @test typeof(_v_call(fn, args...)) == T
                end
            end
        end
        for bundle in (bundle_number_volumeShapeFromImg, bundle_number_volumeGranulometryFromImg, bundle_number_volumeProfileFromImg)
            for wrapper in bundle
                @test all(m -> m.nargs <= 5, methods(wrapper.fn))
                called = 0
                for args in ((vol,), (mask,), (vol, 0.3), (vol, mask), (mask, mask), (_v_binary(falses(dims)),))
                    hasmethod(wrapper.fn, typeof(args)) || continue
                    x = wrapper.fn(args...)
                    called += 1
                    @test x isa Float64 && isfinite(x)
                end
                @test called > 0
            end
        end
        @test length(bundle_image3DIntensity_volume_factory) == 57
        @test length(bundle_image3DBinary_volume_factory) == 41
        @test length(bundle_image2DIntensity_fromVolume_factory) == 36
        @test length(bundle_image2DBinary_fromVolume_factory) == 15
    end
end
