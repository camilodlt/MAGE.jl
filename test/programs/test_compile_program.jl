function _test_ref_source(ref::MAGE.SequentialProgramInputRef)
    return String(ref.name)
end

function _test_ref_source(ref::MAGE.SequentialTmpRef)
    return String(ref.tmp_name)
end

function _test_return_type_source(policy::Type)
    return string(policy)
end

function _test_return_type_source(::MAGE.NoTypeAssertion)
    return "NoTypeAssertion()"
end

function _test_step_source(step::MAGE.SequentialConstantStep)
    return "    $(step.tmp_name) = $(repr(step.value))"
end

function _test_step_source(step::MAGE.SequentialCallStep)
    args = join((_test_ref_source(input) for input in step.inputs), ", ")
    return_type = _test_return_type_source(step.return_type_policy)
    return "    $(step.tmp_name) = safe_call($(step.display_name), $args; return_type=$return_type)"
end

function _test_output_source(output::MAGE.SequentialOutput)
    return "    $(output.output_name) = $(_test_ref_source(output.source))"
end

function _test_return_source(outputs)
    names = join((String(output.output_name) for output in outputs), ", ")
    if length(outputs) == 1
        names *= ","
    end
    return "    return ($names)"
end

function _test_source_from_ir(seq::MAGE.SequentialProgram)
    input_names = join(("x$i" for i in eachindex(seq.input_types)), ", ")
    lines = String["function sequential_program($input_names)"]
    append!(lines, [_test_step_source(step) for step in seq.steps])
    append!(lines, [_test_output_source(output) for output in seq.outputs])
    push!(lines, _test_return_source(seq.outputs))
    push!(lines, "end")
    return join(lines, "\n")
end

function _test_source_matches_ir(seq::MAGE.SequentialProgram)
    source = MAGE.sequential_source(seq)
    lines = split(source, '\n')

    @test source == _test_source_from_ir(seq)
    @test length(lines) == 1 + length(seq.steps) + length(seq.outputs) + 2
    @test lines[2:(1 + length(seq.steps))] == [_test_step_source(step) for step in seq.steps]
    @test lines[(2 + length(seq.steps)):(1 + length(seq.steps) + length(seq.outputs))] ==
        [_test_output_source(output) for output in seq.outputs]
end

@testset "Sequential safe_call applies fallback caster and return policy" begin
    fallback = () -> 0
    plus_one = MAGE.FunctionWrapper(
        (x::Int, args...) -> x + 1,
        :plus_one,
        x -> floor(Int, x),
        fallback,
    )
    bad_div = MAGE.FunctionWrapper(
        (x::Int, args...) -> div(x, 0),
        :bad_div,
        nothing,
        fallback,
    )

    @test MAGE.safe_call(plus_one, 1; return_type = Int) === 2
    @test MAGE.safe_call(plus_one, 1; return_type = MAGE.NoTypeAssertion()) === 2
    @test MAGE.safe_call(bad_div, 1; return_type = Int) === 0
    @test_throws AssertionError MAGE.safe_call(plus_one, 1; return_type = String)
end

@testset "Compile Program source for single output" begin
    genome, model_arch, ml, inputs, nc = _deterministic_program()
    decoded = MAGE.decode_with_output_nodes(genome, ml, model_arch, inputs)
    compiled = MAGE.compile_program(decoded, model_arch, ml)
    source = MAGE.sequential_source(compiled)

    _test_source_matches_ir(compiled)
    @test compiled isa MAGE.SequentialProgram
    @test :source ∉ fieldnames(typeof(compiled))
    @test compiled.steps isa Vector
    @test compiled.outputs isa Vector
    @test compiled.input_types isa Vector
    @test compiled.output_types isa Vector
    @test occursin("function sequential_program(x1, x2)", source)
    @test occursin("safe_call(number_sum, x1, x2; return_type=Int64)", source)
    @test occursin("safe_call(number_div, tmp1, x1; return_type=Int64)", source)
    @test occursin("safe_call(identity_int, tmp3; return_type=Int64)", source)
    @test occursin("out1 = tmp4", source)
    @test occursin("return (out1,)", source)
    @test length(compiled.outputs) == 1
    @test length(compiled.steps) == 4
end

@testset "Compile Program source without return type assertions" begin
    genome, model_arch, ml, inputs, nc = _deterministic_program()
    decoded = MAGE.decode_with_output_nodes(genome, ml, model_arch, inputs)
    compiled = MAGE.compile_program(decoded, model_arch, ml; safe = false)
    source = MAGE.sequential_source(compiled)

    _test_source_matches_ir(compiled)
    @test occursin("return_type=NoTypeAssertion()", source)
    @test !occursin("return_type=Int64", source)
end

