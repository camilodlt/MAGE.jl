# Typed population evaluation

A population graph (`PopulationSequentialProgram`) merges the steps of every
individual of a generation. A `TypedEvaluator` evaluates it with the type of
every value proven by the compiler. A graph whose types cannot be proven is an
error, not a silent fallback: the run stops at the first generation, naming the
step.

## Usage

```julia
# Start of the run: one pool per task that evaluates concurrently.
run_types = [input_types; chromosome_types]
pools = Channel{BufferPool}(Threads.nthreads())
foreach(_ -> put!(pools, BufferPool(run_types)), 1:Threads.nthreads())

# Every generation, in each task (Threads.@threads :static, or Threads.@spawn tasks sharing a queue of samples):
pool = take!(pools)
evaluator = TypedEvaluator(graph, pool)
evaluate_population_into!(outputs, graph, chunk_samples; evaluator)
put!(pools, pool)
```

`outputs` holds one matrix per program output: `outputs[k][individual, sample]`
is the `k`th output of an individual on a sample. For a single-output program a
matrix can be passed instead of a one-matrix tuple. Image outputs are copies.

`individual_times[individual, sample]` (optional) receives each individual's
time: every shared step is timed once and counted for each individual that uses
it, as in the generic interpreter. `check = true` also runs the generic
interpreter and throws if any output differs (images are compared pixel by pixel).

`evaluate_population_steps_into!(step_values, graph, samples; evaluator)` writes
every Float64 step value (NaN for other types), for scoring intermediate nodes
(ISA-CGP). `sequential_step_values(program, samples)` does the same for one
program, in its own step order.

## Proven types

`TypedEvaluator` checks every step while building it, and throws
`TypedEvaluationError` unless:

- every input and step type is concrete;
- inference proves that the step's function (through its caster) returns exactly
  the declared type, and so does its fallback;
- that type satisfies the step's return-type policy;
- a step returning a sized image accepts the `out` keyword
  (see [Image output buffers](library_out_keyword.md)).

Inference is sound, so a proven step returns its type or throws, and a throw is
replaced by the fallback (as in `safe_call`). While evaluating, values only go
into typed storage: typed matrices (tiled engine) or `ValueSlot{T}` (per-sample
engine), whose only writer asserts the type. `SAFE_CALL` does not change the
result: a proven step cannot raise a `MethodError`.

## Engines

The engine is chosen from the run's types, held by the pool: a run with any
non-bits type (images) uses the per-sample engine, otherwise the tiled engine.
It does not depend on one generation's graph. `engine = :tiled` or `:per_sample`
forces one.

| engine | for | how |
|:--|:--|:--|
| tiled | scalar runs (SR) | every step fully specialised; a step runs over a tile of `batch_size` samples before the next step; allocates nothing |
| per-sample | runs with images | one sample at a time; steps not specialised (one dynamic call per step and sample); sized outputs written into preallocated buffers |

The per-sample engine is not specialised because an image operation costs
microseconds to seconds: a dynamic call is negligible, while specialising every
(function, argument types) pair would compile engine code for every new pair,
generation after generation. A new pair only compiles the library method itself.

## Buffer pools

`BufferPool(run_types)` holds, for each sized non-bits type (an `SImageND`,
whose size is part of its type), a list of preallocated images. A 224×224 and a
112×112 binary image are different types, so they have different lists.

When an evaluator is built, the `k`th step returning type `T` gets the `k`th
buffer of `T` (`next_buffer_index` counts them during the build), so no two steps
share a buffer. A list grows when a generation needs more buffers of its type
than any before, and never shrinks. Every build starts from the first buffer, so
the same images are reused in every generation.

A pool must be used by one task at a time: evaluation writes into its buffers.
Taking pools from a `Channel` keeps that true with any scheduling (`:static`, `:dynamic`, `:greedy`, or tasks pulling from a queue)
scheduling and any number of chunks. Types whose size is not part of the type
(e.g. vectors) are not pooled: their functions are called without `out`.

```@docs
BufferPool
```
