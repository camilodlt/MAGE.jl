# -*- coding: utf-8 -*-
"""
Mathematical morphology over images.

# Bundles

- [`bundle_image2DIntensity_morph_factory`](@ref)
- [`bundle_image2DBinary_morph_factory`](@ref)

The exhaustive, always-current list of operators in each bundle is on the
[Bundle Catalogue](@ref) page.
"""
module image2D_morph

using ..MAGE: _factory_type_symbol, @serialized_factory

using ..MAGE: scratch, image_result

using ImageMorphology
using FixedPointNumbers: rawtype
using ..MAGE: image2D_basic
using ..MAGE: FunctionBundle, append_method!
import MAGE:
    CONSTRAINED,
    MIN_INT,
    MAX_INT,
    MIN_FLOAT,
    MAX_FLOAT,
    _positive_params,
    _ceil_positive_params
using ImageCore: N0f8, Normed, clamp01nan!, clamp01nan, float64, Gray, FixedPoint
using ..MAGE:
    SizedImage, SizedImage2D, SImageND, _get_image_tuple_size, _get_image_type, _validate_factory_type, _get_image_pixel_type, 
    IntensityPixel, BinaryPixel, SegmentPixel

fallback(args...) = return nothing
"""
    bundle_image2DIntensity_morph_factory

Grey-level morphology: `erosion_2D`, `dilation_2D`, `opening_2D`, `closing_2D`,
`tophat_2D`, `bothat_2D`, `morphogradient_2D`, `morpholaplace_2D`.

This is a *factory* bundle: each entry is a function of a type that returns the
method specialised for it, so the same operator can be instantiated for several
image or element types. See [Libraries](@ref) for how factories are specialised
into a library.
"""
bundle_image2DIntensity_morph_factory = FunctionBundle(fallback)
"""
    bundle_image2DBinary_morph_factory

Binary morphology over masks: `erosion_2D`, `dilation_2D`, `opening_2D`,
`closing_2D`, `tophat_2D`, `bothat_2D`, `morphogradient_2D`, `morpholaplace_2D`.

This is a *factory* bundle: each entry is a function of a type that returns the
method specialised for it, so the same operator can be instantiated for several
image or element types. See [Libraries](@ref) for how factories are specialised
into a library.
"""
bundle_image2DBinary_morph_factory = FunctionBundle(fallback)
# bundle_image2DSegment_morph_factory = FunctionBundle(fallback) # not applicable

# Bool => Intensity
"`x` clamped to `[lo, hi]` as a Float64; `NaN` and `±Inf` give `default`."
_finite_clamp(x::Real, lo::Float64, hi::Float64, default::Float64) =
    (v = Float64(x); isfinite(v) ? clamp(v, lo, hi) : default)

function cast(to_type::Type{T}, img::Array{Bool}) where {T<: Real}
    to_type.(img) # 0. or 1. we can always promote
end
function cast(to_type::Type{T}, img::BitArray) where {T<: Real}
    to_type.(img) # 0. or 1. we can always promote
end

# do nothing img is already intensity => a Intensity image was eroded
function cast(to_type::Type{T}, img::Array{T}) where T
    return T.(img)    
end
function cast(to_type::Type{T1}, img::Array{T2}) where {T1<:FixedPoint, T2<:AbstractFloat}
    return T1.(img)    
end
function cast(to_type::Type{Bool}, img::BitArray)
    return img    
end
function cast(to_type::Type{Bool}, img::Matrix{Bool})
    return img    
end

# Intensity => Bool
function cast(to_type::Type{Bool}, img::Array{<:Real})
    img_ = clamp01nan.(img)
    img_ .= round.(Int, img_) # to 0 or 1
    to_type.(img_) # returns the boolean (rounded version) of the image
end

# ################### #
# BUILDER             #
# ################### #

"""
Structuring-element size of the morphology operators: rounded, made odd and
clamped to `3 … 13`; `NaN`/`±Inf` give `3` and huge values cannot overflow.
Example: `4.2 → 5`, `0 → 3`, `100 → 13`.
"""
function _morph_kernel_size(k_n::Number)
    k = round(Int, _finite_clamp(k_n, 0.0, 13.0, 3.0))
    k = iseven(k) ? k + 1 : k
    return clamp(k, 3, 13)
