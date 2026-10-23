include(joinpath(@__DIR__, "../programs/fixtures/decode_helpers.jl"))

function _single_output_tuple(genome, model_arch, ml, inputs, values...)
    decoded = MAGE.decode_with_output_nodes(genome, ml, model_arch, inputs)
    replace_shared_inputs!(decoded, Any[values...])
    outputs = MAGE.evaluate_individual_programs(decoded, model_arch.chromosomes_types, ml)
    MAGE.reset_programs!(decoded)
    return Tuple(outputs)
end

@testset "ADF which uses exact required signature prefix and ignores extras" begin
    setup = _install_deterministic_adf()
    slot = setup.slots[1]

    @test which(slot, (Int, Int, String)).nargs == 4
    @test which(slot, Tuple{Int, Int, String}).nargs == 4
    @test_throws MethodError which(slot, (Int,))
    @test_throws MethodError which(slot, (Int, String, Int))
end

@testset "ADF slots can be replaced by genome-backed definitions" begin
    setup = _install_deterministic_adf()
    slot = setup.slots[1]
    decoded = MAGE.decode_with_output_nodes(setup.genome, setup.ml, setup.model_arch, setup.inputs)
    seq = MAGE.compile_program(decoded, setup.model_arch, setup.ml)

    replace_shared_inputs!(decoded, Any[2, 2])
    eval_output = MAGE.evaluate_individual_programs(decoded, setup.model_arch.chromosomes_types, setup.ml)
    MAGE.reset_programs!(decoded)

    @test !adf_is_empty(slot)
    @test eval_output == collect(seq(2, 2)) == [slot(2, 2)]
    @test slot.definition.genome !== setup.genome
    @test slot.definition.sequential_program(3, 12) == seq(3, 12)
    @test setup.registry.wrappers[slot.slot_id].name == :adf_sum_div
    @test setup.registry.wrappers[slot.slot_id].description ==
        MAGE.sequential_source(slot.definition.sequential_program)
end

@testset "ADF usage checks include population and recursive ADF dependencies" begin
    setup = _install_deterministic_adf()
    adf_fn_index = length(setup.ml[1]) - 1
    parent_genome, parent_arch, parent_inputs = _adf_calling_genome(adf_fn_index)
    parent_programs = MAGE.decode_with_output_nodes(parent_genome, setup.ml, parent_arch, parent_inputs)

    replace_adf_slot!(
        setup.registry,
        setup.slots[2].slot_id,
        parent_genome,
        parent_inputs,
        parent_arch,
        setup.ml;
        name = :adf_calls_adf_sum_div,
    )

    @test direct_adf_usage(parent_programs) == Set([setup.slots[1].slot_id])
    @test !can_replace_adf_slot(setup.registry, setup.slots[1].slot_id, [parent_programs])
    @test setup.slots[1].slot_id in recursive_adf_dependencies(setup.registry, setup.slots[2].slot_id)
    @test !can_replace_adf_slot(setup.registry, setup.slots[1].slot_id, MAGE.IndividualPrograms[])
    @test _single_output_tuple(parent_genome, parent_arch, setup.ml, parent_inputs, 2, 2) == (setup.slots[1](2, 2),)
end

