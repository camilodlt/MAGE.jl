# -*- coding: utf-8 -*-

"""
Thresholding: intensity image in, mask out.

# Bundles

- [`bundle_image2DBinary_binarize_factory`](@ref)

The exhaustive, always-current list of operators in each bundle is on the
[Bundle Catalogue](@ref) page.

# How it is computed

The thresholds come from ImageBinarization (local methods: adaptive, Niblack,
Sauvola, already O(1) per pixel through integral images; global methods:
histogram thresholds) or from a manual threshold. Each call:

1. copies the image's values once into a plain array (task scratch);
2. runs ImageBinarization's in-place `binarize!` into a second scratch array
   (or, for the manual threshold, compares each value directly);
3. writes the mask into the output pixels in one pass.

The values passed to ImageBinarization and the conversion of its result are
those of the original implementation, so masks are unchanged.

Call tree:

    binarize_<method>2D(img, params...; out)
    ├── _window_size / _percentage / _bias / _bins          evolved parameters → algorithm settings
    ├── _binarize_into!(pixels, image_pixels, algorithm, V; quiet, nbins)
    │   ├── pixel_values!(values, image_pixels)              image_buffers.jl
    │   ├── _is_constant(values)                             `Moments`, `Polysegment` only
    │   ├── _run_binarize!(result, values, algorithm, quiet; nbins)
    │   └── _store_mask!(pixels, result)
    └── _threshold_into!(pixels, image_pixels, t)            binarize_manual2D
"""
module image2D_binarize

using ImageBinarization
using ImageCore: clamp01nan
using Statistics: mean
using Logging
using ..UTCGP: FunctionBundle, append_method!, output_pixels, image_result, scratch, pixel_values!
using ..UTCGP: SizedImage, _get_image_tuple_size, _get_image_type, _validate_factory_type, _get_image_pixel_type,
    IntensityPixel, BinaryPixel

using ..UTCGP: image2D_morph

# Shared pixel caster of the image2D libraries (a test checks this binding is the morph one and constant).
const cast = image2D_morph.cast
fallback(args...) = return nothing

"""
    bundle_image2DBinary_binarize_factory

Thresholding: intensity image in, mask out.

Global methods `binarize_otsu2D`, `binarize_entropy2D`, `binarize_yen2D`,
`binarize_moments2D`, `binarize_minimumerror2D`, `binarize_intermodes2D`,
`binarize_minimumintermodes2D`, `binarize_unimodalrosin2D`,
`binarize_balanced2D`, `binarize_polysegment2D` and the explicit
`binarize_manual2D`; local methods `binarize_adaptive2D`, `binarize_niblack2D`
and `binarize_sauvola2D`.

This is the bundle that lets an intensity chromosome produce material for the
binary one.

This is a *factory* bundle: each entry is a function of a type that returns the
method specialised for it, so the same operator can be instantiated for several
image or element types. See [Libraries](@ref) for how factories are specialised
into a library.
"""
bundle_image2DBinary_binarize_factory = FunctionBundle(fallback)

# ---------------------------------------------------------------------------
# 1. Evolved parameters → algorithm settings
# ---------------------------------------------------------------------------

"""
`x` clamped to `[lo, hi]` as a Float64; `NaN` and `±Inf` give `default`.
Example: `_finite_clamp(2.5, 0.0, 1.0, 0.5) == 1.0`, `_finite_clamp(NaN, 0.0, 1.0, 0.5) == 0.5`.
"""
function _finite_clamp(x::Real, lo::Float64, hi::Float64, default::Float64)
    v = Float64(x)
    if !isfinite(v)
        return default
    end
    return clamp(v, lo, hi)
end

"""
Window side of the local methods: rounded, at least 5, at most the image's
shorter side; `NaN`/`±Inf` give 15. Example on 28 × 28: `3 → 5`, `40 → 28`, `11.6 → 12`.
"""
_window_size(w::Number, shorter_side::Int) = clamp(round(Int, _finite_clamp(w, 0.0, 1.0e6, 15.0)), 5, shorter_side)

"Adaptive threshold percentage: rounded, in `0 … 100`; `NaN`/`±Inf` give 15. Example: `12.4 → 12`."
_percentage(p::Number) = clamp(round(Int, _finite_clamp(p, 0.0, 100.0, 15.0)), 0, 100)

"Niblack/Sauvola bias in `[-1, 1]`; `NaN`/`±Inf` give 0.2. Example: `3.0 → 1.0`."
_bias(p::Number) = _finite_clamp(p, -1.0, 1.0, 0.2)

