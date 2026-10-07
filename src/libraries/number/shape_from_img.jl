"""
Shape descriptors for classification: Hu moment invariants and descriptors of
the whole foreground, and statistics aggregated over all objects of a mask.

# Bundles

- [`bundle_number_shapeFromImg`](@ref)
- [`bundle_number_objectStatsFromImg`](@ref)

The exhaustive, always-current list of operators in each bundle is on the
[Bundle Catalogue](@ref) page.
"""
module number_shapeFromImg

using ..UTCGP: FunctionBundle, append_method!
using ..UTCGP: SImageND, IntensityPixel, BinaryPixel
using ..image2D_object_common:
    ObjectTable,
    IsSet,
    AtLeast,
    clamp_unit,
    pixel_value,
    fast_foreground_test,
    scratch,
    object_table,
    unit_x,
    unit_y,
    area_fraction,
    circularity,
    elongation,
    extent,
    solidity,
    convex_hull_points,
    extreme_points,
    hull_pixel_count,
    background_holes!

fallback(args...) = return 0.0

"""
    bundle_number_shapeFromImg

Descriptors of the **whole foreground** of a mask, treated as one shape, and
Hu moment invariants.

- `shape_hu1` … `shape_hu7`: Hu's seven moment invariants of the foreground,
  unchanged by translation, rotation and scale (`hu7` changes sign under
  mirroring). Returned as `−sign(h) log10 |h|`, the usual scale.
- `shape_hu1_weighted` … `shape_hu7_weighted`: the same on the intensity
  image, pixels weighted by their value divided by the maximum (so contrast
  does not matter); `(img, roi)` restricts it to a region.
- `shape_solidity` (area / convex-hull area), `shape_circularity`,
  `shape_elongation`, `shape_extent`, `shape_fill` (area / image),
  `shape_hole_fraction` (holes / filled area) and `shape_euler`
  (objects − holes).

Mask inputs: `(mask)`, `(img)` thresholded at `0.5`, `(img, threshold)`; with
`(mask, roi)` only the foreground inside `roi` counts.
"""
bundle_number_shapeFromImg = FunctionBundle(fallback)

"""
    bundle_number_objectStatsFromImg

Per-object descriptors **aggregated over all objects** of a mask:
`objs_<descriptor>_<aggregate>` with descriptors `area` (fraction of the
image), `circularity`, `elongation`, `extent`, `solidity` and `nn_distance`
(normalised distance to the nearest other centroid), and aggregates `mean`,
`std`, `min`, `max`, `median` and `cv` (std / mean). Also `objs_area_gini`
(inequality of object sizes) and `objs_intensity_<aggregate>(img, mask)`, the
mean intensity of each object aggregated the same way.

Inputs: `(mask)`, `(img)` at `0.5`, `(img, threshold)`; `(mask, roi)` keeps the
objects whose centroid lies inside `roi`. No objects → `0.0`.
"""
bundle_number_objectStatsFromImg = FunctionBundle(fallback)

"Intensity 2D image."
const _Img = SImageND{S,T,2,C} where {S,T<:IntensityPixel,C}
"Binary 2D image."
const _Mask = SImageND{S,T,2,C} where {S,T<:BinaryPixel,C}

# ---------------------------------------------------------------------------
# Foreground as a Bool matrix
# ---------------------------------------------------------------------------

"Foreground as a `Bool` matrix in per-task scratch (`is_foreground` is `IsSet()` or `AtLeast(t)`)."
function _foreground(pixels::AbstractMatrix, is_foreground)
    fg = scratch(:shape_desc_fg, Bool, size(pixels)...)
    predicate = fast_foreground_test(pixels, is_foreground)
    @inbounds for i in eachindex(pixels, fg)
        fg[i] = predicate(pixels[i])
    end
    return fg
end

"Whether a region pixel is inside: binary pixels when set, intensity pixels at or above `0.5`."
@inline _roi_in(p::BinaryPixel) = p.pixel == true
@inline _roi_in(p) = Float64(p) >= 0.5

