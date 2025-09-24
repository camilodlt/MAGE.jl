using UTCGP
using Test
using Random
using UTCGP: _trace_dependencies, select_random_subgraph, _extract_input_node_from_operationInput, CGPNode, ConstantNode, InputNode, Operation, Program, SharedInput, InputPromise, modelArchitecture, nodeConfig, MetaLibrary, Library, FunctionWrapper, FunctionBundle

@testset "Modular Functions" begin
    @testset "Subgraph Selection and Execution" begin
        # 1. SETUP
        # --- Configs
        max_arity = 2
        n_inputs = 2
        n_outputs = 1
        cfg_nodes = nodeConfig(3, 1, max_arity, n_inputs)
        cfg_model = modelArchitecture(
            [Int, Int], [2, 2],
            [String, Int],
            [Int], [2]
        )

        # --- Libraries
        fallback_str = () -> ""
        bundle_string = FunctionBundle(fallback_str)
        fn0 = FunctionWrapper((args...) -> "", :empty_str, nothing, fallback_str)
        fn1 = FunctionWrapper((args...) -> " ", :str_space, nothing, fallback_str)
        fn2 = FunctionWrapper((x::Int, args...) -> string(x), :string, nothing, fallback_str)
        push!(bundle_string.functions, [fn0, fn1, fn2]...)

        fallback_int = () -> 0
        bundle_int = FunctionBundle(fallback_int)
        fn3, fn4, fn5 = FunctionWrapper((args...) -> 1, :add, nothing, fallback_int),
            FunctionWrapper((args...) -> 0, :mult, nothing, fallback_int),
            FunctionWrapper((x::Int, y::Int, args...) -> x + y, :add, nothing, fallback_int)
        push!(
            bundle_int.functions,
            [fn3, fn4, fn5]...
        )
        lib_str = Library([bundle_string]) # A separate string library
        lib_int = Library([bundle_int])
        ml = MetaLibrary([lib_str, lib_int])


        # --- Manually create a genome that represents: output = (length(string(input_1)) + input_2) + 5
        ut_genome = UTCGP.make_evolvable_utgenome(cfg_model, cfg_nodes, ml)

        # To make node lookups easy
        str_chromosome = ut_genome[1]
        int_chromosome = ut_genome[2]
        output_chromosome = ut_genome.output_nodes

        # Chromosome 1 (String output): node = string(input_1)
        str_node = str_chromosome[1]
        str_node[1].value = 1 # fn: string
        str_node[2].value = 1 # connection: input_1
        str_node[3].value = 2 # connection_type: Int (from shared inputs)

        # Chromosome 2 (Int output)
        # Node 1: len_node = length(str_node)
        len_node = int_chromosome[1]
        len_node[1].value = 2 # fn: length
        len_node[2].value = 1 # connection: str_node
        len_node[3].value = 1 # connection_type: String (from str_chromosome)

        # Node 2: add_node = len_node + input_2
        add_node = int_chromosome[2]
        add_node[1].value = 1 # fn: add
        add_node[2].value = 2 # connection: len_node
        add_node[3].value = 2 # connection_type: Int (from int_chromosome)
        add_node[4].value = 2 # connection: input_2
        add_node[5].value = 2 # connection_type: Int (from shared inputs)

        # Output Node: output = add_node + 5
        output_node = output_chromosome[1]
        output_node[1].value = 1 # fn: add
        output_node[2].value = 3 # connection: add_node
        output_node[3].value = 2 # connection_type: Int (from int_chromosome)
        # We need a constant node for the value 5
        five_node = ConstantNode(5, 0, 0, 2) # Belongs to Int chromosome
        add_node_5_op_input = OperationInput(five_node, 2, Int)
        # This is a bit of a hack for testing, as we manually insert a ConstantNode
        # The connection allele would normally point to it.
        output_node.node_material.material[4] = UTCGP.CGPElement(5, 0, 2, 2, 2, false, "PARAMETER") # mock connection


        # 2. DECODE AND VERIFY FULL PROGRAM
        shared_inputs = SharedInput([InputNode(1234, 1, 1, 2), InputNode(10, 2, 2, 2)]) # input_1=1234, input_2=10
        programs = UTCGP.decode_with_output_nodes(ut_genome, ml, cfg_model, shared_inputs)

        # Manually add the constant node to the last operation
        push!(programs[1].program[end].inputs, add_node_5_op_input)

        # Expected result: length(string(1234)) -> 4.  4 + 10 = 14.  Output is 14 + 5 = 19.
        results = UTCGP.evaluate_individual_programs(programs, cfg_model.chromosomes_types, ml)
        @test results[1] == 19

        # 3. SELECT SUBGRAPH
        full_program = programs[1]
        rng = Random.MersenneTwister(42) # Seed for deterministic "random" selection
        subgraph_result = select_random_subgraph(full_program, cfg_model, 2; rng = rng)

        @test !isnothing(subgraph_result)
        subgraph_program, sg_input_types, sg_output_type = subgraph_result

        # 4. VERIFY SUBGRAPH and MODULAR FUNCTION
        mod_fn = ModularFunction(
            subgraph_program,
            :my_mod_fn,
            sg_input_types,
            sg_output_type,
            cfg_model.chromosomes_types,
            ml,
        )

        # The end_node of the selected subgraph determines what we test for.
        # It's the calling_node of the last operation in the new subgraph program.
        end_node_of_subgraph = subgraph_program.program[end].calling_node

        # With RNG seed 42, the selection should be deterministic.
        # Let's test for the case where it selects the `add_node`.
        # This subgraph is `length(string(input_1)) + input_2`
        if end_node_of_subgraph.id == add_node.id
            @test sg_output_type == Int
            @test length(sg_input_types) == 2
            @test all(t -> t == Int, sg_input_types)

            # Test `which` overload
            @test which(mod_fn, Tuple{Int, Int}) isa Any
            @test_throws MethodError which(mod_fn, Tuple{String})

            # 5. EXECUTE MODULAR FUNCTION
            # Inputs to this subgraph were the original inputs: 1234 and 10
            result = mod_fn(1234, 10)
            @test result == 14 # length(string(1234)) + 10 = 14
        else
            @warn "Test might need adjustment. RNG seed 42 did not select the expected `add_node`. It selected `$(end_node_of_subgraph.id)`."
            @test false # Fail the test if the expected node wasn't chosen
        end
    end
end
