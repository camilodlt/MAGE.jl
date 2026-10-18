# Call tree: public methods → _foreground_apply! → pooled matrix kernel
# → solver → nearest/bilinear lift into the caller's full-size output.
# Kernels are ordinary functions: evaluation never creates factories or methods.

"""Aspect-preserving grid: `(224, 100, 32)` gives `(32, 14)` without zero axes."""
function _resolution_size(height, width, limit)
    scale = min(1.0, limit / max(height, width))
    return max(1, round(Int, height * scale)), max(1, round(Int, width * scale))
end

"""Read a wrapped pixel or a raw mask bit; for example, `true` gives `1.0`."""
_resolution_value(pixel) = Float64(getfield(pixel, 1))
_resolution_value(pixel::Bool) = Float64(pixel)

"""Box pool pixels; `[0, 1]` averages to `0.5`, while conflicting trimaps become unknown.
Rough masks use component-guarded sparse pooling; watershed masks use any pooling.
"""
function _resolution_pool!(destination, source, policy::Val)
    height, width = size(source)
    output_height, output_width = size(destination)
    @inbounds for column in 1:output_width, row in 1:output_height
        first_row = (row - 1) * height ÷ output_height + 1
        last_row = row * height ÷ output_height
        first_column = (column - 1) * width ÷ output_width + 1
        last_column = column * width ÷ output_width
        total = 0.0
        foreground = false
        background = false
        count = (last_row - first_row + 1) * (last_column - first_column + 1)
        for source_column in first_column:last_column, source_row in first_row:last_row
            value = _resolution_value(source[source_row, source_column])
            total += value
            foreground |= value >= 0.9
            background |= value <= 0.1
        end
        value = _resolution_pool_value(policy, total, count, foreground, background)
        destination[row, column] = eltype(destination)(value)
    end
    return destination
end

_resolution_pool_value(::Val{:mean}, total, count, foreground, background) = total / count
_resolution_pool_value(::Val{:any}, total, count, foreground, background) = total > 0
_resolution_pool_value(::Val{:majority}, total, count, foreground, background) = total >= count / 2
_resolution_pool_value(::Val{:trimap}, total, count, foreground, background) =
    foreground && background ? 0.5 : foreground ? 1.0 : background ? 0.0 : 0.5

_resolution_pool!(destination, source, ::Val{:sparse}) =
    _resolution_sparse_mask!(destination, source)
_resolution_pool!(destination, source, ::Val{:sparse_quarter}) =
    _resolution_sparse_mask!(destination, source, 1 / 4)

"""Interpolate a coarse soft pixel; a constant pixel grid stays constant."""
@inline function _resolution_bilinear(source, row, column, height, width)
    source_height, source_width = size(source)
    y = height == 1 ? 1.0 : 1 + (row - 1) * (source_height - 1) / (height - 1)
    x = width == 1 ? 1.0 : 1 + (column - 1) * (source_width - 1) / (width - 1)
    first_row = floor(Int, y)
    first_column = floor(Int, x)
    row_fraction = y - first_row
    column_fraction = x - first_column
    last_row = min(first_row + 1, source_height)
    last_column = min(first_column + 1, source_width)
    top = (1 - column_fraction) * _resolution_value(source[first_row, first_column]) +
          column_fraction * _resolution_value(source[first_row, last_column])
    bottom = (1 - column_fraction) * _resolution_value(source[last_row, first_column]) +
             column_fraction * _resolution_value(source[last_row, last_column])
    return clamp((1 - row_fraction) * top + row_fraction * bottom, 0.0, 1.0)
end

"""Lift masks by nearest neighbor and soft pixels bilinearly; constants stay constant."""
function _resolution_lift!(destination, source, interpolation::Val)
    height, width = size(destination)
    @inbounds for column in 1:width, row in 1:height
        _resolution_write_pixel!(destination, source, row, column, height, width, interpolation)
    end
    return destination
end

