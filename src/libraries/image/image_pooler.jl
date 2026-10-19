"""
Sliding-window pooling: reduce a window at every position, keeping the image's
size.

# Bundles

- [`bundle_image2DIntensity_pooler_factory`](@ref)
- [`bundle_image2DBinary_pooler_factory`](@ref)
- [`bundle_image2DSegment_pooler_factory`](@ref)

The exhaustive, always-current list of operators in each bundle is on the
[Bundle Catalogue](@ref) page.

# How it is computed

Every pooler runs the same three steps (`_pool_into!`):

1. the image's values are copied once into a plain array (task scratch);
2. the statistic of every `k × k` window is computed into a small grid, with an
   algorithm that does not re-read the `k²` pixels of each window:
   - mean, std: summed-area tables of the raw integers (4 reads per window),
     with the original `mean` / `std` on the rare windows that sit on a
     rounding boundary, so results are identical to computing every window;
   - max, min: doubling spans on the raw integers (about 2·log₂k vectorised
     passes over the image);
   - median, interquartile range, unique count, argmax/argmin count, mode:
     a sliding histogram for 8-bit and binary images with windows of side 4
     or more (the window moves by updating `k` leaving and `k` entering
     values), a reused sort buffer otherwise (small windows, `N0f16`, floats,
     labels);
3. the grid is stretched back to the image size, rescaled for the count
   poolers, and written into the output pixels in one pass.

Nothing is allocated per window; working arrays come from task scratch.

Call tree:

    <pooler>(img, k, stride; out)
    └── _pool_into!(pixels, image_pixels, k, stride, statistic)
        ├── _window_and_stride(k, stride, image_pixels)
        ├── pixel_values!(values, image_pixels)                    pooling_common.jl
        ├── _pool_grid!(grid, values, windows, statistic, P)       one method per statistic family
        │   ├── mean, std:   _summed_area! (exact integers), _mean_grid! / _std_grid!
        │   │                (original mean/std on windows at a rounding boundary)
        │   ├── max, min:    _extreme_along_rows!, _extreme_along_columns! (doubling, raw integers)
        │   └── order stats: _order_grid!(…, _window_order_method(T, k))
        │       ├── SlidingHistogram: _histogram_grid! → _histogram_statistic
        │       │                   → _rank_value / _rank_pair → _rank_level
        │       │                   (IQR: _histogram_quantile → _quantile_of_ranks)
        │       └── SortedBuffer:     _buffer_grid!    → _buffer_statistic
        ├── _rescale01!(grid)                                      count poolers only
        └── _write_stretched!(pixels, grid)
"""
module image_pooler

using ..UTCGP: _factory_type_symbol, @serialized_factory

using Statistics: mean, std, middle, quantile!
using ImageCore: N0f8, FixedPoint
using ..UTCGP: FunctionBundle, append_method!, output_pixels, image_result, scratch
using ..UTCGP:
    SizedImage2D, SImageND, _get_image_type, _validate_factory_type, _get_image_pixel_type,
    _get_image_tuple_size, IntensityPixel, BinaryPixel, SegmentPixel
using ..image_pooling_common: pixel_values!, mode!, unique_count!, median_select!, pooled_pixel

fallback(args...) = return nothing
"""
    bundle_image2DIntensity_pooler_factory

Sliding-window pooling of intensity images: `meanpool`, `maxpool`, `minpool`,
`stdpool`, `medianpool`, `uniquecountpool`, `argmaxcountpool`,
`argmincountpool`, `iqrpool`.

How it works, with `op(img, k, stride)` (defaults `k = 2`, `stride = 1`):

1. a `k × k` window is placed at every `stride`-th position where it fits
   entirely inside the image (no padding), and reduced to one number;
2. this smaller grid of results is stretched back to the image's size with
   nearest-neighbour sampling.

So the output keeps the input's size, but it is a slightly rescaled version
of the window results: with `k = 5` on 28 pixels there are 24 window
positions per row, stretched over 28 pixels. With a larger `stride` the
output looks blocky. `k` is clamped to `1` … the shorter side, `stride` to
`1` … the longer side; `NaN`/`Inf` use the defaults.

The three count-based poolers (`uniquecountpool`, `argmaxcountpool`,
`argmincountpool`) are min–max rescaled to `[0, 1]` over the image.

Compare `bundle_image2DIntensity_pool_factory`, which uses non-overlapping
blocks.

This is a *factory* bundle: each entry is a function of a type that returns the
method specialised for it, so the same operator can be instantiated for several
image or element types. See [Libraries](@ref) for how factories are specialised
into a library.
"""
bundle_image2DIntensity_pooler_factory = FunctionBundle(fallback)
"""
    bundle_image2DBinary_pooler_factory

Sliding-window pooling of masks. See
[`bundle_image2DIntensity_pooler_factory`](@ref).

This is a *factory* bundle: each entry is a function of a type that returns the
method specialised for it, so the same operator can be instantiated for several
image or element types. See [Libraries](@ref) for how factories are specialised
into a library.
"""
bundle_image2DBinary_pooler_factory = FunctionBundle(fallback)
"""
    bundle_image2DSegment_pooler_factory

Sliding-window pooling of label maps. See
[`bundle_image2DIntensity_pooler_factory`](@ref). `meanpool` returns the most
frequent label of each window (a mean of label numbers would invent labels);
the other reducers work on the label numbers and are rounded to integers.

This is a *factory* bundle: each entry is a function of a type that returns the
method specialised for it, so the same operator can be instantiated for several
image or element types. See [Libraries](@ref) for how factories are specialised
into a library.
"""
bundle_image2DSegment_pooler_factory = FunctionBundle(fallback)

# ---------------------------------------------------------------------------
# 1. What is computed on each window
# ---------------------------------------------------------------------------

"What a pooler computes on each window (one singleton type per statistic)."
abstract type WindowStatistic end
struct WindowMean <: WindowStatistic end
struct WindowStd <: WindowStatistic end
struct WindowMax <: WindowStatistic end
struct WindowMin <: WindowStatistic end
struct WindowMedian <: WindowStatistic end
struct WindowIQR <: WindowStatistic end
struct WindowUniqueCount <: WindowStatistic end
struct WindowArgmaxCount <: WindowStatistic end
struct WindowArgminCount <: WindowStatistic end
struct WindowMode <: WindowStatistic end

"Statistics that need the window's values in order (or their counts), not just a sum or an extreme."
const OrderStatistic = Union{WindowMedian,WindowIQR,WindowUniqueCount,WindowArgmaxCount,WindowArgminCount,WindowMode}

