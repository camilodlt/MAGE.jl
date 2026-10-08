"""
Connected-component selection and source-image masking.

# Bundles

- bundle_image2DBinary_blob_extraction_factory
- bundle_image2DIntensity_blob_extraction_factory

Both bundles share an 8-connected-component backbone. The concrete type used
to specialize a factory always determines the output dimensions and pixel type.
"""
module image2D_blob_extraction

using ImageMorphology: label_components, strel_box
using Statistics: median!
using ..UTCGP: FunctionBundle, append_method!
using ..UTCGP:
    BinaryPixel,
    IntensityPixel,
    SImageND,
    SizedImage,
    SizedImage2D,
    _get_image_pixel_type,
    _get_image_tuple_size,
    _get_image_type,
    _validate_factory_type

fallback(args...) = return nothing

"""
    bundle_image2DBinary_blob_extraction_factory

Connected-component selectors that return a same-size binary mask. Operator
names end in _blob to distinguish them from the intensity operators that return
masked source images. Inputs may be intensity saliency maps or binary masks.
Components are 8-connected and ties use first-pixel row-major order.

This is an opt-in factory bundle returned by get_extension_blob_binaryimg.
Specialization fixes the output dimensions and BinaryPixel type.
"""
const bundle_image2DBinary_blob_extraction_factory = FunctionBundle(fallback)

"""
    bundle_image2DIntensity_blob_extraction_factory

Connected-component selectors that return a same-size source intensity image
masked by the selected component. Statistical selectors compare source pixels
within each blob. Empty selections return an all-zero image.

This is an opt-in factory bundle returned by get_extension_blob_intensityimg.
Specialization fixes the output dimensions and IntensityPixel storage type.
"""
const bundle_image2DIntensity_blob_extraction_factory = FunctionBundle(fallback)

struct _BlobGeometry
    label::Int
    area::Int
    min_row::Int
    max_row::Int
    min_col::Int
    max_col::Int
    first_row_major::Int
end

@inline _blob_width(blob::_BlobGeometry) = blob.max_col - blob.min_col + 1
@inline _blob_height(blob::_BlobGeometry) = blob.max_row - blob.min_row + 1

_blob_labels(mask::AbstractMatrix{Bool}) =
    label_components(mask, strel_box((3, 3)))

function _blob_geometries(labels::AbstractMatrix{<:Integer})
    isempty(labels) && return _BlobGeometry[]
    number_of_labels = maximum(labels)
    number_of_labels == 0 && return _BlobGeometry[]

    areas = zeros(Int, number_of_labels)
    min_rows = fill(typemax(Int), number_of_labels)
    max_rows = zeros(Int, number_of_labels)
    min_cols = fill(typemax(Int), number_of_labels)
    max_cols = zeros(Int, number_of_labels)
    first_pixels = fill(typemax(Int), number_of_labels)
    width = size(labels, 2)

    @inbounds for row in axes(labels, 1), col in axes(labels, 2)
        label = Int(labels[row, col])
        label == 0 && continue
        areas[label] += 1
        min_rows[label] = min(min_rows[label], row)
        max_rows[label] = max(max_rows[label], row)
        min_cols[label] = min(min_cols[label], col)
        max_cols[label] = max(max_cols[label], col)
        first_pixels[label] = min(first_pixels[label], (row - 1) * width + col)
    end

    blobs = _BlobGeometry[]
    sizehint!(blobs, number_of_labels)
    for label in 1:number_of_labels
        areas[label] == 0 && continue
        push!(blobs, _BlobGeometry(
            label,
            areas[label],
            min_rows[label],
            max_rows[label],
            min_cols[label],
            max_cols[label],
            first_pixels[label],
        ))
    end
    sort!(blobs; by = blob -> blob.first_row_major)
    return blobs
end

function _threshold_value(value::Real)
    converted = Float64(value)
    return isfinite(converted) ? clamp(converted, 0.0, 1.0) : 0.5
end

function _pixel_count(value::Real, number_of_pixels::Int; default::Int = 1)
    converted = Float64(value)
    isfinite(converted) || return clamp(default, 1, max(number_of_pixels, 1))
    bounded = clamp(converted, 1.0, Float64(max(number_of_pixels, 1)))
    return round(Int, bounded)
