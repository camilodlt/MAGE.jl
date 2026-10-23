"""
    bundle_ski_basic

SkiVector constructors: identity first, input-free singleton one second, then
singleton two and empty. Returned values own their storage; optional `out`
allows callers to reuse a vector. Identity without `out` returns its input.
Use `get_ski_bundles(SkiVector{S})` to specialize the input-free constructors
for the chromosome size. Constants have id zero and reset their owned geometry.
"""
bundle_ski_basic = FunctionBundle(() -> SkiVector())
"""
    bundle_ski_vector

SkiVector transforms, sorted rank subsets, numeric filters and shared-prefix
pairwise arithmetic. Counts `k` are absolute, floored, clamped to `[0,length]`;
nonfinite counts mean zero. Intervals include both ordered endpoints. Log/sqrt
retain NaN for out-of-domain values. Sort uses Julia's total float ordering.
Ids travel with values and all derived outputs reference input geometry.
Pairwise operations use the first input's ids; concat drops the second input's
ids to zero unless both inputs reference exactly the same regions object.
"""
bundle_ski_vector = FunctionBundle(() -> SkiVector())
"""
    bundle_float_ski

SkiVector → Float64 reductions, counts, rank sums, distances and correlation.
Empty sums/counts/rank sums are zero; empty statistics, distance and correlation
are NaN. Std is population std. Percentiles use linear interpolation, with a
percentage in `[0,100]` (nonfinite → 50). Mode ties choose the smallest value;
constant-vector correlation is NaN. Pairwise reductions use shared length.
"""
bundle_float_ski = FunctionBundle(() -> 0.0)

function ski_identity(v::SkiVector, args...; out = nothing)
    out === nothing && return v
    out === v && return v
    derived(out, length(v), v)
    copyto!(out.values, v.values)
    copyto!(out.ids, v.ids)
    out
end
function constant(value, out::SkiVector{S}) where {S}
    n = value === nothing ? 0 : 1
    output(out, n, SkiVector{S})
    out.regions = out.own
    resize!(out.own.boxes, 0)
    resize!(out.own.counts, 0)
    out.own.n = 0
    out.own.image = nothing
    out.own.intensity = nothing
    # Labels are only read through ids in 1:n, so n = 0 makes them unreachable.
    if n == 1
        out.values[1] = value
        out.ids[1] = 0
    end
    out
end
ski_one(args...; out = nothing) = constant(1.0, out === nothing ? SkiVector() : out)
ski_two(args...; out = nothing) = constant(2.0, out === nothing ? SkiVector() : out)
ski_empty(args...; out = nothing) = constant(nothing, out === nothing ? SkiVector() : out)

# Input-free constructors need an explicit chromosome size when called without
# evaluator storage. Other vector/property operators infer size from inputs.
@serialized_factory function constant_factory(::Type{V}, value) where {V<:SkiVector}
    name = Symbol(
        :ski_constant_,
        value === nothing ? :empty : value == 1 ? :one : :two,
        :_,
        _factory_type_symbol(V),
    )
    isdefined(@__MODULE__, name) && return Base.invokelatest(getfield, @__MODULE__, name)
    @eval $name(args...; out = nothing) = constant($value, out === nothing ? $V() : out)
    Base.invokelatest(getfield, @__MODULE__, name)
end
for name in (:ski_identity, :ski_one, :ski_two, :ski_empty)
    register!(
        bundle_ski_basic,
        name,
        "`$name(args...; out=nothing)` constructs or preserves a SkiVector.",
    )
end
function unary(f, v, out)
    r = derived(out, length(v), v)
    @inbounds for i in eachindex(v)
        r[i] = f(v[i])
        r.ids[i] = v.ids[i]
    end
    r
end
for (name, fn) in (
    (:relu, x -> max(0.0, x)),
    (:log, x -> x < 0 ? NaN : log(x)),
    (:log1p, x -> x < -1 ? NaN : log1p(x)),
    (:square, abs2),
    (:sqrt, x -> x < 0 ? NaN : sqrt(x)),
    (:abs, abs),
    (:neg, -),
    (:exp, exp),
    (:reciprocal, x -> 1 / x),
    (:sin, sin),
    (:cos, cos),
)
    name = Symbol(:ski_, name)
    @eval $name(v::SkiVector, args...; out = nothing) = unary($fn, v, out)
    register!(
        bundle_ski_vector,
        name,
        "`$name(v; out=nothing)` transforms each value independently.",
    )
end
function sorted(v, descending = false)
    tmp = resize!(scratch(:ski_sorted, Float64, 0), length(v))
    copyto!(tmp, v.values)
    sort!(tmp; rev = descending, alg = QuickSort)
