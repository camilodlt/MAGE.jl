"""
Convolution filters: gradients, smoothing and second-order operators.

# Bundles

- [`bundle_image2DIntensity_filtering_factory`](@ref)
- [`bundle_image2DBinary_filtering_factory`](@ref)

The exhaustive, always-current list of operators in each bundle is on the
[Bundle Catalogue](@ref) page.
"""
module image2D_filtering

using ..UTCGP: _factory_type_symbol, @serialized_factory

using ..UTCGP: output_pixels, image_result, scratch, pixel_values!

using ImageFiltering
using ImageFiltering: imfilter!
using ..UTCGP: image2D_basic
using ..UTCGP: image2D_morph
using ..UTCGP: FunctionBundle, append_method!
import UTCGP:
    CONSTRAINED,
    MIN_INT,
    MAX_INT,
    MIN_FLOAT,
    MAX_FLOAT,
    _positive_params,
    _ceil_positive_params
using ImageCore: clamp01nan
using ..UTCGP:
    SizedImage, SizedImage2D, SImageND, _get_image_tuple_size, _get_image_type, _validate_factory_type, _get_image_pixel_type,
    IntensityPixel, BinaryPixel, SegmentPixel

const cast = image2D_morph.cast
fallback(args...) = return nothing

"""
    bundle_image2DIntensity_filtering_factory

Convolution filters on intensity images.

Gradients, in x, y and magnitude (`m`) variants: `sobel`, `ando3`, `ando4`,
`ando5`, `bickley`, `prewitt`, `scharr`. Smoothing: `gaussian5` through
`gaussian25`, `moffat5`, `moffat13`, `moffat25`, and the difference of
gaussians `dog_image2D`. Second order: `laplacian3_image2D`.

Every result is rescaled min to max into `[0, 1]` (a flat result is all `0`).
The derivatives `*x` / `*y` are signed: an edge getting brighter to the right
(`x`) or downwards (`y`) comes out dark, the opposite edge bright, and flat
areas in between. The gradients, Gaussians and Laplacian take an optional
second input, the border mode: `< 0` wraps around, `0` (default) repeats the
edge pixels, `> 0` mirrors.

This is a *factory* bundle: each entry is a function of a type that returns the
method specialised for it, so the same operator can be instantiated for several
image or element types. See [Libraries](@ref) for how factories are specialised
into a library.
"""
bundle_image2DIntensity_filtering_factory = FunctionBundle(fallback)
"""
    bundle_image2DBinary_filtering_factory

The filters of [`bundle_image2DIntensity_filtering_factory`](@ref) applied to
masks, plus `findlocalminima_image2D` and `findlocalmaxima_image2D`, which
return a mask of the extrema. The input may be a mask or an intensity image;
the rescaled `[0, 1]` response is rounded to a mask (set where it is above
`0.5`).

This is a *factory* bundle: each entry is a function of a type that returns the
method specialised for it, so the same operator can be instantiated for several
image or element types. See [Libraries](@ref) for how factories are specialised
into a library.
"""
bundle_image2DBinary_filtering_factory = FunctionBundle(fallback)


# ---------------------------------------------------------------------------
# How a filter operator runs
#
# Call tree of e.g. `sobelm_image2D(img, b; out)`:
#
#   output_pixels(out, img, P)                          where to write: out.img or a new array
#   _filter_into!(pixels, img, filter, border)
#   ├── scratch(:filter_input, Float64, …)              input values
#   ├── scratch(:filter_response, Float64, …)           filter response
#   ├── pixel_values!(input, img.img)                   pixels → Float64
#   ├── _respond!(response, input, filter, border)      ImageFiltering's imfilter!
#   └── _store_rescaled!(pixels, response)              NaN/Inf → 0, min–max to [0, 1], cast
#   image_result(out, pixels, size_type)                out, or the new image
#
# Working arrays are Float64, the kernels' type: Float32 arrays made
# imfilter! about 15% slower (mixed-type arithmetic) and changed some pixels
# by one storage level.
# ---------------------------------------------------------------------------

### Kernels ###
# reflect: ImageFiltering correlates; reflecting makes it a convolution.
const _ysobel, _xsobel = reflect.(Kernel.sobel())
const _yando3, _xando3 = reflect.(Kernel.ando3())
const _yando4, _xando4 = reflect.(Kernel.ando4())
const _yando5, _xando5 = reflect.(Kernel.ando5())
const _ybickley, _xbickley = reflect.(Kernel.bickley())
const _yprewitt, _xprewitt = reflect.(Kernel.prewitt())
const _yscharr, _xscharr = reflect.(Kernel.scharr())

const gaussian5 = Kernel.gaussian(1)
const gaussian9 = Kernel.gaussian(2)
const gaussian13 = Kernel.gaussian(3)
const gaussian17 = Kernel.gaussian(4)
const gaussian25 = Kernel.gaussian(6)
const laplacian3 = reflect(convert(AbstractArray, ImageFiltering.Kernel.Laplacian((true, true))))

"`x` clamped to `[lo, hi]` as a Float64; `NaN` and `±Inf` give `default`."
_finite_clamp(x::Real, lo::Float64, hi::Float64, default::Float64) =
    (v = Float64(x); isfinite(v) ? clamp(v, lo, hi) : default)