"Restrict `fg` to the pixels inside `roi` (in place)."
function _intersect!(fg::AbstractMatrix{Bool}, roi::AbstractMatrix)
    size(fg) == size(roi) || throw(DimensionMismatch("mask and region must have the same size"))
    @inbounds for i in eachindex(fg, roi)
        fg[i] &= _roi_in(roi[i])
    end
    return fg
end

# ---------------------------------------------------------------------------
# Hu moments
# ---------------------------------------------------------------------------

"""
Hu's seven invariants of a non-negative weight matrix (x = column, y = row).

1. Raw moments `m00`, `m10`, `m01` give the centroid.
2. Central moments `mu_pq = Σ w (x − x̄)^p (y − ȳ)^q` (p + q = 2, 3) are
   accumulated per column: the inner loop over rows keeps `Σ w`, `Σ w y`,
   `Σ w y²`, `Σ w y³` (vectorised), and the column's powers of `x` are
   applied once per column.
3. Normalised moments `eta_pq = mu_pq / m00^(1 + (p+q)/2)` (scale
   invariant) are combined into Hu's formulas (rotation invariant).
"""
function _hu(weights::AbstractMatrix{Float64})
    h, w = size(weights)
    m00 = 0.0
    m10 = 0.0
    m01 = 0.0
    @inbounds for c in 1:w
        s0 = 0.0                                 # column sums: Σ w, Σ w·r
        s1 = 0.0
        @simd for r in 1:h
            v = weights[r, c]
            s0 += v
            s1 += v * r
        end
        m00 += s0
        m10 += s0 * c
        m01 += s1
    end
    m00 <= 0.0 && return ntuple(_ -> 0.0, 7)
    xc = m10 / m00                               # centroid (x = column, y = row)
    yc = m01 / m00
    mu20 = mu02 = mu11 = mu30 = mu03 = mu21 = mu12 = 0.0
    @inbounds for c in 1:w
        x = c - xc
        s0 = 0.0                                 # column sums: Σ w·y^k for k = 0…3
        s1 = 0.0
        s2 = 0.0
        s3 = 0.0
        @simd for r in 1:h
            v = weights[r, c]
            y = r - yc
            vy = v * y
            s0 += v
            s1 += vy
            s2 += vy * y
            s3 += vy * y * y
        end
        mu20 += s0 * x * x
        mu11 += s1 * x
        mu02 += s2
        mu30 += s0 * x * x * x
        mu21 += s1 * x * x
        mu12 += s2 * x
        mu03 += s3
    end
    norm2 = m00^2                # m00^(1 + (p+q)/2) for p + q = 2
    norm3 = m00^2.5              # … and for p + q = 3
    # Normalised central moments (named eta_pq: `4e11` would parse as 4×10¹¹).
    eta20, eta02, eta11 = mu20 / norm2, mu02 / norm2, mu11 / norm2
    eta30, eta03, eta21, eta12 = mu30 / norm3, mu03 / norm3, mu21 / norm3, mu12 / norm3
    a = eta30 + eta12            # recurring sums in Hu's formulas
    b = eta21 + eta03
    h1 = eta20 + eta02
    h2 = (eta20 - eta02)^2 + 4 * eta11^2
    h3 = (eta30 - 3 * eta12)^2 + (3 * eta21 - eta03)^2
    h4 = a^2 + b^2
    h5 = (eta30 - 3 * eta12) * a * (a^2 - 3 * b^2) + (3 * eta21 - eta03) * b * (3 * a^2 - b^2)
    h6 = (eta20 - eta02) * (a^2 - b^2) + 4 * eta11 * a * b
    h7 = (3 * eta21 - eta03) * a * (a^2 - 3 * b^2) - (eta30 - 3 * eta12) * b * (3 * a^2 - b^2)
    return (h1, h2, h3, h4, h5, h6, h7)
end

