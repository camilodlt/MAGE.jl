```@meta
CurrentModule = UTCGP
```

# GraphMAGE

GraphMAGE is a Monte-Carlo *graph* search over program **behaviours** rather
than over genomes. Instead of one population evolving in place, it grows a DAG
whose vertices are distinct behaviours and repeatedly picks one to expand with a
short GA run.

```@contents
Pages = ["graphmage.md"]
Depth = 2
```

## Why a graph

Two ideas drive it.

**A node is a behaviour, not a genome.** A vertex is identified by a hash of the
program's outputs on a fixed probe set. Two individuals found independently that
compute the same thing collapse into the same vertex — which is also why the
structure is a DAG rather than a tree: a behaviour can have several parents.

**A child searches a smaller library.** Each vertex records which operators its
own decoded program actually calls. When a vertex is expanded, its inner GA only
sees the union of its parents' used functions
([`subset_metalibrary`](@ref), [`remap_genome_to_library!`](@ref)). The operator
set therefore narrows and refocuses as the search descends, instead of staying
at the full library forever.

The loop is the usual UCT one — select, expand, backpropagate — with
backpropagation aware that a node may have several parents.

## Running a search

```@autodocs
Modules = [UTCGP]
Pages = ["graphmage/types.jl"]
```

```@autodocs
Modules = [UTCGP]
Pages = ["graphmage/run.jl"]
```

!!! note "Budget"
    Set `time_budget_minutes` and leave `n_expansions` effectively unreachable
    to run for a wall-clock duration. The loop then finishes the expansion it is
    in and exits cleanly, so the final checkpoint and validation still happen —
    which an external timeout would cut off.

GraphMAGE knows nothing about your loss: it is handed a `fitter_fn` following
the standard GA-fitter calling convention and never inspects it.

## Selection and expansion

```@autodocs
Modules = [UTCGP]
Pages = ["graphmage/selection.jl", "graphmage/ucb.jl", "graphmage/expansion.jl", "graphmage/backprop.jl"]
```

## Behaviours

```@autodocs
Modules = [UTCGP]
Pages = ["graphmage/behavior.jl"]
```

## Restricted libraries

```@autodocs
Modules = [UTCGP]
Pages = ["graphmage/library_subset.jl"]
```

## The graph

```@autodocs
Modules = [UTCGP]
Pages = ["graphmage/graph_core.jl"]
```

## Evaluation, checkpointing and merging

```@autodocs
Modules = [UTCGP]
Pages = ["graphmage/eval_val.jl", "graphmage/checkpoint.jl", "graphmage/merge.jl"]
```

Merging lets several archives grown independently — an island model — be folded
into one graph, with behaviours found by more than one island collapsing into a
single vertex.

## Visualising

```@autodocs
Modules = [UTCGP]
Pages = ["graphmage/visualize.jl"]
```