@testset "Compile Program emits constants as tmp assignments" begin
    fixture = _modular_function_program_fixture()
    decoded = MAGE.IndividualPrograms(MAGE.Program[fixture.full_program])
    compiled = MAGE.compile_program(decoded, fixture.cfg_model, fixture.ml)
    source = MAGE.sequential_source(compiled)

    _test_source_matches_ir(compiled)
    @test occursin("tmp4 = 5", source)
    @test occursin("safe_call(add, tmp3, tmp4; return_type=Int64)", source)
    @test occursin("out1 = tmp5", source)
    @test length(compiled.steps) == 5
    @test compiled.steps[4] isa MAGE.SequentialConstantStep
    @test compiled.steps[5] isa MAGE.SequentialCallStep
end

function _multi_output_shared_program()
    genome, model_arch, ml, inputs, nc = _deterministic_program()
    decoded = MAGE.decode_with_output_nodes(genome, ml, model_arch, inputs)
    return MAGE.IndividualPrograms(MAGE.Program[decoded[1], decoded[1]]), model_arch, ml
end

function _evaluate_program_tuple(decoded, model_arch, ml, args...)
    MAGE.reset_programs!(decoded)
    replace_shared_inputs!(decoded, Any[args...])
    outputs = MAGE.evaluate_individual_programs(decoded, model_arch.chromosomes_types, ml)
    MAGE.reset_programs!(decoded)
    return Tuple(outputs)
end

function _program_calling_node_values(decoded)
    return Any[
        MAGE.get_node_value(operation.calling_node) for program in decoded for
            operation in program
    ]
end

@testset "Compile IndividualPrograms emits one multi-output function with shared tmp values" begin
    decoded, model_arch, ml = _multi_output_shared_program()
    compiled = MAGE.compile_program(decoded, model_arch, ml)
    source = MAGE.sequential_source(compiled)

    _test_source_matches_ir(compiled)
    @test length(compiled.outputs) == 2
    @test length(compiled.steps) == 4
    @test occursin("out1 = tmp4", source)
    @test occursin("out2 = tmp4", source)
    @test occursin("return (out1, out2)", source)
    @test count(line -> occursin("safe_call(number_sum", line), split(source, '\n')) == 1
    @test length(compiled.skipped_duplicates) == 4
end

@testset "Sequential interpreter matches evaluator for single output uni-type program" begin
    genome, model_arch, ml, inputs, nc = _deterministic_program()
    decoded = MAGE.decode_with_output_nodes(genome, ml, model_arch, inputs)
    compiled = MAGE.compile_program(decoded, model_arch, ml)

    @test compiled(2, 2) == _evaluate_program_tuple(decoded, model_arch, ml, 2, 2)
    @test compiled(3, 12) == _evaluate_program_tuple(decoded, model_arch, ml, 3, 12)
end

@testset "Sequential interpreter matches evaluator for multi-output uni-type program" begin
    decoded, model_arch, ml = _multi_output_shared_program()
    compiled = MAGE.compile_program(decoded, model_arch, ml)

    @test compiled(2, 2) == _evaluate_program_tuple(decoded, model_arch, ml, 2, 2)
    @test compiled(3, 12) == _evaluate_program_tuple(decoded, model_arch, ml, 3, 12)
end

@testset "Sequential interpreter matches evaluator for single output multi-type program" begin
    fixture = _modular_function_program_fixture()
    decoded = MAGE.IndividualPrograms(MAGE.Program[fixture.full_program])
    compiled = MAGE.compile_program(decoded, fixture.cfg_model, fixture.ml)

    @test compiled(1234, 10) == _evaluate_program_tuple(decoded, fixture.cfg_model, fixture.ml, 1234, 10)
    @test compiled(10, 1234) == _evaluate_program_tuple(decoded, fixture.cfg_model, fixture.ml, 10, 1234)
end

@testset "Sequential interpreter is thread-safe for shared compiled programs" begin
    decoded, model_arch, ml = _multi_output_shared_program()
    compiled = MAGE.compile_program(decoded, model_arch, ml)
    expected = [compiled(i + 1, i + 2) for i in 1:32]
    actual = Vector{Any}(undef, length(expected))

    MAGE.reset_programs!(decoded)
    @test all(isnothing, _program_calling_node_values(decoded))

    Threads.@threads for i in eachindex(expected)
        actual[i] = compiled(i + 1, i + 2)
    end

    @test actual == expected
    @test all(isnothing, _program_calling_node_values(decoded))
end

@testset "Sequential interpreter matches evaluator for multi-output multi-type program" begin
    fixture = _modular_function_program_fixture()
    decoded = MAGE.IndividualPrograms(MAGE.Program[fixture.full_program, fixture.full_program])
    compiled = MAGE.compile_program(decoded, fixture.cfg_model, fixture.ml)

    @test compiled(1234, 10) == _evaluate_program_tuple(decoded, fixture.cfg_model, fixture.ml, 1234, 10)
    @test compiled(10, 1234) == _evaluate_program_tuple(decoded, fixture.cfg_model, fixture.ml, 10, 1234)
end
