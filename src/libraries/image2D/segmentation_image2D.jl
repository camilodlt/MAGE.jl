"""
Segmentation: intensity image in, label map out.

# Bundles

- [`bundle_image2DSegment_segmentation_factory`](@ref)

The exhaustive, always-current list of operators in each bundle is on the
[Bundle Catalogue](@ref) page.
"""
module image2D_segmentation

using ..UTCGP: _factory_type_symbol, @serialized_factory

# Call tree: fastscanning factory → ImageSegmentation.fast_scanning! → output.
# Watershed factory → _watershed_split → feature/distance transforms,
# component labels, watershed flooding → output.


using ..UTCGP: @image_out, scratch, output_pixels, image_result, pixel_values!
using ..image2D_foreground_extraction_discrete: _resolution_size, _resolution_pool!

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
@serialized_factory function felzenswalb_image2D_factory(i::Type{I}) where {I<:SizedImage}
    TT = Base.unwrap_unionall(I).parameters[2]
    _validate_factory_type(TT)
    FUNCTION_NAME = Symbol(:felzenswalb_2D, :_, _factory_type_symbol(I))
    isdefined(@__MODULE__, FUNCTION_NAME) && return getfield(@__MODULE__, FUNCTION_NAME)
    StorageType = TT.types[1] # UInt8, UInt16 ...

    # out: copy (the kernel currently allocates its result).
    @eval @image_out function $FUNCTION_NAME(img::CONCT, k::Int, args::Vararg{Any}) where {CONCT<:$I}
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
@serialized_factory function unseededgrow_image2D_factory(i::Type{I}) where {I<:SizedImage}
    TT = Base.unwrap_unionall(I).parameters[2]
    _validate_factory_type(TT) # N0f8, N0f16
    FUNCTION_NAME = Symbol(:unseededgrow_2D, :_, _factory_type_symbol(I))
    isdefined(@__MODULE__, FUNCTION_NAME) && return getfield(@__MODULE__, FUNCTION_NAME)
    StorageType = TT.types[1] # UInt8, UInt16 ...
    DefaultTH = 0.3
    # m1 (img, th::Float)

    # out: copy (the kernel currently allocates its result).
    @eval @image_out function $FUNCTION_NAME(img::CONCT, th::Float64, args::Vararg{Any}) where {CONCT<:$I}
        S = CONCT.parameters[1] # Tuple{X,Y}
        th = isnan(th) ? $DefaultTH : th
        th = clamp(th, eps(Float64), th)
        gimg = Gray.(img)
        segments = unseeded_region_growing(gimg, th)
        seg = labels_map(segments)
        reinterpreted = reinterpret.($TT, convert.($StorageType, seg)) # convert Int64 to the correct Normed{StorageType}
        return SImageND(reinterpreted, S)
    end

    # out: copy (the kernel currently allocates its result).
    @eval @image_out function $FUNCTION_NAME(img::CONCT, args::Vararg{Any}) where {CONCT<:$I}
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

