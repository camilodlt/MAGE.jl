############################
# GraphMAGE: selection
############################

"""
    forced_exploration_score(node, parent_visits, c) -> Float64

`Inf` if `node` has never itself been expanded, else its ordinary UCB score.

Forced exploration must key off `expanded`, not `visits == 0`: a node's
`visits` counter can be incremented by `backpropagate!` without the node ever
having been the target of `expand_node!` -- e.g. a different lineage
elsewhere in the graph rediscovers this node's exact behavior, which bumps
its `visits`/`reward_sum` (see `backpropagate!`) even though this node's own
subtree has never been searched. Keying `Inf` off `visits == 0` in that case
would let a node quietly lose its guaranteed first expansion forever, once
some unrelated part of the graph happens to touch it first.
"""
function forced_exploration_score(node::GraphMAGENode, parent_visits::Int, c::Float64)::Float64
    node.expanded && return ucb_score(node, parent_visits, c)
    return Inf
end

"""
    select_node(archive, c) -> String

Pick the node to expand next via UCT descent.

Multiple roots are handled with a virtual super-root: the first choice is an
argmax over `archive.root_labels` using the total number of expansions so far
as the "parent visits" term. From there, descent repeatedly compares:
- if the current node is not yet expanded, it is the selection (stop here);
- otherwise, if it has no children, it is a dead end and remains eligible for
  re-expansion (stop here too -- there is nothing else to descend into);
- otherwise, descend to the best-UCB child and repeat.

This is standard UCT tree descent generalized to a DAG: a node's `visits`
already aggregate every path that reached it, so descent only ever needs the
node currently being stood on to evaluate its children's UCB scores. Every
comparison uses `forced_exploration_score`, not `ucb_score` directly, so a
node that has accrued visits purely from being rediscovered elsewhere (see
its docstring) still gets its guaranteed first expansion.
"""
function select_node(archive::GraphMAGEArchive, c::Float64)::String
    graph = archive.graph
    roots = archive.root_labels
    @assert !isempty(roots) "GraphMAGE: archive has no roots to select from"

    virtual_parent_visits = max(archive.expansions_done, 1)
    current = argmax(label -> forced_exploration_score(get_node(graph, label), virtual_parent_visits, c), roots)

    while true
        node = get_node(graph, current)
        node.expanded || return current
        children = child_labels(graph, current)
        isempty(children) && return current
        current = argmax(label -> forced_exploration_score(get_node(graph, label), node.visits, c), children)
    end
end
