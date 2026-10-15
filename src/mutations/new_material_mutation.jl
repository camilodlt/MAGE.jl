import StatsBase: sample, Weights
import Random
using Debugger

"""
    new_material_mutation!(ut_genome, run_config, model_architecture, meta_library,
                           shared_inputs)

Like [`numbered_mutation!`](@ref), but each sampled node is re-mutated until its
*active material* actually changes.

A CGP mutation is often silent: it can hit dormant material, or resample a node
to something equivalent, and the offspring then costs an evaluation while being
a duplicate of its parent. This variant retries (up to 1000 times per node)
until the node's decoded material differs, so an offspring is always a genuinely
new program.

`run_config.mutation_rate` must be `> 1.0`; its floor is the number of nodes to
mutate. Pass `active_positions=entry::ActiveNodeCacheEntry` to reuse an exact
copy's cached ordered positions. Invalid/layout-mismatched entries are freshly
decoded and captured. A mutated entry is invalidated before node mutation.
The returned selected-node vector is borrowed from the entry until its next use;
without a cache the original fresh-vector behavior is unchanged.

Exposed as [`default_numbered_new_material_mutation_callback`](@ref) and
[`ga_numbered_new_material_mutation_callback`](@ref).
"""
function new_material_mutation!(
        ut_genome::UTGenome,
        run_config::AbstractRunConf,
        model_architecture::modelArchitecture,
        meta_library::MetaLibrary,
        shared_inputs::SharedInput;
        active_positions::Union{Nothing,ActiveNodeCacheEntry} = nothing,
    )
    @assert run_config.mutation_rate > 1.0 "Mutation should be > 1."
    @assert length(model_architecture.inputs_types) > 0 "At least one input ? "
    @assert length(model_architecture.chromosomes_types) == length(ut_genome.genomes) "Need to give all chromosome types (Int, Float64, ...) in order so we check that nodes function with available signatures"  # noqa :: 3501
    # n to sample
    n = floor(Int, run_config.mutation_rate)
    # Cache is opt-in. Layout mismatch follows the original decode path and
    # refreshes the slot before sampling; capture consumes no random numbers.
    if active_positions === nothing
        ind_progs = decode_with_output_nodes(ut_genome, meta_library, model_architecture, shared_inputs)
        active_nodes = get_active_nodes(ind_progs)
    else
        if !active_cache_matches(active_positions, ut_genome)
            ind_progs = decode_with_output_nodes(ut_genome, meta_library, model_architecture, shared_inputs)
            capture_active_nodes!(active_positions, ut_genome, ind_progs)
        end
        active_nodes = active_positions.positions
    end
    n_mutable_nodes = length(active_nodes)
    #
    if n > n_mutable_nodes
        @warn "A mutation of $n nodes was asked. But active graph only has $n_mutable_nodes. It will mutate $n_mutable_nodes"
        n = n_mutable_nodes
    end
    if n > 0
        if active_positions === nothing
            sampled_idx = sample_n(length(active_nodes), n)
            selected_nodes = active_nodes[sampled_idx]
        else
            sampled_idx = _sample_active_nodes!(active_positions, ut_genome, n)
            selected_nodes = active_positions.selected
        end
        @debug "Selected node(s) to mutate : $([n.id for n in selected_nodes])"
        new_material_mutation!(
            selected_nodes,
            meta_library,
            model_architecture,
            ut_genome,
            shared_inputs,
        )
        return selected_nodes, sampled_idx
    end
end

function new_material_mutation!(
        nodes::Vector{<:AbstractGenomeNode},
        meta_library::MetaLibrary,
        model_architecture::modelArchitecture,
        ut_genome::UTGenome,
        shared_inputs::SharedInput,
    )
    for node_to_mutate in nodes
        library = meta_library[node_to_mutate.y_position]
        new_material_mutation!(
            node_to_mutate,
            model_architecture,
            library,
            ut_genome,
            shared_inputs,
        )
    end
    return
end

function new_material_mutation!(
        node::CGPNode,
        model_architecture::modelArchitecture,
        library::Library,
        ut_genome::UTGenome,
        shared_inputs::SharedInput,
    )
    max_calls = 1000
    call_nb = 0
    prev = get_active_node_material(
        node,
        library,
        ut_genome,
        shared_inputs,
        model_architecture,
    )
    while !check_functionning_node(
            node,
            library,
            ut_genome,
            shared_inputs,
            model_architecture,
        ) ||
            get_active_node_material(
            node,
            library,
            ut_genome,
            shared_inputs,
            model_architecture,
        ) == prev
        mutate_one_element_from_node!(node)
        if call_nb > max_calls
            if isinteractive() && isdefined(Main, :infiltrate)
                Main.infiltrate(@__MODULE__, Base.@locals, @__FILE__, @__LINE__)
            end
            @warn "Can't find a correct mutation after $call_nb"
            @warn node_to_vector(node)
            @warn node.id
            node.node_material[1].value = 2 # CONVENTION BY DEFAULT
            @warn "Node didn't find a functionning call after $max_calls iterations. Current call : $call_nb"
            break
        end
        call_nb += 1
    end
    return
end
