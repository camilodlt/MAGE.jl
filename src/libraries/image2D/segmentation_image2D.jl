"""
Segmentation: intensity image in, label map out.

# Bundles

- [`bundle_image2DSegment_segmentation_factory`](@ref)

The exhaustive, always-current list of operators in each bundle is on the
[Bundle Catalogue](@ref) page.
"""
module image2D_segmentation

using ImageSegmentation
using ImageMorphology
using LRUCache
using TimerOutputs
using ..UTCGP: image2D_basic
using ..UTCGP: FunctionBundle, append_method!
import UTCGP:
    CONSTRAINED,
    MIN_INT,
    MAX_INT,
    MIN_FLOAT,
    MAX_FLOAT,
    _positive_params,
    _ceil_positive_params
using ImageCore: N0f8, Normed, clamp01nan!, clamp01nan, float64, Gray, FixedPoint
using ..UTCGP:
    SizedImage, SizedImage2D, SImageND, _get_image_tuple_size, _get_image_type, _validate_factory_type, _get_image_pixel_type, 
    IntensityPixel, BinaryPixel, SegmentPixel

fallback(args...) = return nothing
"""
    bundle_image2DSegment_segmentation_factory

Segmentation: image in, label map out. `fastscanning_image2D` groups
neighbouring pixels of similar intensity; `watershed_image2D` splits the
objects of a mask, cutting touching objects apart.

This is a *factory* bundle: each entry is a function of a type that returns the
method specialised for it, so the same operator can be instantiated for several
image or element types. See [Libraries](@ref) for how factories are specialised
into a library.
"""
bundle_image2DSegment_segmentation_factory = FunctionBundle(fallback)

# ######################## #
# Felzenswalb Segmentation #
# ######################## #

"""
    felzenswalb_image2D_factory(i::Type{I}) where {I<:SizedImage}

Returns the methods specialized on the given type `CONT`.


    m1(img::I, k::Int, args...) where {I <: CONT}

- `k` is clamped between (1,`k`). if not, all pixels are its own class.

TODO 

    m2(img::I, k::Int, min_size ::Int,  args...) where {I <: CONT}

- `k` is clamped between (1,`k`). if not, all pixels are its own class.

- `min_size` is also clamped between (2, `min_size`) because a cluster has at least 2 pixel in it 

"""
function felzenswalb_image2D_factory(i::Type{I}) where {I<:SizedImage}
    TT = Base.unwrap_unionall(I).parameters[2]
    _validate_factory_type(TT)
    FUNCTION_NAME = Symbol(:felzenswalb_2D, :_, Symbol(I))
    isdefined(@__MODULE__, FUNCTION_NAME) && return getfield(@__MODULE__, FUNCTION_NAME)
    StorageType = TT.types[1] # UInt8, UInt16 ...

    @eval function $FUNCTION_NAME(img::CONCT, k::Int, args::Vararg{Any}) where {CONCT<:$I}
        S = CONCT.parameters[1] # Tuple{X,Y}
        k = clamp(k, 1, k)
        segments = felzenszwalb(img, k)
        seg = labels_map(segments)
        reinterpreted = reinterpret.($TT, convert.($StorageType, seg)) # convert Int64 to the correct Normed{StorageType}
        return SImageND(reinterpreted, S)
    end

    return getfield(@__MODULE__, FUNCTION_NAME)
end

# ################### #
# HC Segmentation     #
# ################### #
function _hc_segmentation(img, q_th)
    imsize = size(img)
    img_petite = imresize(img.img, (50, 50))
    v = img_petite[:]
    m = reshape(v, length(v), 1)
    d = pairwise(Euclidean(), float.(m), dims = 1)
    h = hclust(d)
    th = quantile(h.height, q_th) # 80 % of mergin heights are below
    imresize(reshape(cutree(h, h = th), (50, 50)), imsize)
end


# ####################### #
# Unseeded Region Growing #
# ####################### #

