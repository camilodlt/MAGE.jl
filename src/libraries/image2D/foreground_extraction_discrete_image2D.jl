"""
Deterministic discrete foreground extraction for intensity images.

# Bundles

- [`bundle_image2DBinary_foreground_extraction_factory`](@ref)

The exhaustive operator list is on the [Bundle Catalogue](@ref) page.
"""
module image2D_foreground_extraction_discrete

using ..image2D_saliency_fixation: _spectral_residual_grayscale
using ImageFiltering: Kernel, imfilter
using ..UTCGP: FunctionBundle, append_method!
using ..UTCGP:
    BinaryPixel,
    IntensityPixel,
    SImageND,
    SizedImage,
    SizedImage2D,
    _get_image_pixel_type,
    _get_image_tuple_size,
    _get_image_type,
    _validate_factory_type

fallback(args...) = return nothing

"""
    bundle_image2DBinary_foreground_extraction_factory

Seeded, deterministic foreground segmentation operators whose output is a
same-size binary image. Factories are specialized with the concrete binary
output type before insertion into a MAGE library.

The operators are Boykov-Jolly graph cuts and iterative GrabCut. Both can
derive seeds from spectral-residual saliency internally or consume a same-size
saliency map from another MAGE image chromosome.
"""
bundle_image2DBinary_foreground_extraction_factory = FunctionBundle(fallback)

function _normalize_saliency(values::AbstractMatrix{<:Real})
    isempty(values) && return zeros(Float64, size(values))
    lo, hi = extrema(values)
    (!isfinite(lo) || !isfinite(hi) || hi <= lo) && return zeros(Float64, size(values))
    return (Float64.(values) .- lo) ./ (hi - lo)
end

function _graphcut_attention(saliency::AbstractMatrix{<:Real})
    normalized = _normalize_saliency(saliency)
    maximum(normalized) == 0.0 && return normalized
    sigma = clamp(minimum(size(normalized)) / 32, 1.0, 12.0)
    smoothed = imfilter(normalized, Kernel.gaussian(sigma), "replicate")
    return _normalize_saliency(smoothed)
end

function _ranked_indices(values::AbstractMatrix{<:Real}, interior_only::Bool)
    h, w = size(values)
    ranked = Tuple{Float64,Int,Int}[]
    sizehint!(ranked, h * w)
    @inbounds for row in 1:h, col in 1:w
        if !interior_only || (1 < row < h && 1 < col < w)
            push!(ranked, (Float64(values[row, col]), row, col))
        end
    end
    isempty(ranked) && interior_only && return _ranked_indices(values, false)
    return ranked
end

function _border_connected_background(
        saliency::AbstractMatrix{<:Real},
        low_saliency_cutoff::Float64,
    )
    h, w = size(saliency)
    background = falses(h, w)
    queue = Vector{CartesianIndex{2}}(undef, h * w)
    queue_end = 0

    @inbounds for col in 1:w
        if !background[1, col]
            background[1, col] = true
            queue_end += 1
            queue[queue_end] = CartesianIndex(1, col)
        end
        if h > 1 && !background[h, col]
            background[h, col] = true
            queue_end += 1
            queue[queue_end] = CartesianIndex(h, col)
        end
    end
    if h > 2
        @inbounds for row in 2:(h - 1)
            if !background[row, 1]
                background[row, 1] = true
                queue_end += 1
                queue[queue_end] = CartesianIndex(row, 1)
            end
            if w > 1 && !background[row, w]
                background[row, w] = true
                queue_end += 1
                queue[queue_end] = CartesianIndex(row, w)
            end
        end
    end

    queue_start = 1
    while queue_start <= queue_end
        current = queue[queue_start]
        queue_start += 1
        row, col = Tuple(current)
        @inbounds for (neighbor_row, neighbor_col) in (
                (row - 1, col), (row + 1, col),
                (row, col - 1), (row, col + 1),
            )
            if 1 <= neighbor_row <= h && 1 <= neighbor_col <= w &&
                    !background[neighbor_row, neighbor_col] &&
                    saliency[neighbor_row, neighbor_col] <= low_saliency_cutoff
                background[neighbor_row, neighbor_col] = true
                queue_end += 1
                queue[queue_end] = CartesianIndex(neighbor_row, neighbor_col)
            end
        end
    end
    return background
end

