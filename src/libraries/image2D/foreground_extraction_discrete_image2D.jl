"""
Deterministic discrete foreground extraction for intensity images.

# Bundles

- [`bundle_image2DBinary_foreground_extraction_factory`](@ref)

The exhaustive operator list is on the [Bundle Catalogue](@ref) page.
"""
module image2D_foreground_extraction_discrete

using ..UTCGP: _factory_type_symbol

# Call tree: factories → _foreground_apply! → matrix kernels → seeded cuts
# → appearance costs + graph construction
# → _maximum_flow! (_global_relabel!, _recount_heights!) → _source_partition.
# Scratch slots are task-local; separate slots keep simultaneously live arrays distinct.

using ..UTCGP: scratch, output_pixels, image_result
include("foreground_resolution.jl")

using ..image2D_saliency_fixation: _spectral_residual_grayscale
using ImageFiltering: Kernel, imfilter
using ImageMorphology: distance_transform, feature_transform, label_components, label_components!
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
same-size binary image. Images above 32 on either axis
are box pooled to a grid with longer axis 32 and preserved aspect ratio
(224×100 → 32×14). Cut rough masks use guarded 1/4 occupancy and nearest-neighbor lifting.
Images at most 32×32 use their input grid. Existing third arguments retain
their parameter meanings; maximum graph-node arity is three.

Factories are specialized with the concrete binary
output type before insertion into a MAGE library.

The operators are Boykov-Jolly graph cuts and iterative GrabCut. Both take
their hard seeds from one of: spectral-residual saliency computed internally,
a same-size saliency map from another MAGE image chromosome, or a rough binary
mask with an uncertainty band (`(img, mask, band)`), which they refine to the
image's edges. The mask mode is the most reliable: saliency marks edges and
details rather than whole objects.
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

"""Band half-width (pixels) of the mask-seeded methods: rounded, clamped to `[0, 20]`; NaN/Inf → 4 (the default)."""
_seed_band(band::Real) = (b = Float64(band); isfinite(b) ? round(Int, clamp(b, 0.0, 20.0)) : 4)

"""
    _mask_band_seeds(mask, band) -> (foreground_seeds, background_seeds)

Hard seeds from a rough foreground mask: pixels deeper than `band` inside the
mask are foreground, pixels farther than `band` outside it are background, and
the `2·band`-wide strip along the mask's edge is left for the solver to decide.
An object thinner than the band keeps its deepest pixels as seeds, so no object
is lost. Example: a 20-pixel square with `band = 2` gives a 16-pixel square of
foreground seeds and background seeds from 3 pixels outside the square.
"""
function _mask_band_seeds(mask::AbstractMatrix{Bool}, band::Int)
    inside = distance_transform(feature_transform(.!mask))    # distance to the nearest outside pixel
    outside = distance_transform(feature_transform(mask))     # distance to the nearest mask pixel
    components = label_components(mask)
    deepest = zeros(Float64, maximum(components; init = 0))
    @inbounds for index in eachindex(components)
        c = components[index]
        c > 0 && (deepest[c] = max(deepest[c], inside[index]))
    end
    foreground = falses(size(mask))
    background = falses(size(mask))
    @inbounds for index in eachindex(mask)
        c = components[index]
        if c > 0
            foreground[index] = inside[index] >= min(band + 1, deepest[c])
        else
            background[index] = outside[index] > band
        end
    end
    return foreground, background
end

@inline function _histogram_bin(value::Float64, bin_count::Int)
    return clamp(floor(Int, clamp(value, 0.0, 1.0) * bin_count) + 1, 1, bin_count)
end

"""
Compute the same 32-bin log costs in task-local matrices.
For example, equal foreground/background histograms give equal costs.
"""
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

    foreground_cost = scratch(:discrete_foreground_cost, Float64, size(values)...)
    background_cost = scratch(:discrete_background_cost, Float64, size(values)...)
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

