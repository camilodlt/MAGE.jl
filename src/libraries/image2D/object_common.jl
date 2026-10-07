"""
Shared machinery for the 2D object, descriptor, zoom and mask libraries.

Sections of this file:

1. **Scalar inputs and coordinates** — `clamp_unit` sanitises the scalar
   arguments evolved programs pass in; `position_to_unit` / `unit_to_position`
   convert between pixel positions and normalised `[0, 1]` coordinates.
2. **Scratch buffers** — `scratch` hands out per-task working arrays that are
   reused across calls, so hot operators do not allocate temporaries.
3. **Distance transforms** — exact (`squared_distance_map!`) and bounded by a
   radius (`squared_distance_map_upto!`).
4. **Holes** — `background_holes!` finds background regions enclosed by the
   foreground.
5. **Foreground tests** — `IsSet` (binary pixels), `AtLeast` (intensity
   threshold) and `fast_foreground_test`, which swaps in a lookup table for
   8-bit images.
6. **Connected components** — `object_table` labels the 8-connected objects of
   a mask and accumulates their area, bounding box and moments.
7. **Per-object properties and selectors** — descriptors computed in O(1) from
   the table (elongation, circularity, …) and the selectors that pick one
   object (largest, most circular, …).
8. **Convex hulls** — hull vertices, Pick's-theorem pixel count, solidity.

Coordinate convention, shared with `region_*`: `x` is the column and `y` the
row, both normalised to `[0, 1]` so that `0` is the first pixel centre and `1`
the last.
"""
module image2D_object_common

using ImageCore: N0f8
using ..UTCGP: SizedImage, IntensityPixel, BinaryPixel, SegmentPixel

# ---------------------------------------------------------------------------
# 1. Scalar inputs and coordinates
# ---------------------------------------------------------------------------

"""
    clamp_unit(value, default = 0.5) -> Float64

Sanitise a scalar argument coming from an evolved program: clamp it to
`[0, 1]`, and replace `NaN` or `±Inf` by `default`. Every operator taking a
threshold, position, margin or fraction passes it through this first.
"""
@inline function clamp_unit(value::Real, default::Float64 = 0.5)
    v = Float64(value)
    return isfinite(v) ? clamp(v, 0.0, 1.0) : default
end

"""
    position_to_unit(position, n) -> Float64

Continuous pixel position (`1` = first pixel centre, `n` = last) → normalised
coordinate in `[0, 1]`. A single-pixel axis maps to `0.5`.
"""
@inline position_to_unit(position::Float64, n::Int) =
    n <= 1 ? 0.5 : clamp((position - 1.0) / (n - 1), 0.0, 1.0)

"""
    unit_to_position(u, n) -> Float64

Normalised coordinate `u ∈ [0, 1]` → continuous pixel position in `[1, n]`.
"""
@inline unit_to_position(u::Float64, n::Int) = 1.0 + u * (n - 1)

"""
    unit_to_index(u, n) -> Int

Normalised coordinate → index of the nearest pixel, clamped to `1:n`.
"""
@inline unit_to_index(u::Float64, n::Int) = clamp(round(Int, 1.0 + u * (n - 1)), 1, n)

"""
    pixel_value(pixel) -> Float64

The numeric value of a pixel (`IntensityPixel`, `BinaryPixel` → 0/1, …) as a
`Float64`.
"""
@inline pixel_value(pixel) = Float64(pixel)

# ---------------------------------------------------------------------------
# 2. Scratch buffers
# ---------------------------------------------------------------------------

"Key under which each task stores its pool of scratch buffers."
const _SCRATCH_POOL_KEY = :utcgp_image_scratch

"""
    scratch(key, T, dims...) -> Array{T}

A working array reused across calls by the current task, so hot operators do
not allocate (and zero, and later garbage-collect) large temporaries on every
call.

- Each task has its own pool, so this is thread-safe.
- The contents are unspecified on return: callers overwrite or `fill!` it.
- The array is overwritten by the next request for the same `key` in the same
  task: use it only for temporaries that do not outlive the operator, never
  for returned images.
- `scratch(key, T, 0)` is a *growable* vector returned at whatever length it
  currently has; callers `empty!` or `resize!` it.
"""
function scratch(key::Symbol, ::Type{T}, dims::Vararg{Int,N}) where {T,N}
    pool = get!(Dict{Tuple{Symbol,DataType,Int},Any}, task_local_storage(), _SCRATCH_POOL_KEY)::Dict{Tuple{Symbol,DataType,Int},Any}
    slot = (key, T, N)
    buffer = get(pool, slot, nothing)
    growable = N == 1 && dims[1] == 0
    if buffer === nothing || (!growable && size(buffer::Array{T,N}) != dims)
        buffer = Array{T,N}(undef, dims...)
        pool[slot] = buffer
    end
    return buffer::Array{T,N}
