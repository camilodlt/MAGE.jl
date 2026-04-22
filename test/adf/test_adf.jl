function _install_deterministic_adf()
    genome, model_arch, ml, inputs, nc = _deterministic_program()
    registry = ADFRegistry()
    slots = extend_fn_lib_adf!(ml[1], registry, Int, 2; fallback = () -> 0)
    replace_adf_slot!(registry, slots[1].slot_id, genome, inputs, model_arch, ml; name = :adf_sum_div)
    return (; genome, model_arch, ml, inputs, registry, slots)
end

function _adf_calling_genome(adf_fn_index::Int)
    genome, model_arch, ml, inputs, nc = _deterministic_program()

    genome[1][1][1].value = adf_fn_index
    genome[1][1][2].value = 1
    genome[1][1][4].value = 2
    genome.output_nodes[1][1].value = 1
    genome.output_nodes[1][2].value = 3

    return genome, model_arch, inputs
end

function _single_output_tuple(genome, model_arch, ml, inputs, values...)
    decoded = UTCGP.decode_with_output_nodes(genome, ml, model_arch, inputs)
    replace_shared_inputs!(decoded, Any[values...])
    outputs = UTCGP.evaluate_individual_programs(decoded, model_arch.chromosomes_types, ml)
    UTCGP.reset_programs!(decoded)
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
    decoded = UTCGP.decode_with_output_nodes(setup.genome, setup.ml, setup.model_arch, setup.inputs)
    seq = UTCGP.compile_program(decoded, setup.model_arch, setup.ml)

    replace_shared_inputs!(decoded, Any[2, 2])
    eval_output = UTCGP.evaluate_individual_programs(decoded, setup.model_arch.chromosomes_types, setup.ml)
    UTCGP.reset_programs!(decoded)

    @test !adf_is_empty(slot)
    @test eval_output == collect(seq(2, 2)) == [slot(2, 2)]
    @test slot.definition.genome !== setup.genome
    @test slot.definition.sequential_program(3, 12) == seq(3, 12)
end

@testset "ADF usage checks include population and recursive ADF dependencies" begin
    setup = _install_deterministic_adf()
    adf_fn_index = length(setup.ml[1]) - 1
    parent_genome, parent_arch, parent_inputs = _adf_calling_genome(adf_fn_index)
    parent_programs = UTCGP.decode_with_output_nodes(parent_genome, setup.ml, parent_arch, parent_inputs)

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
    @test !can_replace_adf_slot(setup.registry, setup.slots[1].slot_id, UTCGP.IndividualPrograms[])
    @test _single_output_tuple(parent_genome, parent_arch, setup.ml, parent_inputs, 2, 2) == (setup.slots[1](2, 2),)
end

@testset "ADF flattening preserves behavior and removes first-level ADF calls" begin
    setup = _install_deterministic_adf()
    adf_fn_index = length(setup.ml[1]) - 1
    parent_genome, parent_arch, parent_inputs = _adf_calling_genome(adf_fn_index)
    flat_genome = flatten_adfs(parent_genome, parent_inputs, parent_arch, setup.ml, setup.registry)

    parent_seq = UTCGP.compile_program(
        UTCGP.decode_with_output_nodes(parent_genome, setup.ml, parent_arch, parent_inputs),
        parent_arch,
        setup.ml,
    )
    flat_seq = UTCGP.compile_program(
        UTCGP.decode_with_output_nodes(flat_genome, setup.ml, parent_arch, parent_inputs),
        parent_arch,
        setup.ml,
    )

    @test flat_genome !== parent_genome
    @test _single_output_tuple(parent_genome, parent_arch, setup.ml, parent_inputs, 2, 2) ==
        _single_output_tuple(flat_genome, parent_arch, setup.ml, parent_inputs, 2, 2)
    @test !occursin("adf_sum_div", UTCGP.sequential_source(flat_seq))
    @test occursin("adf_sum_div", UTCGP.sequential_source(parent_seq))
end