"""
Fit a deterministic mixture using a reusable sorted-sample workspace.
For example, [0.5] produces one component with mean 0.5.
"""
function _fit_grabcut_gmm(samples::Vector{Float64})
    isempty(samples) && return ([1.0], [0.5], [1.0])
    sorted_samples = scratch(:discrete_gmm_sorted_samples, Float64, 0)
    resize!(sorted_samples, length(samples))
    copyto!(sorted_samples, samples)
    sort!(sorted_samples)
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

"""
Fit both appearance models and fill task-local cost matrices.
For example, identical selected intensities give equal foreground/background costs.
"""
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
    foreground_cost = scratch(:discrete_foreground_cost, Float64, size(values)...)
    background_cost = scratch(:discrete_background_cost, Float64, size(values)...)
    @inbounds for index in eachindex(values)
        value = Float64(values[index])
        foreground_cost[index] =
            _prepared_gmm_cost(value, foreground_model...)
        background_cost[index] =
            _prepared_gmm_cost(value, background_model...)
    end
    return foreground_cost, background_cost
end

# Exact integer residuals prevent rounding errors from leaving excess circulating.
# Scale capacities on insertion so the flow loop uses integer arithmetic throughout.
const _FLOW_CAPACITY_SCALE = 2^20

"""Float capacity -> scaled Int64. Non-finite or negative inputs are clamped (NaN -> 0)."""
function _flow_capacity(capacity::Float64)
    finite = isfinite(capacity) ? clamp(capacity, 0.0, 1.0e9) : (capacity > 0 ? 1.0e9 : 0.0)
    return round(Int64, finite * _FLOW_CAPACITY_SCALE)
end

mutable struct _FlowNetwork
    head::Vector{Int}
    destination::Vector{Int}
    next_edge::Vector{Int}
    capacity::Vector{Int64}
end

"""
    _FlowNetwork(vertex_count, edge_capacity)

Reuse task-local edge arrays, clearing all heads and logical edge lengths.
Edges retain insertion order: adding 1 → 2 gives edge pair (1, 2).
The network is working storage and must not escape a cut.
"""
function _FlowNetwork(vertex_count::Int, edge_capacity::Int)
    head = scratch(:discrete_flow_head, Int, vertex_count)
    fill!(head, 0)
    destination = scratch(:discrete_flow_destination, Int, 0)
    next_edge = scratch(:discrete_flow_next, Int, 0)
    capacity = scratch(:discrete_flow_capacity, Int64, 0)
    empty!(destination)
    empty!(next_edge)
    empty!(capacity)
    sizehint!(destination, edge_capacity)
    sizehint!(next_edge, edge_capacity)
    sizehint!(capacity, edge_capacity)
    return _FlowNetwork(head, destination, next_edge, capacity)
end

function _add_directed_edge!(
        network::_FlowNetwork,
        source::Int,
        sink::Int,
        capacity::Float64,
    )
    push!(network.destination, sink)
    push!(network.next_edge, network.head[source])
    push!(network.capacity, _flow_capacity(capacity))
    network.head[source] = length(network.capacity)

    push!(network.destination, source)
    push!(network.next_edge, network.head[sink])
    push!(network.capacity, 0)
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
    push!(network.capacity, _flow_capacity(capacity))
    network.head[first] = length(network.capacity)

    push!(network.destination, first)
    push!(network.next_edge, network.head[second])
    push!(network.capacity, _flow_capacity(capacity))
    network.head[second] = length(network.capacity)
    return nothing
end

@inline _reverse_edge(edge::Int) = isodd(edge) ? edge + 1 : edge - 1

"""
Fill reverse-residual distances in the existing BFS order.
For example, the sink always has height zero.
"""
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
    @inbounds while queue_start <= queue_end
        vertex = queue[queue_start]
        queue_start += 1
        edge = network.head[vertex]
        while edge != 0
            predecessor = network.destination[edge]
            reverse = _reverse_edge(edge)
            if predecessor != source && height[predecessor] == unreachable &&
                    network.capacity[reverse] > 0
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

