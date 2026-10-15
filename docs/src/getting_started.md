```@meta
CurrentModule = UTCGP
```

# Getting Started

This page builds a complete MAGE run from scratch and explains each object as it
appears. The problem is deliberately tiny — rediscover `y = x1^2 + 2*x2` from 30
samples — so that the pieces stay visible.

```@contents
Pages = ["getting_started.md"]
Depth = 2
```

## 1. Say what the program may compute

A [`FunctionBundle`](@ref) is a themed group of operators. A [`Library`](@ref)
is the set of bundles available to one chromosome, and a
[`MetaLibrary`](@ref) collects one library per chromosome.

```@example gs
using UTCGP
using Random
Random.seed!(1)

float_bundles = UTCGP.get_sr_float_bundles()
lib = Library(float_bundles)
ml  = MetaLibrary([lib])

length(lib)   # number of callable operators
```

`get_sr_float_bundles` is one of the premade collections; see
[Libraries](@ref) for assembling your own, and the
[Bundle Catalogue](@ref) for what each bundle contains.

## 2. Say what the types are

[`modelArchitecture`](@ref) declares the inputs, the chromosomes, and the
outputs. Here everything is `Float64`, so there is a single chromosome.

The two extra inputs (`1.0` and `2.0`) are constants: giving the search a couple
of literals to build with is standard practice in CGP.

```@example gs
n_inputs = 4                                  # x1, x2, and two constants

model_arch = modelArchitecture(
    [Float64 for _ in 1:n_inputs],            # input types
    [1 for _ in 1:n_inputs],                  # each input belongs to chromosome 1
    [Float64],                                # one chromosome, of type Float64
    [Float64],                                # one output, of type Float64
    [1],                                      # read from chromosome 1
)
```

## 3. Say how big the graph is

[`nodeConfig`](@ref) fixes the shape of every chromosome. `offset_by` must equal
the number of inputs.

```@example gs
node_config = nodeConfig(
    20,        # nodes per chromosome
    1,         # connection temperature
    2,         # arity: at most 2 arguments per node
    n_inputs,  # inputs sitting in front of the chromosome
)
```

## 4. Build the genome

[`make_evolvable_utgenome`](@ref) returns the [`SharedInput`](@ref) — the input
nodes every chromosome reads — and an uninitialised [`UTGenome`](@ref).
Initialising fills the integers at random; [`correct_all_nodes!`](@ref) then
repairs any node whose connexions do not match the type its function expects.

```@example gs
shared_inputs, ut_genome = make_evolvable_utgenome(model_arch, ml, node_config)
initialize_genome!(ut_genome)
correct_all_nodes!(ut_genome, model_arch, ml, shared_inputs)

length(ut_genome)          # chromosomes
```

At this point `ut_genome` is a valid random program. See
[Genome and Nodes](@ref) for what the integers mean.

## 5. Say what "good" means

A problem is stated as a [`BatchEndpoint`](@ref UTCGP.AbstractEndpoint): a
struct whose constructor receives every individual's outputs and the expected
value, and stores one score per individual. Lower is better.

```@example gs
struct EndpointMAE <: UTCGP.BatchEndpoint
    fitness_results::Vector{Float64}
    function EndpointMAE(preds::Vector{<:Vector{<:Number}}, y::Number)
        res = Float64[]
        for ind_outputs in preds
            p = ind_outputs[1]
            push!(res, isnan(p) ? 1e6 : abs(p - y))
        end
        return new(res)
    end
end
```

Ready-made endpoints for the standard PSB2 error functions are
[`EndpointBatchAbsDifference`](@ref), [`EndpointBatchLevensthein`](@ref) and
[`EndpointBatchVecDiff`](@ref).

## 6. The data

Each row of `X` is the vector of values for the input nodes, in order — the two
variables followed by the two constants.

```@example gs
target(x1, x2) = x1^2 + 2 * x2

raw = [(round(rand() * 4 - 2; digits = 3), round(rand() * 4 - 2; digits = 3)) for _ in 1:30]
X = [Any[x1, x2, 1.0, 2.0] for (x1, x2) in raw]
Y = [target(x1, x2) for (x1, x2) in raw]

X[1], Y[1]
```

## 7. Run the search

[`runConf`](@ref) configures a `1 + λ` search, and [`fit`](@ref) runs it. The
long argument list is the callback pipeline: one tuple per phase of a
generation. See [Fitters and Callbacks](@ref).

```@example gs
using Logging

run_conf = runConf(
    6,     # lambda: offspring per generation
    30,    # generations
    1.1,   # mutation rate (here: one active node per individual)
    0.1,   # output mutation rate
)

best_genome, best_program, history = with_logger(NullLogger()) do
    fit(
        X, Y, shared_inputs, ut_genome, model_arch, node_config, run_conf, ml,
        nothing,                                             # pre callbacks
        (:default_population_callback,),                     # build the population
        (:default_numbered_new_material_mutation_callback,), # mutate
        (:default_ouptut_mutation_callback,),                # mutate the outputs
        (:default_decoding_callback,),                       # genome -> programs
        EndpointMAE,                                         # fitness
        nothing,                                             # after each batch
        (:default_elite_selection_callback,),                # pick the survivor
        nothing,                                             # after each generation
        (:default_early_stop_callback,),                     # stop at loss 0
        nothing,                                             # after the loop
    )
end

[history[g][1] for g in 1:length(history)]   # best loss per generation
```

## 8. Read the result

The winning genome is `best_genome`, and `best_program` is its decoded
[`Program`](@ref) per output. To *read* the evolved program, compile it and
render its source — only the active path appears:

```@example gs
seq = compile_program(best_program, model_arch, ml)
print(sequential_source(seq))
```

The compiled [`SequentialProgram`](@ref) is also callable, which is how an
evolved model is deployed:

```@example gs
seq(1.0, 2.0, 1.0, 2.0)
```

## Where to go next

- A larger, more realistic run: [Symbolic Regression](@ref).
- Swapping `1 + λ` for a real population: [`fit_ga`](@ref) and
  [`RunConfGA`](@ref), in [Fitters and Callbacks](@ref).
- Adding a second modality — say an image chromosome feeding the float one —
  by giving `modelArchitecture` more than one chromosome type and
  `MetaLibrary` one library per type. See [Model Config](@ref) and
  [Libraries](@ref).
- Recording the search: [Endpoints and Tracking](@ref) and
  [Search Networks](@ref).