end

_saliency_mask(saliency::SizedImage, threshold::Float64) =
    Float64.(reinterpret(saliency.img)) .>= threshold
_binary_mask(mask::SizedImage) = Bool.(reinterpret(mask.img))

function _geometry_value(blob::_BlobGeometry, selector::Symbol)
    selector === :largest && return blob.area
    selector === :smallest && return blob.area
    selector === :longest_horizontally && return _blob_width(blob)
    selector === :shortest_horizontally && return _blob_width(blob)
    selector === :longest_vertically && return _blob_height(blob)
    selector === :shortest_vertically && return _blob_height(blob)
    throw(ArgumentError("unknown blob geometry selector: $selector"))
end

function _select_geometry(mask::AbstractMatrix{Bool}, selector::Symbol, minimum_area::Int)
    labels = _blob_labels(mask)
    blobs = filter(blob -> blob.area >= minimum_area, _blob_geometries(labels))
    isempty(blobs) && return falses(size(mask))

    choose_maximum = selector in (:largest, :longest_horizontally, :longest_vertically)
    selected = first(blobs)
    selected_value = _geometry_value(selected, selector)
    for blob in Iterators.drop(blobs, 1)
        value = _geometry_value(blob, selector)
        better = choose_maximum ? value > selected_value : value < selected_value
        if better
            selected = blob
            selected_value = value
        end
    end
    return labels .== selected.label
end

function _select_area_between(mask::AbstractMatrix{Bool}, minimum_area::Int, maximum_area::Int)
    labels = _blob_labels(mask)
    selected = falses(size(mask))
    for blob in _blob_geometries(labels)
        minimum_area <= blob.area <= maximum_area || continue
        selected .|= labels .== blob.label
    end
    return selected
end

@inline function _finite_value(value::Real)
    converted = Float64(value)
    return isfinite(converted) ? converted : 0.0
end

function _component_statistics(values, labels, blobs, statistic::Symbol)
    number_of_labels = maximum(labels)
    counts = zeros(Int, number_of_labels)

    if statistic === :median
        samples = [Float64[] for _ in 1:number_of_labels]
        for blob in blobs
            sizehint!(samples[blob.label], blob.area)
        end
        @inbounds for index in eachindex(values, labels)
            label = Int(labels[index])
            label == 0 && continue
            push!(samples[label], _finite_value(values[index]))
        end
        return [isempty(sample) ? 0.0 : median!(sample) for sample in samples]
    end

    if statistic === :maximum || statistic === :minimum
        initial = statistic === :maximum ? -Inf : Inf
        result = fill(initial, number_of_labels)
        @inbounds for index in eachindex(values, labels)
            label = Int(labels[index])
            label == 0 && continue
            value = _finite_value(values[index])
            counts[label] += 1
            result[label] = statistic === :maximum ?
                            max(result[label], value) : min(result[label], value)
        end
        return result
    end

    statistic in (:mean, :std) ||
        throw(ArgumentError("unknown blob statistic: $statistic"))
    sums = zeros(Float64, number_of_labels)
    sum_squares = statistic === :std ? zeros(Float64, number_of_labels) : Float64[]
    @inbounds for index in eachindex(values, labels)
        label = Int(labels[index])
        label == 0 && continue
        value = _finite_value(values[index])
        counts[label] += 1
        sums[label] += value
        statistic === :std && (sum_squares[label] += value * value)
    end
    means = sums ./ max.(counts, 1)
    statistic === :mean && return means
    return sqrt.(max.(sum_squares ./ max.(counts, 1) .- means .^ 2, 0.0))
end

function _select_statistic(image_values, mask, statistic::Symbol, direction::Symbol)
    labels = _blob_labels(mask)
    blobs = _blob_geometries(labels)
    isempty(blobs) && return falses(size(mask))

    statistic_values = _component_statistics(image_values, labels, blobs, statistic)
    selected = first(blobs)
    selected_value = statistic_values[selected.label]
    for blob in Iterators.drop(blobs, 1)
        value = statistic_values[blob.label]
        better = direction === :maximum ? value > selected_value : value < selected_value
        if better
            selected = blob
            selected_value = value
        end
    end
    return labels .== selected.label
end

