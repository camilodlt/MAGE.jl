"""
Shared image-region helpers for the image-to-float number libraries
(`region_*`, `haar_*`).

Coordinates are normalised to `[0, 1]` (`0` = first pixel, `1` = last);
non-finite inputs fall back to the image centre (`0.5`) and sizes to `1`,
so values coming from evolved programs never throw.
"""
module number_imgRegionCommon

using ..UTCGP: SImageND, IntensityPixel, BinaryPixel, SegmentPixel

const RegionCompatiblePixel = Union{IntensityPixel, BinaryPixel, SegmentPixel}

function _image_numeric(from::SImageND)
    return Float64.(reinterpret(from.img))
end

"`coord` clamped to `[0, 1]`; `NaN` and `±Inf` become `0.5` (the centre)."
_unit_or_centre(coord::Number) = (c = Float64(coord); isfinite(c) ? clamp(c, 0.0, 1.0) : 0.5)

"""
Index `1:n` of the pixel at normalised coordinate `coord`.

Example with `n = 11`: `0 → 1`, `0.5 → 6`, `1 → 11`.
"""
function _normalized_index(coord::Number, n::Int)
    c = _unit_or_centre(coord)
    return clamp(round(Int, c * (n - 1) + 1), 1, n)
end

"""
Index `1:n` of the element at normalised position `position` in a flattened
(column-major) array of `n` elements.

Example for a `3 × 4` image (`n = 12`): `position = 0` is pixel `(1, 1)`,
`1/11` pixel `(2, 1)`, `3/11` pixel `(1, 2)` (the next column), `1` pixel
`(3, 4)`.
"""
function _normalized_flat_index(position::Number, n::Int)
    p = _unit_or_centre(position)
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

"""
Half-width in pixels from a size parameter: `round(abs(size))`, at least `1`
(a 3-pixel window). Non-finite sizes give `1`; huge ones are capped at
`10^6` before rounding (the window is clipped to the image anyway).
"""
function _half_extent(size_param::Number)
    s = abs(Float64(size_param))
    isfinite(s) || return 1
    return max(round(Int, min(s, 1.0e6)), 1)
end

end