"Histogram bins of the global methods: rounded, in `30 … 500`; `NaN`/`±Inf` give 256. Example: `10 → 30`."
_bins(n::Number) = clamp(round(Int, _finite_clamp(n, 30.0, 500.0, 256.0)), 30, 500)

# ---------------------------------------------------------------------------
# 2. Binarizing into the output
# ---------------------------------------------------------------------------

"""
    _binarize_into!(pixels, image_pixels, algorithm, V; quiet, empty_if_constant, kwargs...) -> pixels

Threshold `image_pixels` with an ImageBinarization `algorithm` into the mask
`pixels`. The image is read as values of type `V` (`N0f8` for most methods,
as `reinterpret(img.img)`; `Float32` for Polysegment, as `float(img.img)`).

- `algorithm` may also be a function of the values that builds the algorithm
  (e.g. `AdaptiveThreshold(values)`, which picks its own window).
- `quiet = true` silences the warnings some histogram methods log.
- `empty_if_constant = true`: a constant image gives an empty mask, for the
  methods that would throw on a single-valued histogram (`Moments`,
  `Polysegment`).
- `kwargs` go to `binarize!` (e.g. `nbins`).

Example: Otsu on an image whose left half is 0.1 and right half 0.9 → a mask
set on the right half.
"""
function _binarize_into!(pixels, image_pixels, algorithm, ::Type{V}; quiet::Bool = false,
        empty_if_constant::Bool = false, kwargs...) where {V}
    values = scratch(:binarize_values, V, size(image_pixels)...)
    pixel_values!(values, image_pixels)
    if empty_if_constant && _is_constant(values)
        return fill!(pixels, eltype(pixels)(false))
    end
    result = scratch(:binarize_result, V, size(image_pixels)...)
    _run_binarize!(result, values, _algorithm_for(algorithm, values), quiet; kwargs...)
    return _store_mask!(pixels, result)
end

"The algorithm itself, or the one built from the image's values (e.g. `AdaptiveThreshold(values)`)."
_algorithm_for(algorithm, values) = algorithm
_algorithm_for(build::Function, values) = build(values)

"All values equal (no threshold can separate anything). Example: `[0.3 0.3; 0.3 0.3]` → true."
_is_constant(values) = all(==(first(values)), values)

"ImageBinarization's in-place `binarize!`, with its log messages silenced when `quiet`."
function _run_binarize!(result, values, algorithm, quiet::Bool; kwargs...)
    if quiet
        return with_logger(NullLogger()) do
            binarize!(result, values, algorithm; kwargs...)
        end
    end
    return binarize!(result, values, algorithm; kwargs...)
end

"""
    _store_mask!(pixels, result) -> pixels

ImageBinarization returns 0 and 1 in the image's value type; a pixel is set
when its value rounds to 1 (as the original `cast(Bool, clamp01nan(result))`).
Example: result `[0.0 1.0]` → pixels `[false true]`.
"""
function _store_mask!(pixels::AbstractArray{P}, result) where {P}
    @inbounds for index in eachindex(pixels, result)
        pixels[index] = P(Bool(round(Int, clamp01nan(result[index]))))
    end
    return pixels
end

"""
    _threshold_into!(pixels, image_pixels, t) -> pixels

Manual threshold: a pixel is set when its value, as `Float32` (as the
original `float(img) .>= t`), is at least `t`. Example: values `[0.2 0.8]`,
`t = 0.5` → `[false true]`.
"""
function _threshold_into!(pixels::AbstractArray{P}, image_pixels, t::Real) where {P}
    @inbounds for index in eachindex(pixels, image_pixels)
        pixels[index] = P(float(image_pixels[index].pixel) >= t)
    end
    return pixels
end

"""
Mean intensity of an image, as the original `mean(float(img))`: the values as
`Float32` in a working array, then `mean` (same summation, same result).
"""
function _mean_intensity(image_pixels)
    values = scratch(:binarize_mean_values, Float32, size(image_pixels)...)
    pixel_values!(values, image_pixels)
    return mean(values)
end

# ---------------------------------------------------------------------------
# 3. Factories
# ---------------------------------------------------------------------------