end

# ---------------------------------------------------------------------------
# 3. Distance transforms
# ---------------------------------------------------------------------------

"Squared distance used for pixels with no feature anywhere in reach."
const _EDT_FAR = 1.0e20

"""
    squared_distance_map!(D, feature) -> D

Exact squared Euclidean distance from every pixel to the nearest `true` pixel
of `feature`, written into `D`. Pixels with no feature anywhere get a value of
at least `1e20`.

Felzenszwalb & Huttenlocher, linear in the number of pixels:

1. Vertical pass: for each column, the squared distance to the nearest feature
   in the same column (one sweep down, one sweep up).
2. Horizontal pass: along each row, the distance is the lower envelope of the
   parabolas `q ↦ (q − c)² + vertical[c]` over all columns `c`.

The array is transposed between the passes so both read contiguous memory.
"""
function squared_distance_map!(D::AbstractMatrix{Float64}, feature::AbstractMatrix{Bool})
    h, w = size(feature)

    # 1. Vertical pass: squared distance to the nearest feature in the column.
    vertical = scratch(:edt_vertical, Float64, h, w)
    @inbounds for c in 1:w
        last_feature = 0                       # row of the last feature seen going down
        for r in 1:h
            if feature[r, c]
                last_feature = r
                vertical[r, c] = 0.0
            else
                vertical[r, c] = last_feature == 0 ? _EDT_FAR : Float64((r - last_feature)^2)
            end
        end
        last_feature = 0                       # same, going up
        for r in h:-1:1
            if feature[r, c]
                last_feature = r
            elseif last_feature != 0
                d = Float64((last_feature - r)^2)
                d < vertical[r, c] && (vertical[r, c] = d)
            end
        end
    end

    # 2. Horizontal pass on the transposed array: each row becomes a column.
    vertical_t = scratch(:edt_transposed, Float64, w, h)
    permutedims!(vertical_t, vertical, (2, 1))
    vertex = scratch(:edt_v, Int, w)                 # columns whose parabolas form the envelope
    boundary = scratch(:edt_z, Float64, w + 1)       # where each envelope parabola starts
    result_t = scratch(:edt_out_transposed, Float64, w, h)
    @inbounds for r in 1:h
        # Build the lower envelope of the parabolas, left to right.
        k = 1
        vertex[1] = 1
        boundary[1] = -Inf
        boundary[2] = Inf
        for q in 2:w
            fq = vertical_t[q, r] + q * q
            vk = vertex[k]
            intersection = (fq - (vertical_t[vk, r] + vk * vk)) / (2q - 2vk)
            # Pop parabolas hidden by the new one.
            while intersection <= boundary[k]
                k -= 1
                vk = vertex[k]
                intersection = (fq - (vertical_t[vk, r] + vk * vk)) / (2q - 2vk)
            end
            k += 1
            vertex[k] = q
            boundary[k] = intersection
            boundary[k+1] = Inf
        end
        # Read the envelope at every column.
        k = 1
        for q in 1:w
            while boundary[k+1] < q
                k += 1
            end
            vk = vertex[k]
            result_t[q, r] = (q - vk)^2 + vertical_t[vk, r]
        end
    end
    permutedims!(D, result_t, (2, 1))
    return D
end

