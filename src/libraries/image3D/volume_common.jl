"""
Shared machinery for volume (3D grayscale) libraries.

# Sections

| Section | Main functions |
|:--|:--|
| Values and foreground | `voxel_values`, `voxel_foreground`, `to_pixels` |
| Connected components | `VolumeTable`, `volume_table`, `centroid`, `covariance3` |
| Holes | `volume_holes!` |
| Distance transforms | `volume_distance_map!` (exact), `volume_distance_map_upto!` (bounded) |
| Separable filters | `box_extremum!`, `cross_extremum!`, `gaussian_kernel`, `separable_convolve!` |
| Resampling | `resample_box` (trilinear), `resample_box_nearest` |

# Conventions

Axes extend the 2D convention: dimension 1 is the row (`y`), dimension 2 the
column (`x`), dimension 3 the slice (`z`). Normalised coordinates map the
first voxel centre to `0` and the last to `1`.

Objects are 26-connected; background regions (holes) are 6-connected, the
dual connectivity, so a diagonal gap never lets a cavity leak out.

# Performance notes

Julia arrays are column-major: `A[r, c, s]` and `A[r+1, c, s]` are adjacent
in memory. The hot loops therefore run along `y` (rows) innermost, and
operations along `x` or `z` are written as whole-array shifts
(`_combine_shift!`) so they also read memory contiguously. Temporary arrays
come from per-task `scratch` buffers, keyed by a `Symbol`; a buffer is reused
by the next call with the same key in the same task.
"""
module image3D_volume_common

using ImageCore: N0f8
using ..UTCGP: SizedImage, IntensityPixel, BinaryPixel, SegmentPixel, AbstractPixel
using ..image2D_object_common:
    scratch, clamp_unit, pixel_value, IsSet, AtLeast, fast_foreground_test, _find_root, _union!
using ..image2D_zoom: to_storage, zero_pixel

"Stand-in for an infinite squared distance (no feature voxel reachable)."
const _FAR = 1.0e20

# ---------------------------------------------------------------------------
# Values and foreground
# ---------------------------------------------------------------------------

"Voxel values as a `Float64` array in per-task scratch (`key` names the buffer)."
function voxel_values(key::Symbol, voxels::AbstractArray{P,3}) where {P}
    values = scratch(key, Float64, size(voxels)...)
    @inbounds @simd for i in eachindex(voxels, values)
        values[i] = pixel_value(voxels[i])
    end
    return values
end

"""
Foreground of `voxels` as a `Bool` array in scratch. `is_foreground` is a
predicate object such as `IsSet()` (binary voxels) or `AtLeast(t)`
(intensity ≥ `t`).
"""
function voxel_foreground(key::Symbol, voxels::AbstractArray{P,3}, is_foreground) where {P}
    fg = scratch(key, Bool, size(voxels)...)
    predicate = fast_foreground_test(voxels, is_foreground)
    @inbounds for i in eachindex(voxels, fg)
        fg[i] = predicate(voxels[i])
    end
    return fg
end

"Pixel array of type `P` from `Float64` values (stored with rounding and clamping) or from a `Bool` mask."
function to_pixels(::Type{IntensityPixel{T}}, values::AbstractArray{Float64,3}) where {T}
    out = Array{IntensityPixel{T},3}(undef, size(values))
    @inbounds for i in eachindex(values)
        out[i] = IntensityPixel{T}(to_storage(T, values[i]))
    end
    return out
end
to_pixels(::Type{BinaryPixel{T}}, fg::AbstractArray{Bool,3}) where {T} = BinaryPixel{T}.(fg)

# ---------------------------------------------------------------------------
# Connected components (26-connectivity), run based
# ---------------------------------------------------------------------------