"`−sign(h) log10 |h|`; `0` for `h == 0`."
@inline _log_hu(h::Float64) = (abs(h) < 1e-300 || !isfinite(h)) ? 0.0 : -sign(h) * log10(abs(h))

"Hu invariants of a mask (weight `1` on the foreground)."
function _hu_mask(fg::AbstractMatrix{Bool})
    weights = scratch(:hu_weights, Float64, size(fg)...)
    @inbounds @simd for i in eachindex(fg, weights)
        weights[i] = fg[i] ? 1.0 : 0.0
    end
    return _hu(weights)
end

"""
Hu invariants of the intensity image (inside `roi` when given). Weights are
divided by their maximum, so the result does not depend on contrast: a uniform
region gives the same values as its mask. The weights are computed once into a
scratch matrix, then read by the moment passes.
"""
function _hu_weighted(pixels::AbstractMatrix, roi)
    h, w = size(pixels)
    weights = scratch(:hu_weights, Float64, h, w)
    largest = 0.0
    @inbounds for i in eachindex(pixels)
        v = pixel_value(pixels[i])
        v = ifelse(v > 0.0, v, 0.0)
        roi === nothing || _roi_in(roi[i]) || (v = 0.0)
        weights[i] = v
        largest = ifelse(v > largest, v, largest)
    end
    largest <= 0.0 && return ntuple(_ -> 0.0, 7)
    scale = 1.0 / largest
    @inbounds @simd for i in eachindex(weights)
        weights[i] *= scale
    end
    return _hu(weights)
end

# ---------------------------------------------------------------------------
# Whole-foreground descriptors
# ---------------------------------------------------------------------------

"""
    _whole_moments(fg) -> (area, var_rr, var_cc, cov_rc, r0, r1, c0, c1) or nothing

Moment summary of the whole foreground: pixel count, row / column variances
(each `+1/12`, the variance of a unit-width pixel) and covariance, and the
bounding box `r0:r1 × c0:c1`. `nothing` when empty.
"""
function _whole_moments(fg::AbstractMatrix{Bool})
    h, w = size(fg)
    n = 0
    sum_r = sum_c = sum_rr = sum_cc = sum_rc = 0.0
    r0, r1, c0, c1 = h + 1, 0, w + 1, 0
    @inbounds for c in 1:w, r in 1:h
        fg[r, c] || continue
        n += 1
        sum_r += r
        sum_c += c
        sum_rr += r * r
        sum_cc += c * c
        sum_rc += r * c
        r0 = min(r0, r); r1 = max(r1, r); c0 = min(c0, c); c1 = max(c1, c)
    end
    n == 0 && return nothing
    mean_r, mean_c = sum_r / n, sum_c / n
    return (n, max(sum_rr / n - mean_r^2, 0.0) + 1 / 12, max(sum_cc / n - mean_c^2, 0.0) + 1 / 12,
            sum_rc / n - mean_r * mean_c, r0, r1, c0, c1)
end

"Foreground area over the pixel area of its convex hull (computed from the extreme pixels of each row)."
function _shape_solidity(fg)
    m = _whole_moments(fg)
    m === nothing && return 0.0
    n, _, _, _, r0, r1, c0, c1 = m
    hull = convex_hull_points(extreme_points(fg, 0, r0, r1, c0, c1))
    return clamp(n / max(hull_pixel_count(hull), 1), 0.0, 1.0)
end

"Moment circularity `area / (2π (var_rr + var_cc))`: `1` for a disk, which minimises the second moment for its area."
function _shape_circularity(fg)
    m = _whole_moments(fg)
    m === nothing && return 0.0
    n, var_rr, var_cc, _ = m
    return clamp(n / (2π * (var_rr + var_cc)), 0.0, 1.0)
end