"""
    _local_binarizer_factory(I, name, with_window_and_parameter, with_window, by_default)

Define `name` for the mask type `I` with the methods `(img, w, p)`, `(img, w)`
and `(img)`, where the three arguments build the ImageBinarization algorithm
from the window size `w` and parameter `p`, from `w` only, or by default.
"""
function _local_binarizer_factory(::Type{I}, name::Symbol, with_window_and_parameter, with_window, by_default) where {SIZE,I<:SizedImage{SIZE,<:BinaryPixel}}
    IT, PT, S = _get_image_type(I), _get_image_pixel_type(I), _get_image_tuple_size(I)
    _validate_factory_type(IT)
    function_name = Symbol(name, :_, Symbol(I))
    if isdefined(@__MODULE__, function_name)
        return getfield(@__MODULE__, function_name)
    end
    shorter_side = floor(Int, min(S.parameters[1], S.parameters[2]))
    @eval function $function_name(img::Image, w::Number, p::Number, args::Vararg{Any}; out = nothing) where {T,Image<:SizedImage{$SIZE,IntensityPixel{T}}}
        pixels = output_pixels(out, img, $PT)
        algorithm = $with_window_and_parameter(_window_size(w, $shorter_side), p)
        _binarize_into!(pixels, img.img, algorithm, T)
        return image_result(out, pixels, $S)
    end
    @eval function $function_name(img::Image, w::Number, args::Vararg{Any}; out = nothing) where {T,Image<:SizedImage{$SIZE,IntensityPixel{T}}}
        pixels = output_pixels(out, img, $PT)
        _binarize_into!(pixels, img.img, $with_window(_window_size(w, $shorter_side)), T)
        return image_result(out, pixels, $S)
    end
    @eval function $function_name(img::Image, args::Vararg{Any}; out = nothing) where {T,Image<:SizedImage{$SIZE,IntensityPixel{T}}}
        pixels = output_pixels(out, img, $PT)
        _binarize_into!(pixels, img.img, $by_default, T)
        return image_result(out, pixels, $S)
    end
    return getfield(@__MODULE__, function_name)
end

"""
    _histogram_binarizer_factory(I, name, algorithm; quiet, empty_if_constant)

Define `name` for the mask type `I` with the methods `(img, n_bins)` and
`(img)` (256 bins), thresholding with the global ImageBinarization `algorithm`.
"""
function _histogram_binarizer_factory(::Type{I}, name::Symbol, algorithm; quiet::Bool = false,
        empty_if_constant::Bool = false) where {SIZE,I<:SizedImage{SIZE,<:BinaryPixel}}
    IT, PT, S = _get_image_type(I), _get_image_pixel_type(I), _get_image_tuple_size(I)
    _validate_factory_type(IT)
    function_name = Symbol(name, :_, Symbol(I))
    if isdefined(@__MODULE__, function_name)
        return getfield(@__MODULE__, function_name)
    end
    @eval function $function_name(img::Image, n_bins::Number, args::Vararg{Any}; out = nothing) where {T,Image<:SizedImage{$SIZE,IntensityPixel{T}}}
        pixels = output_pixels(out, img, $PT)
        _binarize_into!(pixels, img.img, $algorithm, T; quiet = $quiet, empty_if_constant = $empty_if_constant,
            nbins = _bins(n_bins))
        return image_result(out, pixels, $S)
    end
    @eval function $function_name(img::Image, args::Vararg{Any}; out = nothing) where {T,Image<:SizedImage{$SIZE,IntensityPixel{T}}}
        pixels = output_pixels(out, img, $PT)
        _binarize_into!(pixels, img.img, $algorithm, T; quiet = $quiet, empty_if_constant = $empty_if_constant,
            nbins = 256)
        return image_result(out, pixels, $S)
    end
    return getfield(@__MODULE__, function_name)
end

# Local methods. They compute local means (and standard deviations) with
# integral images inside ImageBinarization, already O(1) per pixel.
# TODO speed: ImageBinarization allocates its integral images (and, for
# Sauvola, `img .^ 2`) on every call; passing preallocated integral images would
# need an in-place API in the library (or a local reimplementation).

"""
    binarizeAdaptive_image2D_factory(I)

`binarize_adaptive2D(img, w, p)`, `(img, w)`, `(img)`: a pixel is set unless
it is `p`% darker than the mean of its `w × w` neighbourhood
(`AdaptiveThreshold`; `w` in `5 …` the shorter side, `p` in `0 … 100`; by
default ImageBinarization picks `w` from the image size).
Example: `w = 15`, `p = 15`: a pixel at 0.40 in a neighbourhood of mean 0.50 is
background (0.40 < 0.85 × 0.50).
"""
binarizeAdaptive_image2D_factory(i::Type{I}) where {I<:SizedImage{SIZE,<:BinaryPixel}} where {SIZE} =
    _local_binarizer_factory(I, :binarize_adaptive2D,
        (w, p) -> AdaptiveThreshold(window_size = w, percentage = _percentage(p)),
        w -> AdaptiveThreshold(window_size = w),
        values -> AdaptiveThreshold(values))

