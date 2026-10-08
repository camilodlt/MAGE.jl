"""
Haar-like rectangular image-to-float features.

# Bundles

- [`bundle_number_haarFromImg`](@ref)

The exhaustive, always-current list of operators in each bundle is on the
[Bundle Catalogue](@ref) page.
"""
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
"""
    bundle_number_haarFromImg

Haar-like contrasts between neighbouring regions of an image: `haar_lr`,
`haar_tb`, `haar_diag_main`, `haar_diag_anti`, `haar_center_surround`,
`haar_three_h`, `haar_three_v`.

The same family of features used by cascade detectors, here available as
evolvable operators. Every operator takes `(img, position, size)`:

- `position ∈ [0, 1]` picks the window's centre pixel by walking the pixels in
  column-major order (down the first column, then down the second, …): `0` is
  the top-left pixel, `1` the bottom-right one. One number therefore encodes
  both row and column.
- `size` is the window's half-width in pixels (`round(abs(size))`, at least
  1): the window is `(2·size + 1)` pixels square, clipped at the border.

The value is the mean of the "+" rectangles minus the mean of the "−"
rectangles (see the pictures in the docs, drawn from the same weight masks).
Non-finite inputs fall back to the centre and to `size = 1`.
"""
bundle_number_haarFromImg = FunctionBundle(fallback)

"Window `(row_lo, row_hi, col_lo, col_hi)` of a Haar feature: centre from the flattened `position`, half-width from `region_size`, clipped."
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

"""
Side of the `+` centre of `haar_center_surround` in a window side `n`: about a
third, with the parity of `n` so that it sits exactly in the middle (`3 → 1`,
`5 → 3`, `7 → 3`), unless that would leave no surround (`2 → 1`).
"""
function _centre_side(n::Int)
    c = max(cld(n, 3), 1)
    return isodd(n - c) && c + 1 < n ? c + 1 : c
end

"""
`+1` / `−1` / `0` weight mask of a Haar feature over an `h × w` window: the
feature value is mean(window where `+1`) − mean(window where `−1`). Pixels
with weight `0` (e.g. the middle column of an odd-width `haar_lr`) are
ignored. This is the mask the docs draw.
"""
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
        center_h = _centre_side(h)
        center_w = _centre_side(w)
        row_start = clamp(fld(h - center_h, 2) + 1, 1, h)
        row_end = clamp(row_start + center_h - 1, 1, h)
        col_start = clamp(fld(w - center_w, 2) + 1, 1, w)
        col_end = clamp(col_start + center_w - 1, 1, w)
        weights[row_start:row_end, col_start:col_end] .= 1.0
    elseif kind === :haar_three_h
        third = fld(w, 3)
        third == 0 && return weights
        # Three equal bands centred in the window; the `w - 3·third` leftover
        # columns are split between both sides and ignored.
        o = fld(w - 3 * third, 2)
        weights[:, o + 1:o + third] .= 1.0
        weights[:, o + third + 1:o + 2 * third] .= -1.0
        weights[:, o + 2 * third + 1:o + 3 * third] .= 1.0
    elseif kind === :haar_three_v
        third = fld(h, 3)
        third == 0 && return weights
        o = fld(h - 3 * third, 2)    # centred, as for `haar_three_h`
        weights[o + 1:o + third, :] .= 1.0
        weights[o + third + 1:o + 2 * third, :] .= -1.0
        weights[o + 2 * third + 1:o + 3 * third, :] .= 1.0
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

"""
The image in grey with the feature's window tinted: red where the weight mask
is `+1`, blue where it is `−1` (used by the docs pictures).
"""
function _haar_overlay_canvas(from::SImageND, kind::Symbol, position::Number, region_size::Number)
    img = _normalize01(_image_numeric(from))
    canvas = RGB.(img, img, img)
    row_lo, row_hi, col_lo, col_hi = _haar_bounds(from, position, region_size)
    weights = _haar_overlay_weights(from, kind, position, region_size)

    for local_r in axes(weights, 1), local_c in axes(weights, 2)
        global_r = row_lo + local_r - 1
        global_c = col_lo + local_c - 1
        # Tint rather than paint, so the pixel's brightness stays visible.
        v = img[global_r, global_c]
        if weights[local_r, local_c] > 0
            canvas[global_r, global_c] = RGB(0.5 * v + 0.5, 0.5 * v + 0.05, 0.5 * v + 0.05)
        elseif weights[local_r, local_c] < 0
            canvas[global_r, global_c] = RGB(0.5 * v + 0.05, 0.5 * v + 0.15, 0.5 * v + 0.5)
        end
    end

    return canvas
end

"Feature value: mean of the `+1` pixels of the window minus mean of the `−1` pixels."
function _haar_feature_value(from::SImageND, kind::Symbol, position::Number, region_size::Number)
    row_lo, row_hi, col_lo, col_hi = _haar_bounds(from, position, region_size)
    # Only the window is converted to Float64, not the whole image.
    patch = [Float64(from.img[r, c]) for r in row_lo:row_hi, c in col_lo:col_hi]
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

append_method!(
    bundle_number_haarFromImg,
    haar_lr;
    description = "Computes left-versus-right Haar contrast in a local image region.",
)
append_method!(
    bundle_number_haarFromImg,
    haar_tb;
    description = "Computes top-versus-bottom Haar contrast in a local image region.",
)
append_method!(
    bundle_number_haarFromImg,
    haar_diag_main;
    description = "Computes diagonal Haar contrast favoring main-diagonal quadrants.",
)
append_method!(
    bundle_number_haarFromImg,
    haar_diag_anti;
    description = "Computes diagonal Haar contrast favoring anti-diagonal quadrants.",
)
append_method!(
    bundle_number_haarFromImg,
    haar_center_surround;
    description = "Computes center-versus-surround Haar contrast in a local region.",
)
append_method!(
    bundle_number_haarFromImg,
    haar_three_h;
    description = "Computes horizontal three-band Haar contrast in a local region.",
)
append_method!(
    bundle_number_haarFromImg,
    haar_three_v;
    description = "Computes vertical three-band Haar contrast in a local region.",
)

end