"""
    VolumeTable

Per-object statistics of the 26-connected components of a 3D mask. Objects
are numbered `1:n`; every per-object field is indexed by that number.

| Field | Meaning |
|:--|:--|
| `dims` | size `(h, w, d)` of the volume |
| `n` | number of objects |
| `labels` | object number of each voxel, `0` for background (scratch: valid until the next `volume_table` call in the same task) |
| `area` | voxel count of each object |
| `s1` | `n × 3`: Σ y, Σ x, Σ z over the object's voxels (first moments) |
| `s2` | `n × 6`: Σ y², Σ x², Σ z², Σ yx, Σ yz, Σ xz (second moments) |
| `lo`, `hi` | `n × 3`: bounding box, first and last index along y, x, z |
"""
struct VolumeTable
    dims::NTuple{3,Int}
    n::Int
    labels::Array{Int32,3}
    area::Vector{Int}
    s1::Matrix{Float64}
    s2::Matrix{Float64}
    lo::Matrix{Int}
    hi::Matrix{Int}
end

"""
    volume_table(voxels, is_foreground) -> VolumeTable

Label the 26-connected components of a 3D array (foreground decided by
`is_foreground`, as in `voxel_foreground`) and gather their statistics.
"""
function volume_table(voxels::AbstractArray{P,3}, is_foreground) where {P}
    return _volume_table(voxels, fast_foreground_test(voxels, is_foreground))
end

"""
Run-based labelling behind `volume_table`.

1. Each `(x, z)` column of voxels is split into *runs*: maximal stretches of
   foreground along `y`. Run `k` is stored as `run_col[k]`, `run_slice[k]`,
   `run_r0[k]:run_r1[k]`; the runs of column `(c, s)` are
   `first_run[c, s]:last_run[c, s]`.
2. When a run is created it is merged (union–find on `parent`) with the runs
   of the four already-visited neighbouring columns whose rows overlap it or
   touch it diagonally — the 26-connected neighbours.
3. A second pass numbers the union–find roots `1:n`, writes the labels and
   accumulates the statistics run by run (closed-form sums over a run, so the
   cost is per run, not per voxel).
"""
function _volume_table(voxels::AbstractArray{P,3}, fg::F) where {P,F}
    h, w, d = size(voxels)
    run_col = empty!(scratch(:vol_run_col, Int32, 0))
    run_slice = empty!(scratch(:vol_run_slice, Int32, 0))
    run_r0 = empty!(scratch(:vol_run_r0, Int32, 0))
    run_r1 = empty!(scratch(:vol_run_r1, Int32, 0))
    parent = empty!(scratch(:vol_parent, Int32, 0))
    first_run = scratch(:vol_first_run, Int32, w, d)
    last_run = scratch(:vol_last_run, Int32, w, d)
    @inbounds for s in 1:d, c in 1:w
        first_run[c, s] = Int32(length(run_col) + 1)
        r = 1
        while r <= h
            if !fg(voxels[r, c, s])
                r += 1
                continue
            end
            r0 = r                                    # run covers rows r0:(r - 1)
            while r <= h && fg(voxels[r, c, s])
                r += 1
            end
            push!(run_col, c)
            push!(run_slice, s)
            push!(run_r0, r0)
            push!(run_r1, r - 1)
            id = Int32(length(run_col))
            push!(parent, id)
            # Already-visited neighbouring columns: left, and the three of the previous slice.
            for (nc, ns) in ((c - 1, s), (c - 1, s - 1), (c, s - 1), (c + 1, s - 1))
                (1 <= nc <= w && 1 <= ns <= d) || continue
                for k in first_run[nc, ns]:last_run[nc, ns]
                    # Run k touches rows r0 - 1 … r (one row of diagonal slack on each side).
                    if run_r0[k] <= r && run_r1[k] >= r0 - 1
                        _union!(parent, id, Int32(k))
                    end
                end
            end
        end
        last_run[c, s] = Int32(length(run_col))
    end

    # Number the roots 1:n; `remap[k]` becomes the object number of run k.
    runs = length(run_col)
    remap = fill!(resize!(scratch(:vol_remap, Int32, 0), runs), Int32(0))
    n = 0
    @inbounds for k in 1:runs
        root = _find_root(parent, Int32(k))
        if remap[root] == 0
            n += 1
            remap[root] = Int32(n)
        end
        remap[k] = remap[root]
    end
    labels = fill!(scratch(:vol_labels, Int32, h, w, d), Int32(0))
    area = zeros(Int, n)
    s1 = zeros(n, 3)
    s2 = zeros(n, 6)
    lo = fill(typemax(Int), n, 3)
    hi = zeros(Int, n, 3)
    @inbounds for k in 1:runs
        id = remap[k]
        c = Int(run_col[k])
        s = Int(run_slice[k])
        r0 = Int(run_r0[k])
        r1 = Int(run_r1[k])
        len = r1 - r0 + 1
        for r in r0:r1
            labels[r, c, s] = id
        end
        row_sum = (r0 + r1) * len / 2                                              # Σ r over r0:r1
        row_square_sum = (r1 * (r1 + 1) * (2r1 + 1) - (r0 - 1) * r0 * (2r0 - 1)) / 6  # Σ r² over r0:r1
        area[id] += len
        s1[id, 1] += row_sum
        s1[id, 2] += c * len
        s1[id, 3] += s * len
        s2[id, 1] += row_square_sum
        s2[id, 2] += c * c * len
        s2[id, 3] += s * s * len
        s2[id, 4] += c * row_sum
        s2[id, 5] += s * row_sum
        s2[id, 6] += c * s * len
        lo[id, 1] = min(lo[id, 1], r0); hi[id, 1] = max(hi[id, 1], r1)
        lo[id, 2] = min(lo[id, 2], c); hi[id, 2] = max(hi[id, 2], c)
        lo[id, 3] = min(lo[id, 3], s); hi[id, 3] = max(hi[id, 3], s)
    end
    return VolumeTable((h, w, d), n, labels, area, s1, s2, lo, hi)