# Budget units are inner discharge attempts: pushes, edge advances, and relabels.
# Every solve uses max(FLOOR, C*n). The floor preserves the historical 32×32
# allowance; linear growth bounds larger problems without a quadratic runaway.
# Completed calibration solves need up to ~3,900 attempts/vertex; C=8,192 gives
# over 2× headroom. At 224² the limit is 411,058,176 attempts, measured at about
# 3.53 seconds for one saturated flow (GrabCut runs at most two flows per call).
# Cholesky and package watershed have no loop here; their problem-size caps apply.
const _MAX_FLOW_WORK_FLOOR = 100 * 1026^2
const _MAX_FLOW_WORK_PER_VERTEX = 8192

"""
Run FIFO push-relabel with reused task-local working arrays.
For example, a single edge of capacity 1 transports its scaled integer capacity.
A full sweep refreshes distance labels while gap relabels skip unreachable layers.
"""
function _maximum_flow!(network::_FlowNetwork, source::Int, sink::Int)
    vertex_count = length(network.head)
    height = scratch(:discrete_flow_height, Int, vertex_count)
    fill!(height, 0)
    excess = scratch(:discrete_flow_excess, Int64, vertex_count)
    fill!(excess, 0)
    work = 0
    work_limit = max(_MAX_FLOW_WORK_FLOOR, _MAX_FLOW_WORK_PER_VERTEX * vertex_count)
    current_edge = scratch(:discrete_flow_current, Int, vertex_count)
    copyto!(current_edge, network.head)
    active = scratch(:discrete_flow_active, Bool, vertex_count)
    fill!(active, false)
    height_count = scratch(:discrete_flow_height_count, Int, 2vertex_count + 3)
    fill!(height_count, 0)
    queue = scratch(:discrete_flow_queue, Int, vertex_count)
    relabel_queue = scratch(:discrete_flow_relabel_queue, Int, vertex_count)
    queue_head = 1
    queue_tail = 0
    queue_count = 0

    height[source] = vertex_count
    edge = network.head[source]
    @inbounds while edge != 0
        flow = network.capacity[edge]
        if flow > 0
            destination = network.destination[edge]
            network.capacity[edge] = 0
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
    @inbounds while queue_count > 0
        vertex = queue[queue_head]
        queue_head = queue_head == vertex_count ? 1 : queue_head + 1
        queue_count -= 1
        active[vertex] = false

        while excess[vertex] > 0
            work += 1
            work > work_limit && throw(ErrorException(
                "_maximum_flow! exceeded its work budget ($(work_limit) operations); the cut is abandoned"))
            edge = current_edge[vertex]
            if edge == 0
                minimum_height = typemax(Int)
                candidate = network.head[vertex]
                while candidate != 0
                    if network.capacity[candidate] > 0
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
            if network.capacity[edge] > 0 &&
                    height[vertex] == height[destination] + 1
                flow = min(excess[vertex], network.capacity[edge])
                network.capacity[edge] -= flow
                network.capacity[_reverse_edge(edge)] += flow
                excess[vertex] -= flow
                previous_excess = excess[destination]
                excess[destination] += flow
                if destination != source && destination != sink &&
                        previous_excess == 0 && !active[destination]
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
        # Refresh sink distances to guide subsequent excess discharge.
        if discharge_count == vertex_count
            _global_relabel!(network, source, sink, height, relabel_queue)
            _recount_heights!(height_count, height)
            copyto!(current_edge, network.head)
            discharge_count = 0
        end
    end
    return excess[sink]
end

"""
Return a fresh reachable-vertex mask using a reused BFS queue.
For example, an isolated source is the only true entry.
"""
function _source_partition(network::_FlowNetwork, source::Int)
    reached = falses(length(network.head))
    queue = scratch(:discrete_partition_queue, Int, length(network.head))
    reached[source] = true
    queue_start = 1
    queue_end = 1
    queue[1] = source
    @inbounds while queue_start <= queue_end
        vertex = queue[queue_start]
        queue_start += 1
        edge = network.head[vertex]
        while edge != 0
            destination = network.destination[edge]
            if network.capacity[edge] > 0 && !reached[destination]
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
    return _boykov_jolly_seeded_cut(values, foreground_seed, background_seed, smoothness, attention)
