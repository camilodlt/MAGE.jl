""" Orientation image maps

Exports :

- **bundle\\_image2DIntensity\\_orientation\\_factory** :
    - `grad_magnitude`
    - `grad_orientation`
    - `orientation_select`
"""
module image2D_orientation

using ..UTCGP: FunctionBundle, append_method!
using ..UTCGP:
    SizedImage2D, SImageND, _get_image_type, _get_image_pixel_type, _get_image_tuple_size,
    _validate_factory_type
using ..UTCGP: image2D_orientation_common

fallback(args...) = return nothing
bundle_image2DIntensity_orientation_factory = FunctionBundle(fallback)

_theta_from_number(theta::Number) = mod(Float64(theta), 1.0) * π
_bandwidth_from_number(bw::Number) = clamp(abs(Float64(bw)), 0.01, 1.0) * (π / 2)

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

append_method!(bundle_image2DIntensity_orientation_factory, grad_magnitude_image2D_factory, :grad_magnitude)
append_method!(bundle_image2DIntensity_orientation_factory, grad_orientation_image2D_factory, :grad_orientation)
append_method!(bundle_image2DIntensity_orientation_factory, orientation_select_image2D_factory, :orientation_select)

end