function _masked_values(image::SizedImage, mask::AbstractMatrix{Bool})
    source = reinterpret(image.img)
    result = similar(source)
    zero_value = zero(eltype(source))
    @inbounds for index in eachindex(source, mask)
        result[index] = mask[index] ? source[index] : zero_value
    end
    return result
end

function _binary_geometry_factory(
        ::Type{I},
        selector::Symbol,
    ) where {S1,S2,T,I<:SizedImage2D{S1,S2,BinaryPixel{T}}}
    IT = _get_image_type(I)
    PT = _get_image_pixel_type(I)
    S = _get_image_tuple_size(I)
    _validate_factory_type(IT)
    function_name = Symbol(:blob_, selector, :_binary_, Symbol(I))

    fn = @eval function $function_name(
            saliency::CONCT,
            threshold_input::Real,
            minimum_area_input::Real,
            args::Vararg{Any},
        ) where {ST,CONCT<:SizedImage{$S,IntensityPixel{ST}}}
        threshold = _threshold_value(threshold_input)
        minimum_area = _pixel_count(minimum_area_input, length(saliency))
        selected = _select_geometry(
            _saliency_mask(saliency, threshold),
            $(QuoteNode(selector)),
            minimum_area,
        )
        return SImageND($PT.(selected), $S)
    end
    @eval function $function_name(
            saliency::CONCT,
            threshold::Real,
            args::Vararg{Any},
        ) where {ST,CONCT<:SizedImage{$S,IntensityPixel{ST}}}
        return $function_name(saliency, threshold, 1, args...)
    end
    @eval function $function_name(
            saliency::CONCT,
            args::Vararg{Any},
        ) where {ST,CONCT<:SizedImage{$S,IntensityPixel{ST}}}
        return $function_name(saliency, 0.5, 1, args...)
    end
    @eval function $function_name(
            mask::CONCT,
            minimum_area_input::Real,
            args::Vararg{Any},
        ) where {BT,CONCT<:SizedImage{$S,BinaryPixel{BT}}}
        minimum_area = _pixel_count(minimum_area_input, length(mask))
        selected = _select_geometry(
            _binary_mask(mask),
            $(QuoteNode(selector)),
            minimum_area,
        )
        return SImageND($PT.(selected), $S)
    end
    @eval function $function_name(
            mask::CONCT,
            args::Vararg{Any},
        ) where {BT,CONCT<:SizedImage{$S,BinaryPixel{BT}}}
        return $function_name(mask, 1, args...)
    end
    return fn
end

function _intensity_geometry_factory(
        ::Type{I},
        selector::Symbol,
    ) where {S1,S2,T,I<:SizedImage2D{S1,S2,IntensityPixel{T}}}
    IT = _get_image_type(I)
    PT = _get_image_pixel_type(I)
    S = _get_image_tuple_size(I)
    _validate_factory_type(IT)
    function_name = Symbol(:blob_, selector, :_intensity_, Symbol(I))

    fn = @eval function $function_name(
            image::CONCT,
            saliency::SAL,
            threshold_input::Real,
            args::Vararg{Any},
        ) where {CONCT<:$I,ST,SAL<:SizedImage{$S,IntensityPixel{ST}}}
        selected = _select_geometry(
            _saliency_mask(saliency, _threshold_value(threshold_input)),
            $(QuoteNode(selector)),
            1,
        )
        return SImageND($PT.($IT.(_masked_values(image, selected))), $S)
    end
    @eval function $function_name(
            image::CONCT,
            saliency::SAL,
            args::Vararg{Any},
        ) where {CONCT<:$I,ST,SAL<:SizedImage{$S,IntensityPixel{ST}}}
        return $function_name(image, saliency, 0.5, args...)
    end
    @eval function $function_name(
            image::CONCT,
            mask::MASK,
            minimum_area_input::Real,
            args::Vararg{Any},
        ) where {CONCT<:$I,BT,MASK<:SizedImage{$S,BinaryPixel{BT}}}
        minimum_area = _pixel_count(minimum_area_input, length(mask))
        selected = _select_geometry(
            _binary_mask(mask),
            $(QuoteNode(selector)),
            minimum_area,
        )
        return SImageND($PT.($IT.(_masked_values(image, selected))), $S)
    end
    @eval function $function_name(
            image::CONCT,
            mask::MASK,
            args::Vararg{Any},
        ) where {CONCT<:$I,BT,MASK<:SizedImage{$S,BinaryPixel{BT}}}
        return $function_name(image, mask, 1, args...)
    end
    return fn
