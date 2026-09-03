############################
# GraphMAGE: island merging
############################

"""
    merge_graphmage_archives(archives) -> GraphMAGEArchive

Merge multiple GraphMAGE archives (island runs) into one. All archives must
share the same probe set and behavior rounding -- otherwise their behavior
hashes are not comparable and this throws. Nodes are unioned by
`behavior_hash`: on collision, `visits`/`reward_sum` are summed (a behavior
independently discovered by two islands has genuinely been observed twice)
and the first-encountered genome is kept, never replaced, matching the
in-run collision policy. Edges are unioned via the same cycle-guarded
insertion used during search, so a cycle introduced by combining two islands'
edges is dropped with a warning rather than corrupting the graph.
"""
function merge_graphmage_archives(archives::Vector{GraphMAGEArchive})::GraphMAGEArchive
    @assert !isempty(archives) "GraphMAGE: nothing to merge"
    length(archives) == 1 && return archives[1]

    base = archives[1]
    for other in archives[2:end]
        @assert other.probes == base.probes "GraphMAGE: cannot merge archives with different probe sets"
        @assert other.config.behavior_round_digits == base.config.behavior_round_digits "GraphMAGE: cannot merge archives with different behavior rounding"
    end

    merged_graph = new_graphmage_graph()
    for archive in archives
        for label in all_node_labels(archive.graph)
            other_node = get_node(archive.graph, label)
            if haskey(merged_graph, label)
                existing = get_node(merged_graph, label)
                existing.visits += other_node.visits
                existing.reward_sum += other_node.reward_sum
                if isnothing(existing.val_fitness)
                    existing.val_fitness = other_node.val_fitness
                end
                existing.expanded = existing.expanded || other_node.expanded
            else
                add_node!(merged_graph, deepcopy(other_node))
            end
        end
    end

    merged_roots = String[]
    for archive in archives
        for parent in all_node_labels(archive.graph)
            for child in child_labels(archive.graph, parent)
                add_edge_checked!(merged_graph, parent, child)
            end
        end
        for r in archive.root_labels
            r in merged_roots || push!(merged_roots, r)
        end
    end

    merged_expansions = sum(a.expansions_done for a in archives)
    @info "GraphMAGE: merged archives" n_archives = length(archives) n_nodes = length(all_node_labels(merged_graph)) n_roots = length(merged_roots)
    return GraphMAGEArchive(merged_graph, merged_roots, base.config, base.probes, merged_expansions)
end
