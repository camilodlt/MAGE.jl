# Ordered active-node cache

This is an opt-in MAGE cache for ordinary `UTGenome` mutation, independent of
application types, input count, chromosome count, or chromosome width. Existing
calls without a cache retain their original decode, sampling, and node mutation.
No runner files are changed. Base: `fast-pop-eval`, `8b59d28`.

## Representation and contract

`ActiveNodeCache(n)` owns `n` independent `ActiveNodeCacheEntry` objects. Each has:

- `positions::Vector{NTuple{2,Int32}}`: inline `(row, chromosome_index)` values.
- `layout::Vector{Int}`: every chromosome length, then output count.
- `seen::Vector{Bool}`: reusable flattened chromosome mask for deduplication.
- `selected::Vector{AbstractGenomeNode}`: borrowed workspace containing only the
  sampled nodes, populated immediately before mutation.
- Per-entry sampling indices, Float64 weights, cached `Weights` wrapper, result
  indices, and `Pair{Float64,Int}` heap; no shared mutable scratch.
- `valid::Bool`: explicit lifecycle state.

Positions are derived directly from `node.y_position` and
`node.x_position - genome[row].starting_point`. No node lookup/search is used.
Chromosome widths need not match. Int32 conversion is checked by Julia.
Row zero is reserved for output markers; current `get_active_node` explicitly
excludes `OutputNode` (it is not an `AbstractGenomeNode`), so **no output markers
are currently captured or mutated**. Preserving that exclusion is essential.

Layout validation compares the number of rows, every row length, and output
count before reading positions for mutation. A changed row invalidates reuse
even if the total number of nodes stays constant. Inserted slices, flattening,
and growth therefore fall back to a fresh default decode and recapture. An
entry is not a genome/content hash: arbitrary allele, output, architecture,
library, or same-size graph replacements must explicitly invalidate it. It is
valid only for the exact individual captured or an exact copy of that individual.

## Exact public signatures

```julia
ActiveNodeCache(n::Integer)
ActiveNodeCacheEntry()
Base.getindex(cache::ActiveNodeCache, i::Integer)
capture_active_nodes!(entry::ActiveNodeCacheEntry, genome::UTGenome,
                      programs::MAGE.IndividualPrograms)
copy_active_nodes!(dest::ActiveNodeCacheEntry, src::ActiveNodeCacheEntry)
invalidate_active_nodes!(entry::ActiveNodeCacheEntry)
active_cache_matches(entry::ActiveNodeCacheEntry, genome::UTGenome)::Bool
check_active_nodes(entry::ActiveNodeCacheEntry, genome::UTGenome,
                   ml::MetaLibrary, arch::modelArchitecture, shared::SharedInput)::Bool

new_material_mutation!(genome::UTGenome, config::MAGE.AbstractRunConf,
    arch::modelArchitecture, ml::MetaLibrary, shared::SharedInput;
    active_positions::Union{Nothing,ActiveNodeCacheEntry}=nothing)

MAGE.default_decoding_callback(population::Population, generation::Int,
    config::MAGE.AbstractRunConf, arch::modelArchitecture, nc::nodeConfig,
    ml::MetaLibrary, shared::SharedInput, cache::ActiveNodeCache)

MAGE.ga_population_callback(args::MAGE.GA_POP_ARGS,
    cache::ActiveNodeCache, parent_cache::ActiveNodeCache,
    parent_indices::AbstractVector{<:Integer})

MAGE.ga_numbered_new_material_mutation_callback(args::MAGE.Abstract_GA_MUTATION_ARGS,
    cache::ActiveNodeCache, parent_cache::ActiveNodeCache,
    parent_indices::AbstractVector{<:Integer}; check::Bool=false)
```

The mutation result has the same `(selected_nodes, sampled_idx)` meaning as the
original. **Cached `selected_nodes` is borrowed** until the next use of that slot;
copy it if retaining it. `sampled_idx` is also borrowed until the next slot use.
Execution-value resets/evaluation do not change active positions and need no
invalidation; material/topology changes do. A zero-node graph returns `nothing`, as before, and retains its valid empty entry.

