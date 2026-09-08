```@meta
CurrentModule = UTCGP
```

# Programs

A genome is data; a *program* is what that data means. Turning one into the
other happens in three stages, and each has its own representation:

| Stage | Produces | Used for |
|:--|:--|:--|
| **decode** | [`Program`](@ref) per output | the search loop |
| **evaluate** | output values | fitness |
| **compile** | [`SequentialProgram`](@ref) | fast repeated calls, and readable source |

```@contents
Pages = ["programs.md"]
Depth = 2
```

## Decoding

Decoding walks back from each output node through its connexions, collecting
the nodes it depends on into an ordered list of [`Operation`](@ref)s. Nodes the
outputs do not reach are skipped: they are the *dormant material* a later
mutation may reactivate.

```@autodocs
Modules = [UTCGP]
Pages = ["programs/programs.jl"]
```

### Decoding a genome

```@autodocs
Modules = [UTCGP]
Pages = ["programs/decode.jl", "programs/free_decode.jl"]
```

Two decoders exist. The default one assumes the genome is type-correct — which
it is, if it was built with [`correct_all_nodes!`](@ref) and mutated with
[`standard_mutate!`](@ref) or [`numbered_mutation!`](@ref). The *free* decoder
resolves connexions without that assumption, and is what
[`free_mutate!`](@ref) pairs with.

## Evaluating

```@autodocs
Modules = [UTCGP]
Pages = ["programs/evaluate.jl"]
```

Evaluation runs each operation in order and caches its result on the calling
node, so a node feeding several consumers is computed once. Between two samples
the values are cleared with [`reset_genome!`](@ref) and new inputs are installed
with [`replace_shared_inputs!`](@ref).

Every call goes through a [`FunctionWrapper`](@ref), which applies the bundle's
caster to the result and substitutes the fallback if the call throws — that is
why an evolved program is total and a run never dies on a division by zero.

## Compiling

Decoded programs can be lowered into a [`SequentialProgram`](@ref): a flat list
of steps over temporaries, with no genome objects left in the way. This is both
the fast path for repeated evaluation and the readable form of an evolved model.

```@example prog
using UTCGP, Random, Logging
Random.seed!(7)

lib = Library(UTCGP.get_sr_float_bundles()); ml = MetaLibrary([lib])
model_arch = modelArchitecture([Float64, Float64], [1, 1], [Float64], [Float64], [1])
node_config = nodeConfig(12, 1, 2, 2)

shared_inputs, genome = make_evolvable_utgenome(model_arch, ml, node_config)
initialize_genome!(genome)
correct_all_nodes!(genome, model_arch, ml, shared_inputs)

programs = UTCGP.decode_with_output_nodes(genome, ml, model_arch, shared_inputs)
seq = compile_program(programs, model_arch, ml)
print(sequential_source(seq))
```

The result is callable:

```@example prog
seq(3.0, 4.0)
```

```@autodocs
Modules = [UTCGP]
Pages = ["programs/compile/compile_program.jl"]
```

### Populations of compiled programs

Compiling a whole population once and evaluating it as a batch is the fast path
used by the multithreaded fitters.

```@autodocs
Modules = [UTCGP]
Pages = ["programs/compile/population_sequential_program.jl"]
```

## Subgraph selection

Any node of a decoded program can be treated as the root of a subgraph. That is
the mechanism behind [Automatically Defined Functions](@ref): a promising
subprogram is extracted and installed as a reusable operator.

```@autodocs
Modules = [UTCGP]
Pages = ["libraries/subgraph_selection.jl"]
```
