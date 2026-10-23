# Pure Julia kernels. Persistent region geometry is step-owned; temporaries use TLS.
module ski
using ..MAGE:
    SkiVector,
    SkiRegions,
    SImageND,
    BinaryPixel,
    IntensityPixel,
    scratch,
    FunctionBundle,
    append_method!,
    output_pixels,
    image_result,
    _get_image_tuple_size,
    _get_image_pixel_type,
    SizedImage2D,
    _factory_type_symbol,
    @serialized_factory
using Statistics
using ..image_pooling_common: median_select!
using ..image2D_object_common: background_holes!
const Mask = SImageND{S,T,2,C} where {S,T<:BinaryPixel,C}
const Intensity = SImageND{S,T,2,C} where {S,T<:IntensityPixel,C}
const Source = Union{Mask,Intensity}

const Regions = SkiRegions
foreground(x::BinaryPixel) = Bool(x.pixel)
foreground(x::IntensityPixel) = Float64(x) >= 0.5

function regions!(t::SkiRegions, img::Source, roi::Union{Nothing,Mask} = nothing)
    roi === nothing || size(img) == size(roi) || throw(DimensionMismatch("ROI size"))
    h, w = size(img)
    labels = fill!(t.labels, 0)
    queue = scratch(:ski_queue, Int, h * w)
    boxes = resize!(t.boxes, 0)
    counts = resize!(t.counts, 0)
    t.n = 0
    n = 0
    # Python labels in C order, regardless of Julia's memory layout.
    @inbounds for r in 1:h, c in 1:w
        (
            labels[r, c] != 0 ||
            !foreground(img.img[r, c]) ||
            (roi !== nothing && !foreground(roi.img[r, c]))
        ) && continue
        n += 1
        resize!(counts, n)
        counts[n] = 0
        resize!(boxes, n)
        r0 = r1 = r
        c0 = c1 = c
        head = 1
        tail = 1
        queue[1] = r + (c - 1) * h
        labels[r, c] = n
        while head <= tail
            counts[n] += 1
            k = queue[head]
            head += 1
            y = (k - 1) % h + 1
            x = (k - 1) ÷ h + 1
            r0 = min(r0, y)
            r1 = max(r1, y)
            c0 = min(c0, x)
            c1 = max(c1, x)
            for xx in max(1, x - 1):min(w, x + 1), yy in max(1, y - 1):min(h, y + 1)
                if labels[yy, xx] == 0 &&
                   foreground(img.img[yy, xx]) &&
                   (roi === nothing || foreground(roi.img[yy, xx]))
                    labels[yy, xx] = n
                    tail += 1
                    queue[tail] = yy + (xx - 1) * h
                end
            end
        end
        boxes[n] = (r0, r1, c0, c1)
    end
    t.n = n
    t.image = img
    t

end

function region_mask(t::Regions, id)
    r0, r1, c0, c1 = bounds(t, id)
    a = scratch(:ski_region_mask, Bool, r1 - r0 + 1, c1 - c0 + 1)
    @inbounds for c in c0:c1, r in r0:r1
        a[r-r0+1, c-c0+1] = t.labels[r, c] == id
    end
    a
end
@inline bounds(t, id) = t.boxes[id]

# Direct central accumulation avoids cancellation on small objects far from origin.
function moment(t, id, p, q, central, normalized, source)
    source === nothing && p == 0 && q == 0 && !normalized && return Float64(t.counts[id])
    r0, r1, c0, c1 = bounds(t, id)
    mass = 0.0
    sr = 0.0
    sc = 0.0
    @inbounds for c in c0:c1, r in r0:r1
        t.labels[r, c] == id || continue
        v = source === nothing ? 1.0 : Float64(source.img[r, c])
        mass += v
        sr += v * (r - r0)
        sc += v * (c - c0)
    end
    normalized && p + q < 2 && return NaN
    cr = central ? sr / mass : 0.0
    cc = central ? sc / mass : 0.0
    value = 0.0
    @inbounds for c in c0:c1, r in r0:r1
        t.labels[r, c] == id || continue
        v = source === nothing ? 1.0 : Float64(source.img[r, c])
        value += v * (r - r0 - cr)^p * (c - c0 - cc)^q
    end
    normalized && mass < 0 && isodd(p + q) && return NaN
    normalized ? value / mass^(1 + (p + q) / 2) : value
