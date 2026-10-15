"""
Reusable ordered active-node positions for one population/pool slot. Row zero is
reserved for output markers (outputs are currently excluded by get_active_nodes).
The stamp contains every chromosome length followed by the output count.
Buffers grow on first use or layout growth; warm capture/copy allocate nothing.
"""
mutable struct ActiveNodeCacheEntry
    positions::Vector{NTuple{2,Int32}}
    layout::Vector{Int}
    seen::Vector{Bool}
    selected::Vector{AbstractGenomeNode}
    valid::Bool
end
ActiveNodeCacheEntry() = ActiveNodeCacheEntry(NTuple{2,Int32}[], Int[], Bool[], AbstractGenomeNode[], false)

"""Per-slot cache; use separate instances for the two sides of a genome pool.
Entries must be invalidated after any genome edit, including output mutation.
No genome identity is retained: callers own slot identity and exact-copy tracking.
Not thread safe; each concurrently mutated slot needs its own entry.
"""
struct ActiveNodeCache
    entries::Vector{ActiveNodeCacheEntry}
end
ActiveNodeCache(n::Integer) = ActiveNodeCache([ActiveNodeCacheEntry() for _ in 1:n])
Base.getindex(c::ActiveNodeCache, i::Integer) = c.entries[i]

# Direct coordinates, never a genome search. starting_point supports arbitrary
# input offsets and chromosomes of different lengths.
@inline function active_node_position(node::AbstractGenomeNode, genome::UTGenome)
    return _active_node_position(node, genome.genomes)
end
@inline function _active_node_position(node::AbstractGenomeNode, chromosomes::Vector{C}) where {C}
    row = node.y_position
    return (Int32(row), Int32(node.x_position - (chromosomes[row]::SingleGenome).starting_point))
end

"""Return false on invalid entries or ANY chromosome/output-count mismatch."""
function active_cache_matches(e::ActiveNodeCacheEntry, genome::UTGenome)
    e.valid || return false
    return _active_cache_matches(e, genome.genomes, length(genome.output_nodes))
end
function _active_cache_matches(e, chromosomes::Vector{C}, outputs::Int) where {C}
    length(e.layout) == length(chromosomes) + 1 || return false
    e.layout[end] == outputs || return false
    for row in eachindex(chromosomes)
        e.layout[row] == length((chromosomes[row]::SingleGenome).chromosome) || return false
    end
    return true
end
invalidate_active_nodes!(e::ActiveNodeCacheEntry) = (e.valid = false; e)

"""
    capture_active_nodes!(entry, genome, programs::IndividualPrograms)

Capture evaluation's DEFAULT decode, in program/operation traversal order, with
first-occurrence semantics identical to get_active_nodes. A flattened seen mask
uses prefix lengths, not a fixed chromosome width. Never captures node references.
"""
function capture_active_nodes!(e::ActiveNodeCacheEntry, genome::UTGenome, programs::IndividualPrograms)
    e.valid = false
    return _capture_active_nodes!(e, genome.genomes, length(genome.output_nodes), programs.programs)
end
function _capture_active_nodes!(e, chromosomes::Vector{C}, outputs::Int, programs::Vector{P}) where {C,P}
    rows = length(chromosomes)
    resize!(e.layout, rows + 1)
    total = 0
    for row in 1:rows
        e.layout[row] = length((chromosomes[row]::SingleGenome).chromosome)
        total += e.layout[row]
    end
    e.layout[end] = outputs
    resize!(e.seen, total)
    fill!(e.seen, false)
    # Reserve the layout's maximum active count, so a later, larger active
    # graph in the SAME layout cannot allocate during capture.
    sizehint!(e.positions, total)
    empty!(e.positions)
    _capture_programs!(e, chromosomes, programs)
    e.valid = true
    return e
end

"""Copy parent metadata when its genome is copied into a child slot.
Source and destination may coincide; use distinct caches across generations to
avoid overwriting a parent entry before all of its children have been copied.
"""
function copy_active_nodes!(dest::ActiveNodeCacheEntry, src::ActiveNodeCacheEntry)
    dest === src && return dest
    dest.valid = false
    # A copied slot is ready for any active graph in this layout on evaluation,
    # not merely for the current parent's active count.
    capacity = 0
    for row in 1:(length(src.layout) - 1)
        capacity += src.layout[row]
    end
    sizehint!(dest.positions, capacity)
    resize!(dest.positions, length(src.positions))
    copyto!(dest.positions, src.positions)
    resize!(dest.layout, length(src.layout))
    copyto!(dest.layout, src.layout)
    dest.valid = src.valid
    return dest
end

"""Expensive diagnostic: assert stamp AND ordered equality against fresh decode."""
function check_active_nodes(e::ActiveNodeCacheEntry, genome::UTGenome, ml::MetaLibrary,
        arch::modelArchitecture, shared::SharedInput)
    @assert active_cache_matches(e, genome) "Missing or stale active-node cache"
    nodes = get_active_nodes(decode_with_output_nodes(genome, ml, arch, shared))
    @assert length(nodes) == length(e.positions)
    for i in eachindex(nodes)
        @assert active_node_position(nodes[i], genome) == e.positions[i]
    end
    return true
end

# Return only the sampler's existing result vector; selected nodes live in the
# entry. This avoids adding a temporary tuple to the mutation preparation path.
function _sample_active_nodes!(e::ActiveNodeCacheEntry, genome::UTGenome, n::Int)
    sampled_idx = sample_n(length(e.positions), n)
    _materialize_active_nodes!(e, genome, sampled_idx)
    invalidate_active_nodes!(e) # before node mutation, including on exceptions
    return sampled_idx
end

# Only sampled nodes are resolved; this part is allocation-free after warm-up.
function _materialize_active_nodes!(e::ActiveNodeCacheEntry, genome::UTGenome, sampled_idx::Vector{Int})
    return _materialize_active_nodes!(e, genome.genomes, sampled_idx)
end
function _materialize_active_nodes!(e, chromosomes::Vector{C}, sampled_idx::Vector{Int}) where {C}
    resize!(e.selected, length(sampled_idx))
    for i in eachindex(sampled_idx)
        row, col = e.positions[sampled_idx[i]]
        e.selected[i] = (chromosomes[Int(row)]::SingleGenome).chromosome[Int(col)]
    end
    return e.selected
end

# MAGE stores existentially typed vectors. The barriers here and above keep
# concrete chromosome/program element types throughout hot loops. In particular,
# indexing Vector{SingleGenome} through an abstract vector otherwise boxes each
# immutable SingleGenome, even though individual CGP nodes are mutable references.
function _capture_programs!(e, chromosomes::Vector{C}, programs::Vector{P}) where {C,P}
    for program in programs
        _capture_operations!(e, chromosomes, program.program)
    end
    return nothing
end
function _capture_operations!(e, chromosomes::Vector{C}, operations::Vector{O}) where {C,O}
    for operation in operations
        node = get_active_node(operation)
        isnothing(node) && continue
        _capture_position!(e, chromosomes, node)
    end
    return nothing
end
function _capture_position!(e, chromosomes::Vector{C}, node::AbstractGenomeNode) where {C}
    pos = _active_node_position(node, chromosomes)
    row, col = Int(pos[1]), Int(pos[2])
    @assert 1 <= row < length(e.layout) && 1 <= col <= e.layout[row]
    index = col
    for previous in 1:(row - 1)
        index += e.layout[previous]
    end
    if !e.seen[index]
        push!(e.positions, pos)
        e.seen[index] = true
    end
    return nothing
end