function _automatic_graphcut_seeds(
        saliency::AbstractMatrix{<:Real},
        foreground_quantile::Float64,
    )
    normalized = _graphcut_attention(saliency)
    h, w = size(normalized)
    foreground = falses(h, w)
    background = falses(h, w)
    maximum(normalized) == 0.0 && return foreground, background, normalized

    ranked_foreground = _ranked_indices(normalized, true)
    sort!(ranked_foreground; by = item -> (-item[1], item[2], item[3]))
    positive_count = count(item -> item[1] > 0.0, ranked_foreground)
    target_count = max(
        1,
        ceil(Int, (1.0 - foreground_quantile) * length(ranked_foreground)),
    )
    target_count = min(target_count, max(positive_count, 1))
    @inbounds for index in 1:target_count
        _, row, col = ranked_foreground[index]
        foreground[row, col] = true
    end

    ranked_background = _ranked_indices(normalized, false)
    sort!(ranked_background; by = item -> (item[1], item[2], item[3]))
    background_count = max(1, ceil(Int, 0.2 * length(ranked_background)))
    low_saliency_cutoff = ranked_background[background_count][1]
    background = _border_connected_background(normalized, low_saliency_cutoff)
    background[foreground] .= false
    return foreground, background, normalized
end

@inline function _histogram_bin(value::Float64, bin_count::Int)
    return clamp(floor(Int, clamp(value, 0.0, 1.0) * bin_count) + 1, 1, bin_count)
end

function _appearance_costs(
        values::AbstractMatrix{<:Real},
        foreground::BitMatrix,
        background::BitMatrix,
    )
    bin_count = 32
    foreground_counts = fill(0.5, bin_count)
    background_counts = fill(0.5, bin_count)
    @inbounds for index in eachindex(values)
        bin = _histogram_bin(Float64(values[index]), bin_count)
        foreground[index] && (foreground_counts[bin] += 1.0)
        background[index] && (background_counts[bin] += 1.0)
    end
    foreground_counts ./= sum(foreground_counts)
    background_counts ./= sum(background_counts)

    foreground_cost = Matrix{Float64}(undef, size(values))
    background_cost = Matrix{Float64}(undef, size(values))
    @inbounds for index in eachindex(values)
        bin = _histogram_bin(Float64(values[index]), bin_count)
        foreground_cost[index] = -log(foreground_counts[bin])
        background_cost[index] = -log(background_counts[bin])
    end
    return foreground_cost, background_cost
end

const _GRABCUT_COMPONENT_COUNT = 5
const _GRABCUT_VARIANCE_FLOOR = 1.0e-4
const _GRABCUT_EM_STEPS = 4

function _selected_values(
        values::AbstractMatrix{<:Real},
        selected::AbstractMatrix{Bool},
    )
    samples = Float64[]
    sizehint!(samples, count(selected))
    @inbounds for index in eachindex(values, selected)
        selected[index] && push!(samples, Float64(values[index]))
    end
    return samples
end

function _fit_grabcut_gmm(samples::Vector{Float64})
    isempty(samples) && return ([1.0], [0.5], [1.0])
    sorted_samples = sort(copy(samples))
    sample_count = length(sorted_samples)
    component_count = min(_GRABCUT_COMPONENT_COUNT, sample_count)
    means = Vector{Float64}(undef, component_count)
    @inbounds for component in 1:component_count
        position = clamp(
            round(Int, (component - 0.5) * sample_count / component_count),
            1,
            sample_count,
        )
        means[component] = sorted_samples[position]
    end

    global_mean = sum(sorted_samples) / sample_count
    global_variance = max(
        sum((sample - global_mean)^2 for sample in sorted_samples) / sample_count,
        _GRABCUT_VARIANCE_FLOOR,
    )
    variances = fill(global_variance, component_count)
    weights = fill(1.0 / component_count, component_count)
    log_probabilities = zeros(Float64, component_count)
    component_mass = similar(log_probabilities)
    component_sum = similar(log_probabilities)
    component_square_sum = similar(log_probabilities)
    log_coefficients = similar(log_probabilities)
    inverse_twice_variances = similar(log_probabilities)

    for _ in 1:_GRABCUT_EM_STEPS
        fill!(component_mass, 0.0)
        fill!(component_sum, 0.0)
        fill!(component_square_sum, 0.0)
        @inbounds for component in 1:component_count
            variance = variances[component]
            log_coefficients[component] =
                log(max(weights[component], eps(Float64))) -
                0.5 * log(2pi * variance)
            inverse_twice_variances[component] = 0.5 / variance
        end
        @inbounds for sample in sorted_samples
            maximum_log_probability = -Inf
            for component in 1:component_count
                log_probability =
                    log_coefficients[component] -
                    (sample - means[component])^2 *
                    inverse_twice_variances[component]
                log_probabilities[component] = log_probability
                maximum_log_probability = max(
                    maximum_log_probability,
                    log_probability,
                )
            end
            normalization = 0.0
            for component in 1:component_count
                normalization += exp(
                    log_probabilities[component] - maximum_log_probability,
                )
            end
            for component in 1:component_count
                responsibility = exp(
                    log_probabilities[component] - maximum_log_probability,
                ) / normalization
                component_mass[component] += responsibility
                component_sum[component] += responsibility * sample
                component_square_sum[component] += responsibility * sample^2
            end
        end

        @inbounds for component in 1:component_count
            mass = component_mass[component]
            if mass <= eps(Float64)
                position = clamp(
                    round(Int, (component - 0.5) * sample_count / component_count),
                    1,
                    sample_count,
                )
                means[component] = sorted_samples[position]
                variances[component] = global_variance
                weights[component] = eps(Float64)
            else
                means[component] = component_sum[component] / mass
                variances[component] = max(
                    component_square_sum[component] / mass - means[component]^2,
                    _GRABCUT_VARIANCE_FLOOR,
                )
                weights[component] = mass / sample_count
            end
        end
        weights ./= sum(weights)
    end
    return weights, means, variances