"`1 − sqrt(λmin / λmax)` of the covariance matrix: `0` for a disk or square, towards `1` for a line."
function _shape_elongation(fg)
    m = _whole_moments(fg)
    m === nothing && return 0.0
    _, var_rr, var_cc, cov_rc = m
    # Eigenvalues of [var_rr cov_rc; cov_rc var_cc] are half ± disc.
    half = (var_rr + var_cc) / 2
    disc = sqrt(max(half^2 - (var_rr * var_cc - cov_rc^2), 0.0))
    return clamp(1.0 - sqrt(max(half - disc, 0.0) / (half + disc)), 0.0, 1.0)
end

"Foreground area over its bounding-box area."
function _shape_extent(fg)
    m = _whole_moments(fg)
    m === nothing && return 0.0
    n, _, _, _, r0, r1, c0, c1 = m
    return n / ((r1 - r0 + 1) * (c1 - c0 + 1))
end

"Foreground area over the image area."
_shape_fill(fg) = count(fg) / length(fg)

"Hole area (4-connected background not reaching the border) over the filled foreground area."
function _shape_hole_fraction(fg)
    area = count(fg)
    area == 0 && return 0.0
    _, hole_area = background_holes!(nothing, fg)
    return hole_area / (area + hole_area)
end

"Euler number with 8-connected objects and 4-connected holes: objects − holes."
function _shape_euler(fg)
    objects = object_table(fg, identity).n
    holes, _ = background_holes!(nothing, fg)
    return Float64(objects - holes)
end

# ---------------------------------------------------------------------------
# Per-object aggregates
# ---------------------------------------------------------------------------

"Distance from each object's centroid to the nearest other centroid, normalised by the unit-square diagonal; `0` for a lone object."
function _nn_distances(t::ObjectTable)
    d = zeros(t.n)
    t.n <= 1 && return d
    xs = [unit_x(t, i) for i in 1:t.n]
    ys = [unit_y(t, i) for i in 1:t.n]
    @inbounds for i in 1:t.n
        best = Inf
        for j in 1:t.n
            j == i && continue
            best = min(best, (xs[i] - xs[j])^2 + (ys[i] - ys[j])^2)
        end
        d[i] = sqrt(best / 2)                 # divided by the unit-square diagonal
    end
    return d
end

# (name, values(table, ids) -> one value per object, wording)
const _DESCRIPTORS = (
    (:area, (t, ids) -> [area_fraction(t, i) for i in ids], "area fraction"),
    (:circularity, (t, ids) -> [circularity(t, i) for i in ids], "moment circularity"),
    (:elongation, (t, ids) -> [elongation(t, i) for i in ids], "elongation"),
    (:extent, (t, ids) -> [extent(t, i) for i in ids], "extent"),
    (:solidity, (t, ids) -> [solidity(t, i) for i in ids], "solidity"),
    (:nn_distance, (t, ids) -> _nn_distances(t)[ids], "nearest-neighbour distance"),
)

# Aggregates of per-object values (population standard deviation).
_median(v) = (s = sort(v); n = length(s); isodd(n) ? s[(n + 1) ÷ 2] : (s[n ÷ 2] + s[n ÷ 2 + 1]) / 2)
_mean(v) = sum(v) / length(v)
_std(v) = (m = _mean(v); sqrt(sum(x -> (x - m)^2, v) / length(v)))

# (name, reducer, wording); `cv` is std / mean.
const _AGGREGATES = (
    (:mean, _mean, "mean"),
    (:std, _std, "standard deviation"),
    (:min, minimum, "minimum"),
    (:max, maximum, "maximum"),
    (:median, _median, "median"),
    (:cv, v -> (m = _mean(v); m == 0 ? 0.0 : _std(v) / m), "coefficient of variation"),
)

"Ids of the objects to aggregate: all, or those whose centroid lies inside `roi`."
function _object_ids(t::ObjectTable, roi)
    roi === nothing && return collect(1:t.n)
    ids = Int[]
    for i in 1:t.n
        r = clamp(round(Int, t.sum_r[i] / t.area[i]), 1, t.h)
        c = clamp(round(Int, t.sum_c[i] / t.area[i]), 1, t.w)
        _roi_in(roi[r, c]) && push!(ids, i)
    end
    return ids