"""
    unseededgrow_image2D_factory(i::Type{I}) where {I<:SizedImage}

`unseededgrow_2D(img, th::Float64)` and `unseededgrow_2D(img)` (threshold
`0.3`): unseeded region growing; the threshold limits how different a pixel may
be from the region it joins, so higher thresholds give fewer regions.
"""
function unseededgrow_image2D_factory(i::Type{I}) where {I<:SizedImage}
    TT = Base.unwrap_unionall(I).parameters[2]
    _validate_factory_type(TT) # N0f8, N0f16
    FUNCTION_NAME = Symbol(:unseededgrow_2D, :_, Symbol(I))
    isdefined(@__MODULE__, FUNCTION_NAME) && return getfield(@__MODULE__, FUNCTION_NAME)
    StorageType = TT.types[1] # UInt8, UInt16 ...
    DefaultTH = 0.3
    # m1 (img, th::Float)

    @eval function $FUNCTION_NAME(img::CONCT, th::Float64, args::Vararg{Any}) where {CONCT<:$I}
        S = CONCT.parameters[1] # Tuple{X,Y}
        th = isnan(th) ? $DefaultTH : th
        th = clamp(th, eps(Float64), th)
        gimg = Gray.(img)
        segments = unseeded_region_growing(gimg, th)
        seg = labels_map(segments)
        reinterpreted = reinterpret.($TT, convert.($StorageType, seg)) # convert Int64 to the correct Normed{StorageType}
        return SImageND(reinterpreted, S)
    end

    @eval function $FUNCTION_NAME(img::CONCT, args::Vararg{Any}) where {CONCT<:$I}
        S = CONCT.parameters[1] # Tuple{X,Y}
        gimg = Gray.(img)
        segments = unseeded_region_growing(gimg, $DefaultTH)
        seg = labels_map(segments)
        reinterpreted = reinterpret.($TT, convert.($StorageType, seg)) # convert Int64 to the correct Normed{StorageType}
        return SImageND(reinterpreted, S)
    end
    return getfield(@__MODULE__, FUNCTION_NAME)
end


# ############################ #
# Fast scanning Segmentation   #
# ############################ #

"""
    fastscanning_image2D_factory(i::Type{I}) where {I<:SizedImage}

TODO TEST
"""
function fastscanning_image2D_factory(i::Type{I}) where {I<:SizedImage{SIZE, SegmentPixel{T}}} where {SIZE,T}
    IT, PT, S = _get_image_type(I), _get_image_pixel_type(I), _get_image_tuple_size(I)
    S1, S2 = S.parameters[1], S.parameters[2]
    _validate_factory_type(IT)

    FUNCTION_NAME = Symbol(:fastscanning_image2D, :_, Symbol(I))
    isdefined(@__MODULE__, FUNCTION_NAME) && return getfield(@__MODULE__, FUNCTION_NAME)

    @eval function $FUNCTION_NAME(img::CONCT, th::Number, args::Vararg{Any}) where {CONCT<:SizedImage{$(SIZE), <:Union{BinaryPixel, IntensityPixel}}}
        th = isnan(th) ? 0.1 : th
        th = clamp(th, eps(Float64), 1.)
        segments = fast_scanning(reinterpret(img.img), th)
        seg = labels_map(segments)
        reinterpreted = convert.($T, seg)
        return SImageND($PT.(reinterpreted), $S)
    end
    @eval function $FUNCTION_NAME(img::CONCT, args::Vararg{Any}) where {CONCT<:SizedImage{$(SIZE), <:Union{BinaryPixel, IntensityPixel}}}
        $FUNCTION_NAME(img, 0.1)
    end
    return getfield(@__MODULE__, FUNCTION_NAME)
end