end

function _prepare_grabcut_gmm(
        weights::Vector{Float64},
        means::Vector{Float64},
        variances::Vector{Float64},
    )
    log_coefficients = similar(weights)
    inverse_twice_variances = similar(weights)
    @inbounds for component in eachindex(weights, means, variances)
        variance = variances[component]
        log_coefficients[component] =
            log(max(weights[component], eps(Float64))) -
            0.5 * log(2pi * variance)
        inverse_twice_variances[component] = 0.5 / variance
    end
    return log_coefficients, means, inverse_twice_variances
end

@inline function _prepared_gmm_cost(
        value::Float64,
        log_coefficients::Vector{Float64},
        means::Vector{Float64},
        inverse_twice_variances::Vector{Float64},
    )
    maximum_log_probability = -Inf
    @inbounds for component in eachindex(
            log_coefficients,
            means,
            inverse_twice_variances,
        )
        log_probability =
            log_coefficients[component] -
            (value - means[component])^2 *
            inverse_twice_variances[component]
        maximum_log_probability = max(maximum_log_probability, log_probability)
    end
    probability_sum = 0.0
    @inbounds for component in eachindex(
            log_coefficients,
            means,
            inverse_twice_variances,
        )
        log_probability =
            log_coefficients[component] -
            (value - means[component])^2 *
            inverse_twice_variances[component]
        probability_sum += exp(log_probability - maximum_log_probability)
    end
    return -(maximum_log_probability + log(probability_sum))
end

function _gmm_cost(
        value::Float64,
        weights::Vector{Float64},
        means::Vector{Float64},
        variances::Vector{Float64},
    )
    prepared_model = _prepare_grabcut_gmm(weights, means, variances)
    return _prepared_gmm_cost(value, prepared_model...)
end

function _grabcut_appearance_costs(
        values::AbstractMatrix{<:Real},
        foreground_labels::BitMatrix,
    )
    foreground_samples = _selected_values(values, foreground_labels)
    background_samples = _selected_values(values, .!foreground_labels)
    foreground_model = _prepare_grabcut_gmm(
        _fit_grabcut_gmm(foreground_samples)...,
    )
    background_model = _prepare_grabcut_gmm(
        _fit_grabcut_gmm(background_samples)...,
    )
    foreground_cost = Matrix{Float64}(undef, size(values))
    background_cost = Matrix{Float64}(undef, size(values))
    @inbounds for index in eachindex(values)
        value = Float64(values[index])
        foreground_cost[index] =
            _prepared_gmm_cost(value, foreground_model...)
        background_cost[index] =
            _prepared_gmm_cost(value, background_model...)
    end
    return foreground_cost, background_cost
end

mutable struct _FlowNetwork
    head::Vector{Int}
    destination::Vector{Int}
    next_edge::Vector{Int}
    capacity::Vector{Float64}
end

function _FlowNetwork(vertex_count::Int, edge_capacity::Int)
    network = _FlowNetwork(fill(0, vertex_count), Int[], Int[], Float64[])
    sizehint!(network.destination, edge_capacity)
    sizehint!(network.next_edge, edge_capacity)
    sizehint!(network.capacity, edge_capacity)
    return network