"""
    binarizeNiblack_image2D_factory(I)

`binarize_niblack2D(img, w, bias)`, `(img, w)`, `(img)`: threshold
`mean + bias · std` of the `w × w` neighbourhood (`bias` in `[-1, 1]`).
Example: neighbourhood mean 0.5, std 0.1, bias 0.2 → threshold 0.52.
"""
binarizeNiblack_image2D_factory(i::Type{I}) where {I<:SizedImage{SIZE,<:BinaryPixel}} where {SIZE} =
    _local_binarizer_factory(I, :binarize_niblack2D,
        (w, p) -> Niblack(; window_size = w, bias = _bias(p)),
        w -> Niblack(; window_size = w),
        Niblack())

"""
    binarizeSauvola_image2D_factory(I)

`binarize_sauvola2D(img, w, bias)`, `(img, w)`, `(img)`: Sauvola's local
threshold `mean · (1 + bias · (std / R − 1))` over the `w × w` neighbourhood
(`bias` in `[-1, 1]`), robust to uneven lighting.
"""
binarizeSauvola_image2D_factory(i::Type{I}) where {I<:SizedImage{SIZE,<:BinaryPixel}} where {SIZE} =
    _local_binarizer_factory(I, :binarize_sauvola2D,
        (w, p) -> Sauvola(; window_size = w, bias = _bias(p)),
        w -> Sauvola(; window_size = w),
        Sauvola())

"""
    binarizePolysegment_image2D_factory(I)

`binarize_polysegment2D(img)`: Polysegment threshold, on the values as
`Float32`; a constant image gives an empty mask.
"""
function binarizePolysegment_image2D_factory(i::Type{I}) where {I<:SizedImage{SIZE,<:BinaryPixel}} where {SIZE}
    IT, PT, S = _get_image_type(I), _get_image_pixel_type(I), _get_image_tuple_size(I)
    _validate_factory_type(IT)
    function_name = Symbol(:binarize_polysegment2D, :_, Symbol(I))
    if isdefined(@__MODULE__, function_name)
        return getfield(@__MODULE__, function_name)
    end
    @eval function $function_name(img::Image, args::Vararg{Any}; out = nothing) where {T,Image<:SizedImage{$SIZE,IntensityPixel{T}}}
        pixels = output_pixels(out, img, $PT)
        _binarize_into!(pixels, img.img, Polysegment(), Float32; empty_if_constant = true)
        return image_result(out, pixels, $S)
    end
    return getfield(@__MODULE__, function_name)
end

# Global (histogram) methods: (factory name, operator name, algorithm, quiet, empty_if_constant).
# `quiet`: the method logs warnings on unusual histograms. `empty_if_constant`:
# the method would throw on a single-valued histogram.
const _HISTOGRAM_METHODS = (
    (:binarizeOtsu_image2D_factory, :binarize_otsu2D, Otsu(), false, false),
    (:binarizeMinimumintermodes_image2D_factory, :binarize_minimumintermodes2D, MinimumIntermodes(), true, false),
    (:binarizeIntermodes_image2D_factory, :binarize_intermodes2D, Intermodes(), true, false),
    (:binarizeMinimumError_image2D_factory, :binarize_minimumerror2D, MinimumError(), false, false),
    (:binarizeMoments_image2D_factory, :binarize_moments2D, Moments(), false, true),
    (:binarizeUnimodalRosin_image2D_factory, :binarize_unimodalrosin2D, UnimodalRosin(), false, false),
    (:binarizeEntropy_image2D_factory, :binarize_entropy2D, Entropy(), true, false),
    (:binarizeBalanced_image2D_factory, :binarize_balanced2D, Balanced(), true, false),
    (:binarizeYen_image2D_factory, :binarize_yen2D, Yen(), false, false),
)

for (factory_name, operator, algorithm, quiet, empty_if_constant) in _HISTOGRAM_METHODS
    @eval $factory_name(i::Type{I}) where {I<:SizedImage{SIZE,<:BinaryPixel}} where {SIZE} =
        _histogram_binarizer_factory(I, $(QuoteNode(operator)), $algorithm;
            quiet = $quiet, empty_if_constant = $empty_if_constant)
    doc = """
        $factory_name(I)

    `$operator(img, n_bins)` and `$operator(img)`: global threshold from the image
    histogram with ImageBinarization's `$(nameof(typeof(algorithm)))` (`n_bins` in
    `30 … 500`, default 256); pixels above the threshold are set.
    Example: an image whose left half is 0.1 and right half 0.9 → the right half is set.
    """
    @eval @doc $doc $factory_name
end