end

"Centroid of object `i` as `(y, x, z)` voxel positions."
centroid(t::VolumeTable, i::Int) = (t.s1[i, 1] / t.area[i], t.s1[i, 2] / t.area[i], t.s1[i, 3] / t.area[i])

"""
Covariance matrix of object `i` (axes y, x, z). Each variance gets `+1/12`,
the variance of a unit-width voxel, so a one-voxel-thick object is not
treated as infinitely thin.
"""
function covariance3(t::VolumeTable, i::Int)
    a = Float64(t.area[i])
    my, mx, mz = centroid(t, i)
    vyy = max(t.s2[i, 1] / a - my^2, 0.0) + 1 / 12
    vxx = max(t.s2[i, 2] / a - mx^2, 0.0) + 1 / 12
    vzz = max(t.s2[i, 3] / a - mz^2, 0.0) + 1 / 12
    vyx = t.s2[i, 4] / a - my * mx
    vyz = t.s2[i, 5] / a - my * mz
    vxz = t.s2[i, 6] / a - mx * mz
    return [vyy vyx vyz; vyx vxx vxz; vyz vxz vzz]
end

# ---------------------------------------------------------------------------
# Holes: background components (6-connected) not touching the border
# ---------------------------------------------------------------------------

"""
    volume_holes!(holes, fg) -> (count, voxels)

Cavities of `fg`: 6-connected background components that do not touch the
volume border. Returns their number and total voxel count, and fills `holes`
with them when it is an array (pass `nothing` to only count).

Same run-based union–find as `_volume_table`, on background runs. With
6-connectivity a run only merges with the left and previous-slice columns,
and only when the row ranges really overlap (no diagonal slack). A component
is a border component when any of its runs touches a face of the volume.
"""
function volume_holes!(holes, fg::AbstractArray{Bool,3})
    h, w, d = size(fg)
    run_col = empty!(scratch(:vh_run_col, Int32, 0))
    run_slice = empty!(scratch(:vh_run_slice, Int32, 0))
    run_r0 = empty!(scratch(:vh_run_r0, Int32, 0))
    run_r1 = empty!(scratch(:vh_run_r1, Int32, 0))
    parent = empty!(scratch(:vh_parent, Int32, 0))
    first_run = scratch(:vh_first_run, Int32, w, d)
    last_run = scratch(:vh_last_run, Int32, w, d)
    @inbounds for s in 1:d, c in 1:w
        first_run[c, s] = Int32(length(run_col) + 1)
        r = 1
        while r <= h
            if fg[r, c, s]
                r += 1
                continue
            end
            r0 = r                                    # background run covers rows r0:(r - 1)
            while r <= h && !fg[r, c, s]
                r += 1
            end
            push!(run_col, c)
            push!(run_slice, s)
            push!(run_r0, r0)
            push!(run_r1, r - 1)
            id = Int32(length(run_col))
            push!(parent, id)
            for (nc, ns) in ((c - 1, s), (c, s - 1))           # face neighbours already visited
                (nc >= 1 && ns >= 1) || continue
                for k in first_run[nc, ns]:last_run[nc, ns]
                    (run_r0[k] <= r - 1 && run_r1[k] >= r0) && _union!(parent, id, Int32(k))
                end
            end
        end
        last_run[c, s] = Int32(length(run_col))
    end
    # Per root: does the component touch the border, and how many voxels has it?
    runs = length(run_col)
    touches_border = fill!(resize!(scratch(:vh_border, Bool, 0), runs), false)
    area = fill!(resize!(scratch(:vh_area, Int, 0), runs), 0)
    @inbounds for k in 1:runs
        root = _find_root(parent, Int32(k))
        c, s = run_col[k], run_slice[k]
        (c == 1 || c == w || s == 1 || s == d || run_r0[k] == 1 || run_r1[k] == h) && (touches_border[root] = true)
        area[root] += run_r1[k] - run_r0[k] + 1
    end
    count = 0
    voxels = 0
    @inbounds for k in 1:runs
        if parent[k] == k && !touches_border[k]             # k is a root of an enclosed component
            count += 1
            voxels += area[k]
        end
    end
    if holes !== nothing
        fill!(holes, false)
        @inbounds for k in 1:runs
            touches_border[_find_root(parent, Int32(k))] && continue
            for r in run_r0[k]:run_r1[k]
                holes[r, run_col[k], run_slice[k]] = true
            end
        end
    end
    return count, voxels
