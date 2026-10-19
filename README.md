# MAGE.jl

[![Documentation](https://img.shields.io/badge/docs-adf-4f81bd.svg)](https://camilodlt.github.io/MAGE.jl/adf/)
[![Build Status](https://github.com/camilodlt/MAGE.jl/actions/workflows/CI.yml/badge.svg?branch=adf)](https://github.com/camilodlt/MAGE.jl/actions/workflows/CI.yml?query=branch%3Aadf)

**Multimodal Adaptive Graph Evolution (MAGE)** extends Cartesian Genetic
Programming (CGP) to evolve programs that combine images, numbers, strings and
other data types in one graph. The Julia package is currently named **`UTCGP`**:
install MAGE, then import it with `using UTCGP`.

An evolved pipeline can blur an image, extract edges, reduce them to a scalar,
and use that scalar to control another image operation. Each type has its own
chromosome and library of operators; typed connections let these chromosomes
work together.

## Explore the documentation

The [manual for this branch](https://camilodlt.github.io/MAGE.jl/adf/) includes
an automatically generated list of **all exported bundles grouped by output
type**. The [main branch manual](https://camilodlt.github.io/MAGE.jl/dev/) is
also available.

| Start here | What you will find |
|:--|:--|
| [Getting started](https://camilodlt.github.io/MAGE.jl/adf/getting_started/) | A complete symbolic regression run, from inputs to callable Julia code |
| [Bundle catalogue](https://camilodlt.github.io/MAGE.jl/adf/libraries/catalogue/) | Every exported bundle, its operators and source descriptions |
| [Core image gallery](https://camilodlt.github.io/MAGE.jl/adf/libraries/image_core/) | Actual results of filters, morphology, thresholds and segmentation |
| [Image libraries](https://camilodlt.github.io/MAGE.jl/adf/libraries/image/) | Image types and links to specialised operator galleries |
| [3D volumes](https://camilodlt.github.io/MAGE.jl/adf/libraries/volumes/) | Interactive slice viewers for volume operators |
| [Timing methodology](https://camilodlt.github.io/MAGE.jl/adf/timings/) | Measurement details, unusual inputs and scaling limits |

Gallery pages show the results of real operator calls and finish with warmed
execution times and allocation measurements. Timings depend on the machine,
input and load; the slowest observed sample is not a worst-case bound.

## Install

Requires **Julia 1.11.7 or later**. CI tests Julia 1.11.7 and 1.12; documentation
builds use Julia 1.12. `SearchNetworks` is installed from its repository before
MAGE because it is a package dependency.

```julia
using Pkg
Pkg.add(url="https://github.com/camilodlt/SearchNetworks.jl")
Pkg.add(url="https://github.com/camilodlt/MAGE.jl", rev="adf")
using UTCGP
```

Omit `rev="adf"` to install the repository's default branch instead.

## Build your first genome

Choose the operators, declare the types, and create a graph. This example uses
two floating-point inputs and one floating-point output:

```julia
using UTCGP

library = Library(UTCGP.get_sr_float_bundles())
meta_library = MetaLibrary([library])
architecture = modelArchitecture(
    [Float64, Float64],  # input types
    [1, 1],             # input chromosome assignments
    [Float64],          # chromosome types
    [Float64],          # output types
    [1],                # output chromosome assignments
)
nodes = nodeConfig(30, 1, 2, 2)  # nodes, connection temperature, arity, input count

inputs, genome = make_evolvable_utgenome(architecture, meta_library, nodes)
initialize_genome!(genome)
correct_all_nodes!(genome, architecture, meta_library, inputs)
```

This creates an initial genome. Follow
[Getting started](https://camilodlt.github.io/MAGE.jl/adf/getting_started/) to
supply training data and a loss function, run evolution, and compile the winning
program into readable, callable Julia code.

## What is included

- **Typed programs:** genome construction, decoding, evaluation and compilation.
- **Composable libraries:** `FunctionBundle`, `Library` and `MetaLibrary`, with
  scalar, string, list, 2D image, RGB and 3D volume operators.
- **Evolution:** mutation, crossover, genetic algorithms, MAP-Elites and NSGA-II.
- **GraphMAGE:** Monte-Carlo graph search over program behaviours.
- **Library growth:** automatically defined functions and validated generated
  functions.
- **Experiment tooling:** callbacks, endpoints, tracking and search networks.

See [premade libraries](src/libraries/pre_made_libraries.jl) for ready-to-use
operator collections, or assemble bundles for your own task.

## Develop and build the docs

From a checkout, prepare the package and documentation environments:

```sh
julia --project=. -e 'using Pkg; Pkg.add(url="https://github.com/camilodlt/SearchNetworks.jl"); Pkg.instantiate()'
julia --project=docs -e 'using Pkg; Pkg.develop([PackageSpec(url="https://github.com/camilodlt/SearchNetworks.jl"), PackageSpec(path=pwd())]); Pkg.instantiate()'

JULIA_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 nice -n 15 julia --project=. -e 'using Pkg; Pkg.test()'
JULIA_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 nice -n 15 julia --project=docs docs/test/runtests.jl
JULIA_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 nice -n 15 julia --project=docs docs/make.jl
```

Open `docs/build/index.html` after the build. Documenter runs the examples and
doctests, checks documented exports and references, and enforces page size
limits (the generated catalogue has a size exemption). Generated HTML and gallery
assets are published to `gh-pages`; they are not committed to the source branch.
CI publishes `main` to `/dev/` and `adf` to `/adf/`.

For adding operators or maintaining faithful galleries, read the
[documentation contribution guide](docs/CONTRIBUTING.md).

## Publications

Papers defining MAGE:

- De La Torre, C., Lavinas, Y., Cortacero, K., Luga, H., Wilson, D. G., and Cussat-Blanc, S. "Multimodal Adaptive Graph Evolution." GECCO 2024. https://dl.acm.org/doi/abs/10.1145/3638530.3654347
- De La Torre, C., Lavinas, Y., Cortacero, K., Luga, H., Wilson, D. G., and Cussat-Blanc, S. "Multimodal Adaptive Graph Evolution for Program Synthesis." PPSN 2024. https://link.springer.com/chapter/10.1007/978-3-031-70055-2_19

Papers using MAGE for computer vision:

- De La Torre, C., Nadizar, G., Lavinas, Y., Schwob, R., Franchet, C., Luga, H., Wilson, D. G., and Cussat-Blanc, S. "Evolution of Inherently Interpretable Visual Control Policies." GECCO 2025. https://dl.acm.org/doi/abs/10.1145/3712256.3726332
- De La Torre, C., Nadizar, G., Lavinas, Y., Schwob, R., Franchet, C., Luga, H., Wilson, D. G., and Cussat-Blanc, S. "Evolved and Transparent Pipelines for Biomedical Image Classification." EuroGP 2025. https://link.springer.com/chapter/10.1007/978-3-031-89991-1_11