end

"""
Boykov-Jolly cut from given hard seeds. Appearance costs come from the
intensity histograms of the seeds; `attention` (a `[0, 1]` map, or `nothing`)
adds a soft prior pulling high-attention pixels to the foreground.
"""
function _boykov_jolly_seeded_cut(
        values::AbstractMatrix{<:Real},
        foreground_seed::BitMatrix,
        background_seed::BitMatrix,
        smoothness::Float64,
        attention,
    )
    foreground_cost, background_cost =
        _appearance_costs(values, foreground_seed, background_seed)
    if attention !== nothing
        saliency_prior_weight = 5.0
        foreground_cost .+= saliency_prior_weight .* (1.0 .- attention)
        background_cost .+= saliency_prior_weight .* attention
    end

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

    initial_labels = BitMatrix(attention .>= 0.35)
    return _grabcut_seeded(values, foreground_seed, background_seed, initial_labels, iterations, smoothness)
end

"""
GrabCut from given hard seeds and an initial foreground guess: alternates
fitting the foreground/background Gaussian mixtures to the current labels and
an exact contrast-sensitive minimum cut, for `iterations` rounds.
"""
function _grabcut_seeded(
        values::AbstractMatrix{<:Real},
        foreground_seed::BitMatrix,
        background_seed::BitMatrix,
        initial_labels::BitMatrix,
        iterations::Int,
        smoothness::Float64,
    )
    foreground_labels = copy(initial_labels)
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
Mask-seeded foreground: seeds from `mask` and `band` (see `_mask_band_seeds`),
then `cut(foreground_seeds, background_seeds)`. An empty mask gives an empty
result and a mask with no background seeds (it covers almost everything) is
returned unchanged.
"""
function _mask_seeded(cut, mask::AbstractMatrix{Bool}, band::Int)
    any(mask) || return falses(size(mask))
    foreground_seed, background_seed = _mask_band_seeds(mask, band)
    any(background_seed) || return BitMatrix(mask)
    return cut(foreground_seed, background_seed)
end

"""Write Boykov–Jolly pixels from supplied saliency; e.g. 32×14 in fills 32×14 out."""
function _boykov_jolly_foreground_supplied!(
        pixels::AbstractMatrix{P},
        image::AbstractMatrix, saliency::AbstractMatrix, smoothness_input::Real,
    ) where {P}
    pixel_type = P
    storage_type = fieldtype(P, 1)
    smoothness_value = Float64(smoothness_input)
    smoothness = isfinite(smoothness_value) ?
                 clamp(smoothness_value, 0.0, 20.0) : 5.0
    mask = _boykov_jolly_cut(
        reinterpret(image),
        reinterpret(saliency),
        smoothness,
        0.9,
    )
    pixels .= pixel_type.(storage_type.(mask))
    return pixels
end

"""Write Boykov–Jolly pixels from automatic seeds; e.g. 32×14 in fills 32×14 out."""
function _boykov_jolly_foreground_automatic!(
        pixels::AbstractMatrix{P},
        image::AbstractMatrix, ::Nothing, smoothness_input::Real, foreground_quantile_input::Real,
    ) where {P}
    pixel_type = P
    storage_type = fieldtype(P, 1)
    smoothness_value = Float64(smoothness_input)
    quantile_value = Float64(foreground_quantile_input)
    smoothness = isfinite(smoothness_value) ?
                 clamp(smoothness_value, 0.0, 20.0) : 5.0
    foreground_quantile = isfinite(quantile_value) ?
                          clamp(quantile_value, 0.5, 0.99) : 0.9
    saliency = _spectral_residual_grayscale(image, 1, 2.0)
    mask = _boykov_jolly_cut(
        reinterpret(image),
        saliency,
        smoothness,
        foreground_quantile,
    )
    pixels .= pixel_type.(storage_type.(mask))
    return pixels
end

"""Write Boykov–Jolly pixels from a rough mask; e.g. 32×14 in fills 32×14 out."""
function _boykov_jolly_foreground_mask!(
        pixels::AbstractMatrix{P},
        image::AbstractMatrix, mask::AbstractMatrix, band::Real,
    ) where {P}
    pixel_type = P
    storage_type = fieldtype(P, 1)
    values = reinterpret(image)
    result = _mask_seeded(Bool.(reinterpret(mask)), _seed_band(band)) do foreground_seed, background_seed
        _boykov_jolly_seeded_cut(values, foreground_seed, background_seed, 5.0, nothing)
    end
    pixels .= pixel_type.(storage_type.(result))
    return pixels
end

"""
    boykov_jolly_foreground_image2D_factory(::Type{I})