end

"`aggregate` of `descriptor`'s values over the selected objects; `0` when none."
function _aggregate(descriptor::D, aggregate::A, t::ObjectTable, roi) where {D,A}
    ids = _object_ids(t, roi)
    isempty(ids) && return 0.0
    return Float64(aggregate(descriptor(t, ids)))
end

"Gini coefficient of the selected objects' areas: `Σ (2i − n − 1) aᵢ / (n Σ a)` over the sorted areas."
function _gini(t::ObjectTable, roi)
    ids = _object_ids(t, roi)
    length(ids) <= 1 && return 0.0
    areas = sort(Float64.(t.area[ids]))
    n = length(areas)
    return sum((2i - n - 1) * areas[i] for i in 1:n) / (n * sum(areas))
end

"Mean pixel value of `pixels` inside each object."
function _intensity_means(t::ObjectTable, pixels::AbstractMatrix)
    sums = zeros(t.n)
    @inbounds for i in eachindex(t.labels)
        l = t.labels[i]
        l == 0 && continue
        sums[l] += pixel_value(pixels[i])
    end
    return [sums[i] / t.area[i] for i in 1:t.n]
end

# ---------------------------------------------------------------------------
# Registration
# ---------------------------------------------------------------------------

"""
    @_mask_methods name compute

Define the mask methods of a whole-foreground or aggregate operator whose
value is `compute(fg::Matrix{Bool}, roi_pixels_or_nothing)`:

- `name(mask)`, `name(img)` (at `0.5`), `name(img, threshold)`: no region;
- `name(mask, roi)` (binary or intensity region), `name(img, roi_mask)`.
"""
macro _mask_methods(name, compute)
    name, compute = esc(name), esc(compute)
    return quote
        $name(mask::_Mask, args...) = $compute(_foreground(mask.img, IsSet()), nothing)
        $name(img::_Img, args...) = $compute(_foreground(img.img, AtLeast(0.5)), nothing)
        $name(img::_Img, threshold::Number, args...) =
            $compute(_foreground(img.img, AtLeast(clamp_unit(threshold))), nothing)
        $name(mask::_Mask, roi::Union{_Mask,_Img}, args...) =
            $compute(_foreground(mask.img, IsSet()), roi.img)
        $name(img::_Img, roi::_Mask, args...) =
            $compute(_foreground(img.img, AtLeast(0.5)), roi.img)
    end
end

"Attach `doc` to the function `name` and register it in `bundle`."
function _register!(bundle, name::Symbol, description::String, doc::String)
    @eval @doc $doc $name
    append_method!(bundle, getfield(@__MODULE__, name), name; description = description)
end

const _MASK_SIGNATURES = """
    NAME(mask, args...)
    NAME(img, [threshold], args...)
    NAME(mask, roi, args...)
"""

"Docstring of an operator defined by `@_mask_methods`."
_mask_doc(name, what) = replace(_MASK_SIGNATURES, "NAME" => string(name)) * "\n" * what *
    " Intensity inputs are thresholded at `threshold` (default `0.5`); with `roi`, only the foreground inside it counts."

# Hu moments of the foreground.
for k in 1:7
    name = Symbol(:shape_hu, k)
    compute = (fg, roi) -> _log_hu(_hu_mask(roi === nothing ? fg : _intersect!(fg, roi))[k])
    @eval @_mask_methods $name $compute
    _register!(bundle_number_shapeFromImg, name, "Hu invariant $k of the foreground (log scale).",
        _mask_doc(name, "Hu's moment invariant $k of the foreground, as `−sign(h) log10 |h|`."))

    weighted = Symbol(:shape_hu, k, :_weighted)
    @eval begin
        $weighted(img::_Img, args...) = _log_hu(_hu_weighted(img.img, nothing)[$k])
        function $weighted(img::_Img, roi::Union{_Mask,_Img}, args...)
            size(img) == size(roi) || throw(DimensionMismatch("image and region must have the same size"))
            return _log_hu(_hu_weighted(img.img, roi.img)[$k])
        end
    end
    _register!(bundle_number_shapeFromImg, weighted, "Hu invariant $k of the intensity image (log scale).", """
        $weighted(img, [roi], args...)

    Hu's moment invariant $k of the intensity image, each pixel weighted by its
    value over the maximum value (only inside `roi` when given), as
    `−sign(h) log10 |h|`.
    """)