end

"Diamond structuring element of side `_morph_kernel_size(k_n)`."
_morph_diamond(k_n::Number) = (k = _morph_kernel_size(k_n); strel_diamond((k, k)))

"Clamp a morphology result to `[0, 1]` and store it as the output image type."
function _morph_output(::Type{IT}, ::Type{PT}, ::Type{S}, res) where {IT, PT, S}
    clamp01nan!(res)
    return SImageND(PT.(cast(IT, res)), S)
end

# Reinterpret storage without copying pixel arrays. Compound morphology reuses
# task scratch; mixed storage keeps source arithmetic before the final cast.

"""
    _morph_extremum!(destination, source, take, radius, diamond)

Erosion (`take = min`) or dilation (`take = max`) of `source` into `destination`,
with ImageMorphology's optimised in-place filters (much faster than a direct
neighbourhood loop; their small internal allocations are acceptable).
`diamond = true`: diamond of the given radius (`strel_diamond`, as `erode(img, se)`);
`diamond = false`: ImageMorphology's default element (as `erode(img)`).
"""
# TODO speed: erosion/dilation by a diamond of radius r cost O(r^2) per pixel.
# A diamond is the composition of r 3x3-cross erosions (or decomposes into
# line elements), and a box is separable; with van Herk-Gil-Werman sliding
# max/min per line, each costs O(1) per pixel whatever r. Worth it only if
# profiling shows morphology dominating: ImageMorphology's kernels are already fast.
function _morph_extremum!(destination, source, take::F, radius::Int, diamond::Bool) where {F}
    if diamond
        element = strel_diamond((2radius + 1, 2radius + 1))
        if take === min
            return erode!(destination, source, element)
        end
        return dilate!(destination, source, element)
    end
    if take === min
        return erode!(destination, source)
    end
    return dilate!(destination, source)
end

function _morph_into!(destination, img, op!, se)
    input_storage = _get_image_type(img)
    output_storage = _get_image_type(destination)
    source = reinterpret(input_storage, img.img)
    hat = op! === tophat! || op! === bothat!
    # Hat operators subtract in the floating type used by ImageMorphology,
    # then cast, so fixed-point subtraction cannot change their rounding.
    result_storage = hat ? ImageMorphology.maybe_floattype(input_storage) : input_storage
    if result_storage === output_storage
        result = reinterpret(output_storage, destination.img)
    else
        result = scratch(:morph_result, result_storage, size(source)...)
    end
    diamond = se != 0
    radius = diamond ? se : 1
    if op! === erode!
        _morph_extremum!(result, source, min, radius, diamond)
    elseif op! === dilate!
        _morph_extremum!(result, source, max, radius, diamond)
    else
        temporary = scratch(:morph_compound, input_storage, size(source)...)
        if op! === opening! || op! === tophat!
            _morph_extremum!(temporary, source, min, radius, diamond)
            _morph_extremum!(result, temporary, max, radius, diamond)
        else
            _morph_extremum!(temporary, source, max, radius, diamond)
            _morph_extremum!(result, temporary, min, radius, diamond)
        end
        if op! === tophat!
            @inbounds for index in eachindex(result, source)
                result[index] = source[index] - result[index]
            end
        elseif op! === bothat!
            @inbounds for index in eachindex(result, source)
                result[index] = result[index] - source[index]
            end
        end
    end
    clamp01nan!(result)
    if result_storage !== output_storage
        _morph_cast!(destination.img, result, output_storage)
    end
    return destination
end

function _morph_cast!(destination, result, ::Type{T}) where {T}
    P = eltype(destination)
    for index in eachindex(destination, result)
        destination[index] = P(T(result[index]))
    end
    return destination
end

function _morph_cast!(destination, result, ::Type{Bool})
    P = eltype(destination)
    for index in eachindex(destination, result)
        destination[index] = P(Bool(round(Int, clamp01nan(result[index]))))
    end
    return destination