"""
    squared_distance_map_upto!(D, feature, radius) -> D

Squared Euclidean distance to the nearest `true` of `feature`, **exact wherever
it is at most `radius²`**; larger distances are only guaranteed to stay above
`radius²`. That is all an opening or closing by a disk of that radius needs,
and it is much cheaper than the full transform: along each axis the distance
is the minimum over the `2 radius + 1` shifted copies of the image, computed on
whole contiguous columns (SIMD).
"""
function squared_distance_map_upto!(D::AbstractMatrix{Float64}, feature::AbstractMatrix{Bool}, radius::Int)
    h, w = size(feature)
    # Vertical step: squared distance to a feature at most `radius` rows away.
    vertical = scratch(:edt_vertical, Float64, h, w)
    @inbounds for c in 1:w
        @simd for r in 1:h
            vertical[r, c] = ifelse(feature[r, c], 0.0, _EDT_FAR)
        end
        for d in 1:min(radius, h - 1)
            offset = Float64(d * d)
            @simd for r in 1+d:h          # feature d rows above
                vertical[r, c] = ifelse(feature[r-d, c] & (offset < vertical[r, c]), offset, vertical[r, c])
            end
            @simd for r in 1:h-d          # feature d rows below
                vertical[r, c] = ifelse(feature[r+d, c] & (offset < vertical[r, c]), offset, vertical[r, c])
            end
        end
    end
    # Horizontal step: add dc² for a column dc away and keep the minimum.
    @inbounds for c in 1:w
        @simd for r in 1:h
            D[r, c] = vertical[r, c]
        end
        for dc in 1:radius
            offset = Float64(dc * dc)
            if c - dc >= 1
                @simd for r in 1:h
                    x = offset + vertical[r, c-dc]
                    D[r, c] = ifelse(x < D[r, c], x, D[r, c])
                end
            end
            if c + dc <= w
                @simd for r in 1:h
                    x = offset + vertical[r, c+dc]
                    D[r, c] = ifelse(x < D[r, c], x, D[r, c])
                end
            end
        end
    end
    return D
end

# ---------------------------------------------------------------------------
# 4. Holes: background components not 4-connected to the image border
# ---------------------------------------------------------------------------

"""
    background_holes!(holes, fg) -> (hole_count, hole_pixels)

Find the holes of `fg`: background regions that do not touch the image
border. Background is 4-connected, the dual of 8-connected objects, so a
diagonal gap in an object's outline does not let its hole leak out.

When `holes` is a matrix it is filled with the hole pixels; pass `nothing` to
only count them.

Works like `object_table`, on vertical runs of background pixels merged by
union-find; a merged region is a hole unless one of its runs touches the
border.
"""
function background_holes!(holes, fg::AbstractMatrix{Bool})
    h, w = size(fg)
    # Runs of background pixels: column, first row, last row, union-find parent.
    run_col = empty!(scratch(:hole_run_col, Int32, 0))
    run_r0 = empty!(scratch(:hole_run_r0, Int32, 0))
    run_r1 = empty!(scratch(:hole_run_r1, Int32, 0))
    parent = empty!(scratch(:hole_parent, Int32, 0))
    previous_first = 1          # runs of the previous column are previous_first:previous_last
    previous_last = 0
    @inbounds for c in 1:w
        current_first = length(run_col) + 1
        r = 1
        while r <= h
            if fg[r, c]
                r += 1
                continue
            end
            r0 = r
            while r <= h && !fg[r, c]
                r += 1
            end
            r1 = r - 1
            push!(run_col, c)
            push!(run_r0, r0)
            push!(run_r1, r1)
            id = Int32(length(run_col))
            push!(parent, id)
            # 4-connectivity: merge with previous-column runs sharing a row.
            k = previous_first
            while k <= previous_last && run_r1[k] < r0
                k += 1
            end
            while k <= previous_last && run_r0[k] <= r1
                _union!(parent, id, Int32(k))
                k += 1
            end
            previous_first = max(previous_first, k - 1)
        end
        previous_first = current_first
        previous_last = length(run_col)
    end

    # Per merged region (indexed by its root run): touches the border? area?
    runs = length(run_col)
    border = fill!(resize!(scratch(:hole_border, Bool, 0), runs), false)
    area = fill!(resize!(scratch(:hole_area, Int, 0), runs), 0)
    @inbounds for k in 1:runs
        root = _find_root(parent, Int32(k))
        c = run_col[k]
        touches = c == 1 || c == w || run_r0[k] == 1 || run_r1[k] == h
        touches && (border[root] = true)
        area[root] += run_r1[k] - run_r0[k] + 1
    end
    hole_count = 0
    hole_pixels = 0
    @inbounds for k in 1:runs
        if parent[k] == k && !border[k]          # a root run of an enclosed region
            hole_count += 1
            hole_pixels += area[k]
        end
    end

    if holes !== nothing
        fill!(holes, false)
        @inbounds for k in 1:runs
            border[_find_root(parent, Int32(k))] && continue
            c = run_col[k]
            for r in run_r0[k]:run_r1[k]
                holes[r, c] = true
            end
        end
    end
    return hole_count, hole_pixels