end

# ---------------------------------------------------------------------------
# Distance transforms
# ---------------------------------------------------------------------------

"Squared distance along `y` to the nearest `true` in each column (`_FAR` when the column has none): a downward then an upward sweep."
function _column_distances!(D::Array{Float64,3}, feature::AbstractArray{Bool,3})
    h, w, d = size(feature)
    @inbounds for s in 1:d, c in 1:w
        last = 0                                      # row of the last feature seen, 0 = none yet
        for r in 1:h
            if feature[r, c, s]
                last = r
                D[r, c, s] = 0.0
            else
                D[r, c, s] = last == 0 ? _FAR : Float64((r - last)^2)
            end
        end
        last = 0
        for r in h:-1:1
            if feature[r, c, s]
                last = r
            elseif last != 0
                x = Float64((last - r)^2)
                x < D[r, c, s] && (D[r, c, s] = x)
            end
        end
    end
    return D
end

"""
    _envelope!(out, f, vertex, boundary_num, boundary_den, n)

1D squared distance transform of `f[1:n]` (Felzenszwalb–Huttenlocher):
`out[q] = min over p of (q − p)² + f[p]`, the lower envelope of the parabolas
rooted at each `p`.

- `vertex[1:k]` holds the positions `p` of the parabolas on the envelope.
- Parabola `vertex[j]` is lowest between boundaries `j` and `j + 1`. Each
  boundary is a fraction `boundary_num[j] / boundary_den[j]`
  (`boundary_den > 0`), compared by cross-multiplication so the loop has no
  division.
"""
function _envelope!(out::Vector{Float64}, f::Vector{Float64}, vertex::Vector{Int}, boundary_num::Vector{Float64}, boundary_den::Vector{Float64}, n::Int)
    k = 1
    @inbounds begin
        vertex[1] = 1
        boundary_num[1] = -Inf
        boundary_den[1] = 1.0
        boundary_num[2] = Inf
        boundary_den[2] = 1.0
        for q in 2:n
            fq = f[q] + q * q
            vk = vertex[k]
            # Intersection of the parabolas at q and vk, as num / den.
            num = fq - (f[vk] + vk * vk)
            den = Float64(2q - 2vk)
            # The new parabola hides the last one while it intersects before that one's boundary.
            while num * boundary_den[k] <= boundary_num[k] * den
                k -= 1
                vk = vertex[k]
                num = fq - (f[vk] + vk * vk)
                den = Float64(2q - 2vk)
            end
            k += 1
            vertex[k] = q
            boundary_num[k] = num
            boundary_den[k] = den
            boundary_num[k+1] = Inf
            boundary_den[k+1] = 1.0
        end
        # Read the envelope off from left to right.
        k = 1
        for q in 1:n
            while boundary_num[k+1] < q * boundary_den[k+1]
                k += 1
            end
            out[q] = (q - vertex[k])^2 + f[vertex[k]]
        end
    end
    return out