"""
    binarizeManual_image2D_factory(I)

Manual thresholds; a pixel is set when its value is at least the threshold
(`>=`, so a constant image at or above it gives a full mask):

- `binarize_manual2D(img)`: threshold 0.5;
- `binarize_manual2D(img, t::Float)`: threshold `t`, clamped to `[0, 1]`;
- `binarize_manual2D(img, t::Int)`: threshold `t / 255`, clamped to `[0, 1]`;
- `binarize_manual2D(img1, img2)`: threshold = the mean intensity of `img2`.

Example: `binarize_manual2D(img, 0.3)` on values `[0.2 0.8]` → `[false true]`;
`binarize_manual2D(img, 204)` uses threshold `0.8`.
"""
function binarizeManual_image2D_factory(i::Type{I}) where {I<:SizedImage{SIZE,<:BinaryPixel}} where {SIZE}
    IT, PT, S = _get_image_type(I), _get_image_pixel_type(I), _get_image_tuple_size(I)
    _validate_factory_type(IT)
    function_name = Symbol(:binarize_manual2D, :_, Symbol(I))
    if isdefined(@__MODULE__, function_name)
        return getfield(@__MODULE__, function_name)
    end
    @eval function $function_name(img::Image, t::AbstractFloat, args::Vararg{Any}; out = nothing) where {T,Image<:SizedImage{$SIZE,IntensityPixel{T}}}
        pixels = output_pixels(out, img, $PT)
        _threshold_into!(pixels, img.img, clamp(t, 0.0, 1.0))
        return image_result(out, pixels, $S)
    end
    @eval function $function_name(img::Image, t::Number, args::Vararg{Any}; out = nothing) where {T,Image<:SizedImage{$SIZE,IntensityPixel{T}}}
        pixels = output_pixels(out, img, $PT)
        _threshold_into!(pixels, img.img, clamp(round(Int, t) / 255, 0.0, 1.0))
        return image_result(out, pixels, $S)
    end
    @eval function $function_name(img1::Image, img2::Image, args::Vararg{Any}; out = nothing) where {T,Image<:SizedImage{$SIZE,IntensityPixel{T}}}
        pixels = output_pixels(out, img1, $PT)
        _threshold_into!(pixels, img1.img, _mean_intensity(img2.img))
        return image_result(out, pixels, $S)
    end
    @eval function $function_name(img::Image, args::Vararg{Any}; out = nothing) where {T,Image<:SizedImage{$SIZE,IntensityPixel{T}}}
        pixels = output_pixels(out, img, $PT)
        _threshold_into!(pixels, img.img, 0.5)
        return image_result(out, pixels, $S)
    end
    return getfield(@__MODULE__, function_name)
end

# ---------------------------------------------------------------------------
# 4. Registration
# ---------------------------------------------------------------------------

for (factory, operator, description) in (
    (binarizeAdaptive_image2D_factory, :binarize_adaptive2D, "Binarizes image with adaptive local thresholding."),
    (binarizeNiblack_image2D_factory, :binarize_niblack2D, "Binarizes image using Niblack local thresholding."),
    (binarizePolysegment_image2D_factory, :binarize_polysegment2D, "Binarizes image using polysegment thresholding."),
    (binarizeSauvola_image2D_factory, :binarize_sauvola2D, "Binarizes image using Sauvola local thresholding."),
    (binarizeOtsu_image2D_factory, :binarize_otsu2D, "Binarizes image using Otsu histogram threshold."),
    (binarizeMinimumintermodes_image2D_factory, :binarize_minimumintermodes2D, "Binarizes image using minimum-intermodes histogram threshold."),
    (binarizeIntermodes_image2D_factory, :binarize_intermodes2D, "Binarizes image using intermodes histogram threshold."),
    (binarizeMinimumError_image2D_factory, :binarize_minimumerror2D, "Binarizes image using minimum-error threshold estimation."),
    (binarizeMoments_image2D_factory, :binarize_moments2D, "Binarizes image using moments-based histogram threshold."),
    (binarizeUnimodalRosin_image2D_factory, :binarize_unimodalrosin2D, "Binarizes image using unimodal Rosin threshold."),
    (binarizeEntropy_image2D_factory, :binarize_entropy2D, "Binarizes image using entropy-based thresholding."),
    (binarizeBalanced_image2D_factory, :binarize_balanced2D, "Binarizes image using balanced histogram thresholding."),
    (binarizeYen_image2D_factory, :binarize_yen2D, "Binarizes image using Yen thresholding method."),
    (binarizeManual_image2D_factory, :binarize_manual2D, "Binarizes image using user-controlled manual threshold parameters."),
)
    append_method!(bundle_image2DBinary_binarize_factory, factory, operator; description = description)
end

end