end

# ---------------------------------------------------------------------------
# 5. Foreground tests
# ---------------------------------------------------------------------------

"Foreground test for binary pixels: the stored `Bool`."
struct IsSet end
@inline (::IsSet)(pixel) = pixel.pixel == true

"Foreground test for intensity pixels: value at or above `threshold`."
struct AtLeast
    threshold::Float64
end
@inline (test::AtLeast)(pixel) = Float64(pixel) >= test.threshold

"The foreground test of an image: `IsSet()` for masks, `AtLeast(threshold)` for intensity images."
foreground(::SizedImage{S,<:BinaryPixel}) where {S} = IsSet()
foreground(::SizedImage{S,<:IntensityPixel}, threshold::Real = 0.5) where {S} =
    AtLeast(clamp_unit(threshold))

"""
Lookup table thresholding 8-bit fixed-point intensities: one load per pixel
instead of a conversion and a comparison. Built with the same `Float64`
conversion as `AtLeast`, so results are identical.
"""
struct ThresholdTable8
    table::NTuple{256,Bool}
end
@inline (test::ThresholdTable8)(pixel) = @inbounds test.table[Int(reinterpret(pixel.pixel)) + 1]

"""
    fast_foreground_test(pixels, is_foreground)

The fastest equivalent of `is_foreground` for these pixels: a
`ThresholdTable8` for 8-bit intensity images thresholded with `AtLeast`,
`is_foreground` itself otherwise.
"""
fast_foreground_test(pixels::AbstractArray, is_foreground) = is_foreground
function fast_foreground_test(pixels::AbstractArray{IntensityPixel{N0f8}}, is_foreground::AtLeast)
    return ThresholdTable8(ntuple(k -> Float64(reinterpret(N0f8, UInt8(k - 1))) >= is_foreground.threshold, 256))
end

# ---------------------------------------------------------------------------
# 6. Connected components with moments
# ---------------------------------------------------------------------------

"""
    ObjectTable

Per-object statistics of the 8-connected foreground components of a mask,
from which every per-object descriptor is computed in O(1).

| Field | Meaning |
|:--|:--|
| `h`, `w` | image height (rows) and width (columns) |
| `n` | number of objects |
| `labels` | `labels[r, c]` is `0` on background, the object id otherwise |
| `area` | pixels per object |
| `sum_r`, `sum_c` | sums of row and column indices (centroid = sum / area) |
| `sum_rr`, `sum_cc`, `sum_rc` | sums of `r²`, `c²`, `r·c` (second moments) |
| `min_r`, `max_r`, `min_c`, `max_c` | bounding box |

Ids follow the column-major order of each object's first pixel, which is also
the tie-breaking order of every selector. `labels` lives in a per-task scratch
buffer: it is valid until the next `object_table` call in the same task.
"""
struct ObjectTable
    h::Int
    w::Int
    n::Int
    labels::Matrix{Int32}
    area::Vector{Int}
    sum_r::Vector{Float64}
    sum_c::Vector{Float64}
    sum_rr::Vector{Float64}
    sum_cc::Vector{Float64}
    sum_rc::Vector{Float64}
    min_r::Vector{Int}
    max_r::Vector{Int}
    min_c::Vector{Int}
    max_c::Vector{Int}
end

"Union-find root of `x`, with path halving."
@inline function _find_root(parent::Vector{Int32}, x::Int32)
    @inbounds while parent[x] != x
        parent[x] = parent[parent[x]]
        x = parent[x]
    end
    return x
end

"Merge the sets of `a` and `b`; the smaller id becomes the root, so roots are the first-seen runs."
@inline function _union!(parent::Vector{Int32}, a::Int32, b::Int32)
    ra = _find_root(parent, a)
    rb = _find_root(parent, b)
    ra == rb && return
    @inbounds if ra < rb
        parent[rb] = ra
    else
        parent[ra] = rb
    end
    return
end