"""
    _border_type(b) -> String

ImageFiltering border mode from a number: `< 0` wraps around (`"circular"`,
abcdef | abcd), `0` repeats the edge pixel (`"replicate"`, abcdef | ffff),
`> 0` mirrors (`"reflect"`, abcdef | fedc).
"""
function _border_type(border_index::Real)
    border_index < 0 && return "circular"
    border_index > 0 && return "reflect"
    return "replicate"
end

### Filters ###
# A filter says how to turn the input values into a response; `_respond!` runs it.

"Convolution with one kernel (a derivative along one axis, a blur, the Laplacian, …)."
struct SingleKernel{K}
    kernel::K
end

"Gradient magnitude `sqrt(gx² + gy²)` from the derivative kernels along x and y."
struct GradientMagnitude{KX,KY}
    kernel_x::KX
    kernel_y::KY
end

"""
    _respond!(response, input, filter, border) -> response

Write the filter's response to `input` into `response` (same size), with the
border mode `border` (see `_border_type`).

Example: `_respond!(response, input, SingleKernel(gaussian5), "replicate")`
blurs `input` with σ = 1.
"""
function _respond!(response, input, filter::SingleKernel, border::String)
    # TODO speed: imfilter! pads the input into a new array on every call; a
    # padded working array kept across calls would remove that allocation.
    return imfilter!(response, input, filter.kernel, border)
end

function _respond!(response, input, filter::GradientMagnitude, border::String)
    along_y = scratch(:filter_gradient_y, Float64, size(input)...)
    imfilter!(response, input, filter.kernel_x, border)
    imfilter!(along_y, input, filter.kernel_y, border)
    @inbounds @simd for i in eachindex(response, along_y)
        response[i] = sqrt(response[i]^2 + along_y[i]^2)
    end
    return response
end

"""
    _filter_into!(pixels, img, filter, border) -> pixels

Filter the image `img` (intensity or mask) and write the response, rescaled
min to max into `[0, 1]`, into `pixels` (see `_store_rescaled!`).
"""
function _filter_into!(pixels, img, filter, border::String)
    input = pixel_values!(scratch(:filter_input, Float64, size(img.img)...), img.img)
    response = scratch(:filter_response, Float64, size(img.img)...)
    _respond!(response, input, filter, border)
    return _store_rescaled!(pixels, response)
end

"""
    _store_rescaled!(pixels, response) -> pixels

Rescale `response` min to max into `[0, 1]` and store it as pixels:
`NaN` and `±Inf` count as `0`; a flat response (spread below `1e-9` of its
magnitude) gives all `0`. Intensity pixels take the value; mask pixels are set
above `0.5`. `response` is modified (non-finite values zeroed).

Example: responses `[-2, 0, 2]` → `[0, 0.5, 1]` → intensity `[0, 128/255, 1]`,
mask `[false, false, true]`.
"""
function _store_rescaled!(pixels, response)
    @inbounds for i in eachindex(response)
        isfinite(response[i]) || (response[i] = 0)
    end
    lo, hi = extrema(response)
    if hi - lo <= 1e-9 * max(1.0, abs(lo), abs(hi))
        return _store_unit!(pixels, response, lo, Inf)     # flat: every value maps to 0
    end
    return _store_unit!(pixels, response, lo, hi - lo)
end

"""
    _store_unit!(pixels, response, lo, spread) -> pixels

`pixels .= pixel of clamp01nan((response - lo) / spread)`, in one broadcast
(an infinite `spread` maps everything to `0`).
"""
function _store_unit!(pixels::AbstractArray{IntensityPixel{T}}, response, lo, spread) where {T}
    pixels .= IntensityPixel{T}.(T.(clamp01nan.((response .- lo) ./ spread)))
    return pixels
end

function _store_unit!(pixels::AbstractArray{BinaryPixel{T}}, response, lo, spread) where {T}
    # round(Int, x) is 1 only above 0.5 for x ∈ [0, 1] (0.5 rounds to even, 0).
    pixels .= BinaryPixel{T}.(clamp01nan.((response .- lo) ./ spread) .> 0.5)
    return pixels
end

"""
    _filter_operator!(name, P, size_type, image_size, filter_of)

Define, for output pixels `P`, the method
`name(img, b; out = nothing)` filtering `img` with
`filter_of(img)` and border mode `_border_type(b)`, plus `name(img)` with
`b = 0` (edges replicated). Returns the function.
"""
@serialized_factory function _filter_operator!(name::Symbol, ::Type{P}, size_type, image_size, filter) where {P}
    isdefined(@__MODULE__, name) && return getfield(@__MODULE__, name)
    input = :(SizedImage{$image_size,<:Union{BinaryPixel{Bool},IntensityPixel}})
    fn = @eval function $name(img::Source, b::Real, args::Vararg{Any}; out = nothing) where {Source<:$input}
        pixels = output_pixels(out, img, $P)
        _filter_into!(pixels, img, $filter, _border_type(b))
        return image_result(out, pixels, $size_type)
    end
    @eval function $name(img::Source, args::Vararg{Any}; out = nothing) where {Source<:$input}
        return $name(img, 0.0; out)
    end
    return fn
