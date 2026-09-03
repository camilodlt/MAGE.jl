############################
# GraphMAGE: visualization
############################

"""
    reward_color(frac)

Hex fill color interpolated from red (`frac = 0`, worst reward) to green
(`frac = 1`, best reward).
"""
function reward_color(frac::Float64)::String
    frac = clamp(frac, 0.0, 1.0)
    r = round(Int, 255 * (1 - frac))
    g = round(Int, 255 * frac)
    return "#" * uppercase(string(r; base = 16, pad = 2)) * uppercase(string(g; base = 16, pad = 2)) * "40"
end

"""
    plot_graphmage_archive(archive, path)

Write a Graphviz `.dot` file for `archive`'s graph to `path`, nodes labeled
with their mean reward and visit count, colored by mean reward (greener is
better). Roots (`archive.root_labels`) are drawn as squares, every other node
as an ellipse, so the independent starting trees are visually distinguishable
from GA-discovered offspring. Rendering to SVG/PNG needs a system `graphviz`
install; open the `.dot` file with any Graphviz viewer, or run
`dot -Tpng path -o path.png` if one is installed.
"""
function plot_graphmage_archive(archive::GraphMAGEArchive, path::AbstractString)::String
    graph = archive.graph
    labels_ = all_node_labels(graph)
    roots = Set{String}(archive.root_labels)
    @info "GraphMAGE: plotting archive" path n_nodes = length(labels_) n_roots = length(roots)

    rewards = Float64[]
    for label in labels_
        node = get_node(graph, label)
        node.visits > 0 && push!(rewards, node.reward_sum / node.visits)
    end
    lo, hi = isempty(rewards) ? (0.0, 1.0) : extrema(rewards)
    span = hi - lo
    span = span <= 0 ? 1.0 : span

    g = GraphvizDotLang.digraph()
    for label in labels_
        node = get_node(graph, label)
        mean_reward = node.visits > 0 ? node.reward_sum / node.visits : NaN
        frac = node.visits > 0 ? (mean_reward - lo) / span : 0.0
        node_label = "$(label[1:min(8, end)])\nvisits=$(node.visits)\nreward=$(round(mean_reward, digits = 4))\ntrain=$(round(node.train_fitness, digits = 4))"
        shape = label in roots ? "square" : "ellipse"
        g = g |> GraphvizDotLang.node(label; label = node_label, style = "filled", shape = shape, fillcolor = reward_color(frac))
    end
    for parent in labels_
        for child in child_labels(graph, parent)
            g = g |> GraphvizDotLang.edge(parent, child)
        end
    end

    open(path, "w") do io
        write(io, string(g))
    end
    return path
end