"""
    object_table(pixels, is_foreground) -> ObjectTable

Label the 8-connected components of the pixels for which `is_foreground` holds
and accumulate their area, bounding box and moments.

Works on vertical runs: each column is split into runs of foreground pixels, a
run is merged (union-find) with the runs of the previous column that overlap it
or touch it diagonally, and each run's moments are added in closed form. Per
pixel only the foreground test remains.
"""
function object_table(pixels::AbstractMatrix, is_foreground)
    return _object_table(pixels, fast_foreground_test(pixels, is_foreground))
end

object_table(img::SizedImage, is_foreground) = object_table(img.img, is_foreground)

function _object_table(pixels::AbstractMatrix, is_foreground::P) where {P}
    h, w = size(pixels)

    # Pass 1: find runs and merge them. Each run has a column, a first and a
    # last row, and a union-find parent.
    run_col = empty!(scratch(:run_col, Int32, 0))
    run_r0 = empty!(scratch(:run_r0, Int32, 0))
    run_r1 = empty!(scratch(:run_r1, Int32, 0))
    parent = empty!(scratch(:run_parent, Int32, 0))
    previous_first = 1          # runs of the previous column are previous_first:previous_last
    previous_last = 0
    @inbounds for c in 1:w
        current_first = length(run_col) + 1
        r = 1
        while r <= h
            if !is_foreground(pixels[r, c])
                r += 1
                continue
            end
            r0 = r
            while r <= h && is_foreground(pixels[r, c])
                r += 1
            end
            r1 = r - 1
            push!(run_col, c)
            push!(run_r0, r0)
            push!(run_r1, r1)
            id = Int32(length(run_col))
            push!(parent, id)
            # 8-connectivity: merge with previous-column runs touching rows r0-1:r1+1.
            k = previous_first
            while k <= previous_last && run_r1[k] < r0 - 1
                k += 1
            end
            while k <= previous_last && run_r0[k] <= r1 + 1
                _union!(parent, id, Int32(k))
                k += 1
            end
            # Later runs of this column start below r1 + 1, so the next search
            # in the previous column can resume where this one stopped.
            previous_first = max(previous_first, k - 1)
        end
        previous_first = current_first
        previous_last = length(run_col)
    end

    # Give each merged set a compact id 1:n, in order of first appearance
    # (roots are always the smallest run index of their set).
    runs = length(run_col)
    remap = fill!(resize!(scratch(:run_remap, Int32, 0), runs), Int32(0))
    n = 0
    @inbounds for k in 1:runs
        root = _find_root(parent, Int32(k))
        if remap[root] == 0
            n += 1
            remap[root] = Int32(n)
        end
        remap[k] = remap[root]
    end

    # Pass 2: paint the labels and add each run's moments in closed form.
    labels = fill!(scratch(:labels, Int32, h, w), Int32(0))
    area = zeros(Int, n)
    sum_r = zeros(Float64, n)
    sum_c = zeros(Float64, n)
    sum_rr = zeros(Float64, n)
    sum_cc = zeros(Float64, n)
    sum_rc = zeros(Float64, n)
    min_r = fill(typemax(Int), n)
    max_r = zeros(Int, n)
    min_c = fill(typemax(Int), n)
    max_c = zeros(Int, n)
    @inbounds for k in 1:runs
        id = remap[k]
        c = Int(run_col[k])
        r0 = Int(run_r0[k])
        r1 = Int(run_r1[k])
        len = r1 - r0 + 1
        for r in r0:r1
            labels[r, c] = id
        end
        sum_rows = (r0 + r1) * len / 2                                          # Σ r over r0:r1
        sum_rows_sq = (r1 * (r1 + 1) * (2r1 + 1) - (r0 - 1) * r0 * (2r0 - 1)) / 6   # Σ r²
        fc = Float64(c)
        area[id] += len
        sum_r[id] += sum_rows
        sum_c[id] += fc * len
        sum_rr[id] += sum_rows_sq
        sum_cc[id] += fc * fc * len
        sum_rc[id] += fc * sum_rows
        min_r[id] = min(min_r[id], r0)
        max_r[id] = max(max_r[id], r1)
        min_c[id] = min(min_c[id], c)
        max_c[id] = max(max_c[id], c)
    end

    return ObjectTable(h, w, n, labels, area, sum_r, sum_c, sum_rr, sum_cc,
        sum_rc, min_r, max_r, min_c, max_c)
end

# ---------------------------------------------------------------------------
# 7. Per-object properties (all O(1)) and selectors
# ---------------------------------------------------------------------------