## Annotated code walkthrough

1. `src/mutations/active_node_cache.jl` defines the slot buffers and direct
   coordinate conversion. `active_cache_matches` performs only integer/layout
   comparisons; invalid or mismatched entries cannot reach cached sampling.
2. `capture_active_nodes!` first marks the entry invalid, stamps row lengths and
   output count, resizes/clears its seen mask, and clears the positions' logical
   length while retaining capacity. Position capacity is reserved for ALL nodes
   in the layout, so a larger active cone within the same layout does not allocate.
   `_capture_programs!` and
   `_capture_operations!` are function barriers over the concrete vectors behind
   MAGE's existentially typed containers. The capture/layout/materialization
   barriers also specialize on the chromosome vector: otherwise retrieving an
   immutable `SingleGenome` through an abstract vector boxes it on every access.
   `SingleGenome` assertions identify MAGE's ordinary chromosome representation;
   no application or node-count assumptions are introduced.
3. `_capture_position!` computes the mask index from preceding row lengths.
   It appends a position only on its first occurrence. The nesting is exactly
   program order, then operation order, matching `get_active_nodes`'s final
   `unique` first-occurrence semantics, including repeated nodes across outputs.
   Successful capture alone marks the entry valid again.
4. The default decoding callback already calls `decode_with_output_nodes` for
   evaluation. Its new overload captures those same `IndividualPrograms`, with
   **no second decode and no active-node vector**. Capture before compiling,
   reversing, optimizing, or converting programs. Free/custom decoding must not
   be assumed to have this order: capture a default decode instead, and use
   `check_active_nodes` to verify any custom integration.
5. `copy_active_nodes!` resizes and `copyto!`s positions/stamp into destination-owned
   buffers, reserving the layout's maximum position count on first use. It copies
   validity but neither seen scratch nor selected references.
   A self-copy is harmless. Separate source/destination generation caches prevent
   a repeated parent's metadata being overwritten during population replacement.
6. `new_material_mutation!` keeps the original assertions, floor, truncation
   warning, and exact `sample_n(length(active_nodes), n)` behavior. Missing/stale
   entries decode and capture before sampling. `_sample_active_nodes!` uses
   reusable exact-sampling buffers and returns borrowed indices;
   `_materialize_active_nodes!` resolves only its chosen
   positions into the small reusable selected buffer. Invalidation occurs before
   calling the unchanged vector/node-level mutation, including on exceptions.
7. The GA population overload uses the existing tournament's `return_idx=true`
   path, preserving its random draws and recording exact source slots. Elites
   retain the standard references; children retain the standard `deepcopy`.
   The mutation overload copies parent metadata, optionally checks ordered
   equality, mutates non-elites, and leaves elites valid.
8. `check_active_nodes` checks validity/layout and compares every cached position
   with `get_active_nodes(decode_with_output_nodes(...))`. It intentionally
   allocates and is diagnostic, outside the fast path.

## Runner integration

Allocate two caches beside the two genome pools, sized to their respective slot
counts. Also retain a preallocated `Vector{Int}` of parent indices. During initial
and subsequent default evaluation, capture each slot from its already-decoded
programs (or use the decoding callback overload).

When creating a child, copy the genome to the destination pool slot, record its
source parent index, and `copy_active_nodes!(destination[i], source[parent])`.
Call mutation with `active_positions=destination[i]`. Its entry becomes invalid;
recapture it from its next evaluation decode. An unchanged elite/copy keeps its
valid entry. Invalidate after any other operation that edits an individual,
including output mutation or crossover. Never recopy parent metadata after the
child has already been edited.

For standard GA callbacks, close over both caches and the indices:

```julia
population_cb = args -> MAGE.ga_population_callback(args, dst, src, parents)
mutation_cb = args -> MAGE.ga_numbered_new_material_mutation_callback(
    args, dst, src, parents; check=(args.generation % check_every == 0))
```