end

function _add_directed_edge!(
        network::_FlowNetwork,
        source::Int,
        sink::Int,
        capacity::Float64,
    )
    push!(network.destination, sink)
    push!(network.next_edge, network.head[source])
    push!(network.capacity, capacity)
    network.head[source] = length(network.capacity)

    push!(network.destination, source)
    push!(network.next_edge, network.head[sink])
    push!(network.capacity, 0.0)
    network.head[sink] = length(network.capacity)
    return nothing
end

function _add_bidirectional_edge!(
        network::_FlowNetwork,
        first::Int,
        second::Int,
        capacity::Float64,
    )
    push!(network.destination, second)
    push!(network.next_edge, network.head[first])
    push!(network.capacity, capacity)
    network.head[first] = length(network.capacity)

    push!(network.destination, first)
    push!(network.next_edge, network.head[second])
    push!(network.capacity, capacity)
    network.head[second] = length(network.capacity)
    return nothing
end

@inline _reverse_edge(edge::Int) = isodd(edge) ? edge + 1 : edge - 1

function _global_relabel!(
        network::_FlowNetwork,
        source::Int,
        sink::Int,
        height::Vector{Int},
        queue::Vector{Int},
    )
    vertex_count = length(network.head)
    unreachable = vertex_count + 1
    fill!(height, unreachable)
    height[sink] = 0
    queue_start = 1
    queue_end = 1
    queue[1] = sink
    while queue_start <= queue_end
        vertex = queue[queue_start]
        queue_start += 1
        edge = network.head[vertex]
        while edge != 0
            predecessor = network.destination[edge]
            reverse = _reverse_edge(edge)
            if predecessor != source && height[predecessor] == unreachable &&
                    network.capacity[reverse] > 1.0e-12
                height[predecessor] = height[vertex] + 1
                queue_end += 1
                queue[queue_end] = predecessor
            end
            edge = network.next_edge[edge]
        end
    end
    height[source] = vertex_count
    return nothing
end

function _recount_heights!(height_count::Vector{Int}, height::Vector{Int})
    fill!(height_count, 0)
    @inbounds for value in height
        height_count[value + 1] += 1
    end
    return nothing
end

function _maximum_flow!(network::_FlowNetwork, source::Int, sink::Int)
    vertex_count = length(network.head)
    height = zeros(Int, vertex_count)
    excess = zeros(Float64, vertex_count)
    current_edge = copy(network.head)
    active = falses(vertex_count)
    height_count = zeros(Int, 2vertex_count + 3)
    queue = Vector{Int}(undef, vertex_count)
    relabel_queue = similar(queue)
    queue_head = 1
    queue_tail = 0
    queue_count = 0

    height[source] = vertex_count
    edge = network.head[source]
    while edge != 0
        flow = network.capacity[edge]
        if flow > 1.0e-12
            destination = network.destination[edge]
            network.capacity[edge] = 0.0
            network.capacity[_reverse_edge(edge)] += flow
            excess[destination] += flow
            if destination != sink && !active[destination]
                active[destination] = true
                queue_tail = queue_tail == vertex_count ? 1 : queue_tail + 1
                queue[queue_tail] = destination
                queue_count += 1
            end
        end
        edge = network.next_edge[edge]
    end

    _global_relabel!(network, source, sink, height, relabel_queue)
    _recount_heights!(height_count, height)
    copyto!(current_edge, network.head)
    discharge_count = 0
    while queue_count > 0
        vertex = queue[queue_head]
        queue_head = queue_head == vertex_count ? 1 : queue_head + 1
        queue_count -= 1
        active[vertex] = false

        while excess[vertex] > 1.0e-12
            edge = current_edge[vertex]
            if edge == 0
                minimum_height = typemax(Int)
                candidate = network.head[vertex]
                while candidate != 0
                    if network.capacity[candidate] > 1.0e-12
                        minimum_height = min(
                            minimum_height,
                            height[network.destination[candidate]],
                        )
                    end
                    candidate = network.next_edge[candidate]
                end
                minimum_height == typemax(Int) && break
                old_height = height[vertex]
                new_height = minimum_height + 1
                height_count[old_height + 1] -= 1
                height[vertex] = new_height
                height_count[new_height + 1] += 1
                current_edge[vertex] = network.head[vertex]

                if old_height < vertex_count &&
                        height_count[old_height + 1] == 0
                    @inbounds for candidate in 1:vertex_count
                        candidate == source && continue
                        candidate == sink && continue
                        candidate_height = height[candidate]
                        if old_height < candidate_height < vertex_count
                            height_count[candidate_height + 1] -= 1
                            height[candidate] = vertex_count + 1
                            height_count[vertex_count + 2] += 1
                            current_edge[candidate] = network.head[candidate]
                        end
                    end
                end
                continue
            end

            destination = network.destination[edge]
            if network.capacity[edge] > 1.0e-12 &&
                    height[vertex] == height[destination] + 1
                flow = min(excess[vertex], network.capacity[edge])
                network.capacity[edge] -= flow
                network.capacity[_reverse_edge(edge)] += flow
                excess[vertex] -= flow
                previous_excess = excess[destination]
                excess[destination] += flow
                if destination != source && destination != sink &&
                        previous_excess <= 1.0e-12 && !active[destination]
                    active[destination] = true
                    queue_tail = queue_tail == vertex_count ? 1 : queue_tail + 1
                    queue[queue_tail] = destination
                    queue_count += 1
                end
            else
                current_edge[vertex] = network.next_edge[edge]
            end
        end

        discharge_count += 1
        if discharge_count == vertex_count
            _global_relabel!(network, source, sink, height, relabel_queue)
            _recount_heights!(height_count, height)
            copyto!(current_edge, network.head)
            discharge_count = 0
        end
    end
    return excess[sink]