end

function _binary_area_between_factory(
        ::Type{I},
    ) where {S1,S2,T,I<:SizedImage2D{S1,S2,BinaryPixel{T}}}
    IT = _get_image_type(I)
    PT = _get_image_pixel_type(I)
    S = _get_image_tuple_size(I)
    _validate_factory_type(IT)
    function_name = Symbol(:blob_size_between_binary_, Symbol(I))

    fn = @eval function $function_name(
            saliency::CONCT,
            first_area_input::Real,
            second_area_input::Real,
            args::Vararg{Any},
        ) where {ST,CONCT<:SizedImage{$S,IntensityPixel{ST}}}
        first_area = _pixel_count(first_area_input, length(saliency))
        second_area = _pixel_count(second_area_input, length(saliency))
        minimum_area, maximum_area = minmax(first_area, second_area)
        selected = _select_area_between(
            _saliency_mask(saliency, 0.5),
            minimum_area,
            maximum_area,
        )
        return SImageND($PT.(selected), $S)
    end
    @eval function $function_name(
            saliency::CONCT,
            args::Vararg{Any},
        ) where {ST,CONCT<:SizedImage{$S,IntensityPixel{ST}}}
        return $function_name(saliency, 1, length(saliency), args...)
    end
    @eval function $function_name(
            mask::CONCT,
            first_area_input::Real,
            second_area_input::Real,
            args::Vararg{Any},
        ) where {BT,CONCT<:SizedImage{$S,BinaryPixel{BT}}}
        first_area = _pixel_count(first_area_input, length(mask))
        second_area = _pixel_count(second_area_input, length(mask))
        minimum_area, maximum_area = minmax(first_area, second_area)
        selected = _select_area_between(_binary_mask(mask), minimum_area, maximum_area)
        return SImageND($PT.(selected), $S)
    end
    @eval function $function_name(
            mask::CONCT,
            args::Vararg{Any},
        ) where {BT,CONCT<:SizedImage{$S,BinaryPixel{BT}}}
        return $function_name(mask, 1, length(mask), args...)
    end
    return fn
end

function _binary_statistic_factory(
        ::Type{I},
        statistic::Symbol,
        direction::Symbol,
    ) where {S1,S2,T,I<:SizedImage2D{S1,S2,BinaryPixel{T}}}
    IT = _get_image_type(I)
    PT = _get_image_pixel_type(I)
    S = _get_image_tuple_size(I)
    _validate_factory_type(IT)
    function_name = Symbol(:blob_, direction, :_, statistic, :_binary_, Symbol(I))

    fn = @eval function $function_name(
            image::IMG,
            saliency::SAL,
            threshold_input::Real,
            args::Vararg{Any},
        ) where {
            IST,SST,
            IMG<:SizedImage{$S,IntensityPixel{IST}},
            SAL<:SizedImage{$S,IntensityPixel{SST}},
        }
        selected = _select_statistic(
            Float64.(reinterpret(image.img)),
            _saliency_mask(saliency, _threshold_value(threshold_input)),
            $(QuoteNode(statistic)),
            $(QuoteNode(direction)),
        )
        return SImageND($PT.(selected), $S)
    end
    @eval function $function_name(
            image::IMG,
            saliency::SAL,
            args::Vararg{Any},
        ) where {
            IST,SST,
            IMG<:SizedImage{$S,IntensityPixel{IST}},
            SAL<:SizedImage{$S,IntensityPixel{SST}},
        }
        return $function_name(image, saliency, 0.5, args...)
    end
    @eval function $function_name(
            image::IMG,
            mask::MASK,
            args::Vararg{Any},
        ) where {
            IST,BT,
            IMG<:SizedImage{$S,IntensityPixel{IST}},
            MASK<:SizedImage{$S,BinaryPixel{BT}},
        }
        selected = _select_statistic(
            Float64.(reinterpret(image.img)),
            _binary_mask(mask),
            $(QuoteNode(statistic)),
            $(QuoteNode(direction)),
        )
        return SImageND($PT.(selected), $S)
    end
    return fn
