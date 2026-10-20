```@meta
CurrentModule = UTCGP
```

# Search Networks

A search network (STN) is the whole search recorded as a graph: vertices are
individuals — under whichever notion of "same individual" you choose — and edges
are the transitions between them. It answers questions a loss curve cannot:
how much of the run was spent revisiting known solutions, how many distinct
behaviours were reached, where the search plateaued.

Networks are written to a DuckDB database through
[SearchNetworks.jl](https://github.com/camilodlt/SearchNetworks.jl).

```@contents
Pages = ["search_networks.md"]
Depth = 2
```

## What counts as one node

The choice of hasher decides the resolution of the recording — this is the main
knob:

| Hasher | Same node when... |
|:--|:--|
| `sn_genotype_hasher` | the genomes are identical, dormant material included |
| `sn_softphenotype_hasher` | the decoded programs are identical |
| [`sn_strictphenotype_hasher`](@ref) | the *active* parts of the decoded programs agree |
| [`sn_behavior_hasher`](@ref) | the programs produce the same outputs on a fixed probe set |

They form a ladder from finest to coarsest. A genotype network shows every
silent mutation; a behaviour network shows only genuine discoveries. The
`_except_last` variants exclude the parent, which is what you want when the last
individual of a population is the carried-over elite.

## Writing a network

```@autodocs
Modules = [UTCGP]
Pages = ["search_network/sn_types.jl", "search_network/sn_callbacks.jl", "search_network/sn_writer_init_utils.jl"]
```

## Node hashers

```@autodocs
Modules = [UTCGP]
Pages = ["search_network/node_hashers.jl", "search_network/hashers.jl"]
```

## Edge properties

```@autodocs
Modules = [UTCGP]
Pages = ["search_network/edge_prop_getters.jl"]
```

## Utilities

```@autodocs
Modules = [UTCGP]
Pages = ["search_network/utils.jl"]
```
