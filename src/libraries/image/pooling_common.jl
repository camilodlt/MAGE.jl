"""
Helpers shared by block pooling (`image_pool.jl`) and sliding-window pooling
(`image_pooler.jl`).

Call tree (from a pooling function):

    pixel_values!(values, pixels)        pixels → plain array of their values (image_buffers.jl)
    mode!(buffer)                        most frequent value, in place
    unique_count!(buffer)                number of distinct values, in place
    ├── _value_counts!(buffer, …)        counts per integer value, when the range is small
    └── sort!(buffer; alg = QuickSort)   otherwise
    median_select!(buffer)               median
    └── kth_smallest!(buffer, k)         k-th smallest: counts, byte radix select, or _select!
    pooled_pixel(P, x)                   a pooled number → a pixel of type P

None of them allocates: `sort!`'s default algorithms (radix and counting
sorts) and `median!` / `partialsort!` allocate workspace on every call, so
they are replaced by in-place algorithms giving the same results.
"""
module image_pooling_common

using ImageCore: FixedPoint
using Statistics: middle
using ..MAGE: IntensityPixel, BinaryPixel, SegmentPixel, pixel_values!, scratch

export pixel_values!, mode!, unique_count!, median_select!, kth_smallest!, pooled_pixel   # pixel_values! lives in image_buffers.jl

# ---------------------------------------------------------------------------
# Counting integer values
# ---------------------------------------------------------------------------

"""
    _count_key(x) -> Integer

The integer a value is counted under: labels (`Int64`, `Bool`) are their own
key, fixed-point values (`N0f16`, …) their raw storage integer.
"""
_count_key(x::Integer) = x
_count_key(x::FixedPoint) = reinterpret(x)

"The value of eltype `T` counted under `key` (inverse of `_count_key`)."
_from_key(::Type{T}, key::Integer) where {T<:Integer} = T(key)
_from_key(::Type{T}, key::Integer) where {T<:FixedPoint} = reinterpret(T, key % typeof(reinterpret(zero(T))))

"Whether values of this type have integer keys (floats do not)."
_countable(::Type{<:Union{Integer,FixedPoint}}) = true
_countable(::Type) = false

"""
Counting needs a table as long as the value range: it is used when that range
is at most this many times the number of values (plus a constant), so filling
the table costs no more than sorting.
"""
const _COUNTING_RANGE_FACTOR = 4

"""
    _counting_range(buffer) -> (lowest_key, range)

The smallest key and the number of keys `highest − lowest + 1` when the
values can be counted in a table (`_countable` type, range at most
`_COUNTING_RANGE_FACTOR` times the length plus 64); `(0, 0)` otherwise.

Example: `[3, 1, 3]` → `(1, 3)`; `[1, 10^9]` → `(0, 0)` (range too wide).
"""
function _counting_range(buffer::AbstractVector{T}) where {T}
    (_countable(T) && !isempty(buffer)) || return (0, 0)
    lowest, highest = extrema(_count_key, buffer)
    range = Int128(highest) - Int128(lowest) + 1
    range > _COUNTING_RANGE_FACTOR * length(buffer) + 64 && return (0, 0)
    return (Int(lowest), Int(range))
end

"""
    _value_counts!(buffer, lowest, range) -> counts

How many times each key occurs: `counts[i]` for key `lowest + i − 1`, in a
reused task-scratch table. Example: `[3, 1, 3]`, `lowest = 1`, `range = 3` →
`[1, 0, 2]`.
"""
function _value_counts!(buffer::AbstractVector, lowest::Int, range::Int)
    counts = fill!(resize!(scratch(:pooling_counts, Int, 0), range), 0)
    @inbounds for x in buffer
        counts[Int(_count_key(x)) - lowest + 1] += 1
    end
    return counts
end

# ---------------------------------------------------------------------------
# Mode and distinct values
# ---------------------------------------------------------------------------

"""
    mode!(buffer) -> most frequent value (ties: the smallest)

The "average" of a label map: unlike the mean of label numbers, it never
invents a label. `buffer` may be reordered; nothing is allocated.

How: integer values over a small range are counted in a table and the first
largest count wins (the smallest value on ties). Otherwise `buffer` is sorted,
so equal values are next to each other, and one pass measures each run; a run
replaces the best only when strictly longer, so on ties the first run, which
holds the smallest value, wins.

Example: `[3, 1, 3, 1, 2]` → counts 1×2, 2×1, 3×2 → `1` (tied with 3, smaller).
"""
function mode!(buffer::AbstractVector{T}) where {T}
    lowest, range = _counting_range(buffer)
    range == 0 && return _mode_of_sorted(sort!(buffer; alg = QuickSort))
    counts = _value_counts!(buffer, lowest, range)
    return _from_key(T, lowest + argmax(counts) - 1)   # argmax: the first largest count
