"""
Gradient orientation maps computed from Sobel derivatives.

# Bundles

- [`bundle_image2DIntensity_orientation_factory`](@ref)

The exhaustive, always-current list of operators in each bundle is on the
[Bundle Catalogue](@ref) page.

# Call tree

Every operator, e.g. `orientation_select(img, θ, bw; out)`:

    output_pixels(out, img)                       where to write: out.img or a new array
    _sobel_gradients(img) -> (gx, gy)             Sobel derivatives in task scratch
    ├── pixel_values!(values, img.img)            pixels → Float64
    └── _sobel_xy!(gx, gy, values)                (orientation_common.jl)
    _magnitude! / _select_band!                   per-pixel values, written over gx
    _store_rescaled! / _store_orientation!        min–max to [0, 1] / angle over π, cast
    image_result(out, pixels, size_type)

All arithmetic is in Float64, as before (Float32 noise would defeat the
`_FLAT` threshold that gives flat pixels orientation 0).
"""
module image2D_orientation

using ..UTCGP: _factory_type_symbol, @serialized_factory

using ..UTCGP: output_pixels, image_result, scratch, pixel_values!
using ..UTCGP: FunctionBundle, append_method!
using ..UTCGP:
    SizedImage2D, SImageND, _get_image_type, _get_image_pixel_type, _get_image_tuple_size,
    _validate_factory_type
using ..UTCGP: image2D_orientation_common
using ..UTCGP.image2D_orientation_common: _sobel_xy!

fallback(args...) = return nothing
"""
    bundle_image2DIntensity_orientation_factory

Gradient orientation maps from Sobel derivatives:

- `grad_magnitude(img)`: edge strength, rescaled so the strongest edge of the
  image is `1`.
- `grad_orientation(img)`: the **gradient** orientation (the direction across
  the edge) over `π`, in `[0, 1)`: `0` for a vertical edge, `0.5` for a
  horizontal one. Angles run clockwise on screen. Flat pixels also read `0`.
- `orientation_select(img, θ, bandwidth)`: the gradient magnitude, kept only
  where the gradient orientation is within `bandwidth · 90°` of `θ · 180°`
  (`θ` wraps around `1`), then rescaled to `[0, 1]`. So `θ = 0` keeps
  **vertical** edges and `θ = 0.5` horizontal ones. Defaults `θ = 0`,
  `bandwidth = 0.2` (±18°).

These use the gradient direction, perpendicular to the edge; the scalar
summaries in `bundle_float_orientation` use the edge direction, so
`orientation_energy_90` measures the same vertical edges that
`orientation_select(img, 0)` keeps.

For the scalar counterparts see `bundle_float_orientation`.

This is a *factory* bundle: each entry is a function of a type that returns the
method specialised for it, so the same operator can be instantiated for several
image or element types. See [Libraries](@ref) for how factories are specialised
into a library.
"""
bundle_image2DIntensity_orientation_factory = FunctionBundle(fallback)

"Target gradient angle in radians from a number: wraps around 1, `θ · π`; NaN/Inf → 0."
_theta_from_number(theta::Number) = (t = Float64(theta); isfinite(t) ? mod(t, 1.0) * π : 0.0)
"Half-width of the selected band in radians: `clamp(abs(bw), 0.01, 1) · π/2`; NaN/Inf → 0.2."
_bandwidth_from_number(bw::Number) = (b = Float64(bw); clamp(isfinite(b) ? abs(b) : 0.2, 0.01, 1.0) * (π / 2))

"""
    _sobel_gradients(img) -> (gx, gy)

The Sobel derivatives of the image along x and y, in task scratch (valid until
the next call in the same task).
"""
function _sobel_gradients(img::SImageND)
    dims = size(img.img)
    values = pixel_values!(scratch(:orientation_values, Float64, dims...), img.img)
    gx = scratch(:orientation_gx, Float64, dims...)
    gy = scratch(:orientation_gy, Float64, dims...)
    return _sobel_xy!(gx, gy, values)
end

"Overwrite `gx` with the gradient magnitude `sqrt(gx² + gy²)`."
function _magnitude!(gx, gy)
    @inbounds for i in eachindex(gx, gy)
        gx[i] = sqrt(gx[i]^2 + gy[i]^2)
    end
    return gx
end

"""
    _select_band!(gx, gy, theta, bandwidth) -> gx

Overwrite `gx` with the gradient magnitude where the gradient orientation
(in `[0, π)`) is within `bandwidth` of `theta` (angles wrap around π), `0`
elsewhere.

Example: `theta = 0`, `bandwidth = π/10`: a pixel with orientation `0.95π` is
`0.05π` away (through the wrap) and kept; one at `π/2` is dropped.
"""
function _select_band!(gx, gy, theta::Float64, bandwidth::Float64)
    @inbounds for i in eachindex(gx, gy)
        magnitude = sqrt(gx[i]^2 + gy[i]^2)
        orientation = mod(atan(gy[i], gx[i]) + π, π)
        gap = abs(orientation - theta)
        distance = min(gap, π - gap)           # angular distance modulo π
        gx[i] = ifelse(distance <= bandwidth, magnitude, 0.0)
    end
    return gx