Both callbacks must use the same source generation cache; swap the two caches
along with the pool after evaluation. A runner that owns pooled genome copying
can skip the population overload and populate `parents` itself. For indexed
populations without a pool, allocate a cache for the current population and
recapture after reordering/replacement, or copy entries according to the same
explicit parent mapping. Never infer individual identity from slot number.
Each thread writes only its own destination slots and genomes. The source/parent
cache stays read-only throughout variation. Capture of different slots can run
in parallel; all scratch belongs to an entry. Never concurrently write the same
entry or genome. Julia's task-local default RNG makes multi-threaded draw order
schedule-dependent, as in MAGE without the cache.

## Validation and reproducibility

Run from the MAGENetRunner repository root:

```bash
source POPULATION_tmp_r2/env.sh
taskset -c 4-7 julia --project=POPULATION_MAGE_fastpop/_env3 \
  --startup-file=no --threads=1 --compiled-modules=existing \
  POPULATION_MAGE_fastpop/validation/active_cache_check.jl
taskset -c 4-7 julia --project=POPULATION_MAGE_fastpop/_env3 \
  --startup-file=no --threads=1 --compiled-modules=existing \
  POPULATION_MAGE_fastpop/validation/active_cache_benchmark.jl
```

The test registry includes `test/mutations/test_active_node_cache.jl`, which
runs the same standalone validation. Tests cover random corrected SR and two-type
Float64/Int genomes, multiple outputs, ordered equality and deduplication,
200 cached/uncached mutation seed pairs including full RNG-state equality and
the following RNG draws,
layout growth/output-count mismatch, corruption detection, callback parent
mapping/RNG behavior, elite validity, and warm buffer allocations.

### Exact sampling and allocation

The uncached `sample_n` is unchanged. The installed StatsBase 0.33.21 (XgjIN) dispatches
`sample(rng, idx, Weights(w), n; replace=false)` through `sample!` to
`efraimidis_aexpj_wsample_norep!`. Even `sample!` allocates an internal priority
queue. `_sample_cached_indices!` reproduces that code path's arithmetic, random
draws, heap operations and output order, with a reusable per-entry heap. The
index/weight vectors are resized and filled only when the active count changes;
the Weights wrapper is rebuilt then. Result and heap capacity are reused.
No uniform/unweighted sampler is substituted. Regression tests compare indices,
full RNG state and subsequent draws over many sizes, sample counts and seeds.

Warm sampling plus materialisation must allocate **0 bytes**. First use and
buffer growth/size changes can allocate. Node mutation and public return tuple
escape retain their existing allocations; the full mutation API is not claimed
to be allocation-free. Both returned vectors are borrowed entry-owned buffers.

### Current validation (2026-10-15)

Julia 1.11.7, `_env3`, BLAS/OpenMP one. Four-thread run on CPUs 0–3:
**3,350 passed, 0 failed, 0 errored**. Of these, the new exact sampling test
contributes 1,680 assertions across 420 (active count, sample count, seed) cases,
and the concurrent test contributes 208 assertions for 128 child slots and eight
unchanged parent entries. The remaining 1,462 assertions cover existing cache
behavior, including full cached/uncached mutation RNG equivalence.
Warm sampling allocates **0 bytes** in every sampling case; combined sampling
plus materialisation allocates **0 bytes**. Warm capture/copy/materialisation
checks also pass at zero bytes. See `active_cache_threaded_results.txt`.

```bash
source POPULATION_tmp_r2/env.sh
taskset -c 0-3 julia --project=POPULATION_MAGE_fastpop/_env3 \
  --startup-file=no --compiled-modules=existing --threads=4 \
  POPULATION_MAGE_fastpop/validation/active_cache_check.jl
taskset -c 4-7 julia --project=POPULATION_MAGE_fastpop/_env3 \
  --startup-file=no --compiled-modules=existing --threads=1 \
  POPULATION_MAGE_fastpop/test/runtests.jl
```

