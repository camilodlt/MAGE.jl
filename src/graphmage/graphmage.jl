############################################################################
# GraphMAGE: Monte Carlo Graph Search over program behaviors
############################################################################
#
# A generalization of the tree-based MCTS-over-genomes search (see
# ../../../MAGE_MCTS) to a true DAG: graph nodes are unique program
# *behaviors* (not genomes), so equivalent programs discovered independently
# collapse into one node with multiple parents; a node's GA expansion is
# seeded from all of its parents and searches only the union of functions
# they actually used, so the operator library a child sees shrinks/refocuses
# instead of staying at the full set every time.
#
# Files, by topic:
#   types.jl           - GraphMAGENode / GraphMAGEConfig / GraphMAGEArchive / GraphMAGERunContext
#   graph_core.jl       - MetaGraphsNext wrapper: add_node!, add_edge_checked! (cycle-guarded), label helpers
#   ucb.jl              - the UCB1 formula and its optional exploration-constant annealing
#   selection.jl        - UCT descent from root(s) to the node to expand
#   backprop.jl         - multi-parent-aware backpropagation (BFS, dedup on diamonds)
#   library_subset.jl   - used-function extraction, per-node restricted MetaLibrary construction,
#                         and genome <-> library index remapping
#   behavior.jl         - fixed probe set + behavior hashing (rounded outputs, SHA-256)
#   expansion.jl        - expand_node!: the actual per-node GA run, orchestrating all of the above
#   eval_val.jl         - archive-wide, hyperthreaded raw-output evaluation (generic; endpoint-agnostic)
#   checkpoint.jl        - JLD2 save/load of a full archive
#   merge.jl            - island-merge multiple archives into one
#   visualize.jl        - Graphviz .dot export
#   run.jl              - run_graphmage: the top-level select -> expand -> backprop loop
#
# GraphMAGE's core here has no knowledge of any particular endpoint, loss, or
# time-penalty convention: `expand_node!` and `run_graphmage` are handed a
# `fitter_fn` (any function matching the standard UTCGP GA-fitter calling
# convention) by the caller and never inspect it. The problem-specific,
# time-aware, population-graph-evaluator fitter this project actually uses
# lives in the calling repo (MAGENetRunner's `utils/utils_populationgraph.jl`),
# next to the endpoint types it dispatches on.
############################################################################

include("types.jl")
include("graph_core.jl")
include("ucb.jl")
include("selection.jl")
include("backprop.jl")
include("library_subset.jl")
include("behavior.jl")
include("expansion.jl")
include("eval_val.jl")
include("checkpoint.jl")
include("merge.jl")
include("visualize.jl")
include("run.jl")
