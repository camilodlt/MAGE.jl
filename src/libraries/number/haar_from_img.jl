""" Haar-like rectangular image-to-float features. """
module number_haarFromImg

using Statistics: mean
using ImageCore: RGB
using ..UTCGP: FunctionBundle, append_method!
using ..UTCGP: SImageND, IntensityPixel, BinaryPixel
using ..number_imgRegionCommon:
    _image_numeric,
    _half_extent,
    _region_bounds_from_position

fallback(args...) = return 0.0
bundle_number_haarFromImg = FunctionBundle(fallback)

function _haar_bounds(from::SImageND, position::Number, region_size::Number)
    half = _half_extent(region_size)
    return _region_bounds_from_position(from, position, half, half)
end

function _haar_local_shape(from::SImageND, position::Number, region_size::Number)
    row_lo, row_hi, col_lo, col_hi = _haar_bounds(from, position, region_size)
    return row_hi - row_lo + 1, col_hi - col_lo + 1
end

function _safe_mean(values)
    isempty(values) && return 0.0
    return Float64(mean(values))
end

function _haar_weight_matrix(kind::Symbol, h::Int, w::Int)
    weights = zeros(Float64, h, w)

    if kind === :haar_lr
        mid = fld(w, 2)
        mid == 0 && return weights
        weights[:, 1:mid] .= 1.0
        weights[:, w - mid + 1:w] .= -1.0
    elseif kind === :haar_tb
        mid = fld(h, 2)
        mid == 0 && return weights
        weights[1:mid, :] .= 1.0
        weights[h - mid + 1:h, :] .= -1.0
    elseif kind === :haar_diag_main
        row_mid = fld(h, 2)
        col_mid = fld(w, 2)
        row_mid == 0 && return weights
        col_mid == 0 && return weights
        weights[1:row_mid, 1:col_mid] .= 1.0
        weights[h - row_mid + 1:h, w - col_mid + 1:w] .= 1.0
        weights[1:row_mid, w - col_mid + 1:w] .= -1.0
        weights[h - row_mid + 1:h, 1:col_mid] .= -1.0
    elseif kind === :haar_diag_anti
        row_mid = fld(h, 2)
        col_mid = fld(w, 2)
        row_mid == 0 && return weights
        col_mid == 0 && return weights
        weights[1:row_mid, w - col_mid + 1:w] .= 1.0
        weights[h - row_mid + 1:h, 1:col_mid] .= 1.0
        weights[1:row_mid, 1:col_mid] .= -1.0
        weights[h - row_mid + 1:h, w - col_mid + 1:w] .= -1.0
    elseif kind === :haar_center_surround
        fill!(weights, -1.0)
        row_mid = fld(h, 2)
        col_mid = fld(w, 2)
        row_mid == 0 && return weights
        col_mid == 0 && return weights
        center_h = max(cld(h, 3), 1)
        center_w = max(cld(w, 3), 1)
        row_start = clamp(fld(h - center_h, 2) + 1, 1, h)
        row_end = clamp(row_start + center_h - 1, 1, h)
        col_start = clamp(fld(w - center_w, 2) + 1, 1, w)
        col_end = clamp(col_start + center_w - 1, 1, w)
        weights[row_start:row_end, col_start:col_end] .= 1.0
    elseif kind === :haar_three_h
        third = fld(w, 3)
        third == 0 && return weights
        weights[:, 1:third] .= 1.0
        weights[:, third + 1:2 * third] .= -1.0
        weights[:, 2 * third + 1:3 * third] .= 1.0
    elseif kind === :haar_three_v
        third = fld(h, 3)
        third == 0 && return weights
        weights[1:third, :] .= 1.0
        weights[third + 1:2 * third, :] .= -1.0
        weights[2 * third + 1:3 * third, :] .= 1.0
    else
        error("Unknown Haar feature kind: $kind")
    end

    return weights
end

function _haar_overlay_weights(from::SImageND, kind::Symbol, position::Number, region_size::Number)
    h, w = _haar_local_shape(from, position, region_size)
    return _haar_weight_matrix(kind, h, w)
end

function _normalize01(img::AbstractMatrix{<:Real})
    vals = Float64.(img)
    minv = minimum(vals)
    maxv = maximum(vals)
    return maxv == minv ? zeros(size(vals)) : (vals .- minv) ./ (maxv - minv)
end