end

"""
    _morph_factory(I, SIZE, name, op_with_se, op_default)

Named morphology operator for output type `I` (binary or intensity), with the
methods

- `name(img, k, args...)`: `op_with_se(values, diamond of side k)`;
- `name(img, args...)`: `op_default(values)` (the operator's default element).

`img` may be any binary or intensity image of the same size. The function is
built once per output type and reused on later calls.
"""
@serialized_factory function _morph_factory(::Type{I}, SIZE, name::Symbol, op_with_se, op_default) where {I<:SizedImage}
    inplace = if op_with_se === erode
        erode!
    elseif op_with_se === dilate
        dilate!
    elseif op_with_se === opening
        opening!
    elseif op_with_se === closing
        closing!
    elseif op_with_se === tophat
        tophat!
    elseif op_with_se === bothat
        bothat!
    else
        throw(ArgumentError("Unsupported morphology operation: $name"))
    end
    IT, PT, S = _get_image_type(I), _get_image_pixel_type(I), _get_image_tuple_size(I)
    _validate_factory_type(IT)
    function_name = Symbol(name, :_, _factory_type_symbol(I))
    isdefined(@__MODULE__, function_name) && return Base.invokelatest(getfield, @__MODULE__, function_name)
    fn = @eval function $function_name(img::Source, k::Number, args::Vararg{Any}; out = nothing) where {Source<:SizedImage{$SIZE,<:Union{BinaryPixel,IntensityPixel}}}
        pixels = out === nothing ? similar(img.img, $PT) : out.img
        destination = image_result(out, pixels, $S)
        return _morph_into!(destination, img, $inplace, _morph_kernel_size(k) ÷ 2)
    end
    @eval function $function_name(img::Source, args::Vararg{Any}; out = nothing) where {Source<:SizedImage{$SIZE,<:Union{BinaryPixel,IntensityPixel}}}
        pixels = out === nothing ? similar(img.img, $PT) : out.img
        destination = image_result(out, pixels, $S)
        return _morph_into!(destination, img, $inplace, 0)
    end
    return fn
end

function morph_difference!(destination, img, radius::Int, operation::Symbol, mode::Symbol)
    source = reinterpret(fieldtype(eltype(img.img), 1), img.img)
    T = eltype(source)
    F = ImageMorphology.maybe_floattype(T)
    upper = scratch(:morph_difference_upper, F, size(source)...)
    lower = scratch(:morph_difference_lower, F, size(source)...)
    diamond = radius != 0
    actual_radius = diamond ? radius : 1
    _morph_extremum!(upper, source, max, actual_radius, diamond)
    _morph_extremum!(lower, source, min, actual_radius, diamond)
    @inbounds for index in eachindex(source, upper, lower)
        if operation === :laplace
            upper[index] = upper[index] + lower[index] - 2source[index]
        elseif mode === :internal
            upper[index] = source[index] - lower[index]
        elseif mode === :external
            upper[index] = upper[index] - source[index]
        else
            upper[index] = upper[index] - lower[index]
        end
    end
    if operation === :laplace
        image2D_basic._sanitize_img!(upper)
        low, high = extrema(upper)
        if high - low <= 1e-9 * max(1.0, abs(low), abs(high))
            fill!(upper, zero(F))
        else
            @inbounds for index in eachindex(upper)
                upper[index] = (upper[index] - low) / (high - low)
            end
        end
    end
    clamp01nan!(upper)
    _morph_cast!(destination, upper, fieldtype(eltype(destination), 1))
    return destination
end