Images above 32 pixels on either axis use a 32-pixel working grid.
All third inputs retain their existing parameter meanings.
"""
function boykov_jolly_foreground_image2D_factory(
        ::Type{I},
    ) where {S1,S2,T,I<:SizedImage2D{S1,S2,BinaryPixel{T}}}
    IT = _get_image_type(I)
    PT = _get_image_pixel_type(I)
    S = _get_image_tuple_size(I)
    _validate_factory_type(IT)
    function_name = Symbol(:boykov_jolly_foreground_image2D_, _factory_type_symbol(I))
    isdefined(@__MODULE__, function_name) && return getfield(@__MODULE__, function_name)

    fn = @eval function $function_name(
            image::SOURCE,
            saliency::SALIENCY,
            smoothness_input::Real,
            args::Vararg{Any}; out = nothing,
        ) where {
            ST,
            SOURCE<:SizedImage{$S,IntensityPixel{ST}},
            SAT,
            SALIENCY<:SizedImage{$S,IntensityPixel{SAT}},
        }
        pixels = output_pixels(out, image, $PT)
        _foreground_apply!(
            _boykov_jolly_foreground_supplied!, pixels, image.img, saliency.img,
            (smoothness_input,), Val(:mean), Val(false),
        )
        return image_result(out, pixels, $S)
    end
    @eval function $function_name(
            image::SOURCE,
            saliency::SALIENCY,
            args::Vararg{Any}; out = nothing,
        ) where {
            ST,
            SOURCE<:SizedImage{$S,IntensityPixel{ST}},
            SAT,
            SALIENCY<:SizedImage{$S,IntensityPixel{SAT}},
        }
        return $function_name(image, saliency, 5.0, args...; out)
    end
    @eval function $function_name(
            image::SOURCE,
            smoothness_input::Real,
            foreground_quantile_input::Real,
            args::Vararg{Any}; out = nothing,
        ) where {ST,SOURCE<:SizedImage{$S,IntensityPixel{ST}}}
        pixels = output_pixels(out, image, $PT)
        _foreground_apply!(
            _boykov_jolly_foreground_automatic!, pixels, image.img, nothing,
            (smoothness_input, foreground_quantile_input), Val(:mean), Val(false),
        )
        return image_result(out, pixels, $S)
    end
    @eval function $function_name(
            image::SOURCE,
            smoothness::Real,
            args::Vararg{Any}; out = nothing,
        ) where {ST,SOURCE<:SizedImage{$S,IntensityPixel{ST}}}
        return $function_name(image, smoothness, 0.9, args...; out)
    end
    @eval function $function_name(
            image::SOURCE,
            args::Vararg{Any}; out = nothing,
        ) where {ST,SOURCE<:SizedImage{$S,IntensityPixel{ST}}}
        return $function_name(image, 5.0, 0.9, args...; out)
    end
    # Seeds from a rough mask (e.g. a threshold) and an uncertainty band.
    @eval function $function_name(
            image::SOURCE,
            mask::MASK,
            band::Real,
            args::Vararg{Any}; out = nothing,
        ) where {ST,SOURCE<:SizedImage{$S,IntensityPixel{ST}},MT,MASK<:SizedImage{$S,BinaryPixel{MT}}}
        pixels = output_pixels(out, image, $PT)
        _foreground_apply!(
            _boykov_jolly_foreground_mask!, pixels, image.img, mask.img,
            (band,), Val(:sparse_quarter), Val(false),
        )
        return image_result(out, pixels, $S)
    end
    @eval function $function_name(
            image::SOURCE,
            mask::MASK,
            args::Vararg{Any}; out = nothing,
        ) where {ST,SOURCE<:SizedImage{$S,IntensityPixel{ST}},MT,MASK<:SizedImage{$S,BinaryPixel{MT}}}
        return $function_name(image, mask, 4.0, args...; out)
    end
    return fn
end

"""Write GrabCut pixels from supplied saliency; e.g. 32×14 in fills 32×14 out."""
function _grabcut_foreground_supplied!(
        pixels::AbstractMatrix{P},
        image::AbstractMatrix, saliency::AbstractMatrix, iterations_input::Real,
    ) where {P}
    pixel_type = P
    storage_type = fieldtype(P, 1)
    iterations_value = Float64(iterations_input)
    iterations = isfinite(iterations_value) ?
                 round(Int, clamp(iterations_value, 1.0, 2.0)) : 2
    mask = _grabcut_cut(
        reinterpret(image),
        reinterpret(saliency),
        iterations,
        5.0,
        0.9,
    )
    pixels .= pixel_type.(storage_type.(mask))
    return pixels
end

"""Write GrabCut pixels from automatic seeds; e.g. 32×14 in fills 32×14 out."""
function _grabcut_foreground_automatic!(
        pixels::AbstractMatrix{P},
        image::AbstractMatrix, ::Nothing, iterations_input::Real, smoothness_input::Real,
    ) where {P}
    pixel_type = P
    storage_type = fieldtype(P, 1)
    iterations_value = Float64(iterations_input)
    smoothness_value = Float64(smoothness_input)
    iterations = isfinite(iterations_value) ?
                 round(Int, clamp(iterations_value, 1.0, 2.0)) : 2
    smoothness = isfinite(smoothness_value) ?
                 clamp(smoothness_value, 0.0, 20.0) : 5.0
    saliency = _spectral_residual_grayscale(image, 1, 2.0)
    mask = _grabcut_cut(
        reinterpret(image),
        saliency,
        iterations,
        smoothness,
        0.9,
    )
    pixels .= pixel_type.(storage_type.(mask))
    return pixels
end

"""Write GrabCut pixels from a rough mask; e.g. 32×14 in fills 32×14 out."""
function _grabcut_foreground_mask!(
        pixels::AbstractMatrix{P},
        image::AbstractMatrix, mask::AbstractMatrix, band::Real,
    ) where {P}
    pixel_type = P
    storage_type = fieldtype(P, 1)
    values = reinterpret(image)
    guess = BitMatrix(Bool.(reinterpret(mask)))
    result = _mask_seeded(guess, _seed_band(band)) do foreground_seed, background_seed
        _grabcut_seeded(values, foreground_seed, background_seed, guess, 2, 5.0)
    end
    pixels .= pixel_type.(storage_type.(result))
    return pixels
end

"""
    grabcut_foreground_image2D_factory(::Type{I})