"Centroid row of object `i` (pixel position)."
@inline centroid_row(t::ObjectTable, i::Int) = @inbounds t.sum_r[i] / t.area[i]
"Centroid column of object `i` (pixel position)."
@inline centroid_col(t::ObjectTable, i::Int) = @inbounds t.sum_c[i] / t.area[i]
"Normalised `x` (column) of object `i`'s centroid."
@inline unit_x(t::ObjectTable, i::Int) = position_to_unit(centroid_col(t, i), t.w)
"Normalised `y` (row) of object `i`'s centroid."
@inline unit_y(t::ObjectTable, i::Int) = position_to_unit(centroid_row(t, i), t.h)
"Bounding-box height of object `i`, in pixels."
@inline box_height(t::ObjectTable, i::Int) = @inbounds t.max_r[i] - t.min_r[i] + 1
"Bounding-box width of object `i`, in pixels."
@inline box_width(t::ObjectTable, i::Int) = @inbounds t.max_c[i] - t.min_c[i] + 1

"""
Central second moments `(v_rr, v_cc, v_rc)` of object `i`. Each variance gets
`1/12`, the variance of a unit pixel, so a single pixel is not a point.
"""
@inline function covariance(t::ObjectTable, i::Int)
    @inbounds begin
        a = Float64(t.area[i])
        mr = t.sum_r[i] / a
        mc = t.sum_c[i] / a
        v_rr = max(t.sum_rr[i] / a - mr * mr, 0.0) + 1 / 12
        v_cc = max(t.sum_cc[i] / a - mc * mc, 0.0) + 1 / 12
        v_rc = t.sum_rc[i] / a - mr * mc
    end
    return v_rr, v_cc, v_rc
end

"Eigenvalues `(λmax, λmin)` of object `i`'s covariance: the variance along its main and minor axes."
@inline function eigenvalues(t::ObjectTable, i::Int)
    v_rr, v_cc, v_rc = covariance(t, i)
    half_trace = (v_rr + v_cc) / 2
    disc = sqrt(max(half_trace * half_trace - (v_rr * v_cc - v_rc * v_rc), 0.0))
    return half_trace + disc, max(half_trace - disc, 0.0)
end

"Fraction of image pixels covered by the object."
@inline area_fraction(t::ObjectTable, i::Int) = @inbounds t.area[i] / (t.h * t.w)
"Bounding-box width as a fraction of the image width."
@inline width_fraction(t::ObjectTable, i::Int) = box_width(t, i) / t.w
"Bounding-box height as a fraction of the image height."
@inline height_fraction(t::ObjectTable, i::Int) = box_height(t, i) / t.h

"`1 − sqrt(λmin / λmax)`: `0` for isotropic shapes, towards `1` for lines."
@inline function elongation(t::ObjectTable, i::Int)
    l1, l2 = eigenvalues(t, i)
    return clamp(1.0 - sqrt(l2 / l1), 0.0, 1.0)
end

"Moment circularity `A / (2π (v_rr + v_cc))`: `1` for a disk, lower otherwise."
@inline function circularity(t::ObjectTable, i::Int)
    v_rr, v_cc, _ = covariance(t, i)
    return @inbounds clamp(t.area[i] / (2π * (v_rr + v_cc)), 0.0, 1.0)
end

"Area over bounding-box area: `1` for axis-aligned rectangles."
@inline extent(t::ObjectTable, i::Int) =
    @inbounds t.area[i] / (box_width(t, i) * box_height(t, i))

"""
Principal-axis angle from the x axis towards increasing rows, mapped to
`[0, 1]`: `0.5` is horizontal, `0` and `1` are both vertical. Shapes without a
principal axis (disks, squares) return `0.5`.
"""
@inline function orientation(t::ObjectTable, i::Int)
    v_rr, v_cc, v_rc = covariance(t, i)
    anisotropy = abs(v_cc - v_rr) + 2abs(v_rc)
    anisotropy <= 1e-9 * (v_rr + v_cc) && return 0.5
    θ = 0.5 * atan(2v_rc, v_cc - v_rr)
    return clamp((θ + π / 2) / π, 0.0, 1.0)
end

"Squared normalised distance from object `i`'s centroid to the point `(x, y)`."
@inline function distance2_to(t::ObjectTable, i::Int, x::Float64, y::Float64)
    dx = unit_x(t, i) - x
    dy = unit_y(t, i) - y
    return dx * dx + dy * dy