@serialized_factory function _morph_difference_factory(::Type{I}, SIZE, name::Symbol, operation::Symbol) where {I<:SizedImage}
    PT, S = _get_image_pixel_type(I), _get_image_tuple_size(I)
    function_name = Symbol(name, :_, _factory_type_symbol(I))
    isdefined(@__MODULE__, function_name) && return Base.invokelatest(getfield, @__MODULE__, function_name)
    fn = @eval function $function_name(img::Source, k::Number, args::Vararg{Any}; out = nothing) where {Source<:SizedImage{$SIZE,<:Union{BinaryPixel,IntensityPixel}}}
        pixels = out === nothing ? similar(img.img, $PT) : out.img
        morph_difference!(pixels, img, _morph_kernel_size(k) ÷ 2, $(QuoteNode(operation)), :beucher)
        return image_result(out, pixels, $S)
    end
    @eval function $function_name(img::Source, args::Vararg{Any}; out = nothing) where {Source<:SizedImage{$SIZE,<:Union{BinaryPixel,IntensityPixel}}}
        pixels = out === nothing ? similar(img.img, $PT) : out.img
        morph_difference!(pixels, img, 0, $(QuoteNode(operation)), :beucher)
        return image_result(out, pixels, $S)
    end
    if operation === :gradient
        @eval function $function_name(img::Source, k::Number, mode::Number, args::Vararg{Any}; out = nothing) where {Source<:SizedImage{$SIZE,<:Union{BinaryPixel,IntensityPixel}}}
            pixels = out === nothing ? similar(img.img, $PT) : out.img
            morph_difference!(pixels, img, _morph_kernel_size(k) ÷ 2, $(QuoteNode(operation)), _morph_gradient_mode(mode))
            return image_result(out, pixels, $S)
        end
    end
    return fn
end

# ################### #
# OPERATORS           #
# ################### #

"""
    erosion_image2D_factory(I)

`erosion_2D(img, [k])`: grey/binary erosion with a diamond of side `k`
(see `_morph_kernel_size`; without `k`, ImageMorphology's default element).
"""
erosion_image2D_factory(i::Type{I}) where {I<:SizedImage{SIZE, <:Union{BinaryPixel, IntensityPixel}}} where SIZE =
    _morph_factory(I, SIZE, :erosion_2D, erode, erode)

"""
    dilation_image2D_factory(I)

`dilation_2D(img, [k])`: grey/binary dilation with a diamond of side `k`.
"""
dilation_image2D_factory(i::Type{I}) where {I<:SizedImage{SIZE, <:Union{BinaryPixel, IntensityPixel}}} where SIZE =
    _morph_factory(I, SIZE, :dilation_2D, dilate, dilate)

"""
    opening_image2D_factory(I)

`opening_2D(img, [k])`: dilate(erode(img)), removes bright details smaller than the element.
"""
opening_image2D_factory(i::Type{I}) where {I<:SizedImage{SIZE, <:Union{BinaryPixel, IntensityPixel}}} where SIZE =
    _morph_factory(I, SIZE, :opening_2D, opening, opening)

"""
    closing_image2D_factory(I)

`closing_2D(img, [k])`: erode(dilate(img)), fills dark gaps smaller than the element.
"""
closing_image2D_factory(i::Type{I}) where {I<:SizedImage{SIZE, <:Union{BinaryPixel, IntensityPixel}}} where SIZE =
    _morph_factory(I, SIZE, :closing_2D, closing, closing)

"""
    tophat_image2D_factory(I)

`tophat_2D(img, [k])`: img − opening(img), the bright details smaller than the element.
"""
tophat_image2D_factory(i::Type{I}) where {I<:SizedImage{SIZE, <:Union{BinaryPixel, IntensityPixel}}} where SIZE =
    _morph_factory(I, SIZE, :tophat_2D, tophat, tophat)

"""
    bothat_image2D_factory(I)

`bothat_2D(img, [k])`: closing(img) − img, the dark details smaller than the element.
"""
bothat_image2D_factory(i::Type{I}) where {I<:SizedImage{SIZE, <:Union{BinaryPixel, IntensityPixel}}} where SIZE =
    _morph_factory(I, SIZE, :bothat_2D, bothat, bothat)

"""
    morpholaplace_image2D_factory(I)

`morpholaplace_2D(img, [k])`: morphological Laplacian (dilation + erosion − 2·img),
rescaled to `[0, 1]`.
"""
morpholaplace_image2D_factory(i::Type{I}) where {I<:SizedImage{SIZE, <:Union{BinaryPixel, IntensityPixel}}} where SIZE =
    _morph_difference_factory(I, SIZE, :morpholaplace_2D, :laplace)