end
function sorted_entries(v, descending = false)
    entries = resize!(scratch(:ski_entries, Tuple{Float64,Int32}, 0), length(v))
    @inbounds for i in eachindex(v)
        entries[i] = (v.values[i], v.ids[i])
    end
    sort!(entries; by = first, rev = descending, alg = QuickSort)
end
function ski_sort(v::SkiVector, args...; out = nothing)
    entries = sorted_entries(v)
    r = derived(out, length(v), v)
    @inbounds for i in eachindex(entries)
        r.values[i], r.ids[i] = entries[i]
    end
    r
end
register!(
    bundle_ski_vector,
    :ski_sort,
    "`ski_sort(v; out=nothing)` sorts ascending without mutating the input.",
)
kcount(k, n) = isfinite(k) ? floor(Int, clamp(Float64(k), 0.0, Float64(n))) : 0
fraction(p) = isfinite(p) ? clamp(Float64(p), 0.0, 100.0) / 100 : 0.5
function ranks(v, k, largest, drop, out)
    tmp = sorted_entries(v, largest)
    n = length(v)
    k = kcount(k, n)
    first = drop ? k + 1 : 1
    len = drop ? n - k : k
    r = derived(out, len, v)
    @inbounds for i in 1:len
        r.values[i], r.ids[i] = tmp[first+i-1]
    end
    r
end
for largest in (false, true), drop in (false, true)
    name = Symbol(:ski_, drop ? :drop_ : :take_, largest ? :largest : :smallest)
    @eval $name(v::SkiVector, k::Real, args...; out = nothing) = ranks(v, k, $largest, $drop, out)
    register!(
        bundle_ski_vector,
        name,
        "`$name(v,k; out=nothing)` selects sorted ranks with absolute count k.",
    )
end
function filtered(v, predicate, out)
    entries = empty!(scratch(:ski_filtered_entries, Tuple{Float64,Int32}, 0))
    @inbounds for i in eachindex(v)
        predicate(v.values[i]) && push!(entries, (v.values[i], v.ids[i]))
    end
    r = derived(out, length(entries), v)
    @inbounds for i in eachindex(entries)
        r.values[i], r.ids[i] = entries[i]
    end
    r
end
for (suffix, op) in ((:lt, <), (:lte, <=), (:gt, >), (:gte, >=), (:eq, ==))
    name = Symbol(:ski_filter_, suffix)
    @eval $name(v::SkiVector, x::Real, args...; out = nothing) = filtered(v, y -> $op(y, x), out)
    register!(
        bundle_ski_vector,
        name,
        "`$name(v,x; out=nothing)` keeps values satisfying $suffix x.",
    )
    name = Symbol(:ski_count_, suffix)
    @eval $name(v::SkiVector, x::Real, args...) = Float64(count(y -> $op(y, x), v))
    register!(bundle_float_ski, name, "`$name(v,x)` counts values satisfying $suffix x.")
end
ski_filter_interval(v::SkiVector, a::Real, b::Real, args...; out = nothing) =
    filtered(v, x -> min(a, b) <= x <= max(a, b), out)
register!(
    bundle_ski_vector,
    :ski_filter_interval,
    "`ski_filter_interval(v,a,b; out=nothing)` keeps the inclusive ordered interval.",
)
ski_count_interval(v::SkiVector, a::Real, b::Real, args...) =
    Float64(count(x -> min(a, b) <= x <= max(a, b), v))
register!(
    bundle_float_ski,
    :ski_count_interval,
    "`ski_count_interval(v,a,b)` counts values in the inclusive ordered interval.",
)
function pairwise(f, a::SkiVector{S}, b::SkiVector, out) where {S}
    n = min(length(a), length(b))
    r = derived(out, n, a)
    @inbounds for i in 1:n
        r[i] = f(a[i], b[i])
        r.ids[i] = a.ids[i]
    end
    r
end
for (suffix, op) in (
    (:add, +),
    (:subtract, -),
    (:mul, *),
    (:divide, /),
    (:min, min),
    (:max, max),
    (:absdiff, (a, b) -> abs(a - b)),
)
    name = Symbol(:ski_pair_, suffix)
    @eval $name(a::SkiVector, b::SkiVector, args...; out = nothing) = pairwise($op, a, b, out)
    register!(
        bundle_ski_vector,
        name,
        "`$name(a,b; out=nothing)` combines values up to the shared length.",
    )