"Counts are rescaled to `[0, 1]` over the image (min–max); other statistics keep their values."
_rescaled(::WindowStatistic) = false
_rescaled(::Union{WindowUniqueCount,WindowArgmaxCount,WindowArgminCount}) = true

"""
    _for_pixel(statistic, P) -> statistic

For label maps the mean of label numbers would invent labels: `meanpool` uses
the most frequent label instead. Example: `_for_pixel(WindowMean(),
SegmentPixel{Int}) == WindowMode()`.
"""
_for_pixel(statistic::WindowStatistic, ::Type) = statistic
_for_pixel(::WindowMean, ::Type{<:SegmentPixel}) = WindowMode()

# ---------------------------------------------------------------------------
# 2. Window positions
# ---------------------------------------------------------------------------

"""
Window size and stride from the evolved parameters: rounded and clamped
(`k` to `1` … the shorter side, `stride` to `1` … the longer side); `NaN` and
`±Inf` give the defaults `2` and `1`.

Example on a 28 × 28 image: `(4.6, 0.2) → (5, 1)`, `(NaN, 3) → (2, 3)`.
"""
function _window_and_stride(k::Number, stride::Number, img::AbstractMatrix)
    k_int = _rounded_within(k, 1.0, Float64(minimum(size(img))), 2)
    stride_int = _rounded_within(stride, 1.0, Float64(maximum(size(img))), 1)
    return k_int, stride_int
end

"`x` rounded and clamped to `[low, high]`; `default` when `x` is `NaN` or `±Inf`."
function _rounded_within(x::Number, low::Float64, high::Float64, default::Int)
    value = Float64(x)
    if !isfinite(value)
        return default
    end
    return round(Int, clamp(value, low, high))
end

"""
    WindowGrid(h, w, k, stride)

The `k × k` windows of an `h × w` image: their top rows `rows` and left
columns `cols`, every `stride`-th position where the window fits entirely.

Example: `h = 6`, `k = 3`, `stride = 2` → `rows = 1:2:4`, i.e. windows over
rows 1–3 and 3–5 (a window starting at row 5 would not fit).
"""
struct WindowGrid
    k::Int
    rows::StepRange{Int,Int}
    cols::StepRange{Int,Int}
end
WindowGrid(h::Int, w::Int, k::Int, stride::Int) = WindowGrid(k, 1:stride:(h - k + 1), 1:stride:(w - k + 1))

# ---------------------------------------------------------------------------
# 3. The pooler
# ---------------------------------------------------------------------------

"""
    _pool_into!(pixels, image_pixels, k, stride, statistic) -> pixels

The whole pooler: the statistic of every window, stretched back to the image
size, written into `pixels` (the output, or a new array).

Example (`k = 2`, `stride = 1`, mean) on the 3 × 3 image
`[0 0 1; 0 0 1; 1 1 1]`: the 2 × 2 windows give the grid `[0 0.5; 0.5 0.75]`,
stretched to 3 × 3 as `[0 0.5 0.5; 0.5 0.75 0.75; 0.5 0.75 0.75]` (output
rows and columns 1, 2, 3 read grid indices 1, 2, 2; see `_stretch_index`).
"""
function _pool_into!(pixels, image_pixels, k::Number, stride::Number, statistic::WindowStatistic)
    k_int, stride_int = _window_and_stride(k, stride, image_pixels)
    h, w = size(image_pixels)
    windows = WindowGrid(h, w, clamp(k_int, 1, min(h, w)), max(stride_int, 1))
    values = scratch(:pooler_values, fieldtype(eltype(image_pixels), 1), h, w)
    pixel_values!(values, image_pixels)
    grid = scratch(:pooler_grid, Float64, length(windows.rows), length(windows.cols))
    _pool_grid!(grid, values, windows, statistic, eltype(pixels))
    if _rescaled(statistic)
        _rescale01!(grid)
    end
    return _write_stretched!(pixels, grid)
end

# ---------------------------------------------------------------------------
# 4. Mean and std: exact integer sums, original arithmetic near rounding boundaries
#
# The original computed every window as `mean(window)` / `std(window)`: k²
# reads per window. Here each window's sums come from summed-area tables of
# the raw storage integers (`N0f8` 0…255, `Bool` 0/1, labels), which are exact,
# so the value is correct to the last bit or two. The pixel is that value
# rounded to the output's levels, and it equals the original's pixel unless
# the value lies within the original's own rounding error of a rounding
# boundary (e.g. a 2 × 2 mean of raw 10, 10, 11, 11 = 10.5, exactly halfway
# between two levels). Those few windows are recomputed exactly as the
# original did, so the output is identical.
# ---------------------------------------------------------------------------

"Integer behind a stored value: raw storage for fixed point (`N0f8` 0.502 → 128), 0/1 for `Bool`, the label itself."
_raw(x::FixedPoint) = Int(reinterpret(x))
_raw(x::Integer) = Int(x)

"Value of one raw unit: `1/255` for `N0f8`, `1/65535` for `N0f16`, `1` for `Bool` and labels."
_raw_unit(::Type{T}) where {T<:FixedPoint} = 1.0 / reinterpret(oneunit(T))
_raw_unit(::Type{<:Integer}) = 1.0

"""
    _summed_area!(table, values, term) -> table

`table[r + 1, c + 1]` is the sum of `term(raw value)` over `values[1:r, 1:c]`
in exact integers; row 1 and column 1 are zero. Then the sum over any
rectangle takes four reads (`_area_sum`), whatever its size.

Example: raw values `[1 2; 3 4]`, `term = identity` →
`table = [0 0 0; 0 1 3; 0 4 10]`.
"""
function _summed_area!(table::AbstractMatrix{Int}, values, term::F) where {F}
    h, w = size(values)
    table[1, :] .= 0
    table[:, 1] .= 0
    @inbounds for c in 1:w
        column_sum = 0                                # Σ term(raw) over values[1:r, c]
        for r in 1:h
            column_sum += term(_raw(values[r, c]))
            table[r + 1, c + 1] = table[r + 1, c] + column_sum
        end
    end
    return table
end

"""
    _area_sum(table, r, c, k) -> sum over the `k × k` window whose top-left is `(r, c)`

Example with the table of `[1 2; 3 4]` (see `_summed_area!`):
`_area_sum(table, 1, 1, 2) = 10 − 0 − 0 + 0 = 10`.
"""
@inline function _area_sum(table, r::Int, c::Int, k::Int)
    @inbounds return table[r + k, c + k] - table[r, c + k] - table[r + k, c] + table[r, c]
