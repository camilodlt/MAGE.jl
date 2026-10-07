"""
Gradient orientation maps computed from Sobel derivatives.

# Bundles

- [`bundle_image2DIntensity_orientation_factory`](@ref)

The exhaustive, always-current list of operators in each bundle is on the
[Bundle Catalogue](@ref) page.
"""
module image2D_orientation

using ..UTCGP: FunctionBundle, append_method!
using ..UTCGP:
    SizedImage2D, SImageND, _get_image_type, _get_image_pixel_type, _get_image_tuple_size,
    _validate_factory_type
using ..UTCGP: image2D_orientation_common

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

function grad_magnitude_image2D_factory(i::Type{I}) where {I<:SizedImage2D}
    IT, PT, S = _get_image_type(I), _get_image_pixel_type(I), _get_image_tuple_size(I)
    _validate_factory_type(IT)
    FUNCTION_NAME = Symbol(:grad_magnitude_image2D_, Symbol(I))

    f = @eval function $FUNCTION_NAME(img::CONCT, args::Vararg{Any}) where {CONCT<:$I}
        mag, _, _ = image2D_orientation_common._grad_magnitude_matrix(img)
        out = image2D_orientation_common._normalize01(mag)
        return SImageND($PT.($IT.(out)), $S)
    end
    return f
end

function grad_orientation_image2D_factory(i::Type{I}) where {I<:SizedImage2D}
    IT, PT, S = _get_image_type(I), _get_image_pixel_type(I), _get_image_tuple_size(I)
    _validate_factory_type(IT)
    FUNCTION_NAME = Symbol(:grad_orientation_image2D_, Symbol(I))

    f = @eval function $FUNCTION_NAME(img::CONCT, args::Vararg{Any}) where {CONCT<:$I}
        theta, _, _ = image2D_orientation_common._gradient_orientation_matrix(img)
        out = theta ./ π
        return SImageND($PT.($IT.(out)), $S)
    end
    return f
end

function orientation_select_image2D_factory(i::Type{I}) where {I<:SizedImage2D}
    IT, PT, S = _get_image_type(I), _get_image_pixel_type(I), _get_image_tuple_size(I)
    _validate_factory_type(IT)
    FUNCTION_NAME = Symbol(:orientation_select_image2D_, Symbol(I))

    f = @eval function $FUNCTION_NAME(img::CONCT, theta_::Number, bw_::Number, args::Vararg{Any}) where {CONCT<:$I}
        mag, _, _ = image2D_orientation_common._grad_magnitude_matrix(img)
        theta_map, _, _ = image2D_orientation_common._gradient_orientation_matrix(img)
        theta = _theta_from_number(theta_)
        bw = _bandwidth_from_number(bw_)
        dist = image2D_orientation_common._angle_distance(theta_map, theta)
        out = ifelse.(dist .<= bw, mag, 0.0)
        out = image2D_orientation_common._normalize01(out)
        return SImageND($PT.($IT.(out)), $S)
    end

    @eval function $FUNCTION_NAME(img::CONCT, theta_::Number, args::Vararg{Any}) where {CONCT<:$I}
        return $FUNCTION_NAME(img, theta_, 0.2, args...)
    end

    @eval function $FUNCTION_NAME(img::CONCT, args::Vararg{Any}) where {CONCT<:$I}
        return $FUNCTION_NAME(img, 0.0, 0.2, args...)
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
