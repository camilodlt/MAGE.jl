"""
    bundle_image2DBinary_ski_factory

Sixteen size-specialized selectors: object/bbox × lt/lte/gt/gte/max/min/
top_percentile/bottom_percentile. Each callable has an explicit image form
`f(img, ski[, amount])` and reference form `f(ski[, amount])`. All image/vector
sizes must match. Only max/min omit amount; no numeric amount is defaulted.
A region is kept if any element with its id passes. Id zero is ignored.
Thresholds use all vector values (including id-zero values), retaining ties.
Percentages use [0,100]. ROI has already been applied when properties were
extracted; bbox mode fills the selected rectangles. All methods support `out`.
"""
bundle_image2DBinary_ski_factory = FunctionBundle(() -> nothing)
"""
    bundle_image2DIntensity_ski_factory

The same sixteen selectors, returning supplied image intensities where selected
and zero elsewhere. Reference forms use the referenced intensity source, when
present, or the labeled image when it is an intensity image. Without either they write 1.0 at selected pixels,
including bbox pixels. Binary reference output always marks selected pixels.
"""
bundle_image2DIntensity_ski_factory = FunctionBundle(() -> nothing)

function selected_regions(v, amount, criterion)
    t = v.regions
    keep = fill!(resize!(scratch(:ski_selection_keep, Bool, 0), t.n), false)
    isempty(v) && return keep
    threshold =
        criterion === :max ? maximum(v) :
        criterion === :min ? minimum(v) :
        criterion === :top_percentile ? percentile(v, 100 - 100fraction(amount)) :
        criterion === :bottom_percentile ? percentile(v, amount) : Float64(amount)
    @inbounds for i in eachindex(v)
        id = v.ids[i]
        1 <= id <= t.n || continue
        x = v.values[i]
        yes =
            criterion === :lt ? x < threshold :
            criterion === :lte ? x <= threshold :
            criterion === :gt ? x > threshold :
            criterion === :gte ? x >= threshold :
            criterion in (:max, :min) ? x == threshold :
            criterion === :top_percentile ? x >= threshold : x <= threshold
        yes && (keep[id] = true)
    end
    keep
end

function select_image(img, v::SkiVector{S}, amount, criterion, bbox, ::Type{I}, out) where {S,I}
    t = v.regions
    keep = selected_regions(v, amount, criterion)
    h, w = S.parameters
    chosen = fill!(scratch(:ski_chosen, Bool, h, w), false)
    if bbox
        for id in 1:t.n
            keep[id] || continue
            r0, r1, c0, c1 = bounds(t, id)
            @inbounds for c in c0:c1, r in r0:r1
                chosen[r, c] = true
            end
        end
    else
        @inbounds for i in eachindex(chosen)
            id = t.labels[i]
            chosen[i] = 1 <= id <= t.n && keep[id]
        end
    end
    PT = _get_image_pixel_type(I)
    pixels = out === nothing ? Matrix{PT}(undef, h, w) : out.img
    @inbounds for i in eachindex(pixels)
        yes = chosen[i]
        pixels[i] =
            PT <: BinaryPixel ? PT(yes) :
            !yes ? PT(0) : img === nothing ? PT(1) : PT(Float64(img.img[i]))
    end
    image_result(out, pixels, S)
end
# An intensity image that was itself labeled is its own intensity source.
function reference_image(v)
    t = v.regions
    t.intensity !== nothing && return t.intensity
    t.image isa Intensity ? t.image : nothing
end

@serialized_factory function selection_factory(
    ::Type{I},
    criterion::Symbol,
    bbox::Bool,
    tag::Symbol,
) where {I<:SizedImage2D}
    S = _get_image_tuple_size(I)
    name = Symbol(tag, :_, _factory_type_symbol(I))
    isdefined(@__MODULE__, name) && return Base.invokelatest(getfield, @__MODULE__, name)
    if criterion in (:max, :min)
        @eval begin
            $name(
                img::SImageND{$S,T,2,C},
                v::SkiVector{$S},
                args...;
                out = nothing,
            ) where {T<:Union{BinaryPixel,IntensityPixel},C} =
                select_image(img, v, nothing, $(QuoteNode(criterion)), $bbox, $I, out)
            $name(v::SkiVector{$S}, args...; out = nothing) = select_image(
                reference_image(v),
                v,
                nothing,
                $(QuoteNode(criterion)),
                $bbox,
                $I,
                out,
            )
        end
    else
        @eval begin
            $name(
                img::SImageND{$S,T,2,C},
                v::SkiVector{$S},
                amount::Real,
                args...;
                out = nothing,
            ) where {T<:Union{BinaryPixel,IntensityPixel},C} =
                select_image(img, v, amount, $(QuoteNode(criterion)), $bbox, $I, out)
            $name(v::SkiVector{$S}, amount::Real, args...; out = nothing) =
                select_image(reference_image(v), v, amount, $(QuoteNode(criterion)), $bbox, $I, out)
        end
    end
    Base.invokelatest(getfield, @__MODULE__, name)
end
for criterion in (:lt, :lte, :gt, :gte, :max, :min, :top_percentile, :bottom_percentile),
    bbox in (false, true)

    tag = Symbol(:ski_keep_, bbox ? :bbox_ : :objects_, criterion)
    for (kind, bundle) in (
        (:binary, bundle_image2DBinary_ski_factory),
        (:intensity, bundle_image2DIntensity_ski_factory),
    )
        name = Symbol(tag, :_, kind, :_factory)
        if kind === :binary
            @eval $name(::Type{I}) where {A,B,T,I<:SizedImage2D{A,B,BinaryPixel{T}}} =
                selection_factory(I, $(QuoteNode(criterion)), $bbox, $(QuoteNode(tag)))
        else
            @eval $name(::Type{I}) where {A,B,T,I<:SizedImage2D{A,B,IntensityPixel{T}}} =
                selection_factory(I, $(QuoteNode(criterion)), $bbox, $(QuoteNode(tag)))
        end
        @eval @doc $(
            "`$name(I)` specializes $tag. The callable accepts `(img, ski, amount)` or `(ski, amount)`; max/min omit amount. See the ski selector bundle for provenance and reference semantics."
        ) $name
        append_method!(
            bundle,
            getfield(@__MODULE__, name),
            tag;
            description = "Select $(bbox ? "bboxes" : "objects") by $criterion using SkiVector ids; $kind output.",
        )
    end
end
