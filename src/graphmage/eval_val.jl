############################
# GraphMAGE: archive-wide output evaluation
############################

"""
    evaluate_archive_outputs_on_samples(archive, xs, model_architecture, meta_library, shared_inputs) -> (labels, outputs)

Evaluate every node's genome in `archive` against `xs` (one `Vector` of
per-sample inputs, e.g. `valx`), merging every genome into one shared
`PopulationSequentialProgram` and evaluating hyperthreaded over samples --
the same population-graph evaluator used everywhere else in GraphMAGE, now
applied across the *entire* node set at once for maximal cross-node
computation sharing.

This is deliberately a raw-output helper with no notion of fitness or
endpoint: MAGE core has no knowledge of regression/correlation/time-penalty
specifics (those live in the caller's repo, next to its endpoint type -- see
`utils_populationgraph.jl` in MAGENetRunner). It only computes what every
genome outputs on every sample. Returns `(labels, outputs)` where `labels[i]`
is the node whose outputs are `outputs[i, :]` (one row per node, one column
per sample). Single-output model architectures only (image -> scalar
programs).
"""
function evaluate_archive_outputs_on_samples(
        archive::GraphMAGEArchive,
        xs::AbstractVector,
        model_architecture::modelArchitecture,
        meta_library::MetaLibrary,
        shared_inputs::SharedInput,
    )::Tuple{Vector{String}, Matrix{Float64}}
    graph = archive.graph
    labels_ = all_node_labels(graph)
    @info "GraphMAGE: evaluating archive outputs" n_nodes = length(labels_) n_samples = length(xs)
    isempty(labels_) && return (String[], Matrix{Float64}(undef, 0, 0))

    genomes = UTGenome[get_node(graph, l).genome for l in labels_]
    individual_programs = [
        decode_with_output_nodes(g, meta_library, model_architecture, shared_inputs) for g in genomes
    ]
    sequential_programs = SequentialProgram[
        compile_program(ip, model_architecture, meta_library; safe = true) for ip in individual_programs
    ]
    population_program = PopulationSequentialProgram(sequential_programs)

    sample_inputs = Tuple[Tuple(x) for x in xs]
    sample_outputs = evaluate_population_sequential_program_on_samples(population_program, sample_inputs)

    n = length(labels_)
    n_samples = length(xs)
    outputs = Matrix{Float64}(undef, n, n_samples)
    for s in 1:n_samples
        for i in 1:n
            outputs[i, s] = Float64(first(sample_outputs[s][i]))
        end
    end
    return labels_, outputs
end

"""
    set_val_fitness!(archive, label, value)

Small generic mutator so callers outside MAGE (which compute `value` using
their own endpoint-specific metrics) can write validation fitness back onto
an archive node without reaching into `MetaGraphsNext` internals themselves.
"""
function set_val_fitness!(archive::GraphMAGEArchive, label::String, value::Float64)
    get_node(archive.graph, label).val_fitness = value
    return value
end
