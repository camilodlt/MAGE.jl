# Native ADF call frames

Typed population evaluators automatically lower supported ADF definitions into
`NativeADFFrame` objects. A generated function substitutes formal input refs
and temporary refs with Julia arguments and local assignments. Nested ADFs
are lowered recursively. Constants and wrapper objects are runtime fields;
there is no `eval` or generated source execution.

The population DAG retains one call step per structurally distinct application
of an ADF wrapper. Existing hash-consing shares identical applications across
individuals and local-search candidates. The body executes in a native frame,
without the scalar sequential interpreter's `Any` arrays or per-step dispatch.
Internal body steps are deliberately not hoisted across call boundaries:
return-type assertion failures and throwing fallbacks must abort the rest of
the body and be caught by the enclosing wrapper.

Each primitive invocation and caster is inside its original catch; its fallback
and final return-type assertion are outside that catch. The enclosing ADF wrapper
retains its caster, fallback and assertion. Empty slots use a native first-argument
identity *inside* the outer wrapper, so the outer caster is never elided.
Arithmetic, evaluation order, NaNs, signed zeros and bound clamping are unchanged.

The original `SequentialProgram`, population IR and generic interpreter remain
unchanged. `check=true` therefore compares against the **non-native, non-inlined**
ADF interpreter element by element using `===`. Cached wrappers, SAFE_CALL,
non-IR definitions and cyclic/unsupported nested definitions retain that path.
As before, rebuild the typed evaluator after changing definitions or wrappers.
The weak slot cache revalidates nested definitions, body refs, wrapper functions,
casters, fallbacks and policies whenever a new evaluator is built; construction
is protected by a reentrant lock. Native frames are cached per slot.

## Genome metadata and harvesting

No synthetic body steps are exposed in either sequential or population IR.
`SequentialCallStep.original_node` still denotes the calling genome node.
`sequential_step_values`, node credits and `adf_genome_from_step` operate in their
original step order; a harvested ADF call remains a call in the extracted genome.
Runner candidate DAG builders and harvest builders need no separate expansion
logic: both use the same native-frame lowering.

## Limits

Distinct calls do not share partial internal bodies, even when some arguments
coincide. Side effects retain the pre-existing population sharing assumptions;
this change adds no DAG sharing. Native specialization introduces cold compilation
per distinct body/closure type. Generic evaluation and unsupported graphs remain
unaccelerated. Native frames intentionally do not change scalar slot calls used
as the validation oracle or by library installation checks.
