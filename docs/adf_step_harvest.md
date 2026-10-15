# Step harvesting and ADF extraction

Public APIs:

```julia
evaluate_population_steps_into!(S::Matrix{Float64}, program::PopulationSequentialProgram,
                                samples; workspace=nothing)
sequential_step_values(prog::SequentialProgram, samples)
adf_step_input_indices(prog::SequentialProgram, step_index::Int)
adf_genome_from_step(prog::SequentialProgram, step_index::Int,
                     arch::modelArchitecture, ml::MetaLibrary; max_nodes::Int=8)
set_node_input_connection!(node::CGPNode, input_index::Int, position::Int, type_index::Int)
set_output_node_connection!(output::OutputNode, node::CGPNode)
new_material_mutation!(node::CGPNode, arch::modelArchitecture, library::Library,
                       genome::UTGenome, shared_inputs::SharedInput)
```

All are exported. `sequential_step_values` returns `(steps_by_samples, original_nodes)`
in the compiled program's step order, including output operations. Both harvest APIs
write NaN for non-Float64 steps. Population steps are structurally deduplicated;
single-program rows preserve repeated local steps. Samples are tuples of input values.
A typed workspace is thread-local and must be rebuilt after changing graph/wrappers
or installing a definition with a different slot signature. SAFE_CALL, cached wrappers,
abstract types, and other unsupported typed graphs use the generic interpreter.

Extraction returns only the independent definition genome, or `nothing` when the
limits are exceeded or the cone contains a non-Float64 value. Inputs are mapped in
ascending original input-index order (constant *input columns* count as inputs).
Float64 constant nodes are copied as constants. Output operations count toward
`max_nodes`. The original meta-library and its first-function output convention
must be retained. For a Float64-only chromosome library:

```julia
indices = adf_step_input_indices(seq, step_index)
genome = adf_genome_from_step(seq, step_index, arch, ml; max_nodes=8)
adf_arch = modelArchitecture(fill(Float64, 3), ones(Int, 3),
                             [Float64], [Float64], [1])
adf_inputs, _ = make_evolvable_utgenome(adf_arch, ml, nodeConfig(1, 1, 3, 3))
if genome !== nothing
    replace_adf_slot!(registry, slot_id, genome, adf_inputs, adf_arch, ml)
    args = ntuple(j -> j <= length(indices) ? sample[indices[j]] : 0.0, 3)
    value = registry.slots[slot_id](args...)
end
```

For multiple chromosome types, retain `arch.chromosomes_types`, use the Float64
chromosome's row for all three input type indices and the sole output type index.
Extraction currently accepts SequentialProgram, not a merged population graph.
Harvest the population graph in one pass; retain the compiled single-genome programs
for extracting definitions and associating values with original genome nodes.

The decoder (`src/programs/decode.jl`) consumes `which(fn, types).nargs - 2` inputs.
ADF slots implement `which` explicitly: three declared inputs report `nargs=5`,
so all three CGP connections are consumed. The slot's Julia varargs method does not
reduce that count. Reserved empty slots consume one input; installing a definition
compiled with three inputs changes the slot to consume three. Typed evaluation uses
`slot.output_type` rather than compiler inference and asserts the result type.

Rewiring helpers validate position/type bounds and preserve frozen output chromosome
selection. The caller must check the primitive's type compatibility after rewiring.
Single-node mutation reuses the existing new-material mutation operator, including
its retry limit; no replacement mutation API is introduced.