end

_square(x) = x * x

"The `k × k` window of `values` whose top-left is `(r, c)` (a view)."
@inline _window(values, r::Int, c::Int, k::Int) = view(values, r:(r + k - 1), c:(c + k - 1))

"Most statistics do not depend on the output pixel type."
_pool_grid!(grid, values, windows::WindowGrid, statistic::WindowStatistic, ::Type) =
    _pool_grid!(grid, values, windows, statistic)

function _pool_grid!(grid, values, windows::WindowGrid, ::WindowMean, ::Type{P}) where {P}
    sums = _summed_area!(scratch(:pooler_sums, Int, (size(values) .+ 1)...), values, identity)
    return _mean_grid!(grid, values, sums, windows, P, _largest_level(values))
end

"""
    _mean_grid!(grid, values, sums, windows, P, largest) -> grid

Mean of each window from its exact raw sum; windows whose mean lies within
`_rounding_guard` of a boundary of `P`'s levels get the original's
`mean(window)` instead.

Example (`N0f8`, `k = 2`): raw 10, 10, 11, 11 sum to 42, mean 10.5 raw units,
exactly halfway between two levels: recomputed with `mean(window)`. Raw 10,
11, 11, 11 (mean 10.75) is a quarter level from the boundary: kept.
"""
function _mean_grid!(grid, values, sums, windows::WindowGrid, ::Type{P}, largest::Int) where {P}
    k = windows.k
    n = k^2
    unit = _raw_unit(eltype(values))
    guard = _rounding_guard(n, largest)
    for (j, c) in enumerate(windows.cols), (i, r) in enumerate(windows.rows)
        value = _area_sum(sums, r, c, k) * unit / n
        if _boundary_distance(P, value) < guard
            value = Float64(mean(_window(values, r, c, k)))      # the original computation
        end
        grid[i, j] = value
    end
    return grid
end

function _pool_grid!(grid, values, windows::WindowGrid, ::WindowStd, ::Type{P}) where {P}
    sums = _summed_area!(scratch(:pooler_sums, Int, (size(values) .+ 1)...), values, identity)
    squares = _summed_area!(scratch(:pooler_squares, Int, (size(values) .+ 1)...), values, _square)
    return _std_grid!(grid, values, sums, squares, windows, P, _largest_level(values))
end

"""
    _std_grid!(grid, values, sums, squares, windows, P, largest) -> grid

Sample standard deviation of each window from its exact raw sum `s` and sum
of squares `q` (`n = k²` pixels): `n(n − 1) · variance = n·q − s²` is an exact
integer, so `std = sqrt((n·q − s²) / (n(n − 1)))` raw units, `0` for a 1-pixel
window. Windows within `_rounding_guard` of a boundary of `P`'s levels get the
original's `std(window)` instead.

Example: raw values `[1, 2, 3, 4]`: `s = 10`, `q = 30`, `n·q − s² = 20` →
`sqrt(20 / 12) ≈ 1.29` raw units.
"""
function _std_grid!(grid, values, sums, squares, windows::WindowGrid, ::Type{P}, largest::Int) where {P}
    k = windows.k
    n = k^2
    unit = _raw_unit(eltype(values))
    guard = _rounding_guard(n, largest)
    for (j, c) in enumerate(windows.cols), (i, r) in enumerate(windows.rows)
        value = _std_from_sums(_area_sum(sums, r, c, k), _area_sum(squares, r, c, k), n) * unit
        if _boundary_distance(P, value) < guard
            value = _original_std(_window(values, r, c, k))
        end
        grid[i, j] = value
    end
    return grid
end

"Standard deviation in raw units from exact sums (`0` for one value); the numerator is exact in 128-bit integers."
function _std_from_sums(s::Int, q::Int, n::Int)
    n == 1 && return 0.0
    return sqrt(Float64(Int128(n) * q - Int128(s)^2) / (n * (n - 1)))
end

"The original window std: `std(window)`, `0` for a 1-pixel window."
_original_std(window) = length(window) > 1 ? Float64(std(window)) : 0.0

"""
    _boundary_distance(P, x) -> distance, in output levels, from `x` to the nearest value where its pixel changes

- intensities round to the storage's levels (`N0f8`: steps of 1/255), which
  change halfway between two levels;
- masks are set from `0.5`;
- labels round to the nearest integer, changing at halves.

Example: `_boundary_distance(IntensityPixel{N0f8}, 10.5/255) == 0`,
`_boundary_distance(BinaryPixel{Bool}, 0.75) == 0.25`.
"""
_boundary_distance(::Type{IntensityPixel{T}}, x::Float64) where {T} = _half_distance(x / _raw_unit(T))
_boundary_distance(::Type{<:BinaryPixel}, x::Float64) = abs(x - 0.5)
_boundary_distance(::Type{<:SegmentPixel}, x::Float64) = _half_distance(x)

"Distance from `levels` to the nearest half-integer. Example: `3.4 → 0.1`, `3.5 → 0`."
_half_distance(levels::Float64) = abs(levels - floor(levels) - 0.5)

"""
    _rounding_guard(n, largest) -> half-width of the recomputation band, in levels

`mean` / `std` over `n` values of at most `largest` levels are off by at most
about `n · eps · largest` levels. Outside 8 times that from a rounding
boundary, the original and the exact value round to the same pixel.

Example: 8-bit, `k = 31` (`n = 961`, `largest = 255`): `≈ 4.4e-10` levels.
"""
_rounding_guard(n::Int, largest::Int) = 8 * n * eps(Float64) * max(largest, 1)

"Largest absolute raw value of the image (`255` at most for `N0f8`), for `_rounding_guard`."
_largest_level(values) = maximum(x -> abs(_raw(x)), values)

# ---------------------------------------------------------------------------
# 5. Max and min: doubling spans on the raw integers
#
# The extreme of a window is separable (down the columns, then along the
# rows) and idempotent (overlapping parts do not matter), so it is built by
# doubling: the extreme over spans of 1, 2, 4, … rows, then two overlapping
# spans cover exactly `k`. That is about log₂(k) passes per axis, each a plain
# loop over contiguous memory on raw integers (`UInt8` for `N0f8`), which the
# compiler vectorises: 3–5× faster than van Herk–Gil-Werman at 224², whose
# per-element bookkeeping does not vectorise.
# ---------------------------------------------------------------------------