end

function _source_partition(network::_FlowNetwork, source::Int)
    reached = falses(length(network.head))
    queue = Vector{Int}(undef, length(network.head))
    reached[source] = true
    queue_start = 1
    queue_end = 1
    queue[1] = source
    while queue_start <= queue_end
        vertex = queue[queue_start]
        queue_start += 1
        edge = network.head[vertex]
        while edge != 0
            destination = network.destination[edge]
            if network.capacity[edge] > 1.0e-12 && !reached[destination]
                reached[destination] = true
                queue_end += 1
                queue[queue_end] = destination
            end
            edge = network.next_edge[edge]
        end
    end
    return reached
end

function _contrast_beta(values::AbstractMatrix{<:Real})
    h, w = size(values)
    difference_sum = 0.0
    difference_count = 0
    @inbounds for row in 1:h, col in 1:w
        value = Float64(values[row, col])
        if row < h
            difference_sum += (value - Float64(values[row + 1, col]))^2
            difference_count += 1
        end
        if col < w
            difference_sum += (value - Float64(values[row, col + 1]))^2
            difference_count += 1
        end
    end
    mean_difference = difference_count == 0 ? 0.0 : difference_sum / difference_count
    return mean_difference <= eps(Float64) ? 0.0 : 1.0 / (2.0 * mean_difference)
end

function _boykov_jolly_cut(
        values::AbstractMatrix{<:Real},
        saliency::AbstractMatrix{<:Real},
        smoothness::Float64,
        foreground_quantile::Float64,
    )
    size(values) == size(saliency) ||
        throw(DimensionMismatch("image and saliency sizes differ"))
    foreground_seed, background_seed, attention =
        _automatic_graphcut_seeds(saliency, foreground_quantile)
    any(foreground_seed) || return falses(size(values))
    foreground_cost, background_cost =
        _appearance_costs(values, foreground_seed, background_seed)
    saliency_prior_weight = 5.0
    foreground_cost .+= saliency_prior_weight .* (1.0 .- attention)
    background_cost .+= saliency_prior_weight .* attention

    h, w = size(values)
    pixel_count = h * w
    source = pixel_count + 1
    sink = pixel_count + 2
    expected_edges =
        4pixel_count + 2(h * max(w - 1, 0) + w * max(h - 1, 0))
    network = _FlowNetwork(pixel_count + 2, expected_edges)
    hard_capacity = 1.0e6 + pixel_count * smoothness

    @inbounds for index in eachindex(values)
        if foreground_seed[index]
            _add_directed_edge!(network, source, index, hard_capacity)
        elseif background_seed[index]
            _add_directed_edge!(network, index, sink, hard_capacity)
        else
            _add_directed_edge!(network, source, index, background_cost[index])
            _add_directed_edge!(network, index, sink, foreground_cost[index])
        end
    end

    if smoothness > 0.0
        beta = _contrast_beta(values)
        linear = LinearIndices(values)
        @inbounds for row in 1:h, col in 1:w
            index = linear[row, col]
            value = Float64(values[row, col])
            if row < h
                difference = value - Float64(values[row + 1, col])
                weight = smoothness * exp(-beta * difference^2)
                _add_bidirectional_edge!(
                    network,
                    index,
                    linear[row + 1, col],
                    weight,
                )
            end
            if col < w
                difference = value - Float64(values[row, col + 1])
                weight = smoothness * exp(-beta * difference^2)
                _add_bidirectional_edge!(
                    network,
                    index,
                    linear[row, col + 1],
                    weight,
                )
            end
        end
    end

    _maximum_flow!(network, source, sink)
    source_side = _source_partition(network, source)
    return BitMatrix(reshape(source_side[1:pixel_count], h, w))