"""
Watershed split of the objects (`true` pixels) of a mask into labels.

The depth of an object pixel is its distance to the background. Each object
gets seeds where its depth is at least `h` times its own maximum depth, and the
objects are flooded from the seeds, so touching objects (e.g. two round cells
in contact) are cut along their narrowest part. Example: two disks of radius 9
whose centres are 14 pixels apart touch through a neck of depth ≈ 5.6, i.e.
`0.62` of their depth, so `h = 0.7` gives two labels and `h = 0.5` one.
Background pixels and pixels outside `restrict` are `0`.
"""
function _watershed_split(fg::AbstractMatrix{Bool}, restrict::AbstractMatrix{Bool}, h::Float64)
    objects = fg .& restrict
    any(objects) || return zeros(Int, size(fg))
    depth = distance_transform(feature_transform(.!objects))   # 0 on background
    components = label_components(objects)
    peak = zeros(Float64, maximum(components))
    @inbounds for i in eachindex(components)
        c = components[i]
        c > 0 && (peak[c] = max(peak[c], depth[i]))
    end
    seeds = falses(size(fg))
    @inbounds for i in eachindex(components)
        c = components[i]
        seeds[i] = c > 0 && depth[i] >= h * peak[c]
    end
    labels = labels_map(watershed(-depth, label_components(seeds); mask = objects))
    return labels .* objects
end

"Seed level `h` of `watershed_image2D`: clamped to `[0, 1]`; NaN/Inf → 0.7."
_watershed_level(th::Number) = (t = Float64(th); isfinite(t) ? clamp(t, 0.0, 1.0) : 0.7)

"""
    watershed_image2D_factory(i::Type{I}) where {I<:SizedImage{SIZE, SegmentPixel{T}}}

`watershed_image2D(mask, [restrict], [h])`: splits the objects (`true`
pixels) of `mask` into one label each, cutting touching objects at their
narrowest part. `h ∈ [0, 1]` (default `0.7`) is the seed level as a fraction of
each object's maximal depth: `0` gives one label per connected object, higher
values split more. `restrict`, a second mask, limits the result to its `true`
pixels. Background is `0`.
"""
function watershed_image2D_factory(i::Type{I}) where {I<:SizedImage{SIZE, SegmentPixel{T}}} where {SIZE,T}
    IT, PT, S = _get_image_type(I), _get_image_pixel_type(I), _get_image_tuple_size(I)
    _validate_factory_type(IT)

    FUNCTION_NAME = Symbol(:watershed_image2D, :_, Symbol(I))
    isdefined(@__MODULE__, FUNCTION_NAME) && return getfield(@__MODULE__, FUNCTION_NAME)

    @eval function $FUNCTION_NAME(img::CONCT, restrict::CONCT, th::Number, args::Vararg{Any}) where {CONCT<:SizedImage{$(SIZE), <:BinaryPixel}}
        labels = _watershed_split(reinterpret(img.img), reinterpret(restrict.img), _watershed_level(th))
        return SImageND($PT.(convert.($IT, labels)), $S)
    end

    @eval function $FUNCTION_NAME(img::CONCT, th::Number, args::Vararg{Any}) where {CONCT<:SizedImage{$(SIZE), <:BinaryPixel}}
        fg = reinterpret(img.img)
        labels = _watershed_split(fg, trues(size(fg)), _watershed_level(th))
        return SImageND($PT.(convert.($IT, labels)), $S)
    end

    @eval function $FUNCTION_NAME(img::CONCT, args::Vararg{Any}) where {CONCT<:SizedImage{$(SIZE), <:BinaryPixel}}
        $FUNCTION_NAME(img, 0.7)
    end

    return getfield(@__MODULE__, FUNCTION_NAME)
end

# Factory Methods
# append_method!(
#     bundle_image2D_segmentation_factory,
#     felzenswalb_image2D_factory,
#     :felzenswalb_2D,
# )

# append_method!(
#     bundle_image2D_segmentation_factory,
#     unseededgrow_image2D_factory,
#     :unseededgrow_2D,
# )

append_method!(
    bundle_image2DSegment_segmentation_factory,
    fastscanning_image2D_factory,
    :fastscanning_image2D,
    ;
    description = "Segments the image using a fast scanning region-labeling strategy.",
)

append_method!(
    bundle_image2DSegment_segmentation_factory,
    watershed_image2D_factory,
    :watershed_image2D,
    ;
    description = "(mask, [restrict], [h]): one label per object of the mask, touching objects cut at their narrowest part; h in [0, 1] (default 0.7), higher splits more, 0 keeps connected objects whole.",
)

end