_pool_grid!(grid, values, windows::WindowGrid, ::WindowMax) = _extreme_grid!(grid, values, windows, max)
_pool_grid!(grid, values, windows::WindowGrid, ::WindowMin) = _extreme_grid!(grid, values, windows, min)

"""
    _extreme_grid!(grid, values, windows, take) -> grid

Max (`take = max`) or min of every window: the image's raw integers are
copied into a working array, reduced in place down the columns then along
the rows (`_extreme_along_rows!`, `_extreme_along_columns!`), and the
requested windows are read back as values.
"""
function _extreme_grid!(grid, values, windows::WindowGrid, take::F) where {F}
    work = scratch(:pooler_extremes, _raw_type(eltype(values)), size(values)...)
    work .= _raw_storage.(values)
    _extreme_along_rows!(work, windows.k, take)
    _extreme_along_columns!(work, windows.k, size(work, 1) - windows.k + 1, take)
    return _sample_windows!(grid, work, windows, eltype(values))
end

"Integer type the extremes are computed on: the raw storage of fixed point (`UInt8` for `N0f8`), the type itself otherwise."
_raw_type(::Type{T}) where {T<:FixedPoint} = typeof(reinterpret(zero(T)))
_raw_type(::Type{T}) where {T} = T

"Raw storage of a value (`N0f8` 0.502 → `0x80`); `Bool` and labels unchanged. Order is preserved."
_raw_storage(x::FixedPoint) = reinterpret(x)
_raw_storage(x) = x

"The value of type `T` stored as `raw` (inverse of `_raw_storage`)."
_from_raw(::Type{T}, raw) where {T<:FixedPoint} = reinterpret(T, raw)
_from_raw(::Type{T}, raw) where {T} = raw

"""
    _extreme_along_rows!(work, k, take) -> work

In place, `work[r, c]` becomes `take` over `work[r : r + k − 1, c]`, for the
rows `r ≤ h − k + 1` (the others are left as working values).

Doubling: after the step with span `s`, `work[r, c]` covers rows
`r : r + 2s − 1`; once the span reaches the largest power of 2 not above `k`,
one last step joins two overlapping spans.

Example, `k = 3`, `take = max`, column `[2 7 1 4]`: the pairs step gives
`[7 7 4 4]` (rows 1–2, 2–3, 3–4; the last entry is left over); then
`max(work[r], work[r + 1])` for `r ≤ 2` → `[7 7]` = max over rows 1–3 and 2–4.
"""
function _extreme_along_rows!(work, k::Int, take::F) where {F}
    h = size(work, 1)
    span = 1
    while 2span <= k
        _combine_rows!(work, span, h - 2span + 1, take)       # covers rows r : r + 2span − 1
        span *= 2
    end
    rest = k - span                                           # 0 ≤ rest < span: overlapping spans
    rest > 0 && _combine_rows!(work, rest, h - k + 1, take)
    return work
end

"`work[r, c] = take(work[r, c], work[r + offset, c])` for rows `1:last_row`, every column."
function _combine_rows!(work, offset::Int, last_row::Int, take::F) where {F}
    @inbounds for c in axes(work, 2)
        # Reads are `offset` rows ahead of the writes, so updating in place is safe.
        @simd ivdep for r in 1:last_row
            work[r, c] = take(work[r, c], work[r + offset, c])
        end
    end
    return work
end

"""
    _extreme_along_columns!(work, k, rows, take) -> work

As `_extreme_along_rows!`, across columns: `work[r, c]` becomes `take` over
`work[r, c : c + k − 1]`, for the first `rows` rows and the columns
`c ≤ w − k + 1`. Each step reads whole contiguous column segments.
"""
function _extreme_along_columns!(work, k::Int, rows::Int, take::F) where {F}
    w = size(work, 2)
    span = 1
    while 2span <= k
        _combine_columns!(work, span, w - 2span + 1, rows, take)
        span *= 2
    end
    rest = k - span
    rest > 0 && _combine_columns!(work, rest, w - k + 1, rows, take)
    return work
end

"`work[r, c] = take(work[r, c], work[r, c + offset])` for columns `1:last_column`, rows `1:rows`."
function _combine_columns!(work, offset::Int, last_column::Int, rows::Int, take::F) where {F}
    @inbounds for c in 1:last_column
        @simd ivdep for r in 1:rows
            work[r, c] = take(work[r, c], work[r, c + offset])
        end
    end
    return work
end

"Keep the windows at the requested stride: `grid[i, j]` = the value of type `T` stored at the window `(rows[i], cols[j])`."
function _sample_windows!(grid, results, windows::WindowGrid, ::Type{T}) where {T}
    for (j, c) in enumerate(windows.cols), (i, r) in enumerate(windows.rows)
        @inbounds grid[i, j] = Float64(_from_raw(T, results[r, c]))
    end
    return grid
end

# ---------------------------------------------------------------------------
# 6. Order statistics: sliding histogram or sorted buffer, by storage type
# ---------------------------------------------------------------------------

"Order statistics from counts per value, updated as the window slides (few distinct values)."
struct SlidingHistogram end
"Order statistics from a copy of the window in one reused buffer (many distinct values)."
struct SortedBuffer end

"""
    _window_order_method(T, k) -> SlidingHistogram() or SortedBuffer()

8-bit and binary values have few levels (256, 2): a histogram of the window is
cheap to keep up to date, and pays off once the window is large enough
(`k ≥ 4`): for a tiny window, scanning the histogram's levels costs more than
sorting a few values. `N0f16` (65 536 levels), floats and labels always use a
sorted buffer. Other storage types get the buffer automatically.

Measured on 224 × 224 `N0f8`, stride 1 (ms per call, histogram vs buffer):
median `k = 2`: 5.8 vs 1.7, `k = 4`: 5.9 vs 8.5, `k = 7`: 4.8 vs 20.5;
IQR `k = 2`: 10.7 vs 3.6, `k = 7`: 11.6 vs 47.9.
"""
function _window_order_method(::Type{<:Union{N0f8,Bool}}, k::Int)
    if k >= _HISTOGRAM_MIN_WINDOW
        return SlidingHistogram()
    end
    return SortedBuffer()
end
_window_order_method(::Type, k::Int) = SortedBuffer()

"Smallest window side for which the sliding histogram beats the sorted buffer (see `_window_order_method`)."
const _HISTOGRAM_MIN_WINDOW = 4

_pool_grid!(grid, values, windows::WindowGrid, statistic::OrderStatistic) =
    _order_grid!(grid, values, windows, statistic, _window_order_method(eltype(values), windows.k))

# 6a. Sliding histogram ---------------------------------------------------