end

function _intensity_statistic_factory(
        ::Type{I},
        statistic::Symbol,
        direction::Symbol,
    ) where {S1,S2,T,I<:SizedImage2D{S1,S2,IntensityPixel{T}}}
    IT = _get_image_type(I)
    PT = _get_image_pixel_type(I)
    S = _get_image_tuple_size(I)
    _validate_factory_type(IT)
    function_name = Symbol(:blob_, direction, :_, statistic, :_intensity_, Symbol(I))

    fn = @eval function $function_name(
            image::CONCT,
            saliency::SAL,
            threshold_input::Real,
            args::Vararg{Any},
        ) where {CONCT<:$I,SST,SAL<:SizedImage{$S,IntensityPixel{SST}}}
        selected = _select_statistic(
            Float64.(reinterpret(image.img)),
            _saliency_mask(saliency, _threshold_value(threshold_input)),
            $(QuoteNode(statistic)),
            $(QuoteNode(direction)),
        )
        return SImageND($PT.($IT.(_masked_values(image, selected))), $S)
    end
    @eval function $function_name(
            image::CONCT,
            saliency::SAL,
            args::Vararg{Any},
        ) where {CONCT<:$I,SST,SAL<:SizedImage{$S,IntensityPixel{SST}}}
        return $function_name(image, saliency, 0.5, args...)
    end
    @eval function $function_name(
            image::CONCT,
            mask::MASK,
            args::Vararg{Any},
        ) where {CONCT<:$I,BT,MASK<:SizedImage{$S,BinaryPixel{BT}}}
        selected = _select_statistic(
            Float64.(reinterpret(image.img)),
            _binary_mask(mask),
            $(QuoteNode(statistic)),
            $(QuoteNode(direction)),
        )
        return SImageND($PT.($IT.(_masked_values(image, selected))), $S)
    end
    return fn
end

const _GEOMETRY_OPERATORS = (
    (:largest, "greatest pixel area"),
    (:smallest, "least pixel area after minimum-area filtering"),
    (:longest_horizontally, "widest bounding box"),
    (:shortest_horizontally, "narrowest bounding box after minimum-area filtering"),
    (:longest_vertically, "tallest bounding box"),
    (:shortest_vertically, "shortest bounding box after minimum-area filtering"),
)

for (selector, criterion) in _GEOMETRY_OPERATORS
    intensity_factory_name = Symbol(:blob_extraction_, selector, :_image2D_factory)
    binary_factory_name = Symbol(:blob_extraction_, selector, :_blob_image2D_factory)
    intensity_operator_name = Symbol(:blob_extraction_, selector)
    binary_operator_name = Symbol(:blob_extraction_, selector, :_blob)

    @eval begin
        function $intensity_factory_name(
                output_type::Type{I},
            ) where {S1,S2,T,I<:SizedImage2D{S1,S2,IntensityPixel{T}}}
            return _intensity_geometry_factory(output_type, $(QuoteNode(selector)))
        end
        function $binary_factory_name(
                output_type::Type{I},
            ) where {S1,S2,T,I<:SizedImage2D{S1,S2,BinaryPixel{T}}}
            return _binary_geometry_factory(output_type, $(QuoteNode(selector)))
        end
    end

    intensity_factory = getfield(@__MODULE__, intensity_factory_name)
    binary_factory = getfield(@__MODULE__, binary_factory_name)
    intensity_doc = """
        $(intensity_factory_name)(::Type{I})

    Specializes $(intensity_operator_name). The callable accepts a source
    intensity image plus an intensity saliency map and optional threshold, or a
    source image plus a binary mask and optional minimum area. It selects the
    component with the $(criterion) and returns a same-size, same-type masked
    source image. Threshold defaults to 0.5. Empty selections return zeros.
    """
    binary_doc = """
        $(binary_factory_name)(::Type{I})

    Specializes $(binary_operator_name). The callable accepts an intensity
    saliency map with optional threshold and minimum area, or a binary mask with
    optional minimum area. It selects the component with the $(criterion) and
    returns a same-size BinaryPixel mask. Threshold defaults to 0.5.
    """
    @eval @doc $intensity_doc $intensity_factory_name
    @eval @doc $binary_doc $binary_factory_name
    append_method!(
        bundle_image2DIntensity_blob_extraction_factory,
        intensity_factory,
        intensity_operator_name;
        description = "Returns the source image masked by the component with the $criterion.",
    )
    append_method!(
        bundle_image2DBinary_blob_extraction_factory,
        binary_factory,
        binary_operator_name;
        description = "Returns a binary mask for the component with the $criterion.",
    )