Uses the library scan with a reused label matrix and writes directly to `out`.
For example, a constant 2 × 2 image has label 1 at every pixel.
"""
# TODO speed: the library still allocates region dictionaries and disjoint sets.
@serialized_factory function fastscanning_image2D_factory(i::Type{I}) where {I<:SizedImage{SIZE, SegmentPixel{T}}} where {SIZE,T}
    IT, PT, S = _get_image_type(I), _get_image_pixel_type(I), _get_image_tuple_size(I)
    S1, S2 = S.parameters[1], S.parameters[2]
    _validate_factory_type(IT)

    FUNCTION_NAME = Symbol(:fastscanning_image2D, :_, _factory_type_symbol(I))
    isdefined(@__MODULE__, FUNCTION_NAME) && return getfield(@__MODULE__, FUNCTION_NAME)

    @eval function $FUNCTION_NAME(img::CONCT, th::Number, args::Vararg{Any}; out = nothing) where {CONCT<:SizedImage{$(SIZE), <:Union{BinaryPixel, IntensityPixel}}}
        th = isnan(th) ? 0.1 : th
        th = clamp(th, eps(Float64), 1.)
        values = reinterpret(img.img)
        labels = scratch(:segmentation_scan_labels, Int, size(values)...)
        fill!(labels, -1)
        segments = ImageSegmentation.fast_scanning!(labels, values, th)
        seg = labels_map(segments)
        pixels = output_pixels(out, img, $PT)
        pixels .= $PT.(convert.($T, seg))
        return image_result(out, pixels, $S)
    end
    @eval function $FUNCTION_NAME(img::CONCT, args::Vararg{Any}; out = nothing) where {CONCT<:SizedImage{$(SIZE), <:Union{BinaryPixel, IntensityPixel}}}
        return $FUNCTION_NAME(img, 0.1; out)
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

function _watershed_split(
        foreground::AbstractMatrix{Bool}, restriction::AbstractMatrix{Bool},
        level::Float64, limit::Int = 32,
    )
    height, width = size(foreground)
    height * width <= 1_000_000 || error("watershed input exceeded its work budget")
    working_height, working_width = _resolution_size(height, width, limit)
    working_height * working_width <= 50_176 || error("watershed solve exceeded its work budget")
    if (working_height, working_width) == (height, width)
        return _watershed_split_full(foreground, restriction, level)
    end
    # Pool the intersection so disjoint foreground and restriction cannot merge.
    objects = scratch(:watershed_full_objects, Bool, height, width)
    objects .= foreground .& restriction
    pooled_objects = scratch(:watershed_low_fg, Bool, working_height, working_width)
    _resolution_pool!(pooled_objects, objects, Val(:any))
    pooled_restriction = scratch(:watershed_low_restrict, Bool, working_height, working_width)
    fill!(pooled_restriction, true)
    pooled_labels = _watershed_split_full(pooled_objects, pooled_restriction, level)
    labels = scratch(:watershed_lifted_labels, Int, height, width)
    return _watershed_component_pairs!(labels, objects, pooled_labels)
end

"""Give each (full component, coarse basin) its own ID; two islands never share one.
IDs follow first occurrence in column-major order, e.g. two isolated pixels get 1, 2.
"""
function _watershed_component_pairs!(labels, objects, basins)
    height, width = size(objects)
    working_height, working_width = size(basins)
    components = scratch(:watershed_full_components, Int, height, width)
    label_components!(components, objects)
    # At most one pair per foreground pixel; a half-full table bounds probing.
    capacity = nextpow(2, max(2, 2count(objects)))
    keys = scratch(:watershed_pair_keys, UInt64, capacity)
    values = scratch(:watershed_pair_values, Int, capacity)
    fill!(keys, 0)
    next_label = 0
    @inbounds for column in 1:width, row in 1:height
        component = components[row, column]
        if component == 0
            labels[row, column] = 0
            continue
        end
        basin = basins[cld(row * working_height, height), cld(column * working_width, width)]
        # Both fields fit 32 bits under the existing million-pixel input budget.
        key = (UInt64(component) << 32) | UInt64(basin)
        mixed = (key ⊻ (key >> 33)) * 0xff51afd7ed558ccd
        mixed = mixed ⊻ (mixed >> 33)
        slot = Int(mixed & UInt64(capacity - 1)) + 1
        while keys[slot] != 0 && keys[slot] != key
            slot = slot == capacity ? 1 : slot + 1
        end
        if keys[slot] == 0
            next_label += 1
            keys[slot] = key
            values[slot] = next_label
        end
        labels[row, column] = values[slot]
    end
    return labels
end

function _watershed_split_full(foreground::AbstractMatrix{Bool}, restriction::AbstractMatrix{Bool}, level::Float64)
    objects = scratch(:segmentation_objects, Bool, size(foreground)...)
    objects .= foreground .& restriction
    any(objects) || return zeros(Int, size(foreground))
    # Package kernels determine distances and flooding tie order.
    depth = distance_transform(feature_transform(.!objects))   # 0 on background
    components = scratch(:segmentation_components, Int, size(foreground)...)
    label_components!(components, objects)
    peak = zeros(Float64, maximum(components))
    @inbounds for i in eachindex(components)
        c = components[i]
        c > 0 && (peak[c] = max(peak[c], depth[i]))
    end
    seeds = scratch(:segmentation_seeds, Bool, size(foreground)...)
    @inbounds for i in eachindex(components)
        c = components[i]
        seeds[i] = c > 0 && depth[i] >= level * peak[c]
    end
    flood_depth = scratch(:segmentation_flood_depth, Float64, size(depth)...)
    flood_depth .= .-depth
    markers = scratch(:segmentation_markers, Int, size(foreground)...)
    label_components!(markers, seeds)
    labels = labels_map(watershed(flood_depth, markers; mask = objects))
    labels .*= objects
    return labels
end

"""Write checked watershed labels; e.g. label 256 cannot fit UInt8 storage."""
function _watershed_result(out, image, labels, ::Type{P}, ::Type{S}) where {P,S}
    pixels = output_pixels(out, image, P)
    storage_type = fieldtype(P, 1)
    maximum(labels; init = 0) <= typemax(storage_type) ||
        throw(OverflowError("watershed labels exceed output storage"))
    pixels .= P.(convert.(storage_type, labels))
    return image_result(out, pixels, S)
end

"""Unwrap mask values into scratch; e.g. `BinaryPixel(true)` becomes `true`.
Unlike one-argument `reinterpret`, this does not allocate a full-size BitMatrix.
"""
function _watershed_values!(key, pixels)
    values = scratch(key, Bool, size(pixels)...)
    return pixel_values!(values, pixels)
end

"""Split an unrestricted mask; e.g. a single true pixel receives label 1."""
function _watershed_unrestricted(pixels, level, limit = 32)
    foreground = _watershed_values!(:watershed_input_foreground, pixels)
    restriction = scratch(:segmentation_restrict, Bool, size(foreground)...)
    fill!(restriction, true)
    return _watershed_split(foreground, restriction, level, limit)
end

"""Select the working longer axis by sign; `(225, 0)` gives the half-size axis 113.
NaN takes the cheapest branch, negative infinity selects full, and signed zero
selects half. Comparisons use the original Real value without rounding it.
"""
function _watershed_resolution(longer_axis::Int, resolution::Real)
    resolution < 0 && return longer_axis
    resolution == 0 && return cld(longer_axis, 2)
    return 32
end

"Seed level `h` of `watershed_image2D`: clamped to `[0, 1]`; NaN/Inf → 0.7."
_watershed_level(th::Number) = (t = Float64(th); isfinite(t) ? clamp(t, 0.0, 1.0) : 0.7)

"""
    watershed_image2D_factory(i::Type{I}) where {I<:SizedImage{SIZE, SegmentPixel{T}}}

