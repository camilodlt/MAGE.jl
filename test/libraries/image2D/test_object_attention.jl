using Random
using ImageMorphology: label_components, strel_box

_oa_intensity(values, ::Type{T} = N0f8) where {T} =
    SImageND(IntensityPixel{T}.(clamp.(Float64.(values), 0.0, 1.0)))
_oa_binary(values) = SImageND(BinaryPixel.(Bool.(values)))
_oa_segment(values) = SImageND(SegmentPixel.(Int.(values)))
_oa_float(image) = Float64.(reinterpret(image.img))
_oa_unit(position, n) = (position - 1) / (n - 1)

"Scene of four objects with known geometry, shifted by `(dr, dc)`."
function _oa_scene(height, width; dr = 0, dc = 0)
    square = falses(height, width)   # 4×4, compact
    bar = falses(height, width)      # 2×12, elongated
    dot = falses(height, width)      # single pixel
    disk = falses(height, width)     # radius-3 disk, circular
    square[(3:6) .+ dr, (3:6) .+ dc] .= true
    bar[(15:16) .+ dr, (4:15) .+ dc] .= true
    dot[4 + dr, 20 + dc] = true
    for r in 1:height, c in 1:width
        (r - (12 + dr))^2 + (c - (24 + dc))^2 <= 9 && (disk[r, c] = true)
    end
    return square, bar, dot, disk
end

