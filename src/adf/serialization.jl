############################
# ADF Serialization Helpers
############################

import Serialization

"""
    SavedADFRef(environment_id, slot_id)

Identifies an ADF slot inside one saved ADF environment. The environment id is
part of the identity because two historical individuals can both use old slot
`189` while meaning different ADF definitions.

Example: `SavedADFRef(:elite_1_gen_50, 189)` is distinct from `SavedADFRef(:elite_2_gen_90, 189)`.
"""
struct SavedADFRef
    environment_id::Symbol
    slot_id::Int
end

"""
    SavedADFDefinition

One genome-backed ADF exactly as it existed when an individual was saved. The
stored genome is the canonical representation; `source` is the readable
sequential code attached for inspection and LLM-facing workflows.

Example: a saved `adf_remove_holes` definition stores its old slot id, genome, source, and ADF refs it calls.
"""
struct SavedADFDefinition
    ref::SavedADFRef
    name::Symbol
    input_types::Vector{DataType}
    output_type::DataType
    genome::UTGenome
    shared_inputs::SharedInput
    model_architecture::modelArchitecture
    source::String
    dependencies::Vector{SavedADFRef}
end

"""
    SavedADFEnvironment(environment_id, definitions)

The set of ADF definitions needed to interpret one saved individual without
relying on the current mutable run registry. This is not a callable Julia
closure; it is a namespaced ADF context captured at save time.

Example: if an individual calls `adf_201`, which calls `adf_190`, this environment stores both definitions.
"""
struct SavedADFEnvironment
    environment_id::Symbol
    definitions::Vector{SavedADFDefinition}
end

"""
    SavedIndividualWithADFEnvironment

A saved genome plus the ADF environment required to interpret its ADF function
indices. The environment prevents old ADF slot numbers from colliding with ADFs
saved from other individuals or later generations.

Example: two saved individuals can both contain function index 189 because each carries a different `SavedADFEnvironment`.
"""
struct SavedIndividualWithADFEnvironment
    genome::UTGenome
    shared_inputs::SharedInput
    model_architecture::modelArchitecture
    adf_environment::SavedADFEnvironment
end

"""
    adf_source(slot)

Render a single ADF slot as readable Julia-like source. This is for inspection
and export; genome-backed save paths keep the genome as the canonical behavior.

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

"""
    saved_adf_ref(environment_id, slot_id)

Create the namespaced reference used by saved ADF definitions. Keeping this in a
helper makes later remapping code use the same identity convention everywhere.

Example: `saved_adf_ref(:run_a_elite_5, 201)` identifies old slot 201 inside that saved environment.
"""
function saved_adf_ref(environment_id::Symbol, slot_id::Int)::SavedADFRef
    return SavedADFRef(environment_id, slot_id)
end

function saved_adf_dependencies(
        environment_id::Symbol,
        definition::ActiveADFDefinition,
    )::Vector{SavedADFRef}
    dependency_ids = sort(collect(direct_adf_usage(definition.sequential_program)))
    return SavedADFRef[saved_adf_ref(environment_id, dependency_id) for dependency_id in dependency_ids]
end

"""
    saved_adf_definition(environment_id, slot)

Capture one active ADF slot as a saved definition. Empty slots are rejected
because an individual save only needs ADFs that have real behavior behind them.