end

function _grabcut_graphcut(
        values::AbstractMatrix{<:Real},
        foreground_cost::AbstractMatrix{<:Real},
        background_cost::AbstractMatrix{<:Real},
        foreground_seed::BitMatrix,
        background_seed::BitMatrix,
        smoothness::Float64,
    )
    h, w = size(values)
    pixel_count = h * w
    source = pixel_count + 1
    sink = pixel_count + 2
    expected_edges =
        4pixel_count + 2(h * max(w - 1, 0) + w * max(h - 1, 0))
    network = _FlowNetwork(pixel_count + 2, expected_edges)
    hard_capacity = 1.0e6 + pixel_count * smoothness

    @inbounds for index in eachindex(values)
        if foreground_seed[index]
            _add_directed_edge!(network, source, index, hard_capacity)
        elseif background_seed[index]
            _add_directed_edge!(network, index, sink, hard_capacity)
        else
            foreground_unary = Float64(foreground_cost[index])
            background_unary = Float64(background_cost[index])
            common_offset = min(foreground_unary, background_unary, 0.0)
            foreground_unary -= common_offset
            background_unary -= common_offset
            _add_directed_edge!(network, source, index, background_unary)
            _add_directed_edge!(network, index, sink, foreground_unary)
        end
    end

    if smoothness > 0.0
        beta = _contrast_beta(values)
        linear = LinearIndices(values)
        @inbounds for row in 1:h, col in 1:w
            index = linear[row, col]
            value = Float64(values[row, col])
            if row < h
                difference = value - Float64(values[row + 1, col])
                weight = smoothness * exp(-beta * difference^2)
                _add_bidirectional_edge!(
                    network,
                    index,
                    linear[row + 1, col],
                    weight,
                )
            end
            if col < w
                difference = value - Float64(values[row, col + 1])
                weight = smoothness * exp(-beta * difference^2)
                _add_bidirectional_edge!(
                    network,
                    index,
                    linear[row, col + 1],
                    weight,
                )
            end
        end
    end

    _maximum_flow!(network, source, sink)
    source_side = _source_partition(network, source)
    return BitMatrix(reshape(source_side[1:pixel_count], h, w))
end

function _grabcut_cut(
        values::AbstractMatrix{<:Real},
        saliency::AbstractMatrix{<:Real},
        iterations::Int,
        smoothness::Float64,
        foreground_quantile::Float64,
    )
    size(values) == size(saliency) ||
        throw(DimensionMismatch("image and saliency sizes differ"))
    foreground_seed, background_seed, attention =
        _automatic_graphcut_seeds(saliency, foreground_quantile)
    any(foreground_seed) || return falses(size(values))

    foreground_labels = BitMatrix(attention .>= 0.35)
    foreground_labels[foreground_seed] .= true
    foreground_labels[background_seed] .= false
    any(foreground_labels) || return foreground_seed
    all(foreground_labels) && return foreground_seed

    for _ in 1:iterations
        foreground_cost, background_cost =
            _grabcut_appearance_costs(values, foreground_labels)
        updated_labels = _grabcut_graphcut(
            values,
            foreground_cost,
            background_cost,
            foreground_seed,
            background_seed,
            smoothness,
        )
        updated_labels == foreground_labels && break
        foreground_labels = updated_labels
    end
    return foreground_labels
end

