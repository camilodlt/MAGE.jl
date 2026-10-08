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

using ImageMorphology
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

"""
    _morph_factory(I, SIZE, name, op_with_se, op_default)

Named morphology operator for output type `I` (binary or intensity), with the
methods

- `name(img, k, args...)`: `op_with_se(values, diamond of side k)`;
- `name(img, args...)`: `op_default(values)` (the operator's default element).

`img` may be any binary or intensity image of the same size. The function is
built once per output type and reused on later calls.
"""
function _morph_factory(::Type{I}, SIZE, name::Symbol, op_with_se, op_default) where {I<:SizedImage}
    IT, PT, S = _get_image_type(I), _get_image_pixel_type(I), _get_image_tuple_size(I)
    _validate_factory_type(IT)
    FUNCTION_NAME = Symbol(name, :_, Symbol(I))
    isdefined(@__MODULE__, FUNCTION_NAME) && return getfield(@__MODULE__, FUNCTION_NAME)
    f = @eval function $FUNCTION_NAME(img::CONCT, k_n::Number, args::Vararg{Any}) where {CONCT<:SizedImage{$SIZE, <:Union{BinaryPixel, IntensityPixel}}}
        return _morph_output($IT, $PT, $S, $op_with_se(reinterpret(img.img), _morph_diamond(k_n)))
    end
    @eval function $FUNCTION_NAME(img::CONCT, args::Vararg{Any}) where {CONCT<:SizedImage{$SIZE, <:Union{BinaryPixel, IntensityPixel}}}
        return _morph_output($IT, $PT, $S, $op_default(reinterpret(img.img)))
    end
    return f
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
    _morph_factory(I, SIZE, :morpholaplace_2D,
        (values, se) -> image2D_basic._normalize_img(mlaplacian(values, se)),
        values -> image2D_basic._normalize_img(mlaplacian(values)))

"Mode of `morphogradient_2D` from a number: `< 0` Beucher, `0` internal, `> 0` (or NaN) external."
_morph_gradient_mode(mode_int::Number) = mode_int < 0 ? :beucher : mode_int == 0 ? :internal : :external

"""
    morphogradient_image2D_factory(I)

`morphogradient_2D(img, [k], [mode])`: morphological gradient with a diamond of
side `k`. `mode < 0` Beucher (dilation − erosion, the default without `mode`),
`0` internal (img − erosion), `> 0` external (dilation − img).
"""
function morphogradient_image2D_factory(i::Type{I}) where {I<:SizedImage{SIZE, <:Union{BinaryPixel, IntensityPixel}}} where SIZE
    IT, PT, S = _get_image_type(I), _get_image_pixel_type(I), _get_image_tuple_size(I)
    _validate_factory_type(IT)
    FUNCTION_NAME = Symbol(:morphogradient_2D_, Symbol(I))
    isdefined(@__MODULE__, FUNCTION_NAME) && return getfield(@__MODULE__, FUNCTION_NAME)
    f = @eval function $FUNCTION_NAME(img::CONCT, k_n::Number, mode_int::Number, args::Vararg{Any}) where {CONCT<:SizedImage{$SIZE, <:Union{BinaryPixel, IntensityPixel}}}
        res = mgradient(reinterpret(img.img), _morph_diamond(k_n); mode = _morph_gradient_mode(mode_int))
        return _morph_output($IT, $PT, $S, res)
    end
    @eval function $FUNCTION_NAME(img::CONCT, k_n::Number, args::Vararg{Any}) where {CONCT<:SizedImage{$SIZE, <:Union{BinaryPixel, IntensityPixel}}}
        return _morph_output($IT, $PT, $S, mgradient(reinterpret(img.img), _morph_diamond(k_n); mode = :beucher))
    end
    @eval function $FUNCTION_NAME(img::CONCT, args::Vararg{Any}) where {CONCT<:SizedImage{$SIZE, <:Union{BinaryPixel, IntensityPixel}}}
        return _morph_output($IT, $PT, $S, mgradient(reinterpret(img.img); mode = :beucher))
    end
    return f
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
