############################
# ADF Usage And Dependencies
############################

"""
    adf_slot_from_function(fn)

Return the ADF slot represented by a callable object, or `nothing` for normal
functions.

Example: `adf_slot_from_function(slot)` returns `slot`, while `adf_slot_from_function(+)` returns `nothing`.
"""
adf_slot_from_function(::Any) = nothing
adf_slot_from_function(slot::ADFSlotFunction) = slot

"""
    adf_slot_from_wrapper(wrapper)

Inspect a `FunctionWrapper` and return its inner ADF slot when the wrapper holds
one.

Example: `adf_slot_from_wrapper(wrapper)` returns slot 3 when `wrapper.fn` is that ADF slot.
"""
adf_slot_from_wrapper(wrapper::FunctionWrapper) = adf_slot_from_function(wrapper.fn)

"""
    adf_slot_ids_in_step(step)

Return the ADF slot ids called by one sequential IR step. Non-call steps never
depend on ADFs.

Example: a step that calls `adf_4(x)` returns `Set([4])`.
"""
function adf_slot_ids_in_step(::AbstractSequentialStep)::Set{Int}
    return Set{Int}()
end

function adf_slot_ids_in_step(step::SequentialCallStep)::Set{Int}
    slot = adf_slot_from_wrapper(step.fn)
    isnothing(slot) && return Set{Int}()
    return Set{Int}([slot.slot_id])
end

"""
    direct_adf_usage(program_or_population)

Return the ADF slots used directly by decoded or sequential programs. This does
not recursively inspect the ADF definitions behind those slots.

Example: a program that calls `adf_2(adf_5(x))` directly reports `Set([2, 5])`.
"""
function direct_adf_usage(program::SequentialProgram)::Set{Int}
    used = Set{Int}()
    for step in program.steps
        union!(used, adf_slot_ids_in_step(step))
    end
    return used
end

function direct_adf_usage(program::Program)::Set{Int}
    used = Set{Int}()
    for operation in program
        slot = adf_slot_from_wrapper(operation.fn)
        isnothing(slot) && continue
        push!(used, slot.slot_id)
    end
    return used
end

function direct_adf_usage(programs::IndividualPrograms)::Set{Int}
    used = Set{Int}()
    for program in programs
        union!(used, direct_adf_usage(program))
    end
    return used
end

function direct_adf_usage(population_programs)::Set{Int}
    used = Set{Int}()
    for programs in population_programs
        union!(used, direct_adf_usage(programs))
    end
    return used
end

"""
    adf_dependencies(definition)

Return the direct ADF dependencies inside one ADF definition. Empty definitions
have no dependencies.

Example: an ADF whose body calls slot 7 returns `Set([7])`.
"""
adf_dependencies(::EmptyADFDefinition)::Set{Int} = Set{Int}()
adf_dependencies(definition::ActiveADFDefinition)::Set{Int} =
    direct_adf_usage(definition.sequential_program)

"""
    recursive_adf_dependencies(registry, slot_id)

Walk ADF-to-ADF calls starting from one slot and return every slot reachable
through those definitions.

Example: if `adf_3` calls `adf_2` and `adf_2` calls `adf_1`, this returns `Set([2, 1])`.
"""
function recursive_adf_dependencies(
        registry::ADFRegistry,
        slot_id::Int,
        seen::Set{Int} = Set{Int}(),
    )::Set{Int}
    slot_id in seen && return Set{Int}()
    push!(seen, slot_id)

    direct_dependencies = adf_dependencies(registry.slots[slot_id].definition)
    all_dependencies = copy(direct_dependencies)
    for dependency_id in direct_dependencies
        haskey(registry.slots, dependency_id) || continue
        union!(all_dependencies, recursive_adf_dependencies(registry, dependency_id, seen))
    end
    return all_dependencies
end

"""
    adf_used_by_other_adfs(registry, slot_id)

Return the ADF slots that would break if `slot_id` were removed or replaced,
including indirect dependencies.

Example: if `adf_5` calls `adf_2`, `adf_used_by_other_adfs(registry, 2)` includes `5`.
"""
function adf_used_by_other_adfs(registry::ADFRegistry, slot_id::Int)::Set{Int}
    users = Set{Int}()
    for other_slot_id in keys(registry.slots)
        other_slot_id == slot_id && continue
        slot_id in recursive_adf_dependencies(registry, other_slot_id) && push!(users, other_slot_id)
    end
    return users
end

"""
    can_replace_adf_slot(registry, slot_id, population_programs)

Return true only when no current individual and no other ADF depends on the
candidate slot.

Example: `can_replace_adf_slot(registry, 4, decoded_population)` is false while any individual calls `adf_4`.
"""
function can_replace_adf_slot(
        registry::ADFRegistry,
        slot_id::Int,
        population_programs,
    )::Bool
    slot_id in direct_adf_usage(population_programs) && return false
    return isempty(adf_used_by_other_adfs(registry, slot_id))
end