Example: `saved_adf_definition(:elite_4, slot)` stores the exact ADF genome currently installed in `slot`.
"""
function saved_adf_definition(
        environment_id::Symbol,
        slot::ADFSlotFunction,
    )::SavedADFDefinition
    return saved_adf_definition(environment_id, slot.definition, slot)
end

function saved_adf_definition(
        ::Symbol,
        ::EmptyADFDefinition,
        slot::ADFSlotFunction,
    )::SavedADFDefinition
    throw(ArgumentError("Cannot save empty ADF slot $(slot.slot_id) as an active ADF definition"))
end

function saved_adf_definition(
        environment_id::Symbol,
        definition::ActiveADFDefinition,
        slot::ADFSlotFunction,
    )::SavedADFDefinition
    return SavedADFDefinition(
        saved_adf_ref(environment_id, slot.slot_id),
        slot.name,
        DataType[slot.input_types...],
        slot.output_type,
        deepcopy(definition.genome),
        deepcopy(definition.shared_inputs),
        definition.model_architecture,
        sequential_source(definition.sequential_program),
        saved_adf_dependencies(environment_id, definition),
    )
end

function collect_adf_dependency_ids!(
        collected::Set{Int},
        registry::ADFRegistry,
        slot_id::Int,
    )::Nothing
    slot_id in collected && return nothing
    @assert haskey(registry.slots, slot_id) "ADF slot $slot_id is not registered"
    @assert registry.slots[slot_id].definition isa ActiveADFDefinition "ADF slot $slot_id is empty"

    push!(collected, slot_id)
    for dependency_id in adf_dependencies(registry.slots[slot_id].definition)
        collect_adf_dependency_ids!(collected, registry, dependency_id)
    end
    return nothing
end

"""
    saved_adf_environment(environment_id, registry, root_slot_ids)

Capture the recursive ADF environment needed by one saved individual. Root ids
are the ADF slots the individual calls directly; dependencies are discovered
from the genome-backed ADF definitions.

Example: roots `[201]` can save definitions for `189`, `190`, and `201` when `201 -> 190 -> 189`.
"""
function saved_adf_environment(
        environment_id::Symbol,
        registry::ADFRegistry,
        root_slot_ids::AbstractVector{Int},
    )::SavedADFEnvironment
    collected = Set{Int}()
    for slot_id in root_slot_ids
        collect_adf_dependency_ids!(collected, registry, slot_id)
    end

    definitions = SavedADFDefinition[
        saved_adf_definition(environment_id, registry.slots[slot_id]) for
            slot_id in sort(collect(collected))
    ]
    return SavedADFEnvironment(environment_id, definitions)
end

function saved_adf_environment(
        environment_id::Symbol,
        registry::ADFRegistry,
        programs::IndividualPrograms,
    )::SavedADFEnvironment
    return saved_adf_environment(environment_id, registry, sort(collect(direct_adf_usage(programs))))
end

"""
    saved_individual_with_adfs(environment_id, genome, shared_inputs, model_architecture, registry, programs)

Package one genome with the ADF environment required to interpret it. The caller
passes decoded programs so direct ADF usage is computed from the phenotype that
is actually being saved.

Example: `saved_individual_with_adfs(:elite_1, genome, inputs, ma, registry, decoded)` saves `genome` plus its ADF context.
"""
function saved_individual_with_adfs(
        environment_id::Symbol,
        genome::UTGenome,
        shared_inputs::SharedInput,
        model_architecture::modelArchitecture,
        registry::ADFRegistry,
        programs::IndividualPrograms,
    )::SavedIndividualWithADFEnvironment
    environment = saved_adf_environment(environment_id, registry, programs)
    return SavedIndividualWithADFEnvironment(
        deepcopy(genome),
        deepcopy(shared_inputs),
        model_architecture,
        environment,
    )
end

function saved_definition_by_ref(
        environment::SavedADFEnvironment,
    )::Dict{SavedADFRef, SavedADFDefinition}
    return Dict(definition.ref => definition for definition in environment.definitions)
end

function saved_adf_visit!(
        ordered::Vector{SavedADFDefinition},
        visiting::Set{SavedADFRef},
        visited::Set{SavedADFRef},
        ref::SavedADFRef,
        definitions::Dict{SavedADFRef, SavedADFDefinition},
    )::Nothing
    ref in visited && return nothing
    @assert !(ref in visiting) "ADF dependency cycle detected at $(ref)"
    @assert haskey(definitions, ref) "Saved ADF environment is missing dependency $(ref)"

    push!(visiting, ref)
    definition = definitions[ref]
    for dependency_ref in definition.dependencies
        saved_adf_visit!(ordered, visiting, visited, dependency_ref, definitions)
    end
    delete!(visiting, ref)
    push!(visited, ref)
    push!(ordered, definition)
    return nothing
end

"""
    saved_adf_dependency_order(environment)