end
# Compute the seven normalized moments used by Hu in two passes, rather than
# rescanning a region for every moment separately.
function hu(t, id, k, source)
    r0, r1, c0, c1 = bounds(t, id)
    mass = sr = sc = 0.0
    @inbounds for col in c0:c1, row in r0:r1
        t.labels[row, col] == id || continue
        weight = source === nothing ? 1.0 : Float64(source.img[row, col])
        mass += weight
        sr += weight * (row - r0)
        sc += weight * (col - c0)
    end
    cr, cc = sr / mass, sc / mass
    a = b = c = d = e = f = g = 0.0
    @inbounds for col in c0:c1, row in r0:r1
        t.labels[row, col] == id || continue
        weight = source === nothing ? 1.0 : Float64(source.img[row, col])
        r, x = row - r0 - cr, col - c0 - cc
        rr, xx = r * r, x * x
        a += weight * rr
        b += weight * xx
        c += weight * r * x
        d += weight * rr * r
        e += weight * r * xx
        f += weight * rr * x
        g += weight * xx * x
    end
    scale2 = mass^2
    scale3 = mass < 0 ? NaN : mass^2.5
    a /= scale2
    b /= scale2
    c /= scale2
    d /= scale3
    e /= scale3
    f /= scale3
    g /= scale3
    x = d + e
    y = f + g
    u = d - 3 * e
    v = 3 * f - g
    k == 1 && return a + b
    k == 2 && return (a - b)^2 + 4c^2
    k == 3 && return u^2 + v^2
    k == 4 && return x^2 + y^2
    k == 5 && return u * x * (x^2 - 3y^2) + v * y * (3x^2 - y^2)
    k == 6 && return (a - b) * (x^2 - y^2) + 4c * x * y
    v * x * (x^2 - 3y^2) - u * y * (3x^2 - y^2)
end

# Integer doubled coordinates represent the midpoint-of-pixel-edges hull exactly.
cross(o, a, b) = (a[1] - o[1]) * (b[2] - o[2]) - (a[2] - o[2]) * (b[1] - o[1])
function convex_hull!(pts)
    sort!(pts; alg = QuickSort)
    n = 0
    for p in pts
        if n == 0 || p != pts[n]
            n += 1
            pts[n] = p
        end
    end
    resize!(pts, n)
    hull = empty!(scratch(:ski_hull, Tuple{Int,Int}, 0))
    for p in pts
        while length(hull) >= 2 && cross(hull[end-1], hull[end], p) <= 0
            pop!(hull)
        end
        push!(hull, p)
    end
    lower = length(hull)
    for i in length(pts)-1:-1:1
        p = pts[i]
        while length(hull) > lower && cross(hull[end-1], hull[end], p) <= 0
            pop!(hull)
        end
        push!(hull, p)
    end
    pop!(hull)
    hull
end

function convex_mask(t, id)
    mask = region_mask(t, id)
    h, w = size(mask)
    pts = empty!(scratch(:ski_hull_points, Tuple{Int,Int}, 0))
    @inbounds for c in 1:w, r in 1:h
        mask[r, c] || continue
        # Interior pixels cannot contribute hull vertices.
        r > 1 &&
            r < h &&
            c > 1 &&
            c < w &&
            mask[r-1, c] &&
            mask[r+1, c] &&
            mask[r, c-1] &&
            mask[r, c+1] &&
            continue
        push!(pts, (2r - 1, 2c), (2r + 1, 2c), (2r, 2c - 1), (2r, 2c + 1))
    end
    hull = convex_hull!(pts)
    result = scratch(:ski_convex_mask, Bool, h, w)
    @inbounds for c in 1:w, r in 1:h
        inside = true
        for j in eachindex(hull)
            if cross(hull[j], hull[mod1(j + 1, length(hull))], (2r, 2c)) < 0
                inside = false
                break
            end
        end
        result[r, c] = inside
    end
    result
