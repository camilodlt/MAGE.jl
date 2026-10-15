```@meta
CurrentModule = UTCGP
```

# Mutations

Mutation in MAGE never has to repair anything after the fact. Every
[`CGPElement`](@ref) carries the range it may take, so redrawing an allele
inside its bounds yields a genome that is still legal — the feed-forward
property and the chromosome bounds hold by construction. What the operators
differ on is *how much* to redraw and *where*.

```@contents
Pages = ["mutations.md"]
Depth = 2
```

## Choosing an operator

| Operator | Callback | How much changes |
|:--|:--|:--|
| [`standard_mutate!`](@ref) | [`default_mutation_callback`](@ref) | each allele independently, with probability `mutation_rate` |
| [`numbered_mutation!`](@ref) | [`default_numbered_mutation_callback`](@ref) | a fixed number of *active* nodes |
| [`new_material_mutation!`](@ref) | [`default_numbered_new_material_mutation_callback`](@ref) | same, but retried until the program really differs |
| [`free_mutate!`](@ref) | [`default_free_mutation_callback`](@ref) | as standard, without maintaining type-correctness |

The usual default is `new_material_mutation!`. A CGP mutation is often silent —
it lands on dormant material, or resamples a node to an equivalent one — and a
silent mutation costs a full evaluation while producing a duplicate of the
parent. Retrying until the *active* material changes spends the budget on
genuinely new programs.

Note the consequence for `mutation_rate`: the numbered operators read it as a
count, so a rate of `1.1` means "one node" and values above `1.0` are normal.

## Standard mutation

Per-allele mutation. Each element of each node is redrawn with probability
`run_config.mutation_rate`, and the node is then checked against its function so
that connexions still type-check.

```@autodocs
Modules = [UTCGP]
Pages = ["mutations/standard_mutation.jl"]
```

## Numbered mutation

Instead of a probability per allele, a *number* of active nodes is sampled and
each is mutated. The amount of change per individual then does not drift as the
genome grows.

```@autodocs
Modules = [UTCGP]
Pages = ["mutations/numbered_mutation.jl"]
```

## New-material mutation

The numbered operator, retried per node until the node's decoded material
actually changes (up to 1000 attempts).

```@autodocs
Modules = [UTCGP]
Pages = ["mutations/new_material_mutation.jl"]
```

## Free mutation

Mutation that does not maintain type-correctness. It must be paired with the
free decoder, [`default_free_decoding_callback`](@ref).

```@autodocs
Modules = [UTCGP]
Pages = ["mutations/mt_mutation.jl"]
```

## Correcting a genome

Used after building a genome, and by [`correct_all_nodes_callback`](@ref)
whenever something upstream may have left a node inconsistent — a free
mutation, or a library swapped under an existing genome.

```@autodocs
Modules = [UTCGP]
Pages = ["mutations/correct_all_nodes.jl"]
```

## Utilities

The building blocks the operators above are made of. `get_active_nodes` is also
what tells the search which part of a genome is expressed.

```@autodocs
Modules = [UTCGP]
Pages = ["mutations/utils_mutation.jl"]
```
