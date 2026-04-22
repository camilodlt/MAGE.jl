############################
# Library Extension
############################

"""
    ADFRegistry()

Registry of ADF slots available during one run. The registry is the object used
to check replacement safety and recursive ADF dependencies.

Example: `registry.slots[21]` returns the mutable ADF slot registered at function index 21.
"""
mutable struct ADFRegistry
    slots::Dict{Int, ADFSlotFunction}
end

ADFRegistry() = ADFRegistry(Dict{Int, ADFSlotFunction}())

"""
    register_adf_slot!(registry, slot)

Record one ADF slot so replacement, usage checks, and serialization can find
it by stable slot id.

Example: `register_adf_slot!(registry, slot)` makes `registry.slots[slot.slot_id] === slot`.
"""
function register_adf_slot!(registry::ADFRegistry, slot::ADFSlotFunction)
    @assert !haskey(registry.slots, slot.slot_id) "ADF slot $(slot.slot_id) is already registered"
    registry.slots[slot.slot_id] = slot
    return slot
end

"""
    extend_fn_lib_adf!(library, registry, output_type, how_many; ...)

Append reserved ADF function slots to one library. Empty slots behave as
identity functions until `replace_adf_slot!` installs a real sequential program.

The slot wrapper is appended to `library.library` immediately so this works on
already-unpacked libraries used during a running search. The bundle is also kept
in `library.bundles` so the extension is visible in library metadata.

Example: `extend_fn_lib_adf!(lib, registry, Float64, 10)` appends ten Float64 ADF placeholders.
"""
function extend_fn_lib_adf!(
        library::Library,
        registry::ADFRegistry,
        output_type::DataType,
        how_many::Int;
        first_slot_id::Int = length(registry.slots) + 1,
        name_prefix::Symbol = :adf,
        fallback::Function = () -> nothing,
    )::Vector{ADFSlotFunction}
    @assert how_many >= 0 "Cannot add a negative number of ADF slots"

    added_slots = ADFSlotFunction[]
    bundle = FunctionBundle(fallback)

    for local_index in 1:how_many
        slot_id = first_slot_id + local_index - 1
        slot = ADFSlotFunction(
            slot_id,
            adf_slot_name(name_prefix, slot_id),
            DataType[output_type],
            output_type,
            EmptyADFDefinition(),
        )
        wrapper = FunctionWrapper(slot, slot.name, nothing, fallback)
        push!(bundle.functions, wrapper)
        push!(library.library, wrapper)
        register_adf_slot!(registry, slot)
        push!(added_slots, slot)
    end

    push!(library.bundles, bundle)
    return added_slots
end

"""
    replace_adf_slot!(slot, genome, shared_inputs, model_architecture, meta_library; name)

Install a genome-backed ADF definition into an existing slot. The slot keeps its
function-library position, but its arity, output type, name, and callable body
come from the decoded genome.

Example: `replace_adf_slot!(slot, elite_subgraph_genome, inputs, ma, ml; name=:adf_edges)` makes `slot(args...)` run that subgraph.
"""
function replace_adf_slot!(
        slot::ADFSlotFunction,
        genome::UTGenome,
        shared_inputs::SharedInput,
        model_architecture::modelArchitecture,
        meta_library::MetaLibrary;
        name::Symbol = slot.name,
    )::ADFSlotFunction
    decoded = decode_with_output_nodes(genome, meta_library, model_architecture, shared_inputs)
    program = compile_program(decoded, model_architecture, meta_library)
    @assert length(program.outputs) == 1 "ADF slot replacement requires a single-output SequentialProgram"
    @assert length(program.input_types) >= 1 "ADF slot replacement requires at least one input"

    slot.name = name
    slot.input_types = DataType[program.input_types...]
    slot.output_type = program.output_types[1]
    slot.definition = ActiveADFDefinition(
        deepcopy(genome),
        deepcopy(shared_inputs),
        model_architecture,
        meta_library,
        program,
    )
    return slot
end

"""
    replace_adf_slot!(registry, slot_id, genome, shared_inputs, model_architecture, meta_library; name)

Lookup a registered slot by id and install a genome-backed ADF definition into
it.

Example: `replace_adf_slot!(registry, 21, genome, inputs, ma, ml)` replaces slot 21 in place.
"""
function replace_adf_slot!(
        registry::ADFRegistry,
        slot_id::Int,
        genome::UTGenome,
        shared_inputs::SharedInput,
        model_architecture::modelArchitecture,
        meta_library::MetaLibrary;
        name::Symbol = registry.slots[slot_id].name,
    )::ADFSlotFunction
    @assert haskey(registry.slots, slot_id) "ADF slot $slot_id is not registered"
    return replace_adf_slot!(
        registry.slots[slot_id],
        genome,
        shared_inputs,
        model_architecture,
        meta_library;
        name = name,
    )
end