@testset "ADF saved environments namespace historical slots and order dependencies" begin
    setup = _install_deterministic_adf()
    adf_fn_index = length(setup.ml[1]) - 1
    parent_genome, parent_arch, parent_inputs = _adf_calling_genome(adf_fn_index)
    parent_programs = MAGE.decode_with_output_nodes(parent_genome, setup.ml, parent_arch, parent_inputs)

    replace_adf_slot!(
        setup.registry,
        setup.slots[2].slot_id,
        parent_genome,
        parent_inputs,
        parent_arch,
        setup.ml;
        name = :adf_calls_adf_sum_div,
    )

    environment = saved_adf_environment(
        :elite_1_generation_10,
        setup.registry,
        [setup.slots[2].slot_id],
    )
    ordered_refs = [definition.ref for definition in saved_adf_dependency_order(environment)]
    expected_refs = [
        SavedADFRef(:elite_1_generation_10, setup.slots[1].slot_id),
        SavedADFRef(:elite_1_generation_10, setup.slots[2].slot_id),
    ]

    @test ordered_refs == expected_refs
    @test all(definition.ref.environment_id == :elite_1_generation_10 for definition in environment.definitions)
    @test SavedADFRef(:elite_2_generation_10, setup.slots[1].slot_id) != expected_refs[1]
    @test saved_individual_with_adfs(
        :elite_1_generation_10,
        parent_genome,
        parent_inputs,
        parent_arch,
        setup.registry,
        parent_programs,
    ).adf_environment.environment_id == :elite_1_generation_10
end

@testset "ADF saved environments roundtrip through Serialization" begin
    setup = _install_deterministic_adf()
    adf_fn_index = length(setup.ml[1]) - 1
    parent_genome, parent_arch, parent_inputs = _adf_calling_genome(adf_fn_index)
    parent_programs = MAGE.decode_with_output_nodes(parent_genome, setup.ml, parent_arch, parent_inputs)

    saved = saved_individual_with_adfs(
        :elite_roundtrip,
        parent_genome,
        parent_inputs,
        parent_arch,
        setup.registry,
        parent_programs,
    )

    mktempdir() do dir
        environment_path = joinpath(dir, "adf_environment.jls")
        individual_path = joinpath(dir, "individual_with_adfs.jls")

        save_adf_environment(environment_path, saved.adf_environment)
        loaded_environment = load_adf_environment(environment_path)

        save_individual_with_adfs(individual_path, saved)
        loaded_saved = load_individual_with_adfs(individual_path)

        @test loaded_environment.environment_id == :elite_roundtrip
        @test [definition.ref for definition in saved_adf_dependency_order(loaded_environment)] ==
            [SavedADFRef(:elite_roundtrip, setup.slots[1].slot_id)]
        @test loaded_environment.definitions[1].source == saved.adf_environment.definitions[1].source
        @test loaded_saved.adf_environment.environment_id == :elite_roundtrip
        @test loaded_saved.adf_environment.definitions[1].dependencies ==
            saved.adf_environment.definitions[1].dependencies
        @test _single_output_tuple(
            loaded_saved.genome,
            loaded_saved.model_architecture,
            setup.ml,
            loaded_saved.shared_inputs,
            2,
            2,
        ) == _single_output_tuple(parent_genome, parent_arch, setup.ml, parent_inputs, 2, 2)
    end
end

@testset "ADF flattening preserves behavior and removes first-level ADF calls" begin
    setup = _install_deterministic_adf()
    adf_fn_index = length(setup.ml[1]) - 1
    parent_genome, parent_arch, parent_inputs = _adf_calling_genome(adf_fn_index)
    flat_genome = flatten_adfs(parent_genome, parent_inputs, parent_arch, setup.ml, setup.registry)

    parent_seq = MAGE.compile_program(
        MAGE.decode_with_output_nodes(parent_genome, setup.ml, parent_arch, parent_inputs),
        parent_arch,
        setup.ml,
    )
    flat_seq = MAGE.compile_program(
        MAGE.decode_with_output_nodes(flat_genome, setup.ml, parent_arch, parent_inputs),
        parent_arch,
        setup.ml,
    )

    @test flat_genome !== parent_genome
    @test _single_output_tuple(parent_genome, parent_arch, setup.ml, parent_inputs, 2, 2) ==
        _single_output_tuple(flat_genome, parent_arch, setup.ml, parent_inputs, 2, 2)
    @test !occursin("adf_sum_div", MAGE.sequential_source(flat_seq))
    @test occursin("adf_sum_div", MAGE.sequential_source(parent_seq))
end