@inline function _resolution_write_pixel!(destination, source, row, column, height, width, ::Val{true})
    @inbounds destination[row, column] = eltype(destination)(
        _resolution_bilinear(source, row, column, height, width),
    )
end
@inline function _resolution_write_pixel!(destination, source, row, column, height, width, ::Val{false})
    @inbounds destination[row, column] = source[
        cld(row * size(source, 1), height), cld(column * size(source, 2), width),
    ]
end

"""Preserve explicit trimap constraints when output overlaps it; otherwise borrow it.
For example, `out === trimap` requires a scratch copy before interpolation.
"""
function _resolution_constraints(destination, trimap, ::Val{:trimap})
    Base.mightalias(destination, trimap) || return trimap
    saved = scratch(:foreground_resolution_constraints, eltype(trimap), size(trimap)...)
    return copyto!(saved, trimap)
end

_resolution_constraints(destination, auxiliary, ::Val) = nothing

"""Restore explicit known classes; for example, trimap `0` forces output `0`."""
function _resolution_restore!(destination, constraints::AbstractMatrix)
    @inbounds for index in eachindex(destination)
        value = _resolution_value(constraints[index])
        value <= 0.1 && (destination[index] = eltype(destination)(0))
        value >= 0.9 && (destination[index] = eltype(destination)(1))
    end
    return destination
end
_resolution_restore!(destination, ::Nothing) = destination

"""Pool one auxiliary matrix, or keep `nothing` for automatic seeds.
For example, a rough `224×100` mask pools into `32×14` scratch pixels.
"""
function _resolution_auxiliary(auxiliary::AbstractMatrix, height, width, policy::Val)
    pooled = scratch(:foreground_resolution_input_2, eltype(auxiliary), height, width)
    return _resolution_pool!(pooled, auxiliary, policy)
end
_resolution_auxiliary(::Nothing, height, width, ::Val) = nothing

"""Pool rough masks with component guards; default occupancy threshold is 1/8.
For example, 7 foreground pixels in a 7×7 box survive; an empty box stays background.
Foreground/background counts are kept separately. Majority foreground stays;
a sparse addition requires unambiguous component provenance. Additions cannot
bridge different components: majority wins conflicts, then higher occupancy,
then the earlier scan index. Ambiguous sparse boxes remain background.
"""
function _resolution_sparse_mask!(destination, source, threshold::Real = 1 / 8)
    height, width = size(source)
    output_height, output_width = size(destination)
    mask = scratch(:foreground_hint_mask, Bool, height, width)
    @inbounds for index in eachindex(source)
        mask[index] = _resolution_value(source[index]) >= 0.5
    end
    components = scratch(:foreground_hint_components, Int, height, width)
    label_components!(components, mask)
    owners = scratch(:foreground_hint_owners, Int, output_height, output_width)
    foreground = scratch(:foreground_hint_fg_evidence, Int, output_height, output_width)
    background = scratch(:foreground_hint_bg_evidence, Int, output_height, output_width)
    _resolution_mask_evidence!(destination, components, owners, foreground, background, threshold)
    return _resolution_guard_components!(destination, owners, foreground, background, threshold)
end

"""Collect box occupancy and unique owners; two components in one box have owner 0."""
function _resolution_mask_evidence!(destination, components, owners, foreground, background, threshold)
    height, width = size(components)
    output_height, output_width = size(destination)
    @inbounds for column in 1:output_width, row in 1:output_height
        first_row = (row - 1) * height ÷ output_height + 1
        last_row = row * height ÷ output_height
        first_column = (column - 1) * width ÷ output_width + 1
        last_column = column * width ÷ output_width
        owner = 0
        conflict = false
        foreground_count = 0
        background_count = 0
        for source_column in first_column:last_column, source_row in first_row:last_row
            component = components[source_row, source_column]
            if component > 0
                foreground_count += 1
                conflict |= owner != 0 && owner != component
                owner = component
            else
                background_count += 1
            end
        end
        foreground[row, column] = foreground_count
        background[row, column] = background_count
        owners[row, column] = conflict ? 0 : owner
        destination[row, column] = eltype(destination)(
            foreground_count > 0 && (foreground_count >= (foreground_count + background_count) / 2 ||
                (!conflict && foreground_count >= threshold * (foreground_count + background_count))),
        )
    end
    return destination