end

"""
    volume_distance_map!(D, feature) -> D

Exact squared Euclidean distance from each voxel to the nearest `true` voxel
of `feature`: a column pass along `y`, then lower envelopes along `x` and `z`.
Volumes without any feature get values of at least `1e20`.
"""
function volume_distance_map!(D::Array{Float64,3}, feature::AbstractArray{Bool,3})
    h, w, d = size(feature)
    _column_distances!(D, feature)
    # Lines along x and z are made contiguous by moving that axis first, then moved back.
    Dx = scratch(:vdt_x, Float64, w, h, d)
    permutedims!(Dx, D, (2, 1, 3))
    _envelope_columns!(Dx)
    permutedims!(D, Dx, (2, 1, 3))
    Dz = scratch(:vdt_z3, Float64, d, h, w)
    permutedims!(Dz, D, (3, 1, 2))
    _envelope_columns!(Dz)
    permutedims!(D, Dz, (2, 3, 1))
    return D
end

"Apply `_envelope!` along dimension 1 to every column of a 3D array, in place."
function _envelope_columns!(A::Array{Float64,3})
    n, a, b = size(A)
    f = scratch(:vdt_f, Float64, n)
    out = scratch(:vdt_out, Float64, n)
    vertex = scratch(:vdt_v, Int, n)
    boundary_num = scratch(:vdt_znum, Float64, n + 1)
    boundary_den = scratch(:vdt_zden, Float64, n + 1)
    @inbounds for j in 1:b, i in 1:a
        all_zero = true
        for q in 1:n
            f[q] = A[q, i, j]
            all_zero &= f[q] == 0.0
        end
        all_zero && continue                                   # every voxel is a feature: nothing to do
        _envelope!(out, f, vertex, boundary_num, boundary_den, n)
        for q in 1:n
            A[q, i, j] = out[q]
        end
    end
    return A
end

"""
    volume_distance_map_upto!(D, feature, radius) -> D

Squared distance to the nearest `true` voxel, exact wherever it is at most
`radius²` and otherwise only guaranteed to exceed it. Cheaper than the exact
transform for small radii (morphology by distance thresholding).

Each axis is a minimum over `2 radius + 1` shifted copies, `k² + A[shifted by
k]`, computed on whole contiguous columns: first `y` (on the feature mask
directly), then `x`, then `z`.
"""
function volume_distance_map_upto!(D::Array{Float64,3}, feature::AbstractArray{Bool,3}, radius::Int)
    h, w, d = size(feature)
    A = scratch(:vdtu_a, Float64, h, w, d)
    @inbounds for s in 1:d, c in 1:w
        @simd for r in 1:h
            A[r, c, s] = ifelse(feature[r, c, s], 0.0, _FAR)
        end
        for k in 1:min(radius, h - 1)
            offset = Float64(k * k)
            @simd for r in 1+k:h                       # a feature k rows above
                A[r, c, s] = ifelse(feature[r-k, c, s] & (offset < A[r, c, s]), offset, A[r, c, s])
            end
            @simd for r in 1:h-k                       # a feature k rows below
                A[r, c, s] = ifelse(feature[r+k, c, s] & (offset < A[r, c, s]), offset, A[r, c, s])
            end
        end
    end
    B = scratch(:vdtu_b, Float64, h, w, d)
    _min_plus_axis!(B, A, radius, 2)
    _min_plus_axis!(D, B, radius, 3)
    return D