end

"Output pixel type, size type and image size of the factory type `I` (validated)."
function _filter_types(::Type{I}) where {I}
    _validate_factory_type(_get_image_type(I))
    size_type = _get_image_tuple_size(I)
    return _get_image_pixel_type(I), size_type, size_type
end

### Factories of factories ###

"""
    XYM_filter_image2D_factory(axis, kernel_x, kernel_y, name) -> factory

Factory of `name * axis * "_image2D"` (e.g. `sobelx_image2D`): the derivative
along x (`axis = "x"`), along y (`"y"`), or the gradient magnitude (`"m"`).
Each specialised function takes the image and an optional border mode.

Example: `XYM_filter_image2D_factory("m", _xsobel, _ysobel, "sobel")(I)` is
`sobelm_image2D` for images of type `I`.
"""
function XYM_filter_image2D_factory(axis::String, kernel_x, kernel_y, name::String)
    filter = axis == "x" ? SingleKernel(kernel_x) : axis == "y" ? SingleKernel(kernel_y) :
             GradientMagnitude(kernel_x, kernel_y)
    return function (::Type{I}) where {I<:SizedImage{SIZE,<:Union{BinaryPixel{T1},IntensityPixel{T2}}}} where {SIZE,T1,T2}
        P, size_type, image_size = _filter_types(I)
        return _filter_operator!(Symbol(name, axis, :_image2D_, _factory_type_symbol(I)), P, size_type, image_size, filter)
    end
end

"""
    one_filter_image2D_factory(kernel, name) -> factory

Factory of `name * "_image2D"` (e.g. `gaussian5_image2D`): convolution with one
fixed kernel, then min–max rescaling. Takes the image and an optional border mode.
"""
function one_filter_image2D_factory(kernel, name::String)
    filter = SingleKernel(kernel)
    return function (::Type{I}) where {I<:SizedImage{SIZE,<:Union{BinaryPixel{T},IntensityPixel{T}}}} where {SIZE,T}
        P, size_type, image_size = _filter_types(I)
        return _filter_operator!(Symbol(name, :_image2D_, _factory_type_symbol(I)), P, size_type, image_size, filter)
    end
end

### Kernels built from parameters ###

"""
    _two_parameter_operator!(name, P, size_type, image_size, kernel_of, default; one_parameter = true)

Define `name(img, p1, p2)` and `name(img)` (`p1 = p2 = default`), each
convolving with `kernel_of(p1, p2)` (edges replicated) and rescaling min to
max; with `one_parameter`, also `name(img, p1)` (`p2 = p1`). Without it,
`name(img, p1)` falls to `name(img)` (the extra number is ignored), as Moffat
always did. Returns the function.
"""
@serialized_factory function _two_parameter_operator!(name::Symbol, ::Type{P}, size_type, image_size, kernel_of::K, default::Float64;
        one_parameter::Bool = true) where {P,K}
    isdefined(@__MODULE__, name) && return getfield(@__MODULE__, name)
    input = :(SizedImage{$image_size,<:Union{BinaryPixel,IntensityPixel}})
    fn = @eval function $name(img::Source, p1::Real, p2::Real, args::Vararg{Any}; out = nothing) where {Source<:$input}
        pixels = output_pixels(out, img, $P)
        _filter_into!(pixels, img, SingleKernel($kernel_of(p1, p2)), "replicate")
        return image_result(out, pixels, $size_type)
    end
    if one_parameter
        @eval function $name(img::Source, p1::Real, args::Vararg{Any}; out = nothing) where {Source<:$input}
            return $name(img, p1, p1; out)
        end
    end
    @eval function $name(img::Source, args::Vararg{Any}; out = nothing) where {Source<:$input}
        return $name(img, $default, $default; out)
    end
    return fn
end

"""
Difference of Gaussians `G(σ) − G(√2·σ)` per axis, with σ along y (`p1`) and
x (`p2`) in pixels, clamped to `[0.1, 10]` (`NaN` → 0.5): a band-pass that
highlights blobs about σ pixels wide.
"""
_dog_kernel(p1, p2) = reflect(ImageFiltering.Kernel.DoG((_finite_clamp(p1, 0.1, 10.0, 0.5), _finite_clamp(p2, 0.1, 10.0, 0.5))))

function dog_factory(::Type{I}) where {I<:SizedImage{SIZE,<:Union{BinaryPixel{T},IntensityPixel{T}}}} where {SIZE,T}
    P, size_type, image_size = _filter_types(I)
    return _two_parameter_operator!(Symbol(:dog_image2D_, _factory_type_symbol(I)), P, size_type, image_size, _dog_kernel, 0.5)
end