end

"""
    _store_rescaled!(pixels, values, T) -> pixels

Write `values` rescaled min to max into `[0, 1]` (all `0` when constant) as
pixels of storage type `T`. Example: `[1, 2, 3]` → `[0, 0.5, 1]`.
"""
function _store_rescaled!(pixels::AbstractArray{P}, values, ::Type{T}) where {P,T}
    lo, hi = extrema(values)
    if hi == lo
        return fill!(pixels, P(T(0.0)))
    end
    pixels .= P.(T.((values .- lo) ./ (hi - lo)))
    return pixels
end

"""
    _store_orientation!(pixels, gx, gy, T) -> pixels

Write the gradient orientation over `π` (in `[0, 1)`) as pixels of storage
type `T`. Example: `gx = 0, gy = 1` (gradient straight down) → `0.5`.
"""
function _store_orientation!(pixels::AbstractArray{P}, gx, gy, ::Type{T}) where {P,T}
    pixels .= P.(T.(mod.(atan.(gy, gx) .+ π, π) ./ π))
    return pixels
end

@serialized_factory function grad_magnitude_image2D_factory(i::Type{I}) where {I<:SizedImage2D}
    IT, S = _get_image_type(I), _get_image_tuple_size(I)
    _validate_factory_type(IT)
    FUNCTION_NAME = Symbol(:grad_magnitude_image2D_, _factory_type_symbol(I))
    isdefined(@__MODULE__, FUNCTION_NAME) && return Base.invokelatest(getfield, @__MODULE__, FUNCTION_NAME)
    return @eval function $FUNCTION_NAME(img::CONCT, args::Vararg{Any}; out = nothing) where {CONCT<:$I}
        pixels = output_pixels(out, img)
        gx, gy = _sobel_gradients(img)
        _store_rescaled!(pixels, _magnitude!(gx, gy), $IT)
        return image_result(out, pixels, $S)
    end
end

@serialized_factory function grad_orientation_image2D_factory(i::Type{I}) where {I<:SizedImage2D}
    IT, S = _get_image_type(I), _get_image_tuple_size(I)
    _validate_factory_type(IT)
    FUNCTION_NAME = Symbol(:grad_orientation_image2D_, _factory_type_symbol(I))
    isdefined(@__MODULE__, FUNCTION_NAME) && return Base.invokelatest(getfield, @__MODULE__, FUNCTION_NAME)
    return @eval function $FUNCTION_NAME(img::CONCT, args::Vararg{Any}; out = nothing) where {CONCT<:$I}
        pixels = output_pixels(out, img)
        gx, gy = _sobel_gradients(img)
        _store_orientation!(pixels, gx, gy, $IT)
        return image_result(out, pixels, $S)
    end
end

@serialized_factory function orientation_select_image2D_factory(i::Type{I}) where {I<:SizedImage2D}
    IT, S = _get_image_type(I), _get_image_tuple_size(I)
    _validate_factory_type(IT)
    FUNCTION_NAME = Symbol(:orientation_select_image2D_, _factory_type_symbol(I))
    isdefined(@__MODULE__, FUNCTION_NAME) && return Base.invokelatest(getfield, @__MODULE__, FUNCTION_NAME)
    f = @eval function $FUNCTION_NAME(img::CONCT, theta::Number, bandwidth::Number, args::Vararg{Any}; out = nothing) where {CONCT<:$I}
        pixels = output_pixels(out, img)
        gx, gy = _sobel_gradients(img)
        _select_band!(gx, gy, _theta_from_number(theta), _bandwidth_from_number(bandwidth))
        _store_rescaled!(pixels, gx, $IT)
        return image_result(out, pixels, $S)
    end
    @eval function $FUNCTION_NAME(img::CONCT, theta::Number, args::Vararg{Any}; out = nothing) where {CONCT<:$I}
        return $FUNCTION_NAME(img, theta, 0.2; out)
    end
    @eval function $FUNCTION_NAME(img::CONCT, args::Vararg{Any}; out = nothing) where {CONCT<:$I}
        return $FUNCTION_NAME(img, 0.0, 0.2; out)
    end
    return f
end

append_method!(
    bundle_image2DIntensity_orientation_factory,
    grad_magnitude_image2D_factory,
    :grad_magnitude;
    description = "Computes gradient magnitude map of the input image.",
)
append_method!(
    bundle_image2DIntensity_orientation_factory,
    grad_orientation_image2D_factory,
    :grad_orientation;
    description = "Computes gradient orientation map of the input image.",
)
append_method!(
    bundle_image2DIntensity_orientation_factory,
    orientation_select_image2D_factory,
    :orientation_select;
    description = "Selects image gradients near a target orientation with configurable bandwidth.",
)

end
