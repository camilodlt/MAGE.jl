# Local step specifications use zero for the only external input, `x1`.
const _POPULATION_TEST_INPUT_REF = 0

function _population_test_wrapper(fn::Function, name::Symbol)
    return UTCGP.FunctionWrapper(fn, name, nothing, () -> 0)
end

"""Build one small sequential program from readable local-step specifications.

Each step input is either `_POPULATION_TEST_INPUT_REF` for `x1`, or the positive
index of an earlier local step.
"""
function _population_test_sequence(
        label::Symbol,
        dummy_calling_node,
        dummy_output_node,
        step_specs,
        output_tmp_indices::Vector{Int},
    )
    input_ref = UTCGP.SequentialProgramInputRef(1, :x1, Int, (:input, label, 1))
    tmp_refs = Dict(
        step_index => UTCGP.SequentialTmpRef(
            step_index,
            Symbol("tmp$step_index"),
            Int,
            (:tmp, label, step_index),
        ) for step_index in eachindex(step_specs)
    )

    sequential_steps = UTCGP.AbstractSequentialStep[]
    for (step_index, (fn, name, input_refs)) in enumerate(step_specs)
        refs = UTCGP.AbstractSequentialRef[
            input_index == _POPULATION_TEST_INPUT_REF ? input_ref : tmp_refs[input_index] for input_index in input_refs
        ]
        push!(
            sequential_steps,
            UTCGP.SequentialCallStep(
                Symbol("tmp$step_index"),
                (:step, label, step_index),
                dummy_calling_node,
                fn,
                name,
                refs,
                Int,
                Int,
            ),
        )
    end

    outputs = UTCGP.SequentialOutput[
        UTCGP.SequentialOutput(
            Symbol("out$output_index"),
            tmp_refs[tmp_index],
            output_index,
            dummy_output_node,
        ) for (output_index, tmp_index) in enumerate(output_tmp_indices)
    ]

    return UTCGP.SequentialProgram(
        UTCGP.not_lowered_yet,
        :ir,
        sequential_steps,
        outputs,
        Dict{Tuple, Symbol}(),
        Tuple[],
        Tuple[],
        String[],
        Type[Int],
        Type[Int for _ in outputs],
    )
end

"""
Build the three active graphs discussed for population structural sharing.

The third graph omits `b(a)` and `c(a)` because ordinary sequential compilation
already removes inactive operations that cannot reach an output.
"""
function _population_structural_fixture()
    genome, model_architecture, meta_library, inputs, node_config = _deterministic_program()
    decoded = UTCGP.decode_with_output_nodes(genome, meta_library, model_architecture, inputs)
    compiled = UTCGP.compile_program(decoded, model_architecture, meta_library)

    dummy_calling_node = compiled.steps[1].original_node
    dummy_output_node = compiled.outputs[1].original_output_node

    b_fn = _population_test_wrapper((x::Int) -> x + 1, :population_test_b)
    c_fn = _population_test_wrapper(
        (x::Int, rest::Int...) -> isempty(rest) ? 2 * x : x + 2 * only(rest),
        :population_test_c,
    )
    d_fn = _population_test_wrapper((x::Int) -> 10 * x, :population_test_d)
    e_fn = _population_test_wrapper((x::Int) -> x + 100, :population_test_e)

    first = _population_test_sequence(
        :first,
        dummy_calling_node,
        dummy_output_node,
        [
            (b_fn, :b, [_POPULATION_TEST_INPUT_REF]),
            (c_fn, :c, [1, _POPULATION_TEST_INPUT_REF]),
            (d_fn, :d, [2]),
            (e_fn, :e, [_POPULATION_TEST_INPUT_REF]),
        ],
        [3, 4],
    )
    second = _population_test_sequence(
        :second,
        dummy_calling_node,
        dummy_output_node,
        [
            (b_fn, :b, [_POPULATION_TEST_INPUT_REF]),
            (c_fn, :c, [_POPULATION_TEST_INPUT_REF]),
            (d_fn, :d, [2]),
            (e_fn, :e, [_POPULATION_TEST_INPUT_REF]),
        ],
        [3, 4],
    )
    third = _population_test_sequence(
        :third,
        dummy_calling_node,
        dummy_output_node,
        [
            (d_fn, :d, [_POPULATION_TEST_INPUT_REF]),
            (e_fn, :e, [_POPULATION_TEST_INPUT_REF]),
        ],
        [1, 2],
    )

    return first, second, third
end

@testset "Population sequential program reuses structural prefixes and branches" begin
    first, second, third = _population_structural_fixture()
    population = UTCGP.PopulationSequentialProgram()

    push!(population, first)
    push!(population, second)
    push!(population, third)

    # b(a), c(b(a), a), d(c(b(a), a)), e(a), c(a), d(c(a)), and d(a).
    @test length(population.steps) == 7
    @test length(population) == 3
    @test population.individual_step_ids == [[1, 2, 3, 4], [1, 5, 6, 4], [7, 4]]
    @test population(2) == Any[(70, 102), (40, 102), (20, 102)]
    @test population(3) == Any[(100, 103), (60, 103), (30, 103)]

    # The vector constructor is equivalent to incremental insertion.
    from_vector = UTCGP.PopulationSequentialProgram([first, second, third])
    @test from_vector(2) == population(2)
end

@testset "Population sequential program matches normal and individual sequential evaluation" begin
    genome, model_architecture, meta_library, inputs, node_config = _deterministic_program()
    decoded = UTCGP.decode_with_output_nodes(genome, meta_library, model_architecture, inputs)
    sequential = UTCGP.compile_program(decoded, model_architecture, meta_library)
    population = UTCGP.PopulationSequentialProgram(sequential)

    expected = _evaluate_program_tuple(decoded, model_architecture, meta_library, 3, 12)
    @test sequential(3, 12) == expected
    @test population(3, 12) == Any[expected]

    # Inserting the same sequential program must reuse every global step.
    push!(population, sequential)
    @test length(population.steps) == length(sequential.steps)
    @test population(3, 12) == Any[expected, expected]
end

@testset "Population sequential program returns logical times and parallel sample outputs" begin
    first, second, third = _population_structural_fixture()
    population = UTCGP.PopulationSequentialProgram(first)
    push!(population, second)
    push!(population, third)

    workspace = UTCGP.PopulationSequentialWorkspace(population)
    outputs, individual_times = UTCGP.evaluate_population_sequential_program_with_time(
        population,
        2;
        workspace = workspace,
    )

    @test outputs == Any[(70, 102), (40, 102), (20, 102)]
    @test individual_times == [
        sum(workspace.step_times[step_index] for step_index in step_ids) for
            step_ids in population.individual_step_ids
    ]

    sample_args = [(sample,) for sample in 1:16]
    expected_outputs = [population(args...) for args in sample_args]
    actual_outputs = UTCGP.evaluate_population_sequential_program_on_samples(
        population,
        sample_args,
    )
    @test actual_outputs == expected_outputs

    timed_outputs, timed_individual_times = UTCGP.evaluate_population_sequential_program_on_samples(
        population,
        sample_args;
        measure_time = true,
    )
    @test timed_outputs == expected_outputs
    @test size(timed_individual_times) == (3, length(sample_args))
    @test all(time -> time >= 0.0, timed_individual_times)
end