"""
    moffat_factories(ksize) -> factory

Factory of `moffat<ksize>_image2D(img, α, β)`: blur with a `ksize × ksize`
Moffat kernel, α the core width and β the fall-off, both clamped to
`[0.1, 100]` (`NaN` → 0.5).
"""
function moffat_factories(ksize::Int)
    kernel_of = (p1, p2) -> reflect(ImageFiltering.Kernel.moffat(_finite_clamp(p1, 0.1, 100.0, 0.5), _finite_clamp(p2, 0.1, 100.0, 0.5), ksize))
    return function (::Type{I}) where {I<:SizedImage{SIZE,<:Union{BinaryPixel{T},IntensityPixel{T}}}} where {SIZE,T}
        P, size_type, image_size = _filter_types(I)
        # The kernel size is in the name: moffat5, moffat13 and moffat25 must not share a function.
        # Moffat has no one-number method: `moffat(img, x)` uses the defaults (as the original).
        return _two_parameter_operator!(Symbol(:moffat, ksize, :_image2D_, _factory_type_symbol(I)), P, size_type, image_size, kernel_of, 0.5;
            one_parameter = false)
    end
end

### Local extrema (binary bundle only) ###

"""
    _mark_extrema!(pixels, img, find, w1, w2) -> pixels

Set the pixels at the local extrema `find(values; window = (w1, w2))` (e.g.
`findlocalmaxima`) of the image's values, and unset the others. The window
sizes are clamped to `[2, 25]` and rounded (`NaN` → 3).
"""
function _mark_extrema!(pixels::AbstractArray{P}, img, find::F, w1_::Real, w2_::Real) where {P,F}
    w1 = round(Int, _finite_clamp(w1_, 2.0, 25.0, 3.0))
    w2 = round(Int, _finite_clamp(w2_, 2.0, 25.0, 3.0))
    # TODO speed: findlocalminima/maxima return a new vector of indices on every call.
    extrema_at = find(reinterpret(img.img); window = (w1, w2))
    fill!(pixels, P(false))
    for index in extrema_at
        pixels[index] = P(true)
    end
    return pixels
end

"""
Define `name(img, w1, w2)`, `name(img, w1)` (`w2 = w1`) and `name(img)`
(3 × 3 window), marking the local extrema found by `find`.
"""
@serialized_factory function _extrema_operator!(name::Symbol, ::Type{P}, size_type, image_size, find::F) where {P,F}
    isdefined(@__MODULE__, name) && return getfield(@__MODULE__, name)
    input = :(SizedImage{$image_size,<:Union{BinaryPixel,IntensityPixel}})
    fn = @eval function $name(img::Source, w1::Real, w2::Real, args::Vararg{Any}; out = nothing) where {Source<:$input}
        pixels = output_pixels(out, img, $P)
        _mark_extrema!(pixels, img, $find, w1, w2)
        return image_result(out, pixels, $size_type)
    end
    @eval function $name(img::Source, w1::Real, args::Vararg{Any}; out = nothing) where {Source<:$input}
        return $name(img, w1, w1; out)
    end
    @eval function $name(img::Source, args::Vararg{Any}; out = nothing) where {Source<:$input}
        return $name(img, 3, 3; out)
    end
    return fn
end

"Factory of `findlocalminima_image2D(mask[, w1, w2])`: marks the local minima."
function findlocalminima_factory(::Type{I}) where {I<:SizedImage{SIZE,BinaryPixel{T}}} where {SIZE,T}
    P, size_type, image_size = _filter_types(I)
    return _extrema_operator!(Symbol(:findlocalminima_image2D_, _factory_type_symbol(I)), P, size_type, image_size, findlocalminima)
end

"Factory of `findlocalmaxima_image2D(mask[, w1, w2])`: marks the local maxima."
function findlocalmaxima_factory(::Type{I}) where {I<:SizedImage{SIZE,BinaryPixel{T}}} where {SIZE,T}
    P, size_type, image_size = _filter_types(I)
    return _extrema_operator!(Symbol(:findlocalmaxima_image2D_, _factory_type_symbol(I)), P, size_type, image_size, findlocalmaxima)
end

### BUNDLES ###

# X,Y,M kernels ---
sobelx_image2D_factory = XYM_filter_image2D_factory("x", _xsobel, _ysobel, "sobel")
sobely_image2D_factory = XYM_filter_image2D_factory("y", _xsobel, _ysobel, "sobel")
sobelm_image2D_factory = XYM_filter_image2D_factory("m", _xsobel, _ysobel, "sobel")

ando3x_image2D_factory = XYM_filter_image2D_factory("x", _xando3, _yando3, "ando3")
ando3y_image2D_factory = XYM_filter_image2D_factory("y", _xando3, _yando3, "ando3")
ando3m_image2D_factory = XYM_filter_image2D_factory("m", _xando3, _yando3, "ando3")
ando4x_image2D_factory = XYM_filter_image2D_factory("x", _xando4, _yando4, "ando4")
ando4y_image2D_factory = XYM_filter_image2D_factory("y", _xando4, _yando4, "ando4")
ando4m_image2D_factory = XYM_filter_image2D_factory("m", _xando4, _yando4, "ando4")
ando5x_image2D_factory = XYM_filter_image2D_factory("x", _xando5, _yando5, "ando5")
ando5y_image2D_factory = XYM_filter_image2D_factory("y", _xando5, _yando5, "ando5")
ando5m_image2D_factory = XYM_filter_image2D_factory("m", _xando5, _yando5, "ando5")

bickleyx_image2D_factory = XYM_filter_image2D_factory("x", _xbickley, _ybickley, "bickley")
bickleyy_image2D_factory = XYM_filter_image2D_factory("y", _xbickley, _ybickley, "bickley")
bickleym_image2D_factory = XYM_filter_image2D_factory("m", _xbickley, _ybickley, "bickley")

