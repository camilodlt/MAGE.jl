############################
# ADF Serialization Helpers
############################

"""
    adf_source(slot)

Render a single ADF slot as readable Julia-like source. This is currently for
inspection and export; genome-backed reload serialization will use the stored
ADF genome as the canonical representation.

Example: `adf_source(slot)` returns text like `function adf_edges(x1)\n...`.
"""
function adf_source(slot::ADFSlotFunction)::String
    return adf_source(slot.definition, slot)
end

"""
    adf_source(::EmptyADFDefinition, slot)

Render an empty slot as its placeholder identity behavior.

Example: an empty `adf_3` renders as a function that returns its first argument.
"""
function adf_source(::EmptyADFDefinition, slot::ADFSlotFunction)::String
    return "function $(slot.name)(x, args...)\n    return x\nend"
end

"""
    adf_source(definition::ActiveADFDefinition, slot)

Render an active ADF using the sequential source cached in its definition.

Example: an active `adf_sum_div` renders the same tmp-register code executed by its sequential program.
"""
function adf_source(definition::ActiveADFDefinition, slot::ADFSlotFunction)::String
    body = sequential_source(definition.sequential_program)
    return "# ADF slot $(slot.slot_id): $(slot.name)\n" * body
end

"""
    adf_sources(registry)

Render all registered ADF slots in slot-id order so dependent ADFs can be read
after earlier slots.

Example: `adf_sources(registry)[1]` returns the source text for the lowest slot id.
"""
function adf_sources(registry::ADFRegistry)::Vector{String}
    return String[adf_source(registry.slots[slot_id]) for slot_id in sort(collect(keys(registry.slots)))]
end
