############################
# ADF Slot Types
############################

abstract type AbstractADFDefinition end

"""
    EmptyADFDefinition()

Definition used by a reserved ADF slot before the search installs a real
subprogram. Empty slots behave like identity on their first argument.

Example: an empty slot called as `slot(x)` returns `x`.
"""
struct EmptyADFDefinition <: AbstractADFDefinition end

"""
    ActiveADFDefinition(genome, shared_inputs, model_architecture, meta_library, sequential_program)

Genome-backed definition used by an ADF slot after it has been replaced by a
subprogram extracted from an elite.

The genome is the canonical representation because it can be flattened back
into normal CGP material. The sequential program is a cached callable view used
for fast ADF execution and for source rendering.

Example: an ADF storing `add(x, y)` can run as `slot(2, 3) == 5`.
"""
struct ActiveADFDefinition <: AbstractADFDefinition
    genome::UTGenome
    shared_inputs::SharedInput
    model_architecture::modelArchitecture
    meta_library::MetaLibrary
    sequential_program::SequentialProgram
end

"""
    ADFSlotFunction

Callable object stored inside a `FunctionWrapper`. Keeping the slot object
stable lets genomes keep the same function index while the slot definition is
replaced during search.

Example: function index 21 can keep pointing at the same slot after it changes from identity to `adf_sum_div`.
"""
mutable struct ADFSlotFunction <: AbstractFunction
    slot_id::Int
    name::Symbol
    input_types::Vector{DataType}
    output_type::DataType
    definition::AbstractADFDefinition
end

function adf_slot_name(prefix::Symbol, slot_id::Int)::Symbol
    return Symbol("$(prefix)_$(slot_id)")
end

"""
    call_adf_definition(definition, slot, inputs...)

Execute the current definition of an ADF slot.

Example: `call_adf_definition(EmptyADFDefinition(), slot, x)` returns `x`.
"""
function call_adf_definition(::EmptyADFDefinition, slot::ADFSlotFunction, inputs...)
    @assert length(inputs) >= 1 "Empty ADF slot $(slot.name) needs one input for identity behavior"
    return inputs[1]
end

function call_adf_definition(definition::ActiveADFDefinition, ::ADFSlotFunction, inputs...)
    outputs = definition.sequential_program(inputs...)
    @assert length(outputs) == 1 "ADF programs must currently have exactly one output"
    return outputs[1]
end

"""
    slot(inputs...)

Call an ADF slot as a normal function. This method is what the slot's
`FunctionWrapper` invokes during program evaluation.

Example: `slot(2, 3)` executes the sequential program currently installed in `slot`.
"""
function (slot::ADFSlotFunction)(inputs...)
    return call_adf_definition(slot.definition, slot, inputs...)
end

"""
    sequential_display_name(wrapper::FunctionWrapper{ADFSlotFunction})

Render ADF calls with the slot's current name. The `FunctionWrapper` keeps the
placeholder name that was installed during library extension, but the slot is
renamed when an extracted subprogram replaces that placeholder.

Example: a wrapper installed as `adf_1` can render as `adf_sum_div` after replacement.
"""
function sequential_display_name(wrapper::FunctionWrapper{ADFSlotFunction})::Symbol
    return sequential_safe_identifier(wrapper.fn.name)
end

"""
    which(slot, Tuple{...})

Report arity/type compatibility to the decoder. The returned object follows
the same `nargs` convention used by `ModularFunction`.

Example: an ADF with two declared inputs reports that decode should consume two node inputs.
"""
function Base.which(slot::ADFSlotFunction, actual_types::Tuple)
    # Decode probes a function with every available input on the node. ADF slots
    # only consume the arity declared by their installed sequential program.
    if length(actual_types) < length(slot.input_types)
        throw(MethodError(slot, actual_types))
    end

    for (actual_type, expected_type) in zip(actual_types[1:length(slot.input_types)], slot.input_types)
        if !(actual_type <: expected_type)
            throw(MethodError(slot, actual_types))
        end
    end

    return (nargs = length(slot.input_types) + 2,)
end

function Base.which(slot::ADFSlotFunction, tuple_type::Type{<:Tuple})
    return which(slot, tuple(tuple_type.parameters...))
end

"""
    adf_is_empty(slot_or_definition)

Return true when the slot still has identity-placeholder behavior.

Example: `adf_is_empty(slot)` is true before `replace_adf_slot!` installs a genome.
"""
function adf_is_empty(slot::ADFSlotFunction)::Bool
    return adf_is_empty(slot.definition)
end

adf_is_empty(::EmptyADFDefinition)::Bool = true
adf_is_empty(::ActiveADFDefinition)::Bool = false