end
function ski_concat(a::SkiVector{S}, b::SkiVector, args...; out = nothing) where {S}
    entries = empty!(scratch(:ski_concat_entries, Tuple{Float64,Int32}, 0))
    same = a.regions === b.regions
    @inbounds for i in eachindex(a)
        push!(entries, (a.values[i], a.ids[i]))
    end
    @inbounds for i in eachindex(b)
        push!(entries, (b.values[i], same ? b.ids[i] : Int32(0)))
    end
    r = derived(out, length(entries), a)
    @inbounds for i in eachindex(entries)
        r.values[i], r.ids[i] = entries[i]
    end
    r
end
register!(
    bundle_ski_vector,
    :ski_concat,
    "`ski_concat(a,b; out=nothing)` concatenates both complete vectors.",
)
for (suffix, fn) in
    ((:mean, mean), (:min, minimum), (:max, maximum), (:std, v -> std(v; corrected = false)))
    name = Symbol(:ski_, suffix)
    @eval $name(v::SkiVector, args...) = isempty(v) ? NaN : Float64($fn(v))
    register!(bundle_float_ski, name, "`$name(v)` returns the $suffix; empty → NaN.")
end
ski_sum(v::SkiVector, args...) = sum(v; init = 0.0)
ski_length(v::SkiVector, args...) = Float64(length(v))
ski_median(v::SkiVector, args...) = isempty(v) ? NaN : median_select!(sorted(v))
function ski_mode(v::SkiVector, args...)
    isempty(v) && return NaN
    tmp = sorted(v)
    best = tmp[1]
    count = 1
    bestcount = 1
    for i in 2:length(tmp)
        count = isequal(tmp[i], tmp[i-1]) ? count + 1 : 1
        if count > bestcount
            bestcount = count
            best = tmp[i]
        end
    end
    best
end
function percentile(v, p)
    (isempty(v) || any(isnan, v)) && return NaN
    tmp = sorted(v)
    x = 1 + (length(v) - 1) * fraction(p)
    lo = floor(Int, x)
    hi = ceil(Int, x)
    lo == hi ? tmp[lo] : tmp[lo] + (x - lo) * (tmp[hi] - tmp[lo])
end
ski_percentile(v::SkiVector, p::Real, args...) = percentile(v, p)
for name in (:ski_sum, :ski_length, :ski_median, :ski_mode, :ski_percentile)
    register!(
        bundle_float_ski,
        name,
        "`$name(v[,p])` reduces a SkiVector. See bundle_float_ski for empty and percentile conventions.",
    )
end
for largest in (false, true)
    name = Symbol(:ski_sum_, largest ? :largest : :smallest)
    @eval function $name(v::SkiVector, k::Real, args...)
        tmp = sorted(v, $largest)
        n = kcount(k, length(v))
        s = 0.0
        @inbounds for i in 1:n
            s += tmp[i]
        end
        s
    end
    register!(bundle_float_ski, name, "`$name(v,k)` sums k sorted ranks; empty → zero.")
end
ski_length_difference(a::SkiVector, b::SkiVector, args...) = Float64(length(a) - length(b))
ski_length_ratio(a::SkiVector, b::SkiVector, args...) = length(a) / length(b)
ski_length_equal(a::SkiVector, b::SkiVector, args...) = Float64(length(a) == length(b))
for name in (:ski_length_difference, :ski_length_ratio, :ski_length_equal)
    register!(
        bundle_float_ski,
        name,
        "`$name(a,b)` compares complete vector lengths; ratio uses IEEE division by zero.",
    )
end
for (suffix, kind) in (
    (:distance, :euclidean),
    (:manhattan, :manhattan),
    (:correlation, :correlation),
    (:cosine_similarity, :cosine),
)
    name = Symbol(:ski_, suffix)
    @eval $name(a::SkiVector, b::SkiVector, args...) = pair_reduce(a, b, $(QuoteNode(kind)))
    register!(
        bundle_float_ski,
        name,
        "`$name(a,b)` reduces the shared prefix; empty or undefined → NaN.",
    )
end
function pair_reduce(a, b, kind)
    n = min(length(a), length(b))
    n == 0 && return NaN
    if kind in (:euclidean, :manhattan)
        s = 0.0
        for i in 1:n
            s += kind === :euclidean ? (a[i] - b[i])^2 : abs(a[i] - b[i])
        end
        return kind === :euclidean ? sqrt(s) : s
    end
    ma = kind === :correlation ? sum(a[i] for i in 1:n) / n : 0.0
    mb = kind === :correlation ? sum(b[i] for i in 1:n) / n : 0.0
    aa = 0.0
    bb = 0.0
    ab = 0.0
    for i in 1:n
        x = a[i] - ma
        y = b[i] - mb
        aa += x * x
        bb += y * y
        ab += x * y
    end
    ab / sqrt(aa * bb)
end
