"""
    bundle_ski_properties

Image → SkiVector: scalar skimage-compatible 2D region properties. Binary input
is labeled with 8-connectivity; intensity input uses `>= 0.5`. Optional ROI is
always binary and intersects foreground before labeling. Intensity/weighted
operators accept `(binary, intensity[, roi])`; a single intensity image uses
itself as the source. Values use zero-based coordinates, exclusive bbox maxima,
unit spacing, population intensity std, and untransformed Hu invariants.
"""
bundle_ski_properties = FunctionBundle(() -> SkiVector())
const SHAPE_PROPERTIES = (
    :area,
    :area_bbox,
    :area_convex,
    :area_filled,
    :axis_major_length,
    :axis_minor_length,
    :bbox_min_row,
    :bbox_min_col,
    :bbox_max_row,
    :bbox_max_col,
    :centroid_row,
    :centroid_col,
    :centroid_local_row,
    :centroid_local_col,
    :eccentricity,
    :equivalent_diameter_area,
    :euler_number,
    :extent,
    :feret_diameter_max,
    :inertia_tensor_eigval_0,
    :inertia_tensor_eigval_1,
    :num_pixels,
    :orientation,
    :perimeter,
    :perimeter_crofton,
    :solidity,
)
const INTENSITY_PROPERTIES = (
    :intensity_max,
    :intensity_mean,
    :intensity_median,
    :intensity_min,
    :intensity_std,
    :centroid_weighted_row,
    :centroid_weighted_col,
    :centroid_weighted_local_row,
    :centroid_weighted_local_col,
)

function output(out::SkiVector{S}, n, ::Type{SkiVector{S}}) where {S}
    resize!(out.values, n)
    resize!(out.ids, n)
    out
end
output(::Nothing, n, ::Type{V}) where {V<:SkiVector} = output(V(), n, V)
function derived(out, n, v::SkiVector{S}) where {S}
    result = output(out, n, SkiVector{S})
    result.regions = v.regions
    result
end
function extract(img::SImageND{S}, roi, source, measure, out) where {S}
    source === nothing || size(img) == size(source) || throw(DimensionMismatch("intensity size"))
    result = output(out, 0, SkiVector{S})
    t = regions!(result.own, img, roi)
    t.intensity = source
    result.regions = t
    resize!(result.values, t.n)
    resize!(result.ids, t.n)
    @inbounds for id in 1:t.n
        result.values[id] = measure(t, id, source)
        result.ids[id] = Int32(id)
    end
    result
end
struct Property{P} end
(::Property{P})(t, id, source) where {P} = property(t, id, Val(P), source)
struct Moment{P,Q,C,N,W} end
(::Moment{P,Q,C,N,W})(t, id, source) where {P,Q,C,N,W} =
    moment(t, id, P, Q, C, N, W ? source : nothing)
struct Hu{K,W} end
(::Hu{K,W})(t, id, source) where {K,W} = hu(t, id, K, W ? source : nothing)

function register!(bundle, name, description)
    @eval @doc $description $name
    append_method!(bundle, Base.invokelatest(getfield, @__MODULE__, name), name; description)
end
const PROPERTY_SPECS = Tuple{Symbol,Any,Bool}[]
function define_property!(name, measure, weighted = false)
    push!(PROPERTY_SPECS, (Symbol(String(name)[5:end]), measure, weighted))
    if weighted
        @eval begin
            $name(img::Intensity, args...; out = nothing) =
                extract(img, nothing, img, $measure, out)
            $name(img::Intensity, roi::Mask, args...; out = nothing) =
                extract(img, roi, img, $measure, out)
            $name(img::Mask, source::Intensity, args...; out = nothing) =
                extract(img, nothing, source, $measure, out)
            $name(img::Mask, source::Intensity, roi::Mask, args...; out = nothing) =
                extract(img, roi, source, $measure, out)
        end
    else
        @eval begin
            $name(img::Source, args...; out = nothing) =
                extract(img, nothing, nothing, $measure, out)
            $name(img::Source, roi::Mask, args...; out = nothing) =
                extract(img, roi, nothing, $measure, out)
        end
    end
    register!(
        bundle_ski_properties,
        name,
        "`$name(img[, roi]; out=nothing)` returns one scalar per 8-connected region. Weighted/intensity forms also accept `(binary, intensity[, roi])`. ROI must be binary; out is an optional owned SkiVector.",
    )
end
for p in SHAPE_PROPERTIES
    define_property!(Symbol(:ski_, p), Property{p}())
end
for p in INTENSITY_PROPERTIES
    define_property!(Symbol(:ski_, p), Property{p}(), true)
end
# All order-three entries, each exposed as a scalar purpose operator.
for weighted in (false, true), kind in (:raw, :central, :normalized)
    prefix = weighted ? :moments_weighted : :moments
    prefix = kind === :raw ? prefix : Symbol(prefix, :_, kind)
    for p in 0:3, q in 0:3
        measure = Moment{p,q,kind !== :raw,kind === :normalized,weighted}()
        define_property!(Symbol(:ski_, prefix, :_, p, :_, q), measure, weighted)
    end
end
for weighted in (false, true), k in 1:7
    name = Symbol(weighted ? :ski_moments_weighted_hu_ : :ski_moments_hu_, k)
    define_property!(name, Hu{k,weighted}(), weighted)
end
