############################
# GraphMAGE: behavior identity
############################

"""
    build_behavior_probes(xs, n_probes; rng_seed=0) -> Vector{<:Tuple}

Draw `n_probes` per-sample input tuples once, seeded, from `xs` (a training
set laid out as one `Vector` of inputs per sample, e.g. `trainx`). Reused
verbatim for the whole run and persisted in the archive so behavior hashes
stay comparable across expansions, checkpoints, and merges -- comparing
behaviors computed on different probe sets would be meaningless.
"""
function build_behavior_probes(xs::AbstractVector, n_probes::Int; rng_seed::Int = 0)::Vector{<:Tuple}
    rng = Random.MersenneTwister(rng_seed)
    idx = StatsBase.sample(rng, 1:length(xs), min(n_probes, length(xs)); replace = false)
    return [Tuple(xs[i]) for i in idx]
end

"""
    compute_behaviors_for_population(genomes, model_architecture, meta_library, shared_inputs, probes, round_digits) -> Vector{String}

Evaluate every genome in `genomes` on `probes`, using the population-graph
evaluator (every genome merged into one shared computation DAG, evaluated
hyperthreaded over probes -- both dogfooding the same infrastructure used by
the inner GA and catching duplicate behaviors *within* one batch cheaply).
Each individual's per-probe output vector is rounded to `round_digits`
decimals and hashed (SHA-256 of the rounded vector) into its behavior
identity string. Single-output model architectures only (image -> scalar
programs).
"""
function compute_behaviors_for_population(
        genomes::Vector{UTGenome},
        model_architecture::modelArchitecture,
        meta_library::MetaLibrary,
        shared_inputs::SharedInput,
        probes::Vector{<:Tuple},
        round_digits::Int,
    )::Vector{String}
    n = length(genomes)
    n == 0 && return String[]

    individual_programs = [
        decode_with_output_nodes(genome, meta_library, model_architecture, shared_inputs) for
            genome in genomes
    ]
    sequential_programs = SequentialProgram[
        compile_program(ip, model_architecture, meta_library; safe = true) for ip in individual_programs
    ]
    population_program = PopulationSequentialProgram(sequential_programs)

    sample_outputs = evaluate_population_sequential_program_on_samples(population_program, probes)

    n_probes = length(probes)
    behaviors = Vector{String}(undef, n)
    for ind_idx in 1:n
        outputs = Float64[
            Float64(first(sample_outputs[sample_idx][ind_idx])) for sample_idx in 1:n_probes
        ]
        rounded = round.(outputs, digits = round_digits)
        behaviors[ind_idx] = general_hasher_sha(rounded)
    end
    return behaviors
end

"""
    compute_behaviors_independently(genomes, model_architecture, meta_library, shared_inputs, probes, round_digits) -> Vector{String}

Like `compute_behaviors_for_population`, but hyperthreaded *across genomes*
rather than across probes: `genomes` is split into `Threads.nthreads()`
contiguous partitions, and each thread builds and owns its own small
`PopulationSequentialProgram` for just its partition (still the population-
graph evaluator throughout -- never the old per-node evaluator, and never
touching `genome.*.value`), evaluated sequentially over all probes with one
private `PopulationSequentialWorkspace`. No nested `Threads.@threads`: the
per-sample auto-threading `evaluate_population_sequential_program_on_samples`
provides is exactly what a single outer partition-level `Threads.@threads`
would fight with, so this calls the lower-level, unthreaded
`evaluate_population_sequential_program` in its own probe loop instead.

Appropriate when genomes share little or no structural ancestry, such as a
batch of freshly built random roots: merging *all* of them into one shared
graph (`compute_behaviors_for_population`) only pays off when individuals
share active-node structure (e.g. GA offspring descended from the same
elites) -- for a batch of unrelated genomes there is nothing to share, and
`compute_behaviors_for_population`'s per-probe threading would force every
thread to walk every genome's steps regardless. Partitioning first restores
genome-level parallelism while still going through the same evaluator.
"""
function compute_behaviors_independently(
        genomes::Vector{UTGenome},
        model_architecture::modelArchitecture,
        meta_library::MetaLibrary,
        shared_inputs::SharedInput,
        probes::Vector{<:Tuple},
        round_digits::Int,
    )::Vector{String}
    n = length(genomes)
    n == 0 && return String[]

    behaviors = Vector{String}(undef, n)
    n_probes = length(probes)
    chunk_size = cld(n, Threads.nthreads())

    Threads.@threads for chunk_start in 1:chunk_size:n
        chunk_indices = chunk_start:min(chunk_start + chunk_size - 1, n)
        chunk_genomes = genomes[chunk_indices]

        individual_programs = [
            decode_with_output_nodes(g, meta_library, model_architecture, shared_inputs) for g in chunk_genomes
        ]
        sequential_programs = SequentialProgram[
            compile_program(ip, model_architecture, meta_library; safe = true) for ip in individual_programs
        ]
        population_program = PopulationSequentialProgram(sequential_programs)
        workspace = PopulationSequentialWorkspace(population_program)

        n_chunk = length(chunk_genomes)
        chunk_outputs = [Vector{Float64}(undef, n_probes) for _ in 1:n_chunk]
        for (p, probe) in enumerate(probes)
            sample_out = evaluate_population_sequential_program(population_program, probe...; workspace = workspace)
            for i in 1:n_chunk
                chunk_outputs[i][p] = Float64(first(sample_out[i]))
            end
        end
        for (i, global_idx) in enumerate(chunk_indices)
            rounded = round.(chunk_outputs[i], digits = round_digits)
            behaviors[global_idx] = general_hasher_sha(rounded)
        end
    end
    return behaviors
end