"Number of levels and the level of a value (1-based): `N0f8` raw byte + 1, `Bool` 1 or 2."
_levels(::Type{N0f8}) = 256
_levels(::Type{Bool}) = 2
@inline _level(x::N0f8) = Int(reinterpret(x)) + 1
@inline _level(x::Bool) = Int(x) + 1
"The value of a level. Example: `_level_value(N0f8, 256) == 1.0N0f8`."
@inline _level_value(::Type{N0f8}, level::Int) = reinterpret(N0f8, UInt8(level - 1))
@inline _level_value(::Type{Bool}, level::Int) = level == 2

"""
Counts of each level in the current window, and how many levels are present
(`distinct`, kept up to date as values enter and leave). Rank statistics also
keep counts of groups of 16 levels in `coarse`; other statistics use `nothing`
to avoid paying for updates they never query. Example: levels 1 and 17 give
fine counts at 1 and 17, and coarse counts `[1, 1, 0, …]`.
"""
mutable struct WindowHistogram{C}
    counts::Vector{Int}
    distinct::Int
    coarse::C
end

"""
    WindowHistogram(counts, distinct)

Construct fine counts without a coarse table, preserving the original helper
constructor. Example: `WindowHistogram([2, 1], 2)` describes two false values
and one true value when used with binary pixels.
"""
WindowHistogram(counts::Vector{Int}, distinct::Int) = WindowHistogram(counts, distinct, nothing)

"""
    _coarse_update!(coarse, level, delta)

Update the group containing `level`, or do nothing for non-rank statistics.
Example: level 17 with delta -1 subtracts one from group 2.
"""
@inline _coarse_update!(::Nothing, level::Int, delta::Int) = nothing
@inline function _coarse_update!(coarse::Vector{Int}, level::Int, delta::Int)
    @inbounds coarse[((level - 1) >> 4) + 1] += delta
    return nothing
end

"""
    _clear_coarse!(coarse)

Clear the optional group counts at the start of a sweep. Example: `[2, 1]`
becomes `[0, 0]`; `nothing` needs no work.
"""
_clear_coarse!(::Nothing) = nothing
_clear_coarse!(coarse::Vector{Int}) = fill!(coarse, 0)

"""Add a level to the fine and optional coarse counts; entering level 3 twice gives count 2."""
@inline function _enter!(histogram::WindowHistogram, level::Int)
    _coarse_update!(histogram.coarse, level, 1)
    @inbounds histogram.counts[level] += 1
    @inbounds if histogram.counts[level] == 1
        histogram.distinct += 1
    end
end

"""Remove a level from both counts; removing the last level 3 reduces `distinct` by one."""
@inline function _leave!(histogram::WindowHistogram, level::Int)
    _coarse_update!(histogram.coarse, level, -1)
    @inbounds histogram.counts[level] -= 1
    @inbounds if histogram.counts[level] == 0
        histogram.distinct -= 1
    end
end

"""
Get reusable fine counts and, for byte rank queries, coarse counts, then run
the sweep. Example: a byte median uses 256 fine and 16 coarse bins; a binary
median uses just its two fine bins. Sparse sweeps keep fine counts alone: the
extra coarse updates pay off only when ranks are queried frequently.
"""
function _order_grid!(grid, values, windows::WindowGrid, statistic::OrderStatistic, ::SlidingHistogram)
    counts = scratch(:pooler_histogram, Int, _levels(eltype(values)))
    if statistic isa Union{WindowMedian,WindowIQR} && eltype(values) === N0f8 && step(windows.cols) == 1
        coarse = scratch(:pooler_coarse_histogram, Int, 16)
        return _histogram_grid!(grid, values, windows, statistic, WindowHistogram(counts, 0, coarse))
    end
    return _histogram_grid!(grid, values, windows, statistic, WindowHistogram(counts, 0, nothing))
end

"""
    _histogram_grid!(grid, values, windows, statistic, histogram)

For each row of windows: count the first window, then slide right one column
at a time (the `k` values of the leaving column leave, the `k` of the entering
column enter), and evaluate the statistic at the requested columns. Cost per
step: `2k` updates, instead of reading `k²` values.

Example (`k = 2`) on the two rows `[1 2 2; 1 1 3]`: the first window holds
`1, 1, 2, 1` → counts `{1: 3, 2: 1}`; sliding right, column 1 (`1, 1`) leaves
and column 3 (`2, 3`) enters → `{1: 1, 2: 2, 3: 1}`.
"""
function _histogram_grid!(grid, values, windows::WindowGrid, statistic::OrderStatistic, histogram::WindowHistogram)
    T = eltype(values)
    k = windows.k
    n = k * k
    last_col = last(windows.cols)
    for (i, r) in enumerate(windows.rows)
        fill!(histogram.counts, 0)
        _clear_coarse!(histogram.coarse)
        histogram.distinct = 0
        _enter_block!(histogram, values, r:(r + k - 1), 1:k)
        j = 1
        for c in 1:last_col
            if j <= length(windows.cols) && windows.cols[j] == c
                grid[i, j] = _histogram_statistic(statistic, histogram, T, n)
                j += 1
            end
            if c < last_col
                _leave_block!(histogram, values, r:(r + k - 1), c:c)
                _enter_block!(histogram, values, r:(r + k - 1), (c + k):(c + k))
            end
        end
    end
    return grid
end

function _enter_block!(histogram::WindowHistogram, values, rows, cols)
    @inbounds for c in cols, r in rows
        _enter!(histogram, _level(values[r, c]))
    end
end

function _leave_block!(histogram::WindowHistogram, values, rows, cols)
    @inbounds for c in cols, r in rows
        _leave!(histogram, _level(values[r, c]))
    end
end

"""
    _rank_value(histogram, T, rank) -> the `rank`-th smallest value of the window

Skip whole groups of 16 levels when coarse counts are available, then walk
the fine counts up to `rank`. Both searches use exact integer counts.
Example for `N0f8`: bin counts `{1: 2, 256: 1}` give zero at ranks 1 and 2,
and one at rank 3 (bin indices are one-based, rather than pixel values).
"""
function _rank_value(histogram::WindowHistogram, ::Type{T}, rank::Int) where {T}
    level, _ = _rank_level(histogram, rank)
    return _level_value(T, level)
end