end

for (name, kernel, what) in (
        (:shape_solidity, _shape_solidity, "Area of the foreground over the pixel area of its convex hull."),
        (:shape_circularity, _shape_circularity, "Moment circularity of the foreground (1 for a disk)."),
        (:shape_elongation, _shape_elongation, "Elongation of the foreground, 1 − sqrt(λmin / λmax)."),
        (:shape_extent, _shape_extent, "Foreground area over its bounding-box area."),
        (:shape_fill, _shape_fill, "Foreground area over the image area."),
        (:shape_hole_fraction, _shape_hole_fraction, "Hole area over the filled foreground area."),
        (:shape_euler, _shape_euler, "Euler number: objects minus holes."),
    )
    compute = (fg, roi) -> Float64(kernel(roi === nothing ? fg : _intersect!(fg, roi)))
    @eval @_mask_methods $name $compute
    _register!(bundle_number_shapeFromImg, name, what, _mask_doc(name, what))
end

for (descriptor, values_of, descriptor_doc) in _DESCRIPTORS, (aggregate, reducer, aggregate_doc) in _AGGREGATES
    name = Symbol(:objs_, descriptor, :_, aggregate)
    compute = (fg, roi) -> _aggregate(values_of, reducer, object_table(fg, identity), roi)
    @eval @_mask_methods $name $compute
    _register!(bundle_number_objectStatsFromImg, name,
        "The $aggregate_doc of the objects' $descriptor_doc.",
        _mask_doc(name, "The $aggregate_doc, over all 8-connected objects, of their $descriptor_doc. No objects → `0.0`."))
end

let compute = (fg, roi) -> _gini(object_table(fg, identity), roi)
    @eval @_mask_methods objs_area_gini $compute
end
_register!(bundle_number_objectStatsFromImg, :objs_area_gini,
    "Gini coefficient of object areas (0 = equal sizes).",
    _mask_doc(:objs_area_gini, "Gini coefficient of the object areas: `0` when all objects have the same size, towards `1` when one dominates."))

for (aggregate, reducer, aggregate_doc) in _AGGREGATES
    name = Symbol(:objs_intensity_, aggregate)
    @eval begin
        function $name(img::_Img, mask::_Mask, args...)
            size(img) == size(mask) || throw(DimensionMismatch("image and mask must have the same size"))
            t = object_table(mask.img, IsSet())
            t.n == 0 && return 0.0
            return Float64($reducer(_intensity_means(t, img.img)))
        end
        function $name(img::_Img, saliency::_Img, args...)
            size(img) == size(saliency) || throw(DimensionMismatch("image and mask must have the same size"))
            t = object_table(saliency.img, AtLeast(0.5))
            t.n == 0 && return 0.0
            return Float64($reducer(_intensity_means(t, img.img)))
        end
        function $name(img::_Img, saliency::_Img, threshold::Number, args...)
            size(img) == size(saliency) || throw(DimensionMismatch("image and mask must have the same size"))
            t = object_table(saliency.img, AtLeast(clamp_unit(threshold)))
            t.n == 0 && return 0.0
            return Float64($reducer(_intensity_means(t, img.img)))
        end
    end
    _register!(bundle_number_objectStatsFromImg, name,
        "The $aggregate_doc of the objects' mean intensity.", """
        $name(img, mask, args...)
        $name(img, saliency, [threshold], args...)

    The $aggregate_doc, over the objects of `mask` (or of `saliency` thresholded
    at `threshold`, default `0.5`), of the mean intensity of `img` inside each
    object. No objects → `0.0`.
    """)
end

end
