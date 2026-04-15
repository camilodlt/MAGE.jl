""" Shared image-region helpers for image-to-float number libraries. """
module number_imgRegionCommon

using ..UTCGP: SImageND, IntensityPixel, BinaryPixel, SegmentPixel

const RegionCompatiblePixel = Union{IntensityPixel, BinaryPixel, SegmentPixel}

function _image_numeric(from::SImageND)
    return Float64.(reinterpret(from.img))
end

function _normalized_index(coord::Number, n::Int)
    c = clamp(Float64(coord), 0.0, 1.0)
    return clamp(round(Int, c * (n - 1) + 1), 1, n)
end

function _normalized_flat_index(position::Number, n::Int)
    p = clamp(Float64(position), 0.0, 1.0)
    return clamp(round(Int, p * (n - 1) + 1), 1, n)
end

function _position_row_col(from::SImageND, position::Number)
    img = _image_numeric(from)
    idx = _normalized_flat_index(position, length(img))
    cart = CartesianIndices(img)[idx]
    return cart[1], cart[2]
end

function _square_bounds_from_center(from::SImageND, center_row::Int, center_col::Int, half_h::Int, half_w::Int)
    h, w = size(from)
    row_lo = max(center_row - half_h, 1)
    row_hi = min(center_row + half_h, h)
    col_lo = max(center_col - half_w, 1)
    col_hi = min(center_col + half_w, w)
    return row_lo, row_hi, col_lo, col_hi
end

function _region_bounds(from::SImageND, cx::Number, cy::Number, half_size::Int)
    h, w = size(from)
    center_col = _normalized_index(cx, w)
    center_row = _normalized_index(cy, h)
    return _square_bounds_from_center(from, center_row, center_col, half_size, half_size)
end

function _region_window(from::SImageND, cx::Number, cy::Number, half_size::Int)
    row_lo, row_hi, col_lo, col_hi = _region_bounds(from, cx, cy, half_size)
    img = _image_numeric(from)
    return @view img[row_lo:row_hi, col_lo:col_hi]
end

function _region_bounds_from_position(from::SImageND, position::Number, half_h::Int, half_w::Int)
    center_row, center_col = _position_row_col(from, position)
    return _square_bounds_from_center(from, center_row, center_col, half_h, half_w)
end

function _region_window_from_position(from::SImageND, position::Number, half_h::Int, half_w::Int)
    row_lo, row_hi, col_lo, col_hi = _region_bounds_from_position(from, position, half_h, half_w)
    img = _image_numeric(from)
    return @view img[row_lo:row_hi, col_lo:col_hi]
end

function _half_extent(size_param::Number)
    return max(round(Int, abs(Float64(size_param))), 1)
end

end