"""
    _rank_level(histogram, rank) -> (level, cumulative_count)

Locate a rank and retain the cumulative count through its bin, so an adjacent
rank need not restart the search. Example: counts `{3: 2, 7: 1}` and rank 2
return `(3, 2)`.
"""
function _rank_level(histogram::WindowHistogram, rank::Int)
    seen = 0
    first_level = 1
    if histogram.coarse !== nothing
        first_level = length(histogram.counts) + 1
        @inbounds for group in eachindex(histogram.coarse)
            group_count = histogram.coarse[group]
            if seen + group_count >= rank
                first_level = 16 * (group - 1) + 1
                break
            end
            seen += group_count
        end
    end
    @inbounds for level in first_level:length(histogram.counts)
        seen += histogram.counts[level]
        if seen >= rank
            return level, seen
        end
    end
    throw(ArgumentError("rank $rank exceeds the window size $seen"))
end

"""
    _rank_pair(histogram, T, rank) -> values at ranks `rank` and `rank + 1`

Reuse the first rank's value when its cumulative count also covers the next
rank. At a bin boundary, use the bounded rank search again: coarse groups
skip long empty gaps instead of walking all intervening fine bins.
Example for `N0f8`: bin counts `{1: 2, 256: 1}` give `(0, 1)` at rank 2.
A pair must start before the final rank; otherwise the rank search throws.
"""
function _rank_pair(histogram::WindowHistogram, ::Type{T}, rank::Int) where {T}
    level, seen = _rank_level(histogram, rank)
    first_value = _level_value(T, level)
    if seen > rank
        return first_value, first_value
    end
    next_level, _ = _rank_level(histogram, rank + 1)
    return first_value, _level_value(T, next_level)
end

"""
    _histogram_quantile(histogram, T, n, p) -> quantile at `p`

Fetch the two adjacent ranks together, then use the unchanged interpolation
in `_quantile_of_ranks`. Example: ranks 1 and 2 of `[1, 2, 3, 4]` give the
quarter quantile `1.75`. The single-value case reads rank 1 twice, as before.
"""
function _histogram_quantile(histogram::WindowHistogram, ::Type{T}, n::Int, p::Float64) where {T}
    if n == 1
        return _quantile_of_ranks(r -> Float64(_rank_value(histogram, T, r)), n, p)
    end
    rank, _ = _quantile_position(n, p)            # the ranks _quantile_of_ranks will read: rank, rank + 1
    a, b = _rank_pair(histogram, T, rank)
    function value_at(r)
        if r == rank
            return Float64(a)
        end
        return Float64(b)
    end
    return _quantile_of_ranks(value_at, n, p)
end

"""
Median exactly as `Statistics.median`: the middle value, or `middle` of the
two middle values for an even count, reusing a bin when possible.
Example for `N0f8` values `[0, 0, 1, 1]`: ranks 2 and 3 are zero and one,
so `middle(0.0N0f8, 1.0N0f8) = 0.5f0`.
"""
function _histogram_statistic(::WindowMedian, histogram::WindowHistogram, ::Type{T}, n::Int) where {T}
    mid = div(1 + n, 2)
    if isodd(n)
        return Float64(middle(_rank_value(histogram, T, mid)))
    end
    a, b = _rank_pair(histogram, T, mid)
    return Float64(middle(a, b))
end

"""Interquartile range `q(0.75) − q(0.25)`, with unchanged quantile interpolation.
Example: `[1, 2, 3, 4]` gives `3.25 − 1.75 = 1.5`; each adjacent rank pair is found together."""
function _histogram_statistic(::WindowIQR, histogram::WindowHistogram, ::Type{T}, n::Int) where {T}
    return _histogram_quantile(histogram, T, n, 0.75) - _histogram_quantile(histogram, T, n, 0.25)
end

"""
Median of binary counts without a rank scan: a rank is true exactly when it
exceeds the zero count. Example: two zeros and two ones give `middle(false,
true) == 0.5`, using the same `middle` arithmetic as the general median.
"""
function _histogram_statistic(::WindowMedian, histogram::WindowHistogram, ::Type{Bool}, n::Int)
    @inbounds zero_count = histogram.counts[1]
    mid = div(1 + n, 2)
    if isodd(n)
        return Float64(middle(mid > zero_count))
    end
    return Float64(middle(mid > zero_count, mid + 1 > zero_count))
end

"""
Binary IQR reads each rank by comparison with the zero count and retains
`_quantile_of_ranks` unchanged. Example: `[false, false, true, true]` has
quartiles 0 and 1, hence IQR 1.
"""
function _histogram_statistic(::WindowIQR, histogram::WindowHistogram, ::Type{Bool}, n::Int)
    @inbounds zero_count = histogram.counts[1]
    value_at(rank) = Float64(rank > zero_count)
    return _quantile_of_ranks(value_at, n, 0.75) - _quantile_of_ranks(value_at, n, 0.25)
end

"Number of distinct values in the window. Example: `{3, 3, 7, 9}` → 3."
_histogram_statistic(::WindowUniqueCount, histogram::WindowHistogram, ::Type, n::Int) = Float64(histogram.distinct)

"How many pixels share the window's maximum: the count of the highest present level. Example: `{3, 9, 9}` → 2."
function _histogram_statistic(::WindowArgmaxCount, histogram::WindowHistogram, ::Type, n::Int)
    @inbounds for level in reverse(eachindex(histogram.counts))
        if histogram.counts[level] > 0
            return Float64(histogram.counts[level])
        end
    end
    return 0.0
end

"How many pixels share the window's minimum: the count of the lowest present level. Example: `{3, 3, 9}` → 2."
function _histogram_statistic(::WindowArgminCount, histogram::WindowHistogram, ::Type, n::Int)
    @inbounds for level in eachindex(histogram.counts)
        if histogram.counts[level] > 0
            return Float64(histogram.counts[level])
        end
    end
    return 0.0
end

"Most frequent value (ties: the smallest, as `mode!`). Example: `{3: 2, 7: 2, 9: 1}` → 3."
function _histogram_statistic(::WindowMode, histogram::WindowHistogram, ::Type{T}, n::Int) where {T}
    best_level = 1
    @inbounds for level in eachindex(histogram.counts)
        if histogram.counts[level] > histogram.counts[best_level]
            best_level = level
        end
    end
    return Float64(_level_value(T, best_level))
end

"""
    _quantile_position(n, p) -> (j, γ)

Where `Statistics.quantile` (default `alpha = beta = 1`) reads the quantile `p`
of `n` sorted values: between ranks `j` and `j + 1`, at fraction `γ` of the
way. Shared by `_quantile_of_ranks` and `_histogram_quantile`, so both pick the
same ranks. Example: `n = 4`, `p = 0.25` → `aleph = 1.75` → `(1, 0.75)`.
"""
function _quantile_position(n::Int, p::Float64)
    alpha = 1.0
    beta = 1.0
    m = alpha + p * (one(alpha) - alpha - beta)
    aleph = n * p + oftype(p, m)
    j = clamp(trunc(Int, aleph), 1, n - 1)
    γ = clamp(aleph - j, 0, 1)
    return j, γ