"Mode of `morphogradient_2D` from a number: `< 0` Beucher, `0` internal, `> 0` (or NaN) external."
_morph_gradient_mode(mode_int::Number) = mode_int < 0 ? :beucher : mode_int == 0 ? :internal : :external

"""
    morphogradient_image2D_factory(I)

`morphogradient_2D(img, [k], [mode])`: morphological gradient with a diamond of
side `k`. `mode < 0` Beucher (dilation − erosion, the default without `mode`),
`0` internal (img − erosion), `> 0` external (dilation − img).
"""
function morphogradient_image2D_factory(i::Type{I}) where {I<:SizedImage{SIZE, <:Union{BinaryPixel, IntensityPixel}}} where SIZE
    return _morph_difference_factory(I, SIZE, :morphogradient_2D, :gradient)
end


# Factory Methods
append_method!(
    bundle_image2DIntensity_morph_factory,
    erosion_image2D_factory,
    :erosion_2D;
    description = "Applies morphological erosion to shrink bright regions.",
)
append_method!(
    bundle_image2DIntensity_morph_factory,
    dilation_image2D_factory,
    :dilation_2D;
    description = "Applies morphological dilation to expand bright regions.",
)
append_method!(
    bundle_image2DIntensity_morph_factory,
    opening_image2D_factory,
    :opening_2D;
    description = "Applies opening (erosion followed by dilation) to remove small bright noise.",
)
append_method!(
    bundle_image2DIntensity_morph_factory,
    closing_image2D_factory,
    :closing_2D;
    description = "Applies closing (dilation followed by erosion) to fill small dark gaps.",
)
append_method!(
    bundle_image2DIntensity_morph_factory,
    tophat_image2D_factory,
    :tophat_2D;
    description = "Computes top-hat transform to extract small bright structures.",
)
append_method!(
    bundle_image2DIntensity_morph_factory,
    bothat_image2D_factory,
    :bothat_2D;
    description = "Computes black-hat transform to extract small dark structures.",
)
append_method!(
    bundle_image2DIntensity_morph_factory,
    morphogradient_image2D_factory,
    :morphogradient_2D;
    description = "Computes morphological gradient to emphasize object boundaries.",
)
append_method!(
    bundle_image2DIntensity_morph_factory,
    morpholaplace_image2D_factory,
    :morpholaplace_2D;
    description = "Computes a morphological Laplace-style edge response.",
)

append_method!(
    bundle_image2DBinary_morph_factory,
    erosion_image2D_factory,
    :erosion_2D;
    description = "Applies morphological erosion to shrink bright regions.",
)
append_method!(
    bundle_image2DBinary_morph_factory,
    dilation_image2D_factory,
    :dilation_2D;
    description = "Applies morphological dilation to expand bright regions.",
)
append_method!(
    bundle_image2DBinary_morph_factory,
    opening_image2D_factory,
    :opening_2D;
    description = "Applies opening (erosion followed by dilation) to remove small bright noise.",
)
append_method!(
    bundle_image2DBinary_morph_factory,
    closing_image2D_factory,
    :closing_2D;
    description = "Applies closing (dilation followed by erosion) to fill small dark gaps.",
)
append_method!(
    bundle_image2DBinary_morph_factory,
    tophat_image2D_factory,
    :tophat_2D;
    description = "Computes top-hat transform to extract small bright structures.",
)
append_method!(
    bundle_image2DBinary_morph_factory,
    bothat_image2D_factory,
    :bothat_2D;
    description = "Computes black-hat transform to extract small dark structures.",
)
append_method!(
    bundle_image2DBinary_morph_factory,
    morphogradient_image2D_factory,
    :morphogradient_2D;
    description = "Computes morphological gradient to emphasize object boundaries.",
)
append_method!(
    bundle_image2DBinary_morph_factory,
    morpholaplace_image2D_factory,
    :morpholaplace_2D;
    description = "Computes a morphological Laplace-style edge response.",
)

end