"""
    boykov_jolly_foreground_image2D_factory(::Type{I})

Specialize automatic-seed Boykov-Jolly graph-cut foreground extraction for a
concrete MAGE binary output type `I`.

The returned callable supports these effective signatures:

```julia
boykov_jolly_foreground(image)
boykov_jolly_foreground(image, smoothness::Real)
boykov_jolly_foreground(image, smoothness::Real, foreground_quantile::Real)
boykov_jolly_foreground(image, saliency)
boykov_jolly_foreground(image, saliency, smoothness::Real)
```

`image` is a same-size intensity image. With no supplied saliency map, the
operator computes spectral-residual saliency using its defaults. A supplied
`saliency` must be a same-size intensity image. A scale-space-smoothed version
of the saliency map supplies both a soft spatial prior and hard seeds:
high-saliency interior pixels become foreground seeds, while the image border
and low-saliency pixels connected to it become background seeds. Flat saliency
maps return an empty foreground mask.

`smoothness` controls contrast-sensitive four-neighbor boundary regularization,
is clamped to `[0, 20]`, and defaults to `5`. `foreground_quantile` controls
the high-saliency seed fraction, is clamped to `[0.5, 0.99]`, and defaults to
`0.9`. Non-finite values use the defaults. Appearance terms are deterministic
32-bin foreground/background histograms with Laplace smoothing. The exact
min-cut is computed by an internal FIFO push-relabel max-flow implementation
with global and gap relabeling.

Every overload has at most three MAGE inputs, accepts and ignores trailing
framework `args...`, and returns exactly the dimensions and `BinaryPixel`
storage type fixed by specialization `I`.
"""
function boykov_jolly_foreground_image2D_factory(
        ::Type{I},
    ) where {S1,S2,T,I<:SizedImage2D{S1,S2,BinaryPixel{T}}}
    IT = _get_image_type(I)
    PT = _get_image_pixel_type(I)
    S = _get_image_tuple_size(I)
    _validate_factory_type(IT)
    function_name = Symbol(:boykov_jolly_foreground_image2D_, Symbol(I))

    fn = @eval function $function_name(
            image::SOURCE,
            saliency::SALIENCY,
            smoothness_input::Real,
            args::Vararg{Any},
        ) where {
            ST,
            SOURCE<:SizedImage{$S,IntensityPixel{ST}},
            SAT,
            SALIENCY<:SizedImage{$S,IntensityPixel{SAT}},
        }
        smoothness_value = Float64(smoothness_input)
        smoothness = isfinite(smoothness_value) ?
                     clamp(smoothness_value, 0.0, 20.0) : 5.0
        mask = _boykov_jolly_cut(
            reinterpret(image.img),
            reinterpret(saliency.img),
            smoothness,
            0.9,
        )
        return SImageND($PT.($IT.(mask)), $S)
    end
    @eval function $function_name(
            image::SOURCE,
            saliency::SALIENCY,
            args::Vararg{Any},
        ) where {
            ST,
            SOURCE<:SizedImage{$S,IntensityPixel{ST}},
            SAT,
            SALIENCY<:SizedImage{$S,IntensityPixel{SAT}},
        }
        return $function_name(image, saliency, 5.0, args...)
    end
    @eval function $function_name(
            image::SOURCE,
            smoothness_input::Real,
            foreground_quantile_input::Real,
            args::Vararg{Any},
        ) where {ST,SOURCE<:SizedImage{$S,IntensityPixel{ST}}}
        smoothness_value = Float64(smoothness_input)
        quantile_value = Float64(foreground_quantile_input)
        smoothness = isfinite(smoothness_value) ?
                     clamp(smoothness_value, 0.0, 20.0) : 5.0
        foreground_quantile = isfinite(quantile_value) ?
                              clamp(quantile_value, 0.5, 0.99) : 0.9
        saliency = _spectral_residual_grayscale(image, 1, 2.0)
        mask = _boykov_jolly_cut(
            reinterpret(image.img),
            saliency,
            smoothness,
            foreground_quantile,
        )
        return SImageND($PT.($IT.(mask)), $S)
    end
    @eval function $function_name(
            image::SOURCE,
            smoothness::Real,
            args::Vararg{Any},
        ) where {ST,SOURCE<:SizedImage{$S,IntensityPixel{ST}}}
        return $function_name(image, smoothness, 0.9, args...)
    end
    @eval function $function_name(
            image::SOURCE,
            args::Vararg{Any},
        ) where {ST,SOURCE<:SizedImage{$S,IntensityPixel{ST}}}
        return $function_name(image, 5.0, 0.9, args...)
    end
    return fn
end

