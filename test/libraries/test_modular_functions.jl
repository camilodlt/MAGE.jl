using UTCGP
using Random
using UTCGP: select_random_subgraph, ModularFunction

@testset "Modular Functions" begin
    @testset "Subgraph Selection and Execution" begin
        fixture = _modular_function_program_fixture()
        cfg_model = fixture.cfg_model
        ml = fixture.ml
        full_program = fixture.full_program
        identity_int = fixture.identity_int

        @show full_program

        result = UTCGP.evaluate_program(full_program, cfg_model.chromosomes_types, ml)
        @show result
        @test result == 19

        UTCGP.reset_program!(full_program)

        rng = Random.MersenneTwister(42)
        subgraph_result = select_random_subgraph(full_program, cfg_model, 2; rng = rng, min_ops = 3)

        @show subgraph_result
        @test !isnothing(subgraph_result)

        subgraph_program, sg_input_types, sg_output_type = subgraph_result
        @show subgraph_program
        @show sg_input_types
        @show sg_output_type

        @test sg_output_type == Int
        @test sg_input_types == [Int, Int]
        @test length(subgraph_program.program) == 3

        subgraph_end_node = subgraph_program.program[end].calling_node
        subgraph_output_node = OutputNode(nothing, 4, 4, 2)
        subgraph_output_op = Operation(
            identity_int,
            subgraph_output_node,
            [OperationInput(subgraph_end_node, 2, Int)],
        )
        push!(subgraph_program.program, subgraph_output_op)
        @show subgraph_program

        mod_fn = ModularFunction(
            subgraph_program,
            :my_mod_fn,
            sg_input_types,
            sg_output_type,
            cfg_model.chromosomes_types,
            ml,
        )

        @test which(mod_fn, Tuple{Int, Int}) isa Any
        @test_throws MethodError which(mod_fn, Tuple{String})

        subgraph_value_12 = mod_fn(1234, 10)
        subgraph_value_21 = mod_fn(10, 1234)
        @show subgraph_value_12
        @show subgraph_value_21
        @test sort([subgraph_value_12, subgraph_value_21]) == [14, 1236]
    end
end