prewittx_image2D_factory = XYM_filter_image2D_factory("x", _xprewitt, _yprewitt, "prewitt")
prewitty_image2D_factory = XYM_filter_image2D_factory("y", _xprewitt, _yprewitt, "prewitt")
prewittm_image2D_factory = XYM_filter_image2D_factory("m", _xprewitt, _yprewitt, "prewitt")

scharrx_image2D_factory = XYM_filter_image2D_factory("x", _xscharr, _yscharr, "scharr")
scharry_image2D_factory = XYM_filter_image2D_factory("y", _xscharr, _yscharr, "scharr")
scharrm_image2D_factory = XYM_filter_image2D_factory("m", _xscharr, _yscharr, "scharr")

# One kernel ---
gaussian5_image2D_factory = one_filter_image2D_factory(gaussian5, "gaussian5")
gaussian9_image2D_factory = one_filter_image2D_factory(gaussian9, "gaussian9")
gaussian13_image2D_factory = one_filter_image2D_factory(gaussian13, "gaussian13")
gaussian17_image2D_factory = one_filter_image2D_factory(gaussian17, "gaussian17")
gaussian25_image2D_factory = one_filter_image2D_factory(gaussian25, "gaussian25")
laplacian3_image2D_factory = one_filter_image2D_factory(laplacian3, "laplacian3")

# Special
moffat5_image2D_factory = moffat_factories(5)
moffat13_image2D_factory = moffat_factories(13)
moffat25_image2D_factory = moffat_factories(25)