The direct `test/runtests.jl` run reached the last file (`sn_test.jl`) in
7m56.3s (the independent progress-instrumented run agreed):
**26,209 passed, 41 failed, 3 errored**. All cache assertions passed. The failures
and errors reproduce in independent runs that never invoke the active cache:

- Generated-function reflection: 2 failures at
  `test/libraries/test_llm_generated_functions.jl:88–89`, expecting MethodError
  where Julia 1.11's `which` throws ErrorException.
- Dice: 39 failures because the required constrained environment truncates
  Cartesian products at BIG_ARRAY=1000 while the examples require up to 10,000.
- Find pair: 1 BoundsError from constrained combinations (SMALL_ARRAY=100).
- Behavior hasher: decode of `identity_float(::Vector{Int64})` throws; this
  test is included twice by the registry, yielding 2 errors.

`unrelated_failures_check.jl` reproduces **59 pass / 41 fail / 0 error**;
`unrelated_errors_check.jl` reproduces **51 pass / 0 fail / 2 errors** (one
behavior-hasher include). Logs are `active_cache_unrelated_results.txt` and
`active_cache_unrelated_errors_results.txt`. No unrelated implementation was
changed and the required MAGE bounds were retained.

The temp environment required exposing already-manifested ImageMorphology and
Combinatorics as direct dependencies to load the entire registry. `_env3` remains
untracked. Initial dependency-limited attempts are superseded by the complete
runs above. The final direct-run log is `active_cache_full_results.txt`.

### Previous benchmark results (before reusable sampling)

Julia 1.11.7, one Julia thread, BLAS/OpenMP one, affinity CPUs 4–7,
`_env3`, 2026-10-15. The registered cache suite passed **1,462 assertions**;
existing decoding, numbered mutation, and GA suites passed **37 assertions**.
See `active_cache_test_results.txt` and `active_cache_regression_results.txt`.
The full repository test suite was not run for that earlier revision.

Warm capture, metadata copy, and sampled-node materialization each measured
**0 bytes**, including a 600/599-node typed layout and expansion of a two-node
active cone to 20 nodes without layout growth. The actual cached preparation
helper measured exactly the sampler's allocation, with no additional bytes.
For the 20-active-node benchmark fixture, `sample_n(20, 2)` measured 656 bytes.
Full sampler-plus-node baseline / cached API calls measured 26,160 / 26,256
bytes for one fixed mutation seed. Those totals include node mutation and
return/call-boundary effects; the full public call is not allocation-free.

The benchmark uses a fixed 100-node SR parent, a 20-node identity cone and two
outputs, mutation count two, and preallocated child genomes/cache slots. Every
child receives the parent's material, then mutates; the cached path also copies
the parent's metadata. Both modes use the same seeds. Times include material
copying and mutation, exclude evaluation and initial pool allocation, and are
medians of five batches after one warm batch per mode at each λ. GC runs before
each batch; reported bytes are from the last batch. This is a controlled
`1+λ`-like variation benchmark, not an evolved-dataset throughput estimate.

| λ | Uncached ms | Cached ms | Speedup | Uncached MB | Cached MB |
|---:|---:|---:|---:|---:|---:|
| 256 | 123.272 | 61.902 | 1.99× | 45.475 | 17.266 |
| 1024 | 511.653 | 251.920 | 2.03× | 181.591 | 68.755 |
| 4096 | 2141.482 | 1040.463 | 2.06× | 726.751 | 275.404 |

MB is decimal. Raw measurements are in `active_cache_results.txt`. CPU load and
frequency affect timings; ordered equality, RNG-state equality, layout fallback,
and allocation checks provide firmer evidence than small timing differences.

## Short summary

The cache reuses ordered inline positions for exact copies, validates every
layout dimension, preserves sampling/RNG behavior, and invalidates edited
children. It is application-independent and opt-in. Warm sampling and materialisation allocate zero bytes; active-graph decoding
and full node-vector construction are removed from valid cached mutation.