end

"`dst = min over |k| ≤ radius of k² + src shifted by k along axis` (`axis` 2 or 3)."
function _min_plus_axis!(dst::Array{Float64,3}, src::Array{Float64,3}, radius::Int, axis::Int)
    copyto!(dst, src)
    for k in 1:radius
        offset = Float64(k * k)
        add_min = (current, shifted) -> (x = offset + shifted; ifelse(x < current, x, current))
        _combine_shift!(dst, src, axis, k, add_min)
        _combine_shift!(dst, src, axis, -k, add_min)
    end
    return dst
end

# ---------------------------------------------------------------------------
# Separable filters
# ---------------------------------------------------------------------------

"""
    _combine_shift!(dst, src, axis, k, combine)

`dst[i] = combine(dst[i], src[i shifted by k along axis])` wherever the
shifted position is inside the volume, for `axis` 2 or 3. A shift along these
axes is a constant offset in linear memory (`k·h` along x, `k·h·w` along z),
so each slice (axis 2) or the whole volume (axis 3) is one long contiguous,
vectorised loop.
"""
function _combine_shift!(dst::Array{Float64,3}, src::Array{Float64,3}, axis::Int, k::Int, combine::F) where {F}
    h, w, d = size(src)
    if axis == 2
        lo, hi = max(1, 1 - k), min(w, w - k)          # columns whose neighbour c + k exists
        lo > hi && return dst
        offset = k * h
        @inbounds for s in 1:d
            base = (s - 1) * h * w
            @simd ivdep for i in base+(lo-1)*h+1:base+hi*h
                dst[i] = combine(dst[i], src[i+offset])
            end
        end
    else
        lo, hi = max(1, 1 - k), min(d, d - k)          # slices whose neighbour s + k exists
        lo > hi && return dst
        offset = k * h * w
        @inbounds @simd ivdep for i in (lo-1)*h*w+1:hi*h*w
            dst[i] = combine(dst[i], src[i+offset])
        end
    end
    return dst
end

"Branch-free minimum of two `Float64`s (vectorises better than `min`, which handles `NaN` and `-0.0`)."
@inline fmin(a::Float64, b::Float64) = ifelse(a < b, a, b)
"Branch-free maximum of two `Float64`s."
@inline fmax(a::Float64, b::Float64) = ifelse(a > b, a, b)

"""
    box_extremum!(dst, src, radius, take) -> dst

Separable box minimum (`take = fmin`) or maximum (`fmax`) over a
`(2r+1)³` cube clipped at the border: one pass of shifted comparisons per
axis.
"""
function box_extremum!(dst::Array{Float64,3}, src::Array{Float64,3}, radius::Int, take::T) where {T}
    after_y = scratch(:box_a, Float64, size(src)...)
    after_x = scratch(:box_b, Float64, size(src)...)
    _shift_extremum!(after_y, src, radius, take, 1)
    _shift_extremum!(after_x, after_y, radius, take, 2)
    _shift_extremum!(dst, after_x, radius, take, 3)
    return dst
end

"`dst = take` over `src` shifted by `-radius:radius` along `axis` (clipped at the border)."
function _shift_extremum!(dst, src, radius::Int, take::T, axis::Int) where {T}
    h, w, d = size(src)
    copyto!(dst, src)
    if axis == 1
        @inbounds for s in 1:d, c in 1:w, k in 1:radius
            @simd ivdep for r in 1+k:h
                dst[r, c, s] = take(dst[r, c, s], src[r-k, c, s])
            end
            @simd ivdep for r in 1:h-k
                dst[r, c, s] = take(dst[r, c, s], src[r+k, c, s])
            end
        end
    else
        for k in 1:radius
            _combine_shift!(dst, src, axis, k, take)
            _combine_shift!(dst, src, axis, -k, take)
        end
    end
    return dst