@testset "Object attention: locators, descriptors and zoom" begin
    C = UTCGP.image2D_object_common
    L = UTCGP.number_locateFromImg
    O = UTCGP.number_objectFromImg
    height, width = 20, 30
    square, bar, dot, disk = _oa_scene(height, width)
    union_mask = square .| bar .| dot .| disk
    mask = _oa_binary(union_mask)
    intensity_values = 0.2 .* square .+ 0.6 .* bar .+ 1.0 .* dot .+ 0.8 .* disk
    intensity = _oa_intensity(intensity_values)

    @testset "labelling matches ImageMorphology" begin
        for seed in 1:5
            values = rand(MersenneTwister(seed), height, width) .> 0.6
            t = C.object_table(_oa_binary(values).img, C.IsSet())
            reference = label_components(values, strel_box((3, 3)))
            @test t.n == maximum(reference)
            @test sort(t.area) == sort([count(==(l), reference) for l in 1:maximum(reference)])
            @test (t.labels .> 0) == values
        end
        t = C.object_table(mask.img, C.IsSet())
        @test t.n == 4
        @test sum(t.area) == count(union_mask)
    end

    @testset "selectors pick the expected object" begin
        t = C.object_table(mask.img, C.IsSet())
        id_of(selector) = Dict(C.SELECTOR_FUNCTIONS)[selector](t)
        area_of(id) = t.area[id]
        @test area_of(id_of(:largest)) == 29              # disk
        @test area_of(id_of(:smallest)) == 1              # dot
        @test area_of(id_of(:second_largest)) == 24       # bar
        @test area_of(id_of(:most_elongated)) == 24
        @test area_of(id_of(:widest)) == 24
        @test area_of(id_of(:most_rectangular)) in (1, 16, 24)
        @test area_of(id_of(:topmost)) in (1, 16)
        @test area_of(id_of(:bottommost)) == 24
        @test area_of(id_of(:rightmost)) == 29
        @test area_of(id_of(:leftmost)) == 16
        @test C.circularity(t, id_of(:largest)) > 0.95
        @test C.elongation(t, id_of(:most_elongated)) > 0.8
        @test C.extent(t, id_of(:widest)) == 1.0
        @test C.orientation(t, id_of(:most_elongated)) ≈ 0.5 atol = 1e-6
        @test C.orientation(t, id_of(:largest)) == 0.5            # disk: no axis
        @test C.orientation(t, id_of(:leftmost)) == 0.5           # square: no axis
        vertical = C.object_table(_oa_binary([c == 3 && 2 <= r <= 9 for r in 1:10, c in 1:6]).img, C.IsSet())
        @test min(C.orientation(vertical, 1), 1 - C.orientation(vertical, 1)) < 1e-6
    end

    @testset "object locators" begin
        @test O.obj_x_largest(mask) ≈ _oa_unit(24, width)
        @test O.obj_y_largest(mask) ≈ _oa_unit(12, height)
        @test O.obj_x_smallest(mask) ≈ _oa_unit(20, width)
        @test O.obj_y_smallest(mask) ≈ _oa_unit(4, height)
        @test O.obj_x_most_elongated(mask) ≈ _oa_unit(9.5, width)
        @test O.obj_y_most_elongated(mask) ≈ _oa_unit(15.5, height)

        # Intensity inputs: thresholded at 0.5 by default, or explicitly.
        @test O.obj_x_largest(intensity) ≈ _oa_unit(24, width)
        @test O.obj_x_smallest(intensity, 0.1) ≈ _oa_unit(20, width)
        @test O.obj_count(intensity) == 3.0
        @test O.obj_count(intensity, 0.1) == 4.0
        @test O.obj_count(mask) == 4.0

        @test O.obj_x_brightest(mask, intensity) ≈ _oa_unit(20, width)
        @test O.obj_x_darkest(mask, intensity) ≈ _oa_unit(4.5, width)
        @test O.obj_x_darkest(intensity, intensity, 0.1) ≈ _oa_unit(4.5, width)

        @test O.obj_x_rank_area(mask, 0.0) ≈ O.obj_x_smallest(mask)
        @test O.obj_x_rank_area(mask, 1.0) ≈ O.obj_x_largest(mask)
        @test O.obj_x_like_area(mask, 1 / (height * width)) ≈ O.obj_x_smallest(mask)
        @test O.obj_x_like_elongation(mask, 1.0) ≈ O.obj_x_most_elongated(mask)

        # Nearest: diagonal (s) and explicit (x, y).
        @test O.obj_x_nearest(mask, 0.0) ≈ _oa_unit(4.5, width)
        x_dot, y_dot = _oa_unit(20, width), _oa_unit(4, height)
        @test O.obj_x_nearest(mask, x_dot, y_dot) ≈ x_dot
        @test O.obj_dist_nearest(mask, x_dot, y_dot) ≈ 0.0 atol = 1e-12

        @test O.obj_dx_smallest_largest(mask) ≈ x_dot - _oa_unit(24, width)
        @test O.obj_dy_second_largest_largest(mask) ≈ _oa_unit(15.5, height) - _oa_unit(12, height)
    end

    @testset "translation: locators follow, descriptors stay" begin
        dr, dc = 2, 3
        shifted = _oa_binary(reduce(.|, _oa_scene(height, width; dr = dr, dc = dc)))
        for selector in (:largest, :smallest, :most_elongated, :most_circular, :topmost)
            fx = getfield(O, Symbol(:obj_x_, selector))
            fy = getfield(O, Symbol(:obj_y_, selector))
            @test fx(shifted) ≈ fx(mask) + dc / (width - 1)
            @test fy(shifted) ≈ fy(mask) + dr / (height - 1)
            for descriptor in (:area, :width, :height, :elongation, :circularity, :extent, :orientation)
                fd = getfield(O, Symbol(:obj_, descriptor, :_, selector))
                @test fd(shifted) ≈ fd(mask)
            end
        end
        shifted_intensity = _oa_intensity(Float64.(shifted.img .== true))
        plain_intensity = _oa_intensity(Float64.(mask.img .== true))
        @test L.com_x(shifted_intensity) ≈ L.com_x(plain_intensity) + dc / (width - 1)
        @test L.com_y(shifted_intensity) ≈ L.com_y(plain_intensity) + dr / (height - 1)
        @test L.spread_x(shifted_intensity) ≈ L.spread_x(plain_intensity)
    end

    @testset "empty masks" begin
        empty = _oa_binary(falses(height, width))
        @test O.obj_x_largest(empty) == 0.5
        @test O.obj_area_largest(empty) == 0.0
        @test O.obj_count(empty) == 0.0
        @test O.obj_dist_nearest(empty, 0.2) == 1.0
        @test O.obj_dx_smallest_largest(empty) == 0.0
        black = _oa_intensity(zeros(height, width))
        @test L.com_x(black) == 0.5
        @test L.spread_y(black) == 0.0
        @test L.refine_x_25p(black, 0.3) == 0.3
        @test L.first_x(black) == 0.5
    end

    @testset "mask-free locators" begin
        values = zeros(height, width)
        values[5, 7] = 1.0
        values[15:16, 20:23] .= 0.4
        img = _oa_intensity(values)
        @test L.argmax_x(img) ≈ _oa_unit(7, width)
        @test L.argmax_y(img) ≈ _oa_unit(5, height)
        @test L.argmin_x(_oa_intensity(1 .- values)) ≈ _oa_unit(7, width)
        @test L.projpeak_y(img) ≈ _oa_unit(15, height)
        @test L.first_x(img, 0.3) ≈ _oa_unit(7, width)
        @test L.last_x(img, 0.3) ≈ _oa_unit(23, width)
        @test L.first_y(img) ≈ _oa_unit(5, height)
        @test L.last_y(img, 0.3) ≈ _oa_unit(16, height)
        @test L.com_x(img, 0.5) ≈ _oa_unit(7, width)
        @test L.median_y(img, 0.3) ≈ _oa_unit(15, height)
        @test L.rare_x(img, 0.005) ≈ _oa_unit(7, width)
        @test L.rare_y(img) ≈ (_oa_unit(5, height) + 8 * _oa_unit(15.5, height)) / 9
        @test L.odd_x(img) ≈ L.com_x(img) atol = 1e-2
        @test 0.0 <= L.contrast_x(img) <= 1.0

        # refine pulls a rough point onto the nearby mass; peak finds the max.
        rough_x, rough_y = _oa_unit(9, width), _oa_unit(7, height)
        @test L.refine_x_25p(img, rough_x, rough_y) ≈ _oa_unit(7, width)
        @test L.refine_y_25p(img, rough_x, rough_y) ≈ _oa_unit(5, height)
        @test L.peak_x_10p(img, _oa_unit(8, width), _oa_unit(6, height)) ≈ _oa_unit(7, width)
        @test L.refine_x_50p(img, 0.7) isa Float64

        moved = copy(values)
        moved[5, 7] = 0.0
        moved[6, 9] = 1.0
        @test L.motion_x(img, _oa_intensity(moved)) ≈ _oa_unit(8, width)
        @test L.motion_y(img, _oa_intensity(moved), 0.5) ≈ _oa_unit(5.5, height)
    end

    @testset "number bundles: arity, ranges and NaN safety" begin
        source = intensity
        for bundle in (bundle_number_locateFromImg, bundle_number_objectLocateFromImg,
                bundle_number_objectDescribeFromImg)
            for wrapper in bundle
                fn = wrapper.fn
                @test all(m -> m.nargs <= 5, methods(fn))
                for inputs in ((mask,), (intensity,), (intensity, 0.3), (mask, 0.3),
                        (mask, NaN), (intensity, 0.3, 0.7), (mask, source),
                        (intensity, source), (mask, Inf, -2.0))
                    hasmethod(fn, typeof(inputs)) || continue
                    value = fn(inputs...)
                    @test value isa Float64
                    @test isfinite(value)
                    if !startswith(String(wrapper.name), "obj_count") &&
                       !startswith(String(wrapper.name), "obj_d")
                        @test 0.0 <= value <= 1.0
                    end
                end
            end
        end
        @test length(bundle_number_locateFromImg) == 36
    end

    @testset "zoom operators" begin
        Z = UTCGP.image2D_zoom
        I = typeof(intensity)
        B = typeof(mask)
        segment = _oa_segment(1 .* square .+ 2 .* bar .+ 3 .* dot .+ 4 .* disk)
        G = typeof(segment)
        zoom(bundle, name, T) = bundle[name].fn(T)

        # A uniform object cropped with no margin fills the whole output.
        crop_square = zoom(bundle_image2DIntensity_zoom_factory, :zoom_crop_bbox_leftmost, I)
        out = crop_square(intensity, mask, 0.0)
        @test typeof(out) == I
        @test all(≈(0.2; atol = 0.01), _oa_float(out))
        # The default margin includes some background.
        @test minimum(_oa_float(crop_square(intensity, mask, 0.5))) < 0.2

        # Self-thresholded intensity: only bar, dot and disk are ≥ 0.5.
        crop_all = zoom(bundle_image2DIntensity_zoom_factory, :zoom_crop_bbox, I)
        @test typeof(crop_all(intensity)) == I
        @test crop_all(intensity, 0.1, 0.0) isa I

        # Isolate keeps only the selected object.
        isolate = zoom(bundle_image2DIntensity_zoom_factory, :zoom_crop_isolate_largest, I)
        isolated = _oa_float(isolate(intensity, mask, 0.5))
        @test maximum(isolated) ≈ 0.8 atol = 0.01
        @test minimum(isolated) == 0.0

        # Binary output stays binary with nearest neighbour.
        crop_bar = zoom(bundle_image2DBinary_zoom_factory, :zoom_crop_bbox_most_elongated, B)
        @test all(crop_bar(mask, 0.0).img .== true)
        @test typeof(crop_bar(mask)) == B

        # Segment output only contains existing labels.
        crop_seg = zoom(bundle_image2DSegment_zoom_factory, :zoom_crop_bbox_largest, G)
        seg_out = crop_seg(segment, mask, 0.3)
        @test typeof(seg_out) == G
        @test Set(Int.(reinterpret(seg_out.img))) ⊆ Set(0:4)
        @test 4 in Set(Int.(reinterpret(seg_out.img)))

        # Aspect-preserving box matches the image aspect where it fits.
        r0, r1, c0, c1 = Z._expand_box(10, 11, 10, 11, 20, 30, 0.0, true)
        @test (r1 - r0 + 1) * 30 == (c1 - c0 + 1) * 20

        # Recentering moves the selected centroid to the image centre.
        recenter = zoom(bundle_image2DBinary_zoom_factory, :zoom_recenter_smallest, B)
        centred = recenter(mask)
        @test centred.img[10, 15] == BinaryPixel(true)
        @test count(p -> p == true, centred.img) <= count(union_mask)

        # Glimpses at the border are clipped, not padded.
        glimpse = zoom(bundle_image2DIntensity_zoom_factory, :zoom_glimpse_25p, I)
        @test glimpse(intensity, 0.0) isa I
        @test glimpse(intensity, 0.2, 0.7) isa I
        corner = _oa_intensity([r <= 3 && c <= 4 ? 1.0 : 0.0 for r in 1:height, c in 1:width])
        @test minimum(_oa_float(glimpse(corner, 0.0, 0.0))) > 0.9

        rows = zoom(bundle_image2DBinary_zoom_factory, :zoom_rows, B)
        @test all(rows(mask, _oa_unit(15, height), _oa_unit(16, height)).img[:, 10] .== true)
        @test zoom(bundle_image2DSegment_zoom_factory, :zoom_center, G)(segment) isa G

        # Empty masks leave the source unchanged.
        empty = _oa_binary(falses(height, width))
        @test crop_square(intensity, empty).img == intensity.img
        @test recenter(empty).img == empty.img
    end

    @testset "zoom bundles: every operator on every input form" begin
        empty = _oa_binary(falses(height, width))
        segment = _oa_segment(1 .* square .+ 2 .* bar)
        cases = (
            (bundle_image2DIntensity_zoom_factory, intensity,
                ((intensity,), (intensity, 0.4), (intensity, 0.4, 0.2), (intensity, mask),
                 (intensity, mask, 0.3), (intensity, intensity), (intensity, intensity, NaN),
                 (intensity, empty), (intensity, 0.1, 0.9))),
            (bundle_image2DBinary_zoom_factory, mask,
                ((mask,), (mask, 0.3), (mask, mask), (mask, intensity, 0.2), (mask, empty),
                 (empty,), (mask, 0.1, 0.9))),
            (bundle_image2DSegment_zoom_factory, segment,
                ((segment,), (segment, mask), (segment, intensity, 0.2), (segment, 0.3),
                 (segment, 0.1, 0.9))),
        )
        for (bundle, prototype, input_sets) in cases
            T = typeof(prototype)
            @test length(bundle) >= 90
            for wrapper in bundle
                fn = wrapper.fn(T)
                @test all(m -> m.nargs <= 5, methods(fn))
                called = 0
                for inputs in input_sets
                    hasmethod(fn, typeof(inputs)) || continue
                    called += 1
                    @test typeof(fn(inputs...)) == T
                end
                @test called > 0
            end
        end
    end
end
