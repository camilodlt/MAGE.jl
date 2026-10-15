# Typed population evaluator validation

Measured 2026-10-13 on implementation revision `e10868a` (branch `fast-pop-eval`, base `8b50a70`).

## Design and use

```julia
workspace = UTCGP.TypedPopulationWorkspace(program; batch_size=128)
UTCGP.evaluate_population_into!(P, program, samples; workspace, check=true)
```

`P[individual, sample]` stores one output per individual. Plan construction is
outside the hot loop; reuse the workspace for allocation-free primitive calls.
The workspace is thread-local and must be rebuilt after graph/wrapper changes.
`batch_size=1` selects scalar execution.

Separate concrete workspace matrices are held in a typed tuple, behind a reusable
Ref to avoid boxing at dispatch boundaries. Each reference is isbits, with its
kind/index as integer fields and group/value type encoded in type parameters.
Call plans capture concrete primitive, caster, fallback, return policy and arity;
`ntuple(..., Val(N))` provides specialised tuple calls without argument vectors.
Each step dispatches once per row tile, in graph order. Constants and outputs use
integer references. No evaluator debug or timing hooks occur in the fast loop.

The original caster (including bounds/clamping) is invoked; function/caster errors
use the original fallback, and return assertions stay outside the catch block.
Uncertain/nonconcrete return inference, cached wrappers, `SAFE_CALL=true` (method
status caching), incompatible samples, and heterogeneous output groups retain the
generic interpreter. The old APIs and image-classification callers are unchanged.
The matrix API requires one output per individual; multi-output users retain the
old API. Row batching assumes deterministic primitives, as in this SR library.

## Checks and measurements

Dataset `606_fri_c2_1000_10`, seed 1, shuffled 75/25 split and training-statistic
standardisation: 750 training rows with five fixed constants. A 100-node parent
was evolved for 30 canonical 1+256 generations, then mutated into nested prefixes
of 1+8192. The mu+lambda case uses 16 retained individuals and 256 offspring,
with 100 genome nodes. All graphs use safe compilation and no function cache.

Julia 1.11.7, one Julia thread, taskset CPUs 4-7, BLAS/OpenMP one thread. Times are
medians of three warmed repetitions; explicit GC is outside timed sections.
Baseline is the existing threaded sample evaluator plus output-to-matrix copy.
Typed prediction matrices, plans and workspaces are preallocated; setup costs
are excluded. All four cases passed element-wise `===` against generic outputs
in both scalar and batch modes, including the API's independent check mode.
These are evaluation-only gains, not whole-generation or Kairos measurements.

| Population | N | Merged steps | Generic s | Scalar s | Batch s | Batch speed-up | Generic bytes | Batch bytes |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 1+lambda | 257 | 707 | 1.072857 | 0.040178 | 0.003376 | 317.8× | 344,838,576 | 32 |
| 1+lambda | 1025 | 1389 | 2.306011 | 0.071914 | 0.006602 | 349.3× | 850,061,456 | 32 |
| 1+lambda | 8193 | 2700 | 6.805381 | 0.139769 | 0.019101 | 356.3× | 3,751,876,552 | 32 |
| mu+lambda | 272 | 1081 | 1.612351 | 0.061219 | 0.004895 | 329.4× | 489,546,576 | 32 |

Scalar calls also measured 32 bytes each. The benchmark's closure-driven calls
report this fixed overhead; specialised API allocation tests report **zero bytes**
for allocation-free primitives, including 750-row scalar and batch execution.
Primitive allocation and exception/fallback allocation remain primitive costs.
Raw repetitions and independent `@allocated` checks are in
`fast_pop_eval_results.json`.

**124 focused tests passed**: existing decode, compile and population tests plus
new tests for NaNs/signed zeros, clamping, exception fallback, assertion placement,
uncertain/abstract types, SAFE_CALL fallback, mixed Int/Float64 groups, constants,
three-argument calls, matrix-valued image fallback and large row indices.
Full image-classification datasets, full package suite, reference fitness hashes,
scaling sweeps and Kairos jobs were not run. No runner integration, container or
sysimage changes were made; no push was performed.

## Reproduce

Run from the MAGENetRunner root. The standalone script copies the runner Project
and Manifest into a temporary directory, then Pkg.develops this clone. It never
writes the runner environment. An identical committed copy is provided here.

```bash
export JULIA_DEPOT_PATH=/home/$USER/.julia
export JULIAUP_DEPOT_PATH=/home/$USER/.juliaup
export JULIA_PYTHONCALL_EXE=.CondaPkg/env/bin/python
export UTCGP_CONSTRAINED=yes
export UTCGP_MIN_INT=-10000 UTCGP_MAX_INT=10000
export UTCGP_MIN_FLOAT=-10000 UTCGP_MAX_FLOAT=10000
export UTCGP_SMALL_ARRAY=100 UTCGP_BIG_ARRAY=1000
export OPENBLAS_NUM_THREADS=1 OMP_NUM_THREADS=1
taskset -c 4-7 julia --threads=1 POPULATION_reproducibility/POPULATION_fast_pop_eval_check.jl
```