end

"Most frequent value of a sorted vector (ties: the first, so the smallest)."
function _mode_of_sorted(sorted::AbstractVector)
    best_value = sorted[1]
    best_count = 0
    run_start = 1
    @inbounds for index in 2:(length(sorted) + 1)
        run_ends = index > length(sorted) || !isequal(sorted[index], sorted[run_start])
        if run_ends
            run_length = index - run_start
            if run_length > best_count
                best_count = run_length
                best_value = sorted[run_start]
            end
            run_start = index
        end
    end
    return best_value
end

"""
    unique_count!(buffer) -> number of distinct values

`buffer` may be reordered; nothing is allocated. Counted in a table for
integer values over a small range, otherwise by sorting and counting where
neighbours differ. Example: `[9, 3, 3]` → `2`.
"""
function unique_count!(buffer::AbstractVector)
    lowest, range = _counting_range(buffer)
    range == 0 || return count(!iszero, _value_counts!(buffer, lowest, range))
    sorted = sort!(buffer; alg = QuickSort)
    distinct = 1
    @inbounds for index in 2:length(sorted)
        if !isequal(sorted[index], sorted[index-1])
            distinct += 1
        end
    end
    return distinct
end

# ---------------------------------------------------------------------------
# Median
# ---------------------------------------------------------------------------

"""
    median_select!(buffer) -> median, exactly as `Statistics.median!(buffer)`

The middle value (odd length) or `middle` of the two middle values (even
length), without `median!`'s allocating partial sort. `NaN` anywhere gives
`NaN`, as `median!`. `buffer` may be reordered.

Example: `[5, 1, 4, 2]` → middle values 2 and 4 → `3.0`.
"""
function median_select!(buffer::AbstractVector)
    if eltype(buffer) <: AbstractFloat && any(isnan, buffer)
        return convert(eltype(buffer), NaN)
    end
    n = length(buffer)
    if n <= _SELECT_INSERTION_LENGTH
        # Short windows (e.g. 3 × 3): sorting is cheaper than any table.
        _insertion_sort!(buffer, firstindex(buffer), lastindex(buffer))
        middle_index = firstindex(buffer) + (n - 1) ÷ 2
        return isodd(n) ? middle(buffer[middle_index]) : middle(buffer[middle_index], buffer[middle_index+1])
    end
    if isodd(n)
        return middle(kth_smallest!(buffer, (n + 1) ÷ 2))
    end
    return middle(kth_smallest!(buffer, n ÷ 2), kth_smallest!(buffer, n ÷ 2 + 1))
end

"""
    kth_smallest!(buffer, k) -> the k-th smallest value

Exact, allocation-free, choosing the fastest method for the values:

- integer keys over a small range (labels): walk the counts table;
- 16-bit fixed-point values (`N0f16`): radix select on the two bytes of the
  raw value (`_kth_by_bytes`);
- anything else: quickselect (`_select!`, reorders `buffer`).

Example: `kth_smallest!([7, 2, 9, 4], 2) == 4`.
"""
function kth_smallest!(buffer::AbstractVector{T}, k::Int) where {T}
    lowest, range = _counting_range(buffer)
    if range != 0
        return _from_key(T, lowest + _kth_count_index(_value_counts!(buffer, lowest, range), k) - 1)
    end
    _sixteen_bit(T) && return _kth_by_bytes(buffer, k)
    return _select!(buffer, k)
end

"Whether the values are 16-bit fixed point (`N0f16`), stored as `UInt16`."
_sixteen_bit(::Type{T}) where {T<:FixedPoint} = typeof(reinterpret(zero(T))) === UInt16
_sixteen_bit(::Type) = false

"""
    _kth_count_index(counts, k) -> index of the bin holding the k-th value

Walk the cumulative counts. Example: counts `[1, 0, 2]`, `k = 2` → bin 3.
"""
function _kth_count_index(counts::AbstractVector{Int}, k::Int)
    remaining = k
    @inbounds for index in eachindex(counts)
        remaining <= counts[index] && return index
        remaining -= counts[index]
    end
    return lastindex(counts)
end