# BUNDLE INTENSITY ---
for (factory, name, description) in (
    (sobelx_image2D_factory, :sobelx_image2D, "Sobel derivative along x (across columns): marks vertical edges; signed, rescaled min to max: edges getting brighter to the right are dark, darker to the right bright, flat areas in between. Optional 2nd input: border mode (< 0 wrap around, 0 repeat edge pixels, > 0 mirror)."),
    (sobely_image2D_factory, :sobely_image2D, "Sobel derivative along y (across rows): marks horizontal edges; signed, rescaled min to max: edges getting brighter downwards are dark, darker downwards bright, flat areas in between. Optional 2nd input: border mode (< 0 wrap around, 0 repeat edge pixels, > 0 mirror)."),
    (sobelm_image2D_factory, :sobelm_image2D, "Sobel gradient magnitude sqrt(gx^2 + gy^2): edge strength in any direction, rescaled to [0, 1]. Optional 2nd input: border mode (< 0 wrap around, 0 repeat edge pixels, > 0 mirror)."),
    (ando3x_image2D_factory, :ando3x_image2D, "Ando 3x3 derivative along x (across columns): marks vertical edges; signed, rescaled min to max: edges getting brighter to the right are dark, darker to the right bright, flat areas in between. Optional 2nd input: border mode (< 0 wrap around, 0 repeat edge pixels, > 0 mirror)."),
    (ando3y_image2D_factory, :ando3y_image2D, "Ando 3x3 derivative along y (across rows): marks horizontal edges; signed, rescaled min to max: edges getting brighter downwards are dark, darker downwards bright, flat areas in between. Optional 2nd input: border mode (< 0 wrap around, 0 repeat edge pixels, > 0 mirror)."),
    (ando3m_image2D_factory, :ando3m_image2D, "Ando 3x3 gradient magnitude sqrt(gx^2 + gy^2): edge strength in any direction, rescaled to [0, 1]. Optional 2nd input: border mode (< 0 wrap around, 0 repeat edge pixels, > 0 mirror)."),
    (ando4x_image2D_factory, :ando4x_image2D, "Ando 4x4 derivative along x (across columns): marks vertical edges; signed, rescaled min to max: edges getting brighter to the right are dark, darker to the right bright, flat areas in between. Optional 2nd input: border mode (< 0 wrap around, 0 repeat edge pixels, > 0 mirror)."),
    (ando4y_image2D_factory, :ando4y_image2D, "Ando 4x4 derivative along y (across rows): marks horizontal edges; signed, rescaled min to max: edges getting brighter downwards are dark, darker downwards bright, flat areas in between. Optional 2nd input: border mode (< 0 wrap around, 0 repeat edge pixels, > 0 mirror)."),
    (ando4m_image2D_factory, :ando4m_image2D, "Ando 4x4 gradient magnitude sqrt(gx^2 + gy^2): edge strength in any direction, rescaled to [0, 1]. Optional 2nd input: border mode (< 0 wrap around, 0 repeat edge pixels, > 0 mirror)."),
    (ando5x_image2D_factory, :ando5x_image2D, "Ando 5x5 derivative along x (across columns): marks vertical edges; signed, rescaled min to max: edges getting brighter to the right are dark, darker to the right bright, flat areas in between. Optional 2nd input: border mode (< 0 wrap around, 0 repeat edge pixels, > 0 mirror)."),
    (ando5y_image2D_factory, :ando5y_image2D, "Ando 5x5 derivative along y (across rows): marks horizontal edges; signed, rescaled min to max: edges getting brighter downwards are dark, darker downwards bright, flat areas in between. Optional 2nd input: border mode (< 0 wrap around, 0 repeat edge pixels, > 0 mirror)."),
    (ando5m_image2D_factory, :ando5m_image2D, "Ando 5x5 gradient magnitude sqrt(gx^2 + gy^2): edge strength in any direction, rescaled to [0, 1]. Optional 2nd input: border mode (< 0 wrap around, 0 repeat edge pixels, > 0 mirror)."),
    (bickleyx_image2D_factory, :bickleyx_image2D, "Bickley derivative along x (across columns): marks vertical edges; signed, rescaled min to max: edges getting brighter to the right are dark, darker to the right bright, flat areas in between. Optional 2nd input: border mode (< 0 wrap around, 0 repeat edge pixels, > 0 mirror)."),
    (bickleyy_image2D_factory, :bickleyy_image2D, "Bickley derivative along y (across rows): marks horizontal edges; signed, rescaled min to max: edges getting brighter downwards are dark, darker downwards bright, flat areas in between. Optional 2nd input: border mode (< 0 wrap around, 0 repeat edge pixels, > 0 mirror)."),
    (bickleym_image2D_factory, :bickleym_image2D, "Bickley gradient magnitude sqrt(gx^2 + gy^2): edge strength in any direction, rescaled to [0, 1]. Optional 2nd input: border mode (< 0 wrap around, 0 repeat edge pixels, > 0 mirror)."),
    (prewittx_image2D_factory, :prewittx_image2D, "Prewitt derivative along x (across columns): marks vertical edges; signed, rescaled min to max: edges getting brighter to the right are dark, darker to the right bright, flat areas in between. Optional 2nd input: border mode (< 0 wrap around, 0 repeat edge pixels, > 0 mirror)."),
    (prewitty_image2D_factory, :prewitty_image2D, "Prewitt derivative along y (across rows): marks horizontal edges; signed, rescaled min to max: edges getting brighter downwards are dark, darker downwards bright, flat areas in between. Optional 2nd input: border mode (< 0 wrap around, 0 repeat edge pixels, > 0 mirror)."),
    (prewittm_image2D_factory, :prewittm_image2D, "Prewitt gradient magnitude sqrt(gx^2 + gy^2): edge strength in any direction, rescaled to [0, 1]. Optional 2nd input: border mode (< 0 wrap around, 0 repeat edge pixels, > 0 mirror)."),
    (scharrx_image2D_factory, :scharrx_image2D, "Scharr derivative along x (across columns): marks vertical edges; signed, rescaled min to max: edges getting brighter to the right are dark, darker to the right bright, flat areas in between. Optional 2nd input: border mode (< 0 wrap around, 0 repeat edge pixels, > 0 mirror)."),
    (scharry_image2D_factory, :scharry_image2D, "Scharr derivative along y (across rows): marks horizontal edges; signed, rescaled min to max: edges getting brighter downwards are dark, darker downwards bright, flat areas in between. Optional 2nd input: border mode (< 0 wrap around, 0 repeat edge pixels, > 0 mirror)."),
    (scharrm_image2D_factory, :scharrm_image2D, "Scharr gradient magnitude sqrt(gx^2 + gy^2): edge strength in any direction, rescaled to [0, 1]. Optional 2nd input: border mode (< 0 wrap around, 0 repeat edge pixels, > 0 mirror)."),
    (gaussian5_image2D_factory, :gaussian5_image2D, "Gaussian blur, sigma 1 pixels (5x5 kernel), then rescaled to [0, 1]. Optional 2nd input: border mode (< 0 wrap around, 0 repeat edge pixels, > 0 mirror)."),
    (gaussian9_image2D_factory, :gaussian9_image2D, "Gaussian blur, sigma 2 pixels (9x9 kernel), then rescaled to [0, 1]. Optional 2nd input: border mode (< 0 wrap around, 0 repeat edge pixels, > 0 mirror)."),
    (gaussian13_image2D_factory, :gaussian13_image2D, "Gaussian blur, sigma 3 pixels (13x13 kernel), then rescaled to [0, 1]. Optional 2nd input: border mode (< 0 wrap around, 0 repeat edge pixels, > 0 mirror)."),
    (gaussian17_image2D_factory, :gaussian17_image2D, "Gaussian blur, sigma 4 pixels (17x17 kernel), then rescaled to [0, 1]. Optional 2nd input: border mode (< 0 wrap around, 0 repeat edge pixels, > 0 mirror)."),
    (gaussian25_image2D_factory, :gaussian25_image2D, "Gaussian blur, sigma 6 pixels (25x25 kernel), then rescaled to [0, 1]. Optional 2nd input: border mode (< 0 wrap around, 0 repeat edge pixels, > 0 mirror)."),
    (laplacian3_image2D_factory, :laplacian3_image2D, "3x3 Laplacian (second derivative): strong on thin lines, spots and both sides of edges; signed, rescaled min to max. Optional 2nd input: border mode (< 0 wrap around, 0 repeat edge pixels, > 0 mirror)."),
    (dog_factory, :dog_image2D, "Difference of Gaussians (img, sigma_y, sigma_x): band-pass highlighting blobs of about sigma pixels; rescaled to [0, 1]."),
    (moffat5_image2D_factory, :moffat5_image2D, "Moffat blur on a 5x5 kernel: (img, alpha, beta), alpha the core width, beta the fall-off; rescaled to [0, 1]."),
    (moffat13_image2D_factory, :moffat13_image2D, "Moffat blur on a 13x13 kernel: (img, alpha, beta), alpha the core width, beta the fall-off; rescaled to [0, 1]."),
    (moffat25_image2D_factory, :moffat25_image2D, "Moffat blur on a 25x25 kernel: (img, alpha, beta), alpha the core width, beta the fall-off; rescaled to [0, 1]."),
)
    append_method!(
        bundle_image2DIntensity_filtering_factory,
        factory,
        name;
        description = description,
    )