"""
    grabcut_foreground_image2D_factory(::Type{I})

Specialize deterministic, saliency-initialized GrabCut for a concrete MAGE
binary output type `I`.

The returned callable supports these effective signatures:

```julia
grabcut_foreground(image)
grabcut_foreground(image, iterations::Real)
grabcut_foreground(image, iterations::Real, smoothness::Real)
grabcut_foreground(image, saliency)
grabcut_foreground(image, saliency, iterations::Real)
```

`image` is a same-size intensity image. The operator either computes
spectral-residual saliency internally or consumes a same-size intensity
`saliency` image. Saliency establishes permanent foreground/background seeds
and the initial probable-foreground region. Each GrabCut iteration fits
deterministic five-component one-dimensional Gaussian mixtures to the current
grayscale foreground and background, then computes an exact contrast-sensitive
minimum cut.

`iterations` is rounded and clamped to `[1, 2]`, defaulting to `2`.
`smoothness` is clamped to `[0, 20]`, defaulting to `5`. Non-finite values
use the defaults. Supplied-saliency calls use the default smoothness to respect
the MAGE three-input ceiling. Flat saliency returns an empty mask.

Every overload accepts and ignores trailing framework `args...` and returns
exactly the dimensions and `BinaryPixel` storage type fixed by specialization
`I`.
"""
function grabcut_foreground_image2D_factory(
        ::Type{I},
    ) where {S1,S2,T,I<:SizedImage2D{S1,S2,BinaryPixel{T}}}
    IT = _get_image_type(I)
    PT = _get_image_pixel_type(I)
    S = _get_image_tuple_size(I)
    _validate_factory_type(IT)
    function_name = Symbol(:grabcut_foreground_image2D_, Symbol(I))

    fn = @eval function $function_name(
            image::SOURCE,
            saliency::SALIENCY,
            iterations_input::Real,
            args::Vararg{Any},
        ) where {
            ST,
            SOURCE<:SizedImage{$S,IntensityPixel{ST}},
            SAT,
            SALIENCY<:SizedImage{$S,IntensityPixel{SAT}},
        }
        iterations_value = Float64(iterations_input)
        iterations = isfinite(iterations_value) ?
                     round(Int, clamp(iterations_value, 1.0, 2.0)) : 2
        mask = _grabcut_cut(
            reinterpret(image.img),
            reinterpret(saliency.img),
            iterations,
            5.0,
            0.9,
        )
        return SImageND($PT.($IT.(mask)), $S)
    end
    @eval function $function_name(
            image::SOURCE,
            saliency::SALIENCY,
            args::Vararg{Any},
        ) where {
            ST,
            SOURCE<:SizedImage{$S,IntensityPixel{ST}},
            SAT,
            SALIENCY<:SizedImage{$S,IntensityPixel{SAT}},
        }
        return $function_name(image, saliency, 2.0, args...)
    end
    @eval function $function_name(
            image::SOURCE,
            iterations_input::Real,
            smoothness_input::Real,
            args::Vararg{Any},
        ) where {ST,SOURCE<:SizedImage{$S,IntensityPixel{ST}}}
        iterations_value = Float64(iterations_input)
        smoothness_value = Float64(smoothness_input)
        iterations = isfinite(iterations_value) ?
                     round(Int, clamp(iterations_value, 1.0, 2.0)) : 2
        smoothness = isfinite(smoothness_value) ?
                     clamp(smoothness_value, 0.0, 20.0) : 5.0
        saliency = _spectral_residual_grayscale(image, 1, 2.0)
        mask = _grabcut_cut(
            reinterpret(image.img),
            saliency,
            iterations,
            smoothness,
            0.9,
        )
        return SImageND($PT.($IT.(mask)), $S)
    end
    @eval function $function_name(
            image::SOURCE,
            iterations::Real,
            args::Vararg{Any},
        ) where {ST,SOURCE<:SizedImage{$S,IntensityPixel{ST}}}
        return $function_name(image, iterations, 5.0, args...)
    end
    @eval function $function_name(
            image::SOURCE,
            args::Vararg{Any},
        ) where {ST,SOURCE<:SizedImage{$S,IntensityPixel{ST}}}
        return $function_name(image, 2.0, 5.0, args...)
    end
    return fn
end

append_method!(
    bundle_image2DBinary_foreground_extraction_factory,
    boykov_jolly_foreground_image2D_factory,
    :boykov_jolly_foreground;
    description = "Extracts a binary foreground mask with automatic-seed Boykov-Jolly graph cuts.",
)

append_method!(
    bundle_image2DBinary_foreground_extraction_factory,
    grabcut_foreground_image2D_factory,
    :grabcut_foreground;
    description = "Extracts a binary foreground mask with deterministic saliency-initialized GrabCut.",
)

end
