using UTCGP
using Random
using UTCGP: select_random_subgraph, CGPNode, ConstantNode, InputNode, SharedInput,
             InputPromise, modelArchitecture, Library, FunctionWrapper,
             FunctionBundle, OperationInput, Operation, Program, ModularFunction

@testset "Modular Functions" begin
    @testset "Subgraph Selection and Execution" begin
        cfg_model = modelArchitecture(
            [Int, Int], [2, 2],
            [String, Int],
            [Int], [2],
        )

        fallback_str = () -> ""
        bundle_string = FunctionBundle(fallback_str)
        empty_str = FunctionWrapper((args...) -> "", :empty_str, nothing, fallback_str)
        str_space = FunctionWrapper((args...) -> " ", :str_space, nothing, fallback_str)
        stringify = FunctionWrapper((x::Int, args...) -> string(x), :string, nothing, fallback_str)
        push!(bundle_string.functions, [empty_str, str_space, stringify]...)

        fallback_int = () -> 0
        bundle_int = FunctionBundle(fallback_int)
        identity_int = FunctionWrapper((x::Int, args...) -> x, :identity_int, nothing, fallback_int)
        add = FunctionWrapper((x::Int, y::Int, args...) -> x + y, :add, nothing, fallback_int)
        str_length = FunctionWrapper((x::String, args...) -> length(x), :length, nothing, fallback_int)
        push!(bundle_int.functions, [identity_int, add, str_length]...)

        ml = UTCGP.MetaLibrary([Library([bundle_string]), Library([bundle_int])])

        shared_inputs = SharedInput([
            InputNode(1234, 1, 1, 1),
            InputNode(10, 2, 2, 1),
        ])

        str_node = CGPNode(nothing, 1, 1, 1)
        len_node = CGPNode(nothing, 1, 1, 2)
        add_node = CGPNode(nothing, 2, 2, 2)
        out_node = OutputNode(nothing, 3, 3, 2)
        five_node = ConstantNode(5, 0, 0, 2)

        str_op = Operation(
            stringify,
            str_node,
            [OperationInput(InputPromise(1), -1, Int)],
        )

        len_op = Operation(
            str_length,
            len_node,
            [OperationInput(str_node, 1, String)],
        )

        add_op = Operation(
            add,
            add_node,
            [
                OperationInput(len_node, 2, Int),
                OperationInput(InputPromise(2), -1, Int),
            ],
        )

        out_op = Operation(
            add,
            out_node,
            [
                OperationInput(add_node, 2, Int),
                OperationInput(five_node, 2, Int),
            ],
        )

        full_program = Program([str_op, len_op, add_op, out_op], shared_inputs)
        full_program.is_reversed = true

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