`watershed_image2D(mask, [restrict], [h])`

`watershed_image2D(mask, h, resolution::Real)` selects its working size by sign:
negative uses full resolution; zero (including `-0.0`) uses a longer axis of
`cld(longer_axis, 2)` with aspect preserved; positive or NaN uses a longer axis
of 32. Integers and floats both work; `-Inf` selects full and `Inf` selects 32.
No input is enlarged. For example, `(mask, 0.7, 0)` on a 224×100 mask solves
at 112×50, while `(mask, 0.7, -1)` uses 224×100. A 50,176-pixel solve budget
throws into the existing fallback when exceeded.

Reduced solves keep full-resolution connected components distinct and number
(component, coarse basin) pairs in first-occurrence order.
The default working longer axis is 32. The operator: splits the objects (`true`
pixels) of `mask` into one label each, cutting touching objects at their
narrowest part. `h ∈ [0, 1]` (default `0.7`) is the seed level as a fraction of
each object's maximal depth: `0` gives one label per connected object, higher
values split more. `restrict`, a second mask, limits the result to its `true`
pixels. Background is `0`. For example, an isolated true pixel gets label 1.
"""
@serialized_factory function watershed_image2D_factory(i::Type{I}) where {I<:SizedImage{SIZE, SegmentPixel{T}}} where {SIZE,T}
    IT, PT, S = _get_image_type(I), _get_image_pixel_type(I), _get_image_tuple_size(I)
    _validate_factory_type(IT)

    FUNCTION_NAME = Symbol(:watershed_image2D, :_, _factory_type_symbol(I))
    isdefined(@__MODULE__, FUNCTION_NAME) && return getfield(@__MODULE__, FUNCTION_NAME)

    @eval function $FUNCTION_NAME(img::CONCT, restriction::CONCT, level::Number, args::Vararg{Any}; out = nothing) where {CONCT<:SizedImage{$(SIZE), <:BinaryPixel}}
        foreground = _watershed_values!(:watershed_input_foreground, img.img)
        restriction_values = _watershed_values!(:watershed_input_restriction, restriction.img)
        labels = _watershed_split(foreground, restriction_values, _watershed_level(level))
        return _watershed_result(out, img, labels, $PT, $S)
    end

    # A free third graph input selects resolution without reinterpreting seed level.
    @eval function $FUNCTION_NAME(img::CONCT, level::Number, resolution::Real, args::Vararg{Any}; out = nothing) where {CONCT<:SizedImage{$(SIZE), <:BinaryPixel}}
        limit = _watershed_resolution(maximum(size(img.img)), resolution)
        labels = _watershed_unrestricted(img.img, _watershed_level(level), limit)
        return _watershed_result(out, img, labels, $PT, $S)
    end

    @eval function $FUNCTION_NAME(img::CONCT, level::Number, args::Vararg{Any}; out = nothing) where {CONCT<:SizedImage{$(SIZE), <:BinaryPixel}}
        labels = _watershed_unrestricted(img.img, _watershed_level(level))
        return _watershed_result(out, img, labels, $PT, $S)
    end

    @eval function $FUNCTION_NAME(img::CONCT, args::Vararg{Any}; out = nothing) where {CONCT<:SizedImage{$(SIZE), <:BinaryPixel}}
        return $FUNCTION_NAME(img, 0.7; out)
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
