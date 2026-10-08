# MAGE.jl

[![Docs Dev](https://img.shields.io/badge/docs-dev-4f81bd.svg)](https://camilodlt.github.io/MAGE.jl/dev/)
[![Build Status](https://github.com/camilodlt/MAGE.jl/actions/workflows/CI.yml/badge.svg?branch=main)](https://github.com/camilodlt/MAGE.jl/actions/workflows/CI.yml?query=branch%3Amain)
[![Coverage](https://codecov.io/gh/camilodlt/MAGE.jl/branch/main/graph/badge.svg)](https://codecov.io/gh/camilodlt/MAGE.jl)

MAGE is a type-aware extension of Cartesian Genetic Programming for evolving multimodal programs.

The Julia package that implements MAGE is still named `UTCGP`. Renaming the package is a separate migration because it affects the source tree, documentation, CI, and downstream users.

## What MAGE Does

MAGE evolves typed computational graphs that can mix several modalities in the same program. A typical pipeline can take an image, apply a blur, then a Sobel operator, reduce the result to a scalar statistic, and use that scalar as a parameter for another image-processing function.

This typed composition is the core of the library:

- several data types can coexist in one evolved program
- function selection is constrained by input and output types
- image processing, scalar transforms, and control logic can be combined in the same graph

## Current Scope

The current package already includes infrastructure for:

- typed graph construction, decoding, and compilation to readable Julia source
- `FunctionBundle`, `Library`, and `MetaLibrary`
- mutation operators, crossover, and GA-, MAP-Elites- and NSGA-II-based search
- GraphMAGE: Monte-Carlo graph search over program behaviours
- automatically defined functions: promoting evolved subprograms to library operators
- LLM-synthesised library functions, validated before installation
- search-network tooling and experiment tracing
- multimodal function libraries over images, floats, integers, strings, lists, tuples, and element operators

Existing image-oriented bundles in [`src/libraries/image2D/`](src/libraries/image2D) cover:

- basic image operators
- filtering
- morphology
- binarization
- segmentation
- arithmetic and boolean arithmetic
- transcendental transforms
- experimental masking operators

There are also premade bundle collections for image-heavy setups, including Atari-oriented variants, in [`src/libraries/pre_made_libraries.jl`](src/libraries/pre_made_libraries.jl).

## Documentation

The manual is at <https://camilodlt.github.io/MAGE.jl/dev/>. Good places to
start:

- **Getting Started** — build a model and run a search end to end.
- **Symbolic Regression** — a complete, runnable example.
- **Genome and Nodes** — the representation: elements, nodes, chromosomes.
- **Libraries** and the **Bundle Catalogue** — every operator MAGE ships,
  generated from the source at build time.
- **Fitters and Callbacks** — the search loop and the callback pipeline.
- **GraphMAGE**, **Automatically Defined Functions**, **Generated Functions** —
  the advanced search machinery.

To build the docs locally:

```bash
julia --project=docs -e 'using Pkg; Pkg.develop(path="."); Pkg.instantiate()'
julia --project=docs docs/make.jl
```

The build is strict: `checkdocs = :exports` means every docstring in `UTCGP`
must appear somewhere in the manual, and doctests run as part of it.

## Installation

Until the package rename happens, install and import the current package name:

```julia
using Pkg
Pkg.add(url="https://github.com/camilodlt/SearchNetworks.jl")
Pkg.add(url="https://github.com/camilodlt/MAGE.jl")
using UTCGP
```

For local development:

```julia
using Pkg
Pkg.develop(path=".")
Pkg.instantiate()
```

## Publications

Papers defining MAGE:

- De La Torre, C., Lavinas, Y., Cortacero, K., Luga, H., Wilson, D. G., and Cussat-Blanc, S. "Multimodal Adaptive Graph Evolution." GECCO 2024. https://dl.acm.org/doi/abs/10.1145/3638530.3654347
- De La Torre, C., Lavinas, Y., Cortacero, K., Luga, H., Wilson, D. G., and Cussat-Blanc, S. "Multimodal Adaptive Graph Evolution for Program Synthesis." PPSN 2024. https://link.springer.com/chapter/10.1007/978-3-031-70055-2_19

Papers using MAGE for computer vision:

- De La Torre, C., Nadizar, G., Lavinas, Y., Schwob, R., Franchet, C., Luga, H., Wilson, D. G., and Cussat-Blanc, S. "Evolution of Inherently Interpretable Visual Control Policies." GECCO 2025. https://dl.acm.org/doi/abs/10.1145/3712256.3726332
- De La Torre, C., Nadizar, G., Lavinas, Y., Schwob, R., Franchet, C., Luga, H., Wilson, D. G., and Cussat-Blanc, S. "Evolved and Transparent Pipelines for Biomedical Image Classification." EuroGP 2025. https://link.springer.com/chapter/10.1007/978-3-031-89991-1_11