Images above 32 pixels on either axis use a 32-pixel working grid.
All third inputs retain their existing parameter meanings.
"""
function grabcut_foreground_image2D_factory(
        ::Type{I},
    ) where {S1,S2,T,I<:SizedImage2D{S1,S2,BinaryPixel{T}}}
    IT = _get_image_type(I)
    PT = _get_image_pixel_type(I)
    S = _get_image_tuple_size(I)
    _validate_factory_type(IT)
    function_name = Symbol(:grabcut_foreground_image2D_, _factory_type_symbol(I))
    isdefined(@__MODULE__, function_name) && return getfield(@__MODULE__, function_name)

    fn = @eval function $function_name(
            image::SOURCE,
            saliency::SALIENCY,
            iterations_input::Real,
            args::Vararg{Any}; out = nothing,
        ) where {
            ST,
            SOURCE<:SizedImage{$S,IntensityPixel{ST}},
            SAT,
            SALIENCY<:SizedImage{$S,IntensityPixel{SAT}},
        }
        pixels = output_pixels(out, image, $PT)
        _foreground_apply!(
            _grabcut_foreground_supplied!, pixels, image.img, saliency.img,
            (iterations_input,), Val(:mean), Val(false),
        )
        return image_result(out, pixels, $S)
    end
    @eval function $function_name(
            image::SOURCE,
            saliency::SALIENCY,
            args::Vararg{Any}; out = nothing,
        ) where {
            ST,
            SOURCE<:SizedImage{$S,IntensityPixel{ST}},
            SAT,
            SALIENCY<:SizedImage{$S,IntensityPixel{SAT}},
        }
        return $function_name(image, saliency, 2.0, args...; out)
    end
    @eval function $function_name(
            image::SOURCE,
            iterations_input::Real,
            smoothness_input::Real,
            args::Vararg{Any}; out = nothing,
        ) where {ST,SOURCE<:SizedImage{$S,IntensityPixel{ST}}}
        pixels = output_pixels(out, image, $PT)
        _foreground_apply!(
            _grabcut_foreground_automatic!, pixels, image.img, nothing,
            (iterations_input, smoothness_input), Val(:mean), Val(false),
        )
        return image_result(out, pixels, $S)
    end
    @eval function $function_name(
            image::SOURCE,
            iterations::Real,
            args::Vararg{Any}; out = nothing,
        ) where {ST,SOURCE<:SizedImage{$S,IntensityPixel{ST}}}
        return $function_name(image, iterations, 5.0, args...; out)
    end
    @eval function $function_name(
            image::SOURCE,
            args::Vararg{Any}; out = nothing,
        ) where {ST,SOURCE<:SizedImage{$S,IntensityPixel{ST}}}
        return $function_name(image, 2.0, 5.0, args...; out)
    end
    # Seeds from a rough mask and an uncertainty band; the mask is also the initial guess.
    @eval function $function_name(
            image::SOURCE,
            mask::MASK,
            band::Real,
            args::Vararg{Any}; out = nothing,
        ) where {ST,SOURCE<:SizedImage{$S,IntensityPixel{ST}},MT,MASK<:SizedImage{$S,BinaryPixel{MT}}}
        pixels = output_pixels(out, image, $PT)
        _foreground_apply!(
            _grabcut_foreground_mask!, pixels, image.img, mask.img,
            (band,), Val(:sparse_quarter), Val(false),
        )
        return image_result(out, pixels, $S)
    end
    @eval function $function_name(
            image::SOURCE,
            mask::MASK,
            args::Vararg{Any}; out = nothing,
        ) where {ST,SOURCE<:SizedImage{$S,IntensityPixel{ST}},MT,MASK<:SizedImage{$S,BinaryPixel{MT}}}
        return $function_name(image, mask, 4.0, args...; out)
    end
    return fn
end

append_method!(
    bundle_image2DBinary_foreground_extraction_factory,
    boykov_jolly_foreground_image2D_factory,
    :boykov_jolly_foreground;
    description = "Boykov-Jolly graph-cut foreground: (img, [smoothness], [quantile]) with saliency-derived seeds, (img, saliency) or (img, mask, [band]) refining a rough mask.",
)

append_method!(
    bundle_image2DBinary_foreground_extraction_factory,
    grabcut_foreground_image2D_factory,
    :grabcut_foreground;
    description = "GrabCut foreground: (img, [iterations], [smoothness]) with saliency-derived seeds, (img, saliency) or (img, mask, [band]) refining a rough mask.",
)

end