end

"Minimum (`take = fmin`) or maximum (`fmax`) over each voxel and its 6 face neighbours."
function cross_extremum!(dst::Array{Float64,3}, src::Array{Float64,3}, take::T) where {T}
    h, w, d = size(src)
    @inbounds for s in 1:d, c in 1:w
        @simd ivdep for r in 1:h
            dst[r, c, s] = src[r, c, s]
        end
        @simd for r in 2:h                             # neighbour above
            dst[r, c, s] = take(dst[r, c, s], src[r-1, c, s])
        end
        @simd for r in 1:h-1                           # neighbour below
            dst[r, c, s] = take(dst[r, c, s], src[r+1, c, s])
        end
        for (cc, ss) in ((c - 1, s), (c + 1, s), (c, s - 1), (c, s + 1))   # left, right, previous, next slice
            (1 <= cc <= w && 1 <= ss <= d) || continue
            @simd ivdep for r in 1:h
                dst[r, c, s] = take(dst[r, c, s], src[r, cc, ss])
            end
        end
    end
    return dst
end

"`(weights, radius)`: normalised 1D Gaussian weights for `sigma`, over `-radius:radius` with `radius = ⌈3σ⌉` (at least 1)."
function gaussian_kernel(sigma::Float64)
    radius = max(1, ceil(Int, 3sigma))
    kernel = [exp(-k^2 / (2sigma^2)) for k in -radius:radius]
    return kernel ./ sum(kernel), radius
end

"""
    separable_convolve!(dst, src, kernel, radius) -> dst

Convolve with the same symmetric 1D kernel (`length 2 radius + 1`) along each
axis; borders replicate the edge voxel.
"""
function separable_convolve!(dst::Array{Float64,3}, src::Array{Float64,3}, kernel::Vector{Float64}, radius::Int)
    after_y = scratch(:conv_a, Float64, size(src)...)
    after_x = scratch(:conv_b, Float64, size(src)...)
    _convolve_axis!(after_y, src, kernel, radius, 1)
    _convolve_axis!(after_x, after_y, kernel, radius, 2)
    _convolve_axis!(dst, after_x, kernel, radius, 3)
    return dst
end

"""
1D convolution along `axis` with edge replication: for each tap `k`, add
`weight · src[shifted by k]`. Positions whose shifted neighbour is outside
the volume use the edge voxel instead.
"""
function _convolve_axis!(dst, src, kernel, radius::Int, axis::Int)
    h, w, d = size(src)
    fill!(dst, 0.0)
    if axis == 1
        @inbounds for s in 1:d, c in 1:w
            for (k, weight) in zip(-radius:radius, kernel)
                # Interior rows need no clamping, so the loop vectorises.
                lo = max(1, 1 - k)
                hi = min(h, h - k)
                @simd ivdep for r in lo:hi
                    dst[r, c, s] += weight * src[r+k, c, s]
                end
                for r in 1:lo-1                         # neighbour above the volume: top edge
                    dst[r, c, s] += weight * src[1, c, s]
                end
                for r in hi+1:h                         # neighbour below the volume: bottom edge
                    dst[r, c, s] += weight * src[h, c, s]
                end
            end
        end
        return dst
    end
    n = axis == 2 ? w : d
    for (k, weight) in zip(-radius:radius, kernel)
        _combine_shift!(dst, src, axis, k, (acc, shifted) -> acc + weight * shifted)
        # Positions j whose neighbour j + k falls outside replicate the edge.
        for j in (k > 0 ? (max(1, n - k + 1):n) : (1:min(n, -k)))
            edge = k > 0 ? n : 1
            @inbounds if axis == 2
                for s in 1:d
                    @simd ivdep for r in 1:h
                        dst[r, j, s] += weight * src[r, edge, s]
                    end
                end
            else
                for c in 1:w
                    @simd ivdep for r in 1:h
                        dst[r, c, j] += weight * src[r, c, edge]
                    end
                end
            end
        end
    end
    return dst