Return saved ADF definitions ordered so callees come before callers. This is the
order future remapping/restoration code must use when rebuilding stacked ADFs in
a common library.

Example: if `adf_201` calls `adf_190`, which calls `adf_189`, this returns `[189, 190, 201]`.
"""
function saved_adf_dependency_order(
        environment::SavedADFEnvironment,
    )::Vector{SavedADFDefinition}
    definitions = saved_definition_by_ref(environment)
    ordered = SavedADFDefinition[]
    visiting = Set{SavedADFRef}()
    visited = Set{SavedADFRef}()

    for definition in environment.definitions
        saved_adf_visit!(ordered, visiting, visited, definition.ref, definitions)
    end
    return ordered
end

"""
    save_adf_environment(path, environment)

Write one saved ADF environment with Julia's `Serialization` stdlib. This format
is intended for MAGE-to-MAGE checkpoints, not as a stable cross-language file.

Example: `save_adf_environment("elite_1_adfs.jls", environment)` writes the environment to disk.
"""
function save_adf_environment(
        path::AbstractString,
        environment::SavedADFEnvironment,
    )::AbstractString
    open(path, "w") do io
        Serialization.serialize(io, environment)
    end
    return path
end

"""
    load_adf_environment(path)

Read a saved ADF environment previously written by `save_adf_environment`.

Example: `load_adf_environment("elite_1_adfs.jls")` returns a `SavedADFEnvironment`.
"""
function load_adf_environment(path::AbstractString)::SavedADFEnvironment
    return open(path, "r") do io
        Serialization.deserialize(io)
    end
end

"""
    save_individual_with_adfs(path, saved)

Write a genome and its saved ADF environment together. This keeps historical ADF
slot meanings attached to the individual that used them.

Example: `save_individual_with_adfs("elite_1.jls", saved)` writes both the genome and ADF environment.
"""
function save_individual_with_adfs(
        path::AbstractString,
        saved::SavedIndividualWithADFEnvironment,
    )::AbstractString
    open(path, "w") do io
        Serialization.serialize(io, saved)
    end
    return path
end

"""
    load_individual_with_adfs(path)

Read a saved individual package written by `save_individual_with_adfs`.

Example: `load_individual_with_adfs("elite_1.jls")` returns the saved genome plus its ADF environment.
"""
function load_individual_with_adfs(path::AbstractString)::SavedIndividualWithADFEnvironment
    return open(path, "r") do io
        Serialization.deserialize(io)
    end
end

# Future common-library remap plan:
# 1. Load each saved individual; each one carries the ADF environment it used.
# 2. For each environment, order definitions with `saved_adf_dependency_order`
#    so callees are considered before callers.
# 3. Compute a behavior/structure hash for each saved ADF definition. The hash
#    should include the ADF genome plus the already-remapped dependency refs so
#    semantically identical resurrected ADFs can reuse one target slot.
# 4. If the hash is new, allocate a fresh ADF slot in the correct output-type
#    function library and record `SavedADFRef => new function index`.
# 5. Rewrite every saved ADF genome so old environment-local ADF calls point to
#    the remapped target library indices. This must be done before installing a
#    caller ADF, because decode must see its callees in the target library.
# 6. Install/rebuild ADFs into the common registry in dependency order using the
#    rewritten genomes.
# 7. Rewrite each saved individual's genome with the same `SavedADFRef => new
#    function index` mapping.
# 8. After all ADFs are allocated, update every CGP node function allele upper
#    bound for each chromosome/type so mutation can see the final library size.
# 9. Validate by comparing original saved behavior against restored common-lib
#    behavior, including collision cases where two environments used the same
#    old slot id for different ADFs.