end

"""Reject sparse bridges using fixed evidence; a majority neighbor wins a conflict."""
function _resolution_guard_components!(destination, owners, foreground, background, threshold)
    output_height, output_width = size(destination)
    # label_components! uses its default diamond (four-neighbor) connectivity.
    # Compare the immutable evidence, so this decision does not depend on updates.
    @inbounds for column in 1:output_width, row in 1:output_height
        owner = owners[row, column]
        owner > 0 || continue
        foreground_count = foreground[row, column]
        count = foreground_count + background[row, column]
        foreground_count >= count / 2 && continue
        index = row + (column - 1) * output_height
        for (dr, dc) in ((-1, 0), (1, 0), (0, -1), (0, 1))
            neighbor_row, neighbor_column = row + dr, column + dc
            1 <= neighbor_row <= output_height && 1 <= neighbor_column <= output_width || continue
            neighbor = owners[neighbor_row, neighbor_column]
            neighbor != owner || continue
            neighbor_foreground = foreground[neighbor_row, neighbor_column]
            neighbor_count = neighbor_foreground + background[neighbor_row, neighbor_column]
            neighbor_foreground > 0 || continue
            majority = neighbor_foreground >= neighbor_count / 2
            (majority || (neighbor > 0 && neighbor_foreground >= threshold * neighbor_count)) || continue
            neighbor_index = neighbor_row + (neighbor_column - 1) * output_height
            if majority || neighbor_foreground * count > foreground_count * neighbor_count ||
                    (neighbor_foreground * count == foreground_count * neighbor_count && neighbor_index < index)
                destination[row, column] = eltype(destination)(false)
            end
        end
    end
    return destination
end

"""Scale a nonzero uncertainty band to at least one pixel; zero remains zero."""
function _resolution_parameters(
        parameters, ::Union{Val{:majority},Val{:sparse},Val{:sparse_quarter}}, source_size, working_size,
    )
    band = _seed_band(only(parameters))
    scaled_band = band == 0 ? 0.0 :
                  Float64(max(1, round(Int, band * maximum(working_size) / maximum(source_size))))
    return (scaled_band,)
end
_resolution_parameters(parameters, ::Val, source_size, working_size) = parameters

"""Call a matrix kernel on the input or pooled grid, then write full-size output.
For example, `224×100` uses a `32×14` kernel with no factory calls or runtime eval.
Quantize on the working grid before interpolation to preserve pixel precision.
"""
function _foreground_apply!(
        kernel::F, destination, image, auxiliary, parameters, pooling::Val, interpolation::Val,
    ) where {F}
    maximum(size(image)) <= 32 &&
        return kernel(destination, image, auxiliary, parameters...)
    height, width = size(image)
    height * width <= 1_000_000 || error("foreground input exceeded its work budget")
    working_size = _resolution_size(height, width, 32)
    pooled_image = scratch(:foreground_resolution_input_1, eltype(image), working_size...)
    _resolution_pool!(pooled_image, image, Val(:mean))
    pooled_auxiliary = _resolution_auxiliary(auxiliary, working_size..., pooling)
    working_parameters = _resolution_parameters(parameters, pooling, size(image), working_size)
    pooled_output = scratch(:foreground_resolution_output, eltype(destination), working_size...)
    kernel(pooled_output, pooled_image, pooled_auxiliary, working_parameters...)
    constraints = _resolution_constraints(destination, auxiliary, pooling)
    _resolution_lift!(destination, pooled_output, interpolation)
    return _resolution_restore!(destination, constraints)
end