end

# Contours at level .5 have vertices at foreground/background edge midpoints.
function feret(mask)
    pts = empty!(scratch(:ski_feret, Tuple{Int,Int}, 0))
    h, w = size(mask)
    @inbounds for c in 1:w, r in 1:h
        mask[r, c] || continue
        (r == 1 || !mask[r-1, c]) && push!(pts, (2r - 1, 2c))
        (r == h || !mask[r+1, c]) && push!(pts, (2r + 1, 2c))
        (c == 1 || !mask[r, c-1]) && push!(pts, (2r, 2c - 1))
        (c == w || !mask[r, c+1]) && push!(pts, (2r, 2c + 1))
    end
    hull = convex_hull!(pts)
    n = length(hull)
    n < 2 && return 0.0
    # Rotating calipers: antipodal vertices of the midpoint contour's hull.
    d = 0
    j = 2
    distance2(a, b) = (a[1] - b[1])^2 + (a[2] - b[2])^2
    for i in 1:n
        next = mod1(i + 1, n)
        while cross(hull[i], hull[next], hull[mod1(j + 1, n)]) > cross(hull[i], hull[next], hull[j])
            j = mod1(j + 1, n)
        end
        d = max(d, distance2(hull[i], hull[j]), distance2(hull[next], hull[j]))
    end
    sqrt(d) / 2
end
at(a, r, c) = checkbounds(Bool, a, r, c) && a[r, c]
const CROFTON = (
    0.0,
    π / 4 * (1 + 1 / sqrt(2)),
    π / (4sqrt(2)),
    π / (2sqrt(2)),
    0.0,
    π / 4 * (1 + 1 / sqrt(2)),
    0.0,
    π / (4sqrt(2)),
    π / 4,
    π / 2,
    π / (4sqrt(2)),
    π / (4sqrt(2)),
    π / 4,
    π / 2,
    0.0,
    0.0,
)
function perimeter(mask, crofton)
    h, w = size(mask)
    value = 0.0
    if crofton
        for c in 1:w+1, r in 1:h+1
            k =
                Int(at(mask, r, c)) +
                2Int(at(mask, r - 1, c)) +
                4Int(at(mask, r, c - 1)) +
                8Int(at(mask, r - 1, c - 1))
            value += CROFTON[k+1]
        end
        return value
    end
    border = scratch(:ski_border, Bool, h, w)
    @inbounds for c in 1:w, r in 1:h
        border[r, c] =
            mask[r, c] &&
            !(at(mask, r - 1, c) && at(mask, r + 1, c) && at(mask, r, c - 1) && at(mask, r, c + 1))
    end
    for c in 1:w, r in 1:h
        k =
            Int(border[r, c]) +
            2 * (
                at(border, r - 1, c) +
                at(border, r + 1, c) +
                at(border, r, c - 1) +
                at(border, r, c + 1)
            ) +
            10 * (
                at(border, r - 1, c - 1) +
                at(border, r + 1, c - 1) +
                at(border, r - 1, c + 1) +
                at(border, r + 1, c + 1)
            )
        value +=
            k in (5, 7, 15, 17, 25, 27) ? 1.0 :
            k in (21, 33) ? sqrt(2) : k in (13, 23) ? (1 + sqrt(2)) / 2 : 0.0
    end
    value
end

# Filled area uses 8-connected background in skimage, whereas Euler uses 4.
function filled_area(mask)
    h, w = size(mask)
    seen = fill!(scratch(:ski_fill_seen, Bool, h, w), false)
    queue = scratch(:ski_fill_queue, Int, h * w)
    head = 1
    tail = 0
    for c in 1:w, r in 1:h
        if (r == 1 || r == h || c == 1 || c == w) && !mask[r, c] && !seen[r, c]
            tail += 1
            queue[tail] = r + (c - 1) * h
            seen[r, c] = true
        end
    end
    while head <= tail
        k = queue[head]
        head += 1
        r = (k - 1) % h + 1
        c = (k - 1) ÷ h + 1
        for x in max(1, c - 1):min(w, c + 1), y in max(1, r - 1):min(h, r + 1)
            if !mask[y, x] && !seen[y, x]
                tail += 1
                queue[tail] = y + (x - 1) * h
                seen[y, x] = true
            end
        end
    end
    Float64(h * w - tail)
