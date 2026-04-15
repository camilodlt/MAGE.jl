using Test
using Statistics

function haar_test_image(::Type{IntensityPixel{T}}) where {T}
    img = Float64[
        1  2  3  4  5;
        6  7  8  9 10;
       11 12 13 14 15;
       16 17 18 19 20;
       21 22 23 24 25;
    ]
    img ./= maximum(img)
    return SImageND(IntensityPixel{T}.(img))
end

function haar_test_image(::Type{BinaryPixel{Bool}})
    img = Bool[
        1 1 0 0 0;
        1 1 0 0 0;
        1 1 1 0 0;
        1 1 1 1 0;
        1 1 1 1 1;
    ]
    return SImageND(BinaryPixel{Bool}.(img))
end

function haar_test_image(::Type{SegmentPixel{Int}})
    img = Int[
        1 1 2 2 2;
        1 1 2 2 2;
        3 3 3 2 2;
        3 3 3 4 4;
        3 3 4 4 4;
    ]
    return SImageND(SegmentPixel{Int}.(img))
end

function _manual_flat_index(position::Number, n::Int)
    p = clamp(Float64(position), 0.0, 1.0)
    return clamp(round(Int, p * (n - 1) + 1), 1, n)
end

function _manual_bounds(img::AbstractMatrix, position::Number, size_param::Number)
    idx = _manual_flat_index(position, length(img))
    cart = CartesianIndices(img)[idx]
    half = max(round(Int, abs(Float64(size_param))), 1)
    row_lo = max(cart[1] - half, 1)
    row_hi = min(cart[1] + half, size(img, 1))
    col_lo = max(cart[2] - half, 1)
    col_hi = min(cart[2] + half, size(img, 2))
    return row_lo, row_hi, col_lo, col_hi
end

function _manual_weight_matrix(kind::Symbol, h::Int, w::Int)
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
        error("unknown test haar kind")
    end
    return weights
end

function _manual_haar_expected(img::AbstractMatrix, kind::Symbol, position::Number, size_param::Number)
    row_lo, row_hi, col_lo, col_hi = _manual_bounds(img, position, size_param)
    patch = @view img[row_lo:row_hi, col_lo:col_hi]
    weights = _manual_weight_matrix(kind, size(patch, 1), size(patch, 2))
    pos = patch[weights .> 0]
    neg = patch[weights .< 0]
    pos_mean = isempty(pos) ? 0.0 : mean(Float64.(pos))
    neg_mean = isempty(neg) ? 0.0 : mean(Float64.(neg))
    return pos_mean - neg_mean
end

@testset "Haar From Image" begin
    intensity_img = haar_test_image(IntensityPixel{N0f8})
    binary_img = haar_test_image(BinaryPixel{Bool})
    segment_img = haar_test_image(SegmentPixel{Int})

    kinds = Dict(
        :haar_lr => UTCGP.bundle_number_haarFromImg[:haar_lr].fn,
        :haar_tb => UTCGP.bundle_number_haarFromImg[:haar_tb].fn,
        :haar_diag_main => UTCGP.bundle_number_haarFromImg[:haar_diag_main].fn,
        :haar_diag_anti => UTCGP.bundle_number_haarFromImg[:haar_diag_anti].fn,
        :haar_center_surround => UTCGP.bundle_number_haarFromImg[:haar_center_surround].fn,
        :haar_three_h => UTCGP.bundle_number_haarFromImg[:haar_three_h].fn,
        :haar_three_v => UTCGP.bundle_number_haarFromImg[:haar_three_v].fn,
    )

    @test vec([1 0 0; 1 0 1; 1 1 1]) == [1, 1, 1, 0, 0, 1, 0, 1, 1]

    @testset "Return Type And Exact Feature Values" begin
        intensity_data = Float64.(reinterpret(intensity_img.img))
        binary_data = Float64.(reinterpret(binary_img.img))
        for (kind, fn) in kinds
            expected_int = _manual_haar_expected(intensity_data, kind, 0.5, 1)
            expected_bin = _manual_haar_expected(binary_data, kind, 0.5, 1)
            @test fn(intensity_img, 0.5, 1) ≈ expected_int
            @test fn(binary_img, 0.5, 1) ≈ expected_bin
            @test fn(intensity_img, 0.5, 1) isa Float64
            @test fn(binary_img, 0.5, 1) isa Float64
        end
    end

    @testset "Clamped Position And Clipped Bounds" begin
        intensity_data = Float64.(reinterpret(intensity_img.img))
        for (kind, fn) in kinds
            @test fn(intensity_img, -1.0, 2) ≈ fn(intensity_img, 0.0, 2)
            @test fn(intensity_img, 2.0, 2) ≈ fn(intensity_img, 1.0, 2)
            @test fn(intensity_img, 0.0, 2) ≈ _manual_haar_expected(intensity_data, kind, 0.0, 2)
            @test fn(intensity_img, 1.0, 2) ≈ _manual_haar_expected(intensity_data, kind, 1.0, 2)
        end
    end

    @testset "Segment Images Are Not Accepted" begin
        for (_, fn) in kinds
            @test_throws MethodError fn(segment_img, 0.5, 1)
        end
    end
end
