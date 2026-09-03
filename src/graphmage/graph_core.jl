############################
# GraphMAGE: graph plumbing
############################

"""
    new_graphmage_graph()

An empty directed `MetaGraphsNext.MetaGraph` keyed by behavior-hash `String`
labels, holding `GraphMAGENode` vertex data and no edge data.
"""
function new_graphmage_graph()
    return MetaGraphsNext.MetaGraph(
        Graphs.DiGraph();
        label_type = String,
        vertex_data_type = GraphMAGENode,
        edge_data_type = Nothing,
    )
end

function add_node!(graph, node::GraphMAGENode)::String
    graph[node.behavior_hash] = node
    return node.behavior_hash
end

function get_node(graph, label::String)::GraphMAGENode
    return graph[label]
end

function all_node_labels(graph)::Vector{String}
    return collect(MetaGraphsNext.labels(graph))
end

function parent_labels(graph, label::String)::Vector{String}
    return collect(MetaGraphsNext.inneighbor_labels(graph, label))
end

function child_labels(graph, label::String)::Vector{String}
    return collect(MetaGraphsNext.outneighbor_labels(graph, label))
end

"""
    is_ancestor_or_self(graph, target_label, from_label)

`true` iff `target_label` can be reached by walking upward (via in-neighbors)
from `from_label`, or is `from_label` itself. Used to guard against creating
cycles when a GA run rediscovers one of its own ancestors' behavior.
"""
function is_ancestor_or_self(graph, target_label::String, from_label::String)::Bool
    target_label == from_label && return true
    visited = Set{String}([from_label])
    queue = String[from_label]
    while !isempty(queue)
        current = popfirst!(queue)
        for parent in parent_labels(graph, current)
            parent == target_label && return true
            if !(parent in visited)
                push!(visited, parent)
                push!(queue, parent)
            end
        end
    end
    return false
end

"""
    add_edge_checked!(graph, parent_label, child_label) -> Bool

Add a `parent_label -> child_label` edge unless it is a self-loop, already
exists, or would create a cycle (`child_label` is already an ancestor of
`parent_label`) -- in which case it is skipped with a `@warn` instead of
erroring. Returns whether a new edge was actually added.
"""
function add_edge_checked!(graph, parent_label::String, child_label::String)::Bool
    if parent_label == child_label
        @warn "GraphMAGE: skipping self-loop edge" node = parent_label
        return false
    end
    if haskey(graph, parent_label, child_label)
        return false
    end
    if is_ancestor_or_self(graph, child_label, parent_label)
        @warn "GraphMAGE: skipping edge that would create a cycle" parent = parent_label child = child_label
        return false
    end
    graph[parent_label, child_label] = nothing
    return true
end