function _haar_overlay_canvas(from::SImageND, kind::Symbol, position::Number, region_size::Number)
    img = _normalize01(_image_numeric(from))
    canvas = RGB.(img, img, img)
    row_lo, row_hi, col_lo, col_hi = _haar_bounds(from, position, region_size)
    weights = _haar_overlay_weights(from, kind, position, region_size)

    for local_r in axes(weights, 1), local_c in axes(weights, 2)
        global_r = row_lo + local_r - 1
        global_c = col_lo + local_c - 1
        if weights[local_r, local_c] > 0
            canvas[global_r, global_c] = RGB(0.85, 0.2, 0.2)
        elseif weights[local_r, local_c] < 0
            canvas[global_r, global_c] = RGB(0.2, 0.35, 0.9)
        end
    end

    return canvas
end

function _haar_feature_value(from::SImageND, kind::Symbol, position::Number, region_size::Number)
    row_lo, row_hi, col_lo, col_hi = _haar_bounds(from, position, region_size)
    patch = @view _image_numeric(from)[row_lo:row_hi, col_lo:col_hi]
    weights = _haar_weight_matrix(kind, size(patch, 1), size(patch, 2))

    pos_values = patch[weights .> 0]
    neg_values = patch[weights .< 0]

    return _safe_mean(pos_values) - _safe_mean(neg_values)
end

"""
    haar_lr(from::SImageND, position::Number, size::Number, args...)

Return the mean contrast between the left and right halves of a clipped local
region centered from a column-major flattened normalized position.
"""
function haar_lr(from::SImageND{S,T,2,C}, position::Number, region_size::Number, args...) where {S,T<:Union{IntensityPixel,BinaryPixel},C}
    return _haar_feature_value(from, :haar_lr, position, region_size)
end

"""
    haar_tb(from::SImageND, position::Number, size::Number, args...)

Return the mean contrast between the top and bottom halves of a clipped local
region centered from a column-major flattened normalized position.
"""
function haar_tb(from::SImageND{S,T,2,C}, position::Number, region_size::Number, args...) where {S,T<:Union{IntensityPixel,BinaryPixel},C}
    return _haar_feature_value(from, :haar_tb, position, region_size)
end

"""
    haar_diag_main(from::SImageND, position::Number, size::Number, args...)

Return the checkerboard diagonal contrast between the main-diagonal quadrants
and the anti-diagonal quadrants of a clipped local region.
"""
function haar_diag_main(from::SImageND{S,T,2,C}, position::Number, region_size::Number, args...) where {S,T<:Union{IntensityPixel,BinaryPixel},C}
    return _haar_feature_value(from, :haar_diag_main, position, region_size)
end

"""
    haar_diag_anti(from::SImageND, position::Number, size::Number, args...)

Return the checkerboard diagonal contrast between the anti-diagonal quadrants
and the main-diagonal quadrants of a clipped local region.
"""
function haar_diag_anti(from::SImageND{S,T,2,C}, position::Number, region_size::Number, args...) where {S,T<:Union{IntensityPixel,BinaryPixel},C}
    return _haar_feature_value(from, :haar_diag_anti, position, region_size)
end

"""
    haar_center_surround(from::SImageND, position::Number, size::Number, args...)

Return the mean contrast between a center box and its clipped surrounding ring.
"""
function haar_center_surround(from::SImageND{S,T,2,C}, position::Number, region_size::Number, args...) where {S,T<:Union{IntensityPixel,BinaryPixel},C}
    return _haar_feature_value(from, :haar_center_surround, position, region_size)
end

"""
    haar_three_h(from::SImageND, position::Number, size::Number, args...)

Return a horizontal three-rectangle contrast over a clipped local region.
"""
function haar_three_h(from::SImageND{S,T,2,C}, position::Number, region_size::Number, args...) where {S,T<:Union{IntensityPixel,BinaryPixel},C}
    return _haar_feature_value(from, :haar_three_h, position, region_size)
end

"""
    haar_three_v(from::SImageND, position::Number, size::Number, args...)

Return a vertical three-rectangle contrast over a clipped local region.
"""
function haar_three_v(from::SImageND{S,T,2,C}, position::Number, region_size::Number, args...) where {S,T<:Union{IntensityPixel,BinaryPixel},C}
    return _haar_feature_value(from, :haar_three_v, position, region_size)
end

append_method!(bundle_number_haarFromImg, haar_lr)
append_method!(bundle_number_haarFromImg, haar_tb)
append_method!(bundle_number_haarFromImg, haar_diag_main)
append_method!(bundle_number_haarFromImg, haar_diag_anti)
append_method!(bundle_number_haarFromImg, haar_center_surround)
append_method!(bundle_number_haarFromImg, haar_three_h)
append_method!(bundle_number_haarFromImg, haar_three_v)

end