end

"""
    _quantile_of_ranks(value_at, n, p) -> quantile `p` of `n` sorted values

The interpolation of `Statistics.quantile` (its default `alpha = beta = 1`),
reading the sorted values through `value_at(rank)`, so the result is the same
as `quantile(values, p)`. Example: values `[1, 2, 3, 4]`, `p = 0.25` →
position `aleph = 4·0.25 + 0.75 = 1.75` → `1 + 0.75·(2 − 1) = 1.75`.
"""
function _quantile_of_ranks(value_at::F, n::Int, p::Float64) where {F}
    j, γ = _quantile_position(n, p)
    if n == 1
        a = value_at(1)
        b = value_at(1)
    else
        a = value_at(j)
        b = value_at(j + 1)
    end
    if isfinite(a) && isfinite(b) && a ≈ b
        return a + γ * (b - a)
    end
    return (1 - γ) * a + γ * b
end

# 6b. Sorted buffer --------------------------------------------------------

"Element type of the buffer: the IQR works on Float64 copies (as the original); the others on the values themselves."
_buffer_type(::WindowIQR, ::Type) = Float64
_buffer_type(::OrderStatistic, ::Type{T}) where {T} = T

function _order_grid!(grid, values, windows::WindowGrid, statistic::OrderStatistic, ::SortedBuffer)
    buffer = scratch(:pooler_window_buffer, _buffer_type(statistic, eltype(values)), windows.k^2)
    return _buffer_grid!(grid, values, windows, statistic, buffer)
end

"""
    _buffer_grid!(grid, values, windows, statistic, buffer)

Each window is copied into the same `buffer` (length `k²`), which the
statistic then sorts or partially sorts in place: no allocation per window.
"""
function _buffer_grid!(grid, values, windows::WindowGrid, statistic::OrderStatistic, buffer)
    k = windows.k
    for (j, c) in enumerate(windows.cols), (i, r) in enumerate(windows.rows)
        window = view(values, r:(r + k - 1), c:(c + k - 1))
        grid[i, j] = _buffer_statistic(statistic, window, buffer)
    end
    return grid
end

"Median of a copy of the window (quickselect, exactly `median(window)`, without allocating)."
_buffer_statistic(::WindowMedian, window, buffer) = Float64(median_select!(copyto!(buffer, window)))

"Interquartile range of the window's values as Float64, both quantiles from one partial sort."
function _buffer_statistic(::WindowIQR, window, buffer)
    q1, q3 = quantile!(copyto!(buffer, window), (0.25, 0.75))
    return q3 - q1
end

"Number of distinct values of a copy of the window. Example: `[9, 3, 3]` → 2."
_buffer_statistic(::WindowUniqueCount, window, buffer) = Float64(unique_count!(copyto!(buffer, window)))

"How many values equal the window's maximum (the window is read in place, no buffer)."
function _buffer_statistic(::WindowArgmaxCount, window, buffer)
    largest = maximum(window)
    return Float64(count(==(largest), window))
end

"How many values equal the window's minimum (the window is read in place, no buffer)."
function _buffer_statistic(::WindowArgminCount, window, buffer)
    smallest = minimum(window)
    return Float64(count(==(smallest), window))
end

"Most frequent value of the window (ties: the smallest)."
_buffer_statistic(::WindowMode, window, buffer) = Float64(mode!(copyto!(buffer, window)))

# ---------------------------------------------------------------------------
# 7. Output
# ---------------------------------------------------------------------------

"""
    _rescale01!(grid) -> grid

Min–max rescaling to `[0, 1]` (all zeros when the grid is flat), for the count
poolers. Example: `[2 4 6]` → `[0 0.5 1]`.
"""
function _rescale01!(grid)
    low, high = extrema(grid)
    if high == low
        return fill!(grid, 0.0)
    end
    grid .= (grid .- low) ./ (high - low)
    return grid
end

"""
    _stretch_index(i, out_n, src_n) -> source index of output index `i`

Nearest-neighbour stretch of `src_n` values over `out_n`, centre-aligned.
Example: 3 values over 6 → output 1–6 read source `1 1 2 2 3 3`.
"""
@inline _stretch_index(i::Int, out_n::Int, src_n::Int) = clamp(round(Int, (i - 0.5) * src_n / out_n + 0.5), 1, src_n)

"""
    _write_stretched!(pixels, grid) -> pixels

Stretch the grid of window results over the whole image and store each value
as a pixel (`pooled_pixel`: majority for masks, rounding for labels). The
values are first gathered in a Float64 working array, then converted with one
broadcast, which vectorises (a per-pixel conversion loop is much slower).
"""
function _write_stretched!(pixels::AbstractMatrix{P}, grid) where {P}
    stretched = scratch(:pooler_stretched, Float64, size(pixels)...)
    _stretch!(stretched, grid)
    pixels .= pooled_pixel.(P, stretched)
    return pixels
end

function _stretch!(stretched, grid)
    out_h, out_w = size(stretched)
    src_h, src_w = size(grid)
    @inbounds for j in 1:out_w
        source_col = _stretch_index(j, out_w, src_w)
        for i in 1:out_h
            stretched[i, j] = grid[_stretch_index(i, out_h, src_h), source_col]
        end
    end
    return stretched
end

# ---------------------------------------------------------------------------
# 8. Factories
# ---------------------------------------------------------------------------

"""
    _make_pooler_factory(I, statistic, name) -> Function

Define `name` for the image type `I`, with the methods `(img, k, stride)`,
`(img, k)` (stride 1) and `(img)` (k = 2, stride 1), each accepting `out`.
"""
@serialized_factory function _make_pooler_factory(::Type{I}, statistic::WindowStatistic, name::Symbol) where {I<:SizedImage2D}
    IT, PT, S = _get_image_type(I), _get_image_pixel_type(I), _get_image_tuple_size(I)
    _validate_factory_type(IT)
    function_name = Symbol(name, :_image2D_, _factory_type_symbol(I))
    isdefined(@__MODULE__, function_name) && return getfield(@__MODULE__, function_name)
    pixel_statistic = _for_pixel(statistic, PT)
    f = @eval function $function_name(img::Image, k::Number, stride::Number, args::Vararg{Any}; out = nothing) where {Image<:$I}
        pixels = output_pixels(out, img)
        _pool_into!(pixels, img.img, k, stride, $pixel_statistic)
        return image_result(out, pixels, $S)
    end
    @eval function $function_name(img::Image, k::Number, args::Vararg{Any}; out = nothing) where {Image<:$I}
        return $function_name(img, k, 1, args...; out)
    end
    @eval function $function_name(img::Image, args::Vararg{Any}; out = nothing) where {Image<:$I}
        return $function_name(img, 2, 1, args...; out)
    end
    return f