end

"Normalised distance from object `i`'s centroid to the nearest other centroid (`√2` when alone)."
function isolation(t::ObjectTable, i::Int)
    t.n <= 1 && return sqrt(2.0)
    best = Inf
    xi, yi = unit_x(t, i), unit_y(t, i)
    for j in 1:t.n
        j == i && continue
        dx = unit_x(t, j) - xi
        dy = unit_y(t, j) - yi
        best = min(best, dx * dx + dy * dy)
    end
    return sqrt(best)
end

"Id of the object maximising `score(t, i)`; ties go to the lowest id; `0` when there are no objects."
@inline function argmax_object(score::F, t::ObjectTable) where {F}
    t.n == 0 && return 0
    best = 1
    best_score = score(t, 1)
    for i in 2:t.n
        s = score(t, i)
        if s > best_score
            best = i
            best_score = s
        end
    end
    return best
end

"""
The fixed object selectors, as `(name, score, description)`: the selected
object is the one maximising `score(table, id)`. Every `<sel>` operator of the
object, zoom and descriptor libraries comes from this list.
"""
const SELECTORS = (
    (:largest, (t, i) -> t.area[i], "greatest pixel area"),
    (:smallest, (t, i) -> -t.area[i], "least pixel area"),
    (:most_elongated, elongation, "greatest elongation"),
    (:least_elongated, (t, i) -> -elongation(t, i), "least elongation"),
    (:most_circular, circularity, "greatest moment circularity"),
    (:least_circular, (t, i) -> -circularity(t, i), "least moment circularity"),
    (:most_rectangular, extent, "greatest bounding-box fill (extent)"),
    (:least_rectangular, (t, i) -> -extent(t, i), "least bounding-box fill (extent)"),
    (:widest, box_width, "widest bounding box"),
    (:narrowest, (t, i) -> -box_width(t, i), "narrowest bounding box"),
    (:tallest, box_height, "tallest bounding box"),
    (:shortest, (t, i) -> -box_height(t, i), "shortest bounding box"),
    (:topmost, (t, i) -> -centroid_row(t, i), "topmost centroid"),
    (:bottommost, centroid_row, "bottommost centroid"),
    (:leftmost, (t, i) -> -centroid_col(t, i), "leftmost centroid"),
    (:rightmost, centroid_col, "rightmost centroid"),
    (:most_central, (t, i) -> -distance2_to(t, i, 0.5, 0.5), "centroid closest to the image centre"),
    (:most_peripheral, (t, i) -> distance2_to(t, i, 0.5, 0.5), "centroid farthest from the image centre"),
    (:most_isolated, isolation, "centroid farthest from any other centroid"),
    (:least_isolated, (t, i) -> -isolation(t, i), "centroid closest to another centroid"),
)

"Second-largest object by area; the largest when there is only one."
function second_largest(t::ObjectTable)
    t.n <= 1 && return t.n
    first_id = argmax_object((tt, i) -> tt.area[i], t)
    return argmax_object((tt, i) -> i == first_id ? typemin(Int) : tt.area[i], t)
end

"`name => select(table) -> id` for every fixed selector, plus `second_largest`."
const SELECTOR_FUNCTIONS = (
    map(entry -> entry[1] => (t -> argmax_object(entry[2], t)), SELECTORS)...,
    :second_largest => second_largest,
)

"Human-readable criterion of each selector, used in operator descriptions."
const SELECTOR_DESCRIPTIONS = Dict{Symbol,String}(
    map(entry -> entry[1] => entry[3], SELECTORS)...,
    :second_largest => "second-greatest pixel area",
)

"""
    select_rank_area(t, k)

Object at relative rank `k ∈ [0, 1]` by area: `0` smallest, `1` largest.
"""
function select_rank_area(t::ObjectTable, k::Float64)
    t.n == 0 && return 0
    order = sortperm(t.area)
    return order[clamp(round(Int, 1 + k * (t.n - 1)), 1, t.n)]
end

"Object whose centroid is closest to the normalised point `(x, y)`."
select_nearest(t::ObjectTable, x::Float64, y::Float64) =
    argmax_object((tt, i) -> -distance2_to(tt, i, x, y), t)

"Object whose `property(t, id)` is closest to `target`."
select_like(property::F, t::ObjectTable, target::Float64) where {F} =
    argmax_object((tt, i) -> -abs(property(tt, i) - target), t)