end

function property(t, id, ::Val{P}, source = nothing) where {P}
    r0, r1, c0, c1 = bounds(t, id)
    h = r1 - r0 + 1
    w = c1 - c0 + 1
    a = Float64(t.counts[id])
    P in (:area, :num_pixels) && return a
    P === :area_bbox && return Float64(h * w)
    P === :extent && return a / (h * w)
    P === :equivalent_diameter_area && return sqrt(4a / π)
    P === :bbox_min_row && return Float64(r0 - 1)
    P === :bbox_min_col && return Float64(c0 - 1)
    P === :bbox_max_row && return Float64(r1)
    P === :bbox_max_col && return Float64(c1)
    if P in (
        :centroid_row,
        :centroid_col,
        :centroid_local_row,
        :centroid_local_col,
        :centroid_weighted_row,
        :centroid_weighted_col,
        :centroid_weighted_local_row,
        :centroid_weighted_local_col,
    )
        weighted = P in (
            :centroid_weighted_row,
            :centroid_weighted_col,
            :centroid_weighted_local_row,
            :centroid_weighted_local_col,
        )
        row = P in (
            :centroid_row,
            :centroid_local_row,
            :centroid_weighted_row,
            :centroid_weighted_local_row,
        )
        s = weighted ? source : nothing
        mass = moment(t, id, 0, 0, false, false, s)
        x = moment(t, id, Int(row), Int(!row), false, false, s) / mass
        local_coordinate = P in (
            :centroid_local_row,
            :centroid_local_col,
            :centroid_weighted_local_row,
            :centroid_weighted_local_col,
        )
        return x + (local_coordinate ? 0 : row ? r0 - 1 : c0 - 1)
    end
    if P in (
        :axis_major_length,
        :axis_minor_length,
        :eccentricity,
        :orientation,
        :inertia_tensor_eigval_0,
        :inertia_tensor_eigval_1,
    )
        rr = moment(t, id, 2, 0, true, false, nothing) / a
        cc = moment(t, id, 0, 2, true, false, nothing) / a
        rc = moment(t, id, 1, 1, true, false, nothing) / a
        d = hypot(rr - cc, 2rc)
        l1 = max(0.0, (rr + cc + d) / 2)
        l2 = max(0.0, (rr + cc - d) / 2)
        P === :axis_major_length && return 4sqrt(l1)
        P === :axis_minor_length && return 4sqrt(l2)
        P === :eccentricity && return l1 == 0 ? 0.0 : sqrt(1 - l2 / l1)
        P === :inertia_tensor_eigval_0 && return l1
        P === :inertia_tensor_eigval_1 && return l2
        return cc == rr ? (rc > 0 ? π / 4 : -π / 4) : atan(2rc, rr - cc) / 2
    end
    if P in (:intensity_max, :intensity_min, :intensity_mean, :intensity_median, :intensity_std)
        vals = empty!(scratch(:ski_intensities, Float64, 0))
        @inbounds for c in c0:c1, r in r0:r1
            t.labels[r, c] == id && push!(vals, Float64(source.img[r, c]))
        end
        P === :intensity_max && return maximum(vals)
        P === :intensity_min && return minimum(vals)
        P === :intensity_mean && return mean(vals)
        P === :intensity_median && return median_select!(vals)
        return std(vals; corrected = false)
    end
    if P in (:area_convex, :solidity, :feret_diameter_max)
        mask = convex_mask(t, id)
        return P === :area_convex ? Float64(count(mask)) :
               P === :solidity ? a / count(mask) : feret(mask)
    end
    mask = region_mask(t, id)
    P === :area_filled && return filled_area(mask)
    P === :euler_number && return Float64(1 - first(background_holes!(nothing, mask)))
    P === :perimeter && return perimeter(mask, false)
    P === :perimeter_crofton && return perimeter(mask, true)
    error("Unknown ski property $P")
end

include("properties.jl")
include("vectors.jl")
include("images.jl")
end # module ski