end

"""
    meanpool_image2D_factory(i::Type{I}) where {I<:SizedImage2D}

Mean of each `k × k` window (labels: the most frequent label), stretched back
to the image size. Example (`k = 2`): windows of `[0 0 1; 0 0 1; 1 1 1]` →
`[0 0.5; 0.5 0.75]`.
"""
meanpool_image2D_factory(i::Type{I}) where {I<:SizedImage2D} =
    _make_pooler_factory(i, WindowMean(), :meanpool)

"""
    maxpool_image2D_factory(i::Type{I}) where {I<:SizedImage2D}

Maximum of each `k × k` window, stretched back to the image size.
Example (`k = 2`): windows of `[1 5 0; 3 2 0; 0 0 9]` → `[5 5; 3 9]`.
"""
maxpool_image2D_factory(i::Type{I}) where {I<:SizedImage2D} =
    _make_pooler_factory(i, WindowMax(), :maxpool)

"""
    minpool_image2D_factory(i::Type{I}) where {I<:SizedImage2D}

Minimum of each `k × k` window, stretched back to the image size.
Example (`k = 2`): windows of `[1 5 0; 3 2 0; 0 0 9]` → `[1 0; 0 0]`.
"""
minpool_image2D_factory(i::Type{I}) where {I<:SizedImage2D} =
    _make_pooler_factory(i, WindowMin(), :minpool)

"""
    stdpool_image2D_factory(i::Type{I}) where {I<:SizedImage2D}

Sample standard deviation of each `k × k` window (0 for `k = 1`), stretched
back to the image size. Example: a window `[1 2; 3 4]` → `≈ 1.29`.
"""
stdpool_image2D_factory(i::Type{I}) where {I<:SizedImage2D} =
    _make_pooler_factory(i, WindowStd(), :stdpool)

"""
    medianpool_image2D_factory(i::Type{I}) where {I<:SizedImage2D}

Median of each `k × k` window, stretched back to the image size.
Example: a window `[3 7; 3 9]` → `middle(3, 7) = 5`.
"""
medianpool_image2D_factory(i::Type{I}) where {I<:SizedImage2D} =
    _make_pooler_factory(i, WindowMedian(), :medianpool)

"""
    uniquecountpool_image2D_factory(i::Type{I}) where {I<:SizedImage2D}

Number of distinct values in each `k × k` window, rescaled to `[0, 1]` over the
image. Example: a window `[3 7; 3 9]` → 3 before rescaling.
"""
uniquecountpool_image2D_factory(i::Type{I}) where {I<:SizedImage2D} =
    _make_pooler_factory(i, WindowUniqueCount(), :uniquecountpool)

"""
    argmaxcountpool_image2D_factory(i::Type{I}) where {I<:SizedImage2D}

How many pixels of each `k × k` window share its maximum, rescaled to `[0, 1]`
over the image. Example: a window `[9 7; 3 9]` → 2 before rescaling.
"""
argmaxcountpool_image2D_factory(i::Type{I}) where {I<:SizedImage2D} =
    _make_pooler_factory(i, WindowArgmaxCount(), :argmaxcountpool)

"""
    argmincountpool_image2D_factory(i::Type{I}) where {I<:SizedImage2D}

How many pixels of each `k × k` window share its minimum, rescaled to `[0, 1]`
over the image. Example: a window `[3 7; 3 9]` → 2 before rescaling.
"""
argmincountpool_image2D_factory(i::Type{I}) where {I<:SizedImage2D} =
    _make_pooler_factory(i, WindowArgminCount(), :argmincountpool)

"""
    iqrpool_image2D_factory(i::Type{I}) where {I<:SizedImage2D}

Interquartile range (75th minus 25th percentile, `Statistics.quantile`'s
interpolation) of each `k × k` window, stretched back to the image size.
Example: a window `[1 2; 3 4]` → `3.25 − 1.75 = 1.5`.
"""
iqrpool_image2D_factory(i::Type{I}) where {I<:SizedImage2D} =
    _make_pooler_factory(i, WindowIQR(), :iqrpool)

function _pooler_description(name::Symbol)::String
    if name === :meanpool
        return "Applies sliding-window mean pooling (labels: most frequent) and resizes back to the original image size."
    elseif name === :maxpool
        return "Applies sliding-window max pooling and resizes back to the original image size."
    elseif name === :minpool
        return "Applies sliding-window min pooling and resizes back to the original image size."
    elseif name === :stdpool
        return "Applies sliding-window standard-deviation pooling and resizes back to the original image size."
    elseif name === :medianpool
        return "Applies sliding-window median pooling and resizes back to the original image size."
    elseif name === :uniquecountpool
        return "Applies sliding-window unique-count pooling and rescales values to [0, 1]."
    elseif name === :argmaxcountpool
        return "Applies sliding-window argmax-count pooling and rescales values to [0, 1]."
    elseif name === :argmincountpool
        return "Applies sliding-window argmin-count pooling and rescales values to [0, 1]."
    elseif name === :iqrpool
        return "Applies sliding-window interquartile-range pooling and resizes back to the original image size."
    end
    return "Applies sliding-window pooling and resizes the result to the original image size."
end

for (factory, name) in (
    (meanpool_image2D_factory, :meanpool),
    (maxpool_image2D_factory, :maxpool),
    (minpool_image2D_factory, :minpool),
    (stdpool_image2D_factory, :stdpool),
    (medianpool_image2D_factory, :medianpool),
    (uniquecountpool_image2D_factory, :uniquecountpool),
    (argmaxcountpool_image2D_factory, :argmaxcountpool),
    (argmincountpool_image2D_factory, :argmincountpool),
    (iqrpool_image2D_factory, :iqrpool),
)
    for bundle in (bundle_image2DIntensity_pooler_factory, bundle_image2DBinary_pooler_factory, bundle_image2DSegment_pooler_factory)
        append_method!(bundle, factory, name; description = _pooler_description(name))
    end
end

end