end

# BUNDLE BINARY ---
for (factory, name, description) in (
    (sobelx_image2D_factory, :sobelx_image2D, "Sobel derivative along x (across columns): marks vertical edges; signed, rescaled min to max: edges getting brighter to the right are dark, darker to the right bright, flat areas in between. Optional 2nd input: border mode (< 0 wrap around, 0 repeat edge pixels, > 0 mirror)."),
    (sobely_image2D_factory, :sobely_image2D, "Sobel derivative along y (across rows): marks horizontal edges; signed, rescaled min to max: edges getting brighter downwards are dark, darker downwards bright, flat areas in between. Optional 2nd input: border mode (< 0 wrap around, 0 repeat edge pixels, > 0 mirror)."),
    (sobelm_image2D_factory, :sobelm_image2D, "Sobel gradient magnitude sqrt(gx^2 + gy^2): edge strength in any direction, rescaled to [0, 1]. Optional 2nd input: border mode (< 0 wrap around, 0 repeat edge pixels, > 0 mirror)."),
    (ando3x_image2D_factory, :ando3x_image2D, "Ando 3x3 derivative along x (across columns): marks vertical edges; signed, rescaled min to max: edges getting brighter to the right are dark, darker to the right bright, flat areas in between. Optional 2nd input: border mode (< 0 wrap around, 0 repeat edge pixels, > 0 mirror)."),
    (ando3y_image2D_factory, :ando3y_image2D, "Ando 3x3 derivative along y (across rows): marks horizontal edges; signed, rescaled min to max: edges getting brighter downwards are dark, darker downwards bright, flat areas in between. Optional 2nd input: border mode (< 0 wrap around, 0 repeat edge pixels, > 0 mirror)."),
    (ando3m_image2D_factory, :ando3m_image2D, "Ando 3x3 gradient magnitude sqrt(gx^2 + gy^2): edge strength in any direction, rescaled to [0, 1]. Optional 2nd input: border mode (< 0 wrap around, 0 repeat edge pixels, > 0 mirror)."),
    (ando4x_image2D_factory, :ando4x_image2D, "Ando 4x4 derivative along x (across columns): marks vertical edges; signed, rescaled min to max: edges getting brighter to the right are dark, darker to the right bright, flat areas in between. Optional 2nd input: border mode (< 0 wrap around, 0 repeat edge pixels, > 0 mirror)."),
    (ando4y_image2D_factory, :ando4y_image2D, "Ando 4x4 derivative along y (across rows): marks horizontal edges; signed, rescaled min to max: edges getting brighter downwards are dark, darker downwards bright, flat areas in between. Optional 2nd input: border mode (< 0 wrap around, 0 repeat edge pixels, > 0 mirror)."),
    (ando4m_image2D_factory, :ando4m_image2D, "Ando 4x4 gradient magnitude sqrt(gx^2 + gy^2): edge strength in any direction, rescaled to [0, 1]. Optional 2nd input: border mode (< 0 wrap around, 0 repeat edge pixels, > 0 mirror)."),
    (ando5x_image2D_factory, :ando5x_image2D, "Ando 5x5 derivative along x (across columns): marks vertical edges; signed, rescaled min to max: edges getting brighter to the right are dark, darker to the right bright, flat areas in between. Optional 2nd input: border mode (< 0 wrap around, 0 repeat edge pixels, > 0 mirror)."),
    (ando5y_image2D_factory, :ando5y_image2D, "Ando 5x5 derivative along y (across rows): marks horizontal edges; signed, rescaled min to max: edges getting brighter downwards are dark, darker downwards bright, flat areas in between. Optional 2nd input: border mode (< 0 wrap around, 0 repeat edge pixels, > 0 mirror)."),
    (ando5m_image2D_factory, :ando5m_image2D, "Ando 5x5 gradient magnitude sqrt(gx^2 + gy^2): edge strength in any direction, rescaled to [0, 1]. Optional 2nd input: border mode (< 0 wrap around, 0 repeat edge pixels, > 0 mirror)."),
    (bickleyx_image2D_factory, :bickleyx_image2D, "Bickley derivative along x (across columns): marks vertical edges; signed, rescaled min to max: edges getting brighter to the right are dark, darker to the right bright, flat areas in between. Optional 2nd input: border mode (< 0 wrap around, 0 repeat edge pixels, > 0 mirror)."),
    (bickleyy_image2D_factory, :bickleyy_image2D, "Bickley derivative along y (across rows): marks horizontal edges; signed, rescaled min to max: edges getting brighter downwards are dark, darker downwards bright, flat areas in between. Optional 2nd input: border mode (< 0 wrap around, 0 repeat edge pixels, > 0 mirror)."),
    (bickleym_image2D_factory, :bickleym_image2D, "Bickley gradient magnitude sqrt(gx^2 + gy^2): edge strength in any direction, rescaled to [0, 1]. Optional 2nd input: border mode (< 0 wrap around, 0 repeat edge pixels, > 0 mirror)."),
    (prewittx_image2D_factory, :prewittx_image2D, "Prewitt derivative along x (across columns): marks vertical edges; signed, rescaled min to max: edges getting brighter to the right are dark, darker to the right bright, flat areas in between. Optional 2nd input: border mode (< 0 wrap around, 0 repeat edge pixels, > 0 mirror)."),
    (prewitty_image2D_factory, :prewitty_image2D, "Prewitt derivative along y (across rows): marks horizontal edges; signed, rescaled min to max: edges getting brighter downwards are dark, darker downwards bright, flat areas in between. Optional 2nd input: border mode (< 0 wrap around, 0 repeat edge pixels, > 0 mirror)."),
    (prewittm_image2D_factory, :prewittm_image2D, "Prewitt gradient magnitude sqrt(gx^2 + gy^2): edge strength in any direction, rescaled to [0, 1]. Optional 2nd input: border mode (< 0 wrap around, 0 repeat edge pixels, > 0 mirror)."),
    (scharrx_image2D_factory, :scharrx_image2D, "Scharr derivative along x (across columns): marks vertical edges; signed, rescaled min to max: edges getting brighter to the right are dark, darker to the right bright, flat areas in between. Optional 2nd input: border mode (< 0 wrap around, 0 repeat edge pixels, > 0 mirror)."),
    (scharry_image2D_factory, :scharry_image2D, "Scharr derivative along y (across rows): marks horizontal edges; signed, rescaled min to max: edges getting brighter downwards are dark, darker downwards bright, flat areas in between. Optional 2nd input: border mode (< 0 wrap around, 0 repeat edge pixels, > 0 mirror)."),
    (scharrm_image2D_factory, :scharrm_image2D, "Scharr gradient magnitude sqrt(gx^2 + gy^2): edge strength in any direction, rescaled to [0, 1]. Optional 2nd input: border mode (< 0 wrap around, 0 repeat edge pixels, > 0 mirror)."),
    (gaussian5_image2D_factory, :gaussian5_image2D, "Gaussian blur, sigma 1 pixels (5x5 kernel), then rescaled to [0, 1]. Optional 2nd input: border mode (< 0 wrap around, 0 repeat edge pixels, > 0 mirror)."),
    (gaussian9_image2D_factory, :gaussian9_image2D, "Gaussian blur, sigma 2 pixels (9x9 kernel), then rescaled to [0, 1]. Optional 2nd input: border mode (< 0 wrap around, 0 repeat edge pixels, > 0 mirror)."),
    (gaussian13_image2D_factory, :gaussian13_image2D, "Gaussian blur, sigma 3 pixels (13x13 kernel), then rescaled to [0, 1]. Optional 2nd input: border mode (< 0 wrap around, 0 repeat edge pixels, > 0 mirror)."),
    (gaussian17_image2D_factory, :gaussian17_image2D, "Gaussian blur, sigma 4 pixels (17x17 kernel), then rescaled to [0, 1]. Optional 2nd input: border mode (< 0 wrap around, 0 repeat edge pixels, > 0 mirror)."),
    (gaussian25_image2D_factory, :gaussian25_image2D, "Gaussian blur, sigma 6 pixels (25x25 kernel), then rescaled to [0, 1]. Optional 2nd input: border mode (< 0 wrap around, 0 repeat edge pixels, > 0 mirror)."),
    (laplacian3_image2D_factory, :laplacian3_image2D, "3x3 Laplacian (second derivative): strong on thin lines, spots and both sides of edges; signed, rescaled min to max. Optional 2nd input: border mode (< 0 wrap around, 0 repeat edge pixels, > 0 mirror)."),
    (dog_factory, :dog_image2D, "Difference of Gaussians (img, sigma_y, sigma_x): band-pass highlighting blobs of about sigma pixels; rescaled to [0, 1]."),
    (moffat5_image2D_factory, :moffat5_image2D, "Moffat blur on a 5x5 kernel: (img, alpha, beta), alpha the core width, beta the fall-off; rescaled to [0, 1]."),
    (moffat13_image2D_factory, :moffat13_image2D, "Moffat blur on a 13x13 kernel: (img, alpha, beta), alpha the core width, beta the fall-off; rescaled to [0, 1]."),
    (moffat25_image2D_factory, :moffat25_image2D, "Moffat blur on a 25x25 kernel: (img, alpha, beta), alpha the core width, beta the fall-off; rescaled to [0, 1]."),
    (findlocalminima_factory, :findlocalminima_image2D, "Marks local minima locations in the filtered image."),
    (findlocalmaxima_factory, :findlocalmaxima_image2D, "Marks local maxima locations in the filtered image."),
)
    append_method!(
        bundle_image2DBinary_filtering_factory,
        factory,
        name;
        description = description,
    )
end

end