"Mean of the `source` pixels inside each object (same size as the labelled mask)."
function object_means(t::ObjectTable, source::AbstractMatrix)
    size(source) == (t.h, t.w) ||
        throw(DimensionMismatch("source and mask must have the same size"))
    sums = zeros(Float64, t.n)
    @inbounds for index in eachindex(t.labels)
        l = t.labels[index]
        l == 0 && continue
        sums[l] += pixel_value(source[index])
    end
    @inbounds for i in 1:t.n
        sums[i] /= t.area[i]
    end
    return sums
end

"Brightest (`direction = 1`) or darkest (`direction = -1`) object by its mean `source` value."
function select_by_mean(t::ObjectTable, source::AbstractMatrix, direction::Float64)
    t.n == 0 && return 0
    means = object_means(t, source)
    return argmax_object((tt, i) -> direction * means[i], t)
end

# ---------------------------------------------------------------------------
# 8. Convex hulls
# ---------------------------------------------------------------------------

"""
    convex_hull_points(points) -> Vector{Tuple{Int,Int}}

Vertices of the convex hull of `(row, col)` points, counter-clockwise
(Andrew's monotone chain). Two or fewer distinct points are returned as is.
"""
function convex_hull_points(points::Vector{Tuple{Int,Int}})
    pts = sort!(unique(points))
    length(pts) <= 2 && return pts
    # > 0 when o → a → b turns counter-clockwise.
    cross(o, a, b) = (a[1] - o[1]) * (b[2] - o[2]) - (a[2] - o[2]) * (b[1] - o[1])
    lower = Tuple{Int,Int}[]
    for p in pts
        while length(lower) >= 2 && cross(lower[end-1], lower[end], p) <= 0
            pop!(lower)
        end
        push!(lower, p)
    end
    upper = Tuple{Int,Int}[]
    for p in Iterators.reverse(pts)
        while length(upper) >= 2 && cross(upper[end-1], upper[end], p) <= 0
            pop!(upper)
        end
        push!(upper, p)
    end
    return vcat(lower[1:end-1], upper[1:end-1])
end

"""
    extreme_points(labels, id, r0, r1, c0, c1) -> Vector{Tuple{Int,Int}}

The leftmost and rightmost pixel of each row of object `id` (or of all
non-zero pixels when `id == 0`) within the box `r0:r1 × c0:c1`. The convex
hull of a shape is the hull of these points, which are far fewer than its
pixels.
"""
function extreme_points(labels::AbstractMatrix, id::Integer, r0, r1, c0, c1)
    points = Tuple{Int,Int}[]
    @inbounds for r in r0:r1
        first_c = 0
        last_c = 0
        for c in c0:c1
            l = labels[r, c]
            (id == 0 ? l != 0 : l == id) || continue
            first_c == 0 && (first_c = c)
            last_c = c
        end
        first_c == 0 && continue
        push!(points, (r, first_c))
        last_c != first_c && push!(points, (r, last_c))
    end
    return points
end

"""
    hull_pixel_count(hull) -> Int

Number of pixels inside or on the convex polygon `hull` (whose vertices are
pixel centres), by Pick's theorem: `A + B/2 + 1`, with `A` the shoelace area
and `B` the number of pixel centres on the boundary.
"""
function hull_pixel_count(hull::Vector{Tuple{Int,Int}})
    n = length(hull)
    n == 0 && return 0
    n == 1 && return 1
    twice_area = 0
    boundary = 0
    for k in 1:n
        a = hull[k]
        b = hull[k == n ? 1 : k + 1]
        twice_area += a[2] * b[1] - b[2] * a[1]
        boundary += gcd(abs(b[1] - a[1]), abs(b[2] - a[2]))
    end
    n == 2 && return boundary ÷ 2 + 1          # a segment: its edge was counted twice
    return (abs(twice_area) + boundary) ÷ 2 + 1
end

"Solidity of object `i`: its area over the pixel count of its convex hull (`1` for convex shapes)."
function solidity(t::ObjectTable, i::Int)
    hull = convex_hull_points(extreme_points(t.labels, i, t.min_r[i], t.max_r[i], t.min_c[i], t.max_c[i]))
    return @inbounds clamp(t.area[i] / max(hull_pixel_count(hull), 1), 0.0, 1.0)
end

end