end

"""
    blob_extraction_size_between_blob_image2D_factory(::Type{I})

Specializes blob_extraction_size_between_blob for a concrete binary output
type. The callable keeps all components with inclusive pixel area between two
ordered, clamped bounds. Intensity input uses a fixed threshold of 0.5; binarize
first to use another threshold. With no bounds, all components are retained.
"""
blob_extraction_size_between_blob_image2D_factory(output_type::Type{I}) where {
    S1,S2,T,I<:SizedImage2D{S1,S2,BinaryPixel{T}},
} = _binary_area_between_factory(output_type)

append_method!(
    bundle_image2DBinary_blob_extraction_factory,
    blob_extraction_size_between_blob_image2D_factory,
    :blob_extraction_size_between_blob;
    description = "Returns all component pixels whose inclusive areas lie within two bounds.",
)

const _STATISTIC_OPERATORS = (
    (:max_mean, :mean, :maximum, "greatest mean"),
    (:max_median, :median, :maximum, "greatest median"),
    (:max_std, :std, :maximum, "greatest population standard deviation"),
    (:max_max, :maximum, :maximum, "greatest maximum"),
    (:max_min, :minimum, :maximum, "greatest minimum"),
    (:min_mean, :mean, :minimum, "least mean"),
    (:min_median, :median, :minimum, "least median"),
    (:min_std, :std, :minimum, "least population standard deviation"),
    (:min_max, :maximum, :minimum, "least maximum"),
    (:min_min, :minimum, :minimum, "least minimum"),
)

for (selector, statistic, direction, criterion) in _STATISTIC_OPERATORS
    intensity_factory_name = Symbol(:blob_extraction_, selector, :_image2D_factory)
    binary_factory_name = Symbol(:blob_extraction_, selector, :_blob_image2D_factory)
    intensity_operator_name = Symbol(:blob_extraction_, selector)
    binary_operator_name = Symbol(:blob_extraction_, selector, :_blob)

    @eval begin
        function $intensity_factory_name(
                output_type::Type{I},
            ) where {S1,S2,T,I<:SizedImage2D{S1,S2,IntensityPixel{T}}}
            return _intensity_statistic_factory(
                output_type,
                $(QuoteNode(statistic)),
                $(QuoteNode(direction)),
            )
        end
        function $binary_factory_name(
                output_type::Type{I},
            ) where {S1,S2,T,I<:SizedImage2D{S1,S2,BinaryPixel{T}}}
            return _binary_statistic_factory(
                output_type,
                $(QuoteNode(statistic)),
                $(QuoteNode(direction)),
            )
        end
    end

    intensity_factory = getfield(@__MODULE__, intensity_factory_name)
    binary_factory = getfield(@__MODULE__, binary_factory_name)
    intensity_doc = """
        $(intensity_factory_name)(::Type{I})

    Specializes $(intensity_operator_name). The callable accepts a source image
    and either an intensity saliency map with optional threshold or a binary
    mask. It selects the component with the $(criterion) of source pixels and
    returns a same-size, same-type masked source image.
    """
    binary_doc = """
        $(binary_factory_name)(::Type{I})

    Specializes $(binary_operator_name). It selects the component with the
    $(criterion) of source-image pixels and returns that component as a
    same-size BinaryPixel mask. Intensity saliency uses threshold 0.5 by default;
    binary saliency needs no threshold.
    """
    @eval @doc $intensity_doc $intensity_factory_name
    @eval @doc $binary_doc $binary_factory_name
    append_method!(
        bundle_image2DIntensity_blob_extraction_factory,
        intensity_factory,
        intensity_operator_name;
        description = "Returns the source image masked by the blob with the $criterion.",
    )
    append_method!(
        bundle_image2DBinary_blob_extraction_factory,
        binary_factory,
        binary_operator_name;
        description = "Returns the blob with the $criterion as a binary mask.",
    )
end

end
