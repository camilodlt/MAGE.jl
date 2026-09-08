```@meta
CurrentModule = UTCGP
```

# MAGE.jl

MAGE — **M**ultimodal **A**daptive **G**raph **E**volution — is a type-aware
extension of Cartesian Genetic Programming (CGP) for evolving programs that mix
several data types in one graph.

!!! note "Package name"
    The Julia package that implements MAGE is still called `UTCGP`. Renaming it
    is a separate migration, so throughout this manual the module is `UTCGP`
    while the method is MAGE.

    ```julia
    using UTCGP
    ```

## What makes it different

A classic CGP genome is one row of nodes producing one type. A MAGE genome is a
[`UTGenome`](@ref): **one chromosome per type**, all reading from the same
[`SharedInput`](@ref). A node in the float chromosome can connect to a node in
the image chromosome, because each connexion carries a `TYPE` element saying
which chromosome it reads from.

That single change buys three things:

- **Type-safe mutation.** Bounds are computed so that a mutated connexion is
  still legal. A program is well-typed by construction, not by trial and error.
- **Multimodality.** One evolved program can blur an image, run a Sobel
  operator, reduce the result to a scalar, and feed that scalar back as the
  parameter of another image operator.
- **Modularity.** Each output has its own chromosome, so adding an output type
  does not disturb the others.

MAGE has been applied to symbolic regression, program synthesis, image
classification, image segmentation and policy search.

## A minimal run

```julia
using UTCGP

lib          = Library(UTCGP.get_sr_float_bundles())     # what the program may call
ml           = MetaLibrary([lib])                        # one library per chromosome
model_arch   = modelArchitecture([Float64, Float64], [1, 1], [Float64], [Float64], [1])
node_config  = nodeConfig(30, 1, 2, 2)                    # 30 nodes, arity 2, 2 inputs

shared_inputs, ut_genome = make_evolvable_utgenome(model_arch, ml, node_config)
initialize_genome!(ut_genome)
correct_all_nodes!(ut_genome, model_arch, ml, shared_inputs)
```

The full walkthrough, including the loss function and the search loop, is in
[Getting Started](@ref).

## Reading order

| Page | What it covers |
|:--|:--|
| [Getting Started](@ref) | build a model and run a search end to end |
| [Symbolic Regression](@ref) | a complete, runnable example |
| [Model Config](@ref) | `modelArchitecture`, `nodeConfig`, run configurations |
| [Genome and Nodes](@ref) | the representation: elements, nodes, chromosomes |
| [Libraries](@ref) | bundles, libraries, casters, premade collections |
| [Bundle Catalogue](@ref) | every operator MAGE ships, generated from the source |
| [Programs](@ref) | decoding a genome, evaluating and compiling programs |
| [Mutations](@ref) | the mutation operators and how they differ |
| [Crossover](@ref) | the crossover operator |
| [Fitters and Callbacks](@ref) | `fit`, `fit_ga`, and the callback pipeline |
| [Endpoints and Tracking](@ref) | stating a problem, and recording a run |
| [Automatically Defined Functions](@ref) | promoting subprograms to reusable operators |
| [GraphMAGE](@ref) | Monte-Carlo graph search over program behaviours |
| [Generated Functions](@ref) | growing new operators with an LLM |
| [Search Networks](@ref) | recording the search as a graph |
| [Package Extensions](@ref) | optional CMA-ES and LLM backends |
| [API Index](@ref) | everything, alphabetically |

## Publications

Defining MAGE:

- De La Torre, C., Lavinas, Y., Cortacero, K., Luga, H., Wilson, D. G., and
  Cussat-Blanc, S. *Multimodal Adaptive Graph Evolution.* GECCO 2024.
  [doi](https://dl.acm.org/doi/abs/10.1145/3638530.3654347)
- De La Torre, C., Lavinas, Y., Cortacero, K., Luga, H., Wilson, D. G., and
  Cussat-Blanc, S. *Multimodal Adaptive Graph Evolution for Program Synthesis.*
  PPSN 2024.
  [doi](https://link.springer.com/chapter/10.1007/978-3-031-70055-2_19)

Using MAGE for computer vision:

- De La Torre, C., Nadizar, G., Lavinas, Y., Schwob, R., Franchet, C., Luga, H.,
  Wilson, D. G., and Cussat-Blanc, S. *Evolution of Inherently Interpretable
  Visual Control Policies.* GECCO 2025.
  [doi](https://dl.acm.org/doi/abs/10.1145/3712256.3726332)
- De La Torre, C., Nadizar, G., Lavinas, Y., Schwob, R., Franchet, C., Luga, H.,
  Wilson, D. G., and Cussat-Blanc, S. *Evolved and Transparent Pipelines for
  Biomedical Image Classification.* EuroGP 2025.
  [doi](https://link.springer.com/chapter/10.1007/978-3-031-89991-1_11)