"""
    _kth_by_bytes(buffer, k) -> the k-th smallest of 16-bit fixed-point values

Radix select on the raw `UInt16`: count the high bytes (256 bins) and find
the bin of the k-th value, then count the low bytes of the values in that bin
and find it there. Two passes over the values, no reordering, no allocation.

Example: raw values `0x0102, 0x0101, 0x0201`, `k = 2`: high bytes 1, 1, 2 →
the 2nd value has high byte 1; low bytes in that bin 2, 1 → it is `0x0102`.
"""
function _kth_by_bytes(buffer::AbstractVector{T}, k::Int) where {T}
    high_counts = fill!(scratch(:select_high_bytes, Int, 256), 0)
    @inbounds for x in buffer
        high_counts[(reinterpret(x) >> 8) + 1] += 1
    end
    high = _kth_count_index(high_counts, k) - 1
    remaining = k - sum(view(high_counts, 1:high))          # rank of the value within its bin
    low_counts = fill!(scratch(:select_low_bytes, Int, 256), 0)
    @inbounds for x in buffer
        raw = reinterpret(x)
        if raw >> 8 == high
            low_counts[(raw & 0xff) + 1] += 1
        end
    end
    low = _kth_count_index(low_counts, remaining) - 1
    return reinterpret(T, UInt16(high << 8 | low))
end

"Ranges at most this long are finished by insertion sort in `_select!`."
const _SELECT_INSERTION_LENGTH = 16

"""
    _select!(v, k) -> the k-th smallest element of `v`

Quickselect (Hoare partition, median-of-three pivot): `v` is reordered so that
`v[k]` holds the k-th smallest value, every element before it is `≤` and every
element after it `≥` (under `isless`). In place, no allocation.

Example: `_select!([7, 2, 9, 4], 2) == 4`.
"""
function _select!(v::AbstractVector, k::Int)
    lo, hi = firstindex(v), lastindex(v)
    @inbounds while hi - lo > _SELECT_INSERTION_LENGTH
        pivot = _median_of_three!(v, lo, (lo + hi) >>> 1, hi)
        i, j = lo, hi
        while i <= j                                   # Hoare partition around the pivot value
            while isless(v[i], pivot)
                i += 1
            end
            while isless(pivot, v[j])
                j -= 1
            end
            if i <= j
                v[i], v[j] = v[j], v[i]
                i += 1
                j -= 1
            end
        end
        # Now v[lo:j] ≤ pivot ≤ v[i:hi], and v[j+1:i-1] equal the pivot.
        if k <= j
            hi = j
        elseif k >= i
            lo = i
        else
            return v[k]
        end
    end
    _insertion_sort!(v, lo, hi)
    return v[k]
end

"Order `v[a] ≤ v[b] ≤ v[c]` and return the middle value, `v[b]`."
@inline function _median_of_three!(v, a::Int, b::Int, c::Int)
    @inbounds begin
        isless(v[b], v[a]) && ((v[a], v[b]) = (v[b], v[a]))
        isless(v[c], v[b]) && ((v[b], v[c]) = (v[c], v[b]))
        isless(v[b], v[a]) && ((v[a], v[b]) = (v[b], v[a]))
        return v[b]
    end
end

"Sort `v[lo:hi]` in place by insertion (for short ranges)."
function _insertion_sort!(v, lo::Int, hi::Int)
    @inbounds for i in (lo + 1):hi
        x = v[i]
        j = i - 1
        while j >= lo && isless(x, v[j])
            v[j+1] = v[j]
            j -= 1
        end
        v[j+1] = x
    end
    return v
end

# ---------------------------------------------------------------------------
# Back to pixels
# ---------------------------------------------------------------------------

"""
    pooled_pixel(P, x) -> P

Turn a pooled number `x` back into a pixel of type `P`, as the pooling
functions always did:

- masks (`BinaryPixel`): set when `x ≥ 0.5` (a majority);
- labels (`SegmentPixel{T}`): `x` rounded to the nearest label (labels pass
  through Float64, so labels beyond `2^53` lose precision, as before);
- intensities (`IntensityPixel{T}`): `x` converted to the storage type `T`.

Example: `pooled_pixel(BinaryPixel{Bool}, 0.75) == BinaryPixel(true)`,
`pooled_pixel(SegmentPixel{Int}, 2.0) == SegmentPixel(2)`.
"""
pooled_pixel(::Type{BinaryPixel{T}}, x::Real) where {T} = BinaryPixel{T}(T(x >= 0.5))
pooled_pixel(::Type{SegmentPixel{T}}, x::Real) where {T} = SegmentPixel{T}(T(round(x)))
pooled_pixel(::Type{IntensityPixel{T}}, x::Real) where {T} = IntensityPixel{T}(T(x))

end
