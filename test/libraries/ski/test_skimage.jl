# PythonCall belongs to the test environment only; implementation is pure Julia.
using PythonCall
const measure = pyimport("skimage.measure")
const np = pyimport("numpy")
function pyregions(a, source)
    pa = np.array(Matrix(a); copy = true)
    measure.regionprops(
        measure.label(pa, connectivity = 2),
        intensity_image = np.array(source; copy = true),
    )
end
function expected(props, p)
    name = String(p)
    if startswith(name, "bbox_")
        k = findfirst(==(p), (:bbox_min_row, :bbox_min_col, :bbox_max_row, :bbox_max_col))
        return [pyconvert(Float64, x.bbox[k-1]) for x in props]
    elseif startswith(name, "centroid_")
        row = endswith(name, "row")
        base = replace(name, r"_(row|col)$" => "")
        return [pyconvert(Float64, pygetattr(x, base)[row ? 0 : 1]) for x in props]
    elseif startswith(name, "inertia_tensor_eigval_")
        k = endswith(name, "0") ? 0 : 1
        return [pyconvert(Float64, x.inertia_tensor_eigvals[k]) for x in props]
    elseif p === :intensity_median
        return [pyconvert(Float64, np.median(x.image_intensity[x.image])) for x in props]
    end
    [pyconvert(Float64, pygetattr(x, name)) for x in props]
end
approx_nan(a, b) =
    length(a) == length(b) &&
    all(isequal(x, y) || isapprox(x, y; atol = 2e-8, rtol = 2e-7) for (x, y) in zip(a, b))
@testset "skimage randomized property parity" begin
    rng = MersenneTwister(20261023)
    scenes = [
        rand(rng, h, w) .> p for (h, w, p) in
        ((1, 1, 0.5), (1, 12, 0.6), (12, 1, 0.6), (13, 17, 0.8), (15, 19, 0.55), (20, 21, 0.3))
    ]
    append!(scenes, [falses(4, 5), trues(4, 5), Bool[1 0 0; 0 1 0; 0 0 1]])
    for a in scenes, use_roi in (false, true)
        src = rand(rng, size(a)...)
        roi = rand(rng, size(a)...) .> 0.2
        effective = use_roi ? a .& roi : a
        props = pyregions(effective, src)
        img = mask(a)
        source = intensity(src)
        for p in SK.SHAPE_PROPERTIES
            fn = getfield(SK, Symbol(:ski_, p))
            got = use_roi ? fn(img, mask(roi)) : fn(img)
            @testset "$p $(size(a)) ROI=$use_roi" begin
                @test approx_nan(got, expected(props, p))
            end
        end
        for p in SK.INTENSITY_PROPERTIES
            fn = getfield(SK, Symbol(:ski_, p))
            got = use_roi ? fn(img, source, mask(roi)) : fn(img, source)
            @testset "$p $(size(a)) ROI=$use_roi" begin
                @test approx_nan(got, expected(props, p))
            end
        end
        for weighted in (false, true), kind in (:raw, :central, :normalized)
            prefix = weighted ? :moments_weighted : :moments
            prefix = kind === :raw ? prefix : Symbol(prefix, :_, kind)
            for p in 0:3, q in 0:3
                fn = getfield(SK, Symbol(:ski_, prefix, :_, p, :_, q))
                got =
                    weighted ? (use_roi ? fn(img, source, mask(roi)) : fn(img, source)) :
                    (use_roi ? fn(img, mask(roi)) : fn(img))
                want = [pyconvert(Float64, pygetattr(x, String(prefix))[p, q]) for x in props]
                @testset "$prefix $p,$q $(size(a)) ROI=$use_roi" begin
                    @test approx_nan(got, want)
                end
            end
        end
        for weighted in (false, true), k in 1:7
            base = weighted ? :moments_weighted_hu : :moments_hu
            fn = getfield(SK, Symbol(:ski_, base, :_, k))
            got =
                weighted ? (use_roi ? fn(img, source, mask(roi)) : fn(img, source)) :
                (use_roi ? fn(img, mask(roi)) : fn(img))
            want = [pyconvert(Float64, pygetattr(x, String(base))[k-1]) for x in props]
            @testset "$base $k $(size(a)) ROI=$use_roi" begin
                @test approx_nan(got, want)
            end
        end
    end
end

@testset "skimage property-driven image selection" begin
    rng = MersenneTwister(17)
    a = falses(15, 20)
    a[2:5, 2:6] .= true
    a[9:12, 3:4] .= true
    a[5:9, 13:17] .= true
    a[6:8, 14:16] .= false
    values = (0.55 .+ 0.45 .* rand(rng, size(a)...)) .* a
    roi_values = trues(size(a))
    roi_values[2, 2] = false
    img, roi = intensity(values), mask(roi_values)
    effective = a .& roi_values
    props = pyregions(effective, values)
    python_labels = measure.label(np.array(Matrix(effective); copy = true), connectivity = 2)
    labels = [pyconvert(Int, python_labels[r-1, c-1]) for r in axes(a, 1), c in axes(a, 2)]
    for p in (:area, :intensity_mean, :moments_hu_1)
        scores =
            p === :moments_hu_1 ? [pyconvert(Float64, x.moments_hu[0]) for x in props] :
            expected(props, p)
        for criterion in (:lt, :lte, :gt, :gte, :max, :min, :top_percentile, :bottom_percentile),
            bbox in (false, true)

            amount =
                criterion in (:top_percentile, :bottom_percentile) ? 40.0 :
                (minimum(scores) + maximum(scores)) / 2
            threshold =
                criterion === :max ? maximum(scores) :
                criterion === :min ? minimum(scores) :
                criterion === :top_percentile ?
                pyconvert(Float64, np.percentile(np.array(scores; copy = true), 60.0)) :
                criterion === :bottom_percentile ?
                pyconvert(Float64, np.percentile(np.array(scores; copy = true), 40.0)) : amount
            keep = [
                criterion === :lt ? x < threshold :
                criterion === :lte ? x <= threshold :
                criterion === :gt ? x > threshold :
                criterion === :gte ? x >= threshold :
                criterion in (:max, :min) ? x == threshold :
                criterion === :top_percentile ? x >= threshold : x <= threshold for x in scores
            ]
            wanted = falses(size(a))
            for id in eachindex(keep)
                keep[id] || continue
                if bbox
                    box = pyconvert(Tuple{Int,Int,Int,Int}, props[id-1].bbox)
                    wanted[box[1]+1:box[3], box[2]+1:box[4]] .= true
                else
                    wanted .|= labels .== id
                end
            end
            bbox || (wanted .&= roi_values)
            name = Symbol(:ski_keep_, bbox ? :bbox_ : :objects_, criterion)
            for (bundle, T) in (
                (bundle_image2DBinary_ski_factory, typeof(mask(a))),
                (bundle_image2DIntensity_ski_factory, typeof(img)),
            )
                fn = bundle[name].fn(T)
                property_fn = getfield(SK, Symbol(:ski_, p))
                v = property_fn(img, roi)
                result =
                    criterion in (:max, :min) ? Base.invokelatest(fn, img, v) :
                    Base.invokelatest(fn, img, v, amount)
                want = T === typeof(img) ? values .* wanted : Float64.(wanted)
                @test Float64.(result.img) ≈ want
            end
        end
    end
end
