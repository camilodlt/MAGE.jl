############################
# GraphMAGE: backpropagation
############################

"""
    backpropagate!(archive, node_label, reward) -> Int

Increment `visits`/`reward_sum` on `node_label` and every one of its
ancestors (BFS upward over in-neighbors), each exactly once. This is the
direct multi-parent generalization of single-parent-chain MCTS backprop: a
node reachable from `node_label` via two different parent chains (a diamond
in the DAG) is only updated once per call, via a visited set, so the same
observation is never double-counted. Returns how many nodes were updated.
"""
function backpropagate!(archive::GraphMAGEArchive, node_label::String, reward::Float64)::Int
    graph = archive.graph
    visited = Set{String}()
    queue = String[node_label]
    while !isempty(queue)
        label = popfirst!(queue)
        label in visited && continue
        push!(visited, label)
        node = get_node(graph, label)
        node.visits += 1
        node.reward_sum += reward
        for parent in parent_labels(graph, label)
            parent in visited || push!(queue, parent)
        end
    end
    return length(visited)
end