end

# ---------------------------------------------------------------------------
# Resampling a box back to full size
# ---------------------------------------------------------------------------

"""
    _source_position(i, n, lo, hi) -> (a, b, fraction)

When the index range `lo:hi` is stretched to `n` output voxels, output voxel
`i` (centre-aligned) reads between source indices `a` and `b = a + 1` (or `a`
at the end), at `fraction` of the way from `a` to `b`.
"""
@inline function _source_position(i::Int, n::Int, lo::Int, hi::Int)
    position = clamp(lo - 0.5 + (i - 0.5) * (hi - lo + 1) / n, Float64(lo), Float64(hi))
    a = unsafe_trunc(Int, position)
    return a, min(a + 1, hi), position - a
end

"""
Trilinear resize of `src[lo[1]:hi[1], lo[2]:hi[2], lo[3]:hi[3]]` to
`size(src)`, one axis at a time: z first (on the small crop), then x, then y.
"""
function resample_box(src::Array{Float64,3}, lo::NTuple{3,Int}, hi::NTuple{3,Int})
    h, w, d = size(src)
    crop_h = hi[1] - lo[1] + 1
    crop_w = hi[2] - lo[2] + 1
    # Stage 1, along z: (crop_h, crop_w, d).
    along_z = scratch(:resample_1, Float64, crop_h, crop_w, d)
    @inbounds for s in 1:d
        a, b, f = _source_position(s, d, lo[3], hi[3])
        for c in 1:crop_w, r in 1:crop_h
            x = src[lo[1]+r-1, lo[2]+c-1, a]
            along_z[r, c, s] = x + f * (src[lo[1]+r-1, lo[2]+c-1, b] - x)
        end
    end
    # Stage 2, along x: (crop_h, w, d). Source columns are shifted to crop coordinates.
    along_x = scratch(:resample_2, Float64, crop_h, w, d)
    @inbounds for s in 1:d, c in 1:w
        a, b, f = _source_position(c, w, lo[2], hi[2])
        a -= lo[2] - 1
        b -= lo[2] - 1
        @simd for r in 1:crop_h
            x = along_z[r, a, s]
            along_x[r, c, s] = x + f * (along_z[r, b, s] - x)
        end
    end
    # Stage 3, along y: (h, w, d). Row sources are precomputed once, reused for every column.
    out = Array{Float64,3}(undef, h, w, d)
    rows_a = scratch(:resample_ra, Int, h)
    rows_b = scratch(:resample_rb, Int, h)
    rows_f = scratch(:resample_rf, Float64, h)
    @inbounds for r in 1:h
        a, b, f = _source_position(r, h, lo[1], hi[1])
        rows_a[r], rows_b[r], rows_f[r] = a - lo[1] + 1, b - lo[1] + 1, f
    end
    @inbounds for s in 1:d, c in 1:w, r in 1:h
        x = along_x[rows_a[r], c, s]
        out[r, c, s] = x + rows_f[r] * (along_x[rows_b[r], c, s] - x)
    end
    return out
end

"Nearest-neighbour resize of the box `lo:hi` of any 3D array (e.g. binary pixels) to the array's full size."
function resample_box_nearest(src::AbstractArray{T,3}, lo::NTuple{3,Int}, hi::NTuple{3,Int}) where {T}
    dims = size(src)
    # Source index of output i when l:u is stretched to n (centre-aligned, integer arithmetic).
    source_index(i, n, l, u) = l + ((2i - 1) * (u - l + 1)) ÷ (2n)
    out = similar(src)
    @inbounds for s in 1:dims[3]
        ss = source_index(s, dims[3], lo[3], hi[3])
        for c in 1:dims[2]
            cc = source_index(c, dims[2], lo[2], hi[2])
            for r in 1:dims[1]
                out[r, c, s] = src[source_index(r, dims[1], lo[1], hi[1]), cc, ss]
            end
        end
    end
    return out
end

end
