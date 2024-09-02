using UTCGP
using Debugger
using Test

import UTCGP: decode_with_output_node
function get_example_utgraph()
    # 2 types
    # 2 inputs, 3 nodes, 1 output node 

    ma =
        modelArchitecture([String, String], [1, 1], [String, Vector{String}], [String], [1])
    bundles_string =
        [bundle_string_basic, bundle_string_paste, bundle_string_concat_list_string]
    bundles_list_string = [bundle_listgeneric_basic, bundle_liststring_split]

    # Libraries
    lib_str = Library(bundles_string)
    lib_list_str = Library(bundles_list_string)
    ml = MetaLibrary([lib_str, lib_list_str])
    nc = nodeConfig(3, 1, 2, 2)
    shared_inputs, ut_genome = make_evolvable_utgenome(ma, ml, nc)
    initialize_genome!(ut_genome)
    shared_inputs.inputs[1].value = "b.e.g.i.n"
    shared_inputs.inputs[2].value = "."
    print(list_functions_names(ml))

    # Modify manually the genome
    # Node 3 calls with `paste` inputs 1,2 => >String
    ut_genome[1][1][1].value = 5 # Function paste0
    ut_genome[1][1][2].value = 1 # con 1
    ut_genome[1][1][4].value = 2 # con 2
    ut_genome[1][1][3].value = 1 # type string
    ut_genome[1][1][5].value = 1 # type string 
    # => "b.e.g.i.n."

    # Node 4,2 calls with split by inputs 3 and 1 => list str
    ut_genome[2][2][1].value = 4 # Function split_string_to_vector
    ut_genome[2][2][2].value = 3 # con 3 "b.e.g.i.n."
    ut_genome[2][2][4].value = 2 # con 1 "."
    ut_genome[2][2][3].value = 1 # type string
    ut_genome[2][2][5].value = 1 # type string
    # => ["b","e","g","i","n"]

    # Node 5,1 calls with concat from input 4 => string
    ut_genome[1][3][1].value = 9 # Function paste_list_string # TODO replace with get_fn_by_name or smth
    ut_genome[1][3][2].value = 4 # con 3
    ut_genome[1][3][4].value = 1 # con 1, does not matter
    ut_genome[1][3][3].value = 2 # type string
    ut_genome[1][3][5].value = 1 # type string, does not matter
    # => "begin"
    # Output node
    ut_genome.output_nodes[1][2].value = 5
    ut_genome.output_nodes[1][3].value = 1
    # => "begin"

    # Decode
    program =
        decode_with_output_node(ut_genome, ut_genome.output_nodes[1], ml, ma, shared_inputs)
    res = UTCGP.evaluate_program(program, [String, Vector{String}], ml)
    return ma, ml, nc, program, res, shared_inputs, ut_genome
end


function get_example_utgraph_2out()
    # 2 types
    # 2 inputs, 3 nodes, 1 output node 

    ma = modelArchitecture(
        [String, String],
        [1, 1],
        [String, Vector{String}],
        [String, String],
        [1, 1],
    )
    bundles_string =
        [bundle_string_basic, bundle_string_paste, bundle_string_concat_list_string]
    bundles_list_string = [bundle_listgeneric_basic, bundle_liststring_split]

    # Libraries
    lib_str = Library(bundles_string)
    lib_list_str = Library(bundles_list_string)
    ml = MetaLibrary([lib_str, lib_list_str])
    nc = nodeConfig(3, 1, 2, 2)
    shared_inputs, ut_genome = make_evolvable_utgenome(ma, ml, nc)
    initialize_genome!(ut_genome)
    shared_inputs.inputs[1].value = "b.e.g.i.n"
    shared_inputs.inputs[2].value = "."
    print(list_functions_names(ml))

    # Modify manually the genomebundle_liststring_split
    # Node 3 calls with `paste` inputs 1,2 => >String
    ut_genome[1][1][1].value = 5 # Function paste0
    ut_genome[1][1][2].value = 1 # con 1
    ut_genome[1][1][4].value = 2 # con 2
    ut_genome[1][1][3].value = 1 # type string
    ut_genome[1][1][5].value = 1 # type string 
    # => "b.e.g.i.n."

    # Node 4,2 calls with split by inputs 3 and 1 => list str
    ut_genome[2][2][1].value = 4 # Function split_string_to_vector
    ut_genome[2][2][2].value = 3 # con 3 "b.e.g.i.n."
    ut_genome[2][2][4].value = 2 # con 1 "."
    ut_genome[2][2][3].value = 1 # type string
    ut_genome[2][2][5].value = 1 # type string
    # => ["b","e","g","i","n"]

    # Node 5,1 calls with concat from input 4 => string
    ut_genome[1][3][1].value = 9 # Function paste_list_string # TODO replace with get_fn_by_name or smth
    ut_genome[1][3][2].value = 4 # con 3
    ut_genome[1][3][4].value = 1 # con 1, does not matter
    ut_genome[1][3][3].value = 2 # type list_string
    ut_genome[1][3][5].value = 1 # type string, does not matter
    # => "begin"
    # Output node 1 connects to (5,1)
    ut_genome.output_nodes[1][2].value = 5
    ut_genome.output_nodes[1][3].value = 1
    # Output node 2 connects to (3,1)
    ut_genome.output_nodes[2][2].value = 3
    ut_genome.output_nodes[2][3].value = 1
    # => "begin"

    # Decode
    program_1 =
        decode_with_output_node(ut_genome, ut_genome.output_nodes[1], ml, ma, shared_inputs)
    program_2 =
        decode_with_output_node(ut_genome, ut_genome.output_nodes[2], ml, ma, shared_inputs)
    res_1 = UTCGP.evaluate_program(program_1, [String, Vector{String}], ml)
    res_2 = UTCGP.evaluate_program(program_2, [String, Vector{String}], ml)
    @show res_1
    @show res_2
    return ma, ml, nc, program_1, program_2, res_1, res_2, shared_inputs, ut_genome
end

@testset "Numbered Mutation" begin

    # TEST WITH 1 OUTPUT -----
    @test begin

        ma, ml, nc, program, res, shared_inputs, ut_genome = get_example_utgraph()
        res == "begin"
    end

    @test begin
        ma, ml, nc, program, res, shared_inputs, ut_genome = get_example_utgraph()
        ind_programs = UTCGP.IndividualPrograms([program])
        active_nodes = get_active_nodes(ind_programs)
        length(active_nodes) == 3
    end
    @test begin
        ma, ml, nc, program, res, shared_inputs, ut_genome = get_example_utgraph()
        ind_programs = UTCGP.IndividualPrograms([program])
        active_nodes = get_active_nodes(ind_programs)
        active_nodes[1].id == "nd (3,1)"
    end
    @test begin
        ma, ml, nc, program, res, shared_inputs, ut_genome = get_example_utgraph()
        ind_programs = UTCGP.IndividualPrograms([program])
        active_nodes = get_active_nodes(ind_programs)
        active_nodes[2].id == "nd (4,2)"
    end
    @test begin
        ma, ml, nc, program, res, shared_inputs, ut_genome = get_example_utgraph()
        ind_programs = UTCGP.IndividualPrograms([program])
        active_nodes = get_active_nodes(ind_programs)
        active_nodes[3].id == "nd (5,1)"
    end

    # TEST WITH 2 OUTPUTS -----
    @test begin
        ma, ml, nc, program_1, program_2, res_1, res_2, shared_inputs, ut_genome =
            get_example_utgraph_2out()
        res_1 == "begin" && res_2 == "b.e.g.i.n."
    end
    # THE NUMBER OF UNIQUE ACTIVE NODES IS STILL 3
    @test begin
        ma, ml, nc, program_1, program_2, res_1, res_2, shared_inputs, ut_genome =
            get_example_utgraph_2out()
        ind_programs = UTCGP.IndividualPrograms([program_1, program_2])
        active_nodes = get_active_nodes(ind_programs)
        length(active_nodes) == 3
    end
    @test begin
        ma, ml, nc, program_1, program_2, res_1, res_2, shared_inputs, ut_genome =
            get_example_utgraph_2out()
        ind_programs = UTCGP.IndividualPrograms([program_1, program_2])
        active_nodes = get_active_nodes(ind_programs)
        active_nodes[1].id == "nd (3,1)"
    end
    @test begin
        ma, ml, nc, program_1, program_2, res_1, res_2, shared_inputs, ut_genome =
            get_example_utgraph_2out()
        ind_programs = UTCGP.IndividualPrograms([program_1, program_2])
        active_nodes = get_active_nodes(ind_programs)
        active_nodes[2].id == "nd (4,2)"
    end
    @test begin
        ma, ml, nc, program_1, program_2, res_1, res_2, shared_inputs, ut_genome =
            get_example_utgraph_2out()
        ind_programs = UTCGP.IndividualPrograms([program_1, program_2])
        active_nodes = get_active_nodes(ind_programs)
        active_nodes[3].id == "nd (5,1)"
    end

    #
    # NUMBERED_MUTATION -- bad run conf 
    @test_throws AssertionError begin

        ma, ml, nc, program_1, program_2, res_1, res_2, shared_inputs, ut_genome =
            get_example_utgraph_2out()
        run_conf = runConf(3, 100_000, 0.8, 0.1)
        numbered_mutation!(ut_genome, run_conf, ma, ml, shared_inputs)
    end
    # NUMBERED_MUTATION -- logs the mutation so at least one will take place
    @test_logs (:debug, r"Selected node.*") match_mode = :any begin
        ma, ml, nc, program_1, program_2, res_1, res_2, shared_inputs, ut_genome =
            get_example_utgraph_2out()
        run_conf = runConf(3, 100_000, 1.1, 0.1)
        numbered_mutation!(ut_genome, run_conf, ma, ml, shared_inputs)
    end
    # NUMBERED_MUTATION -- Make the mutation
    @test begin
        Random.seed!(1234)
        ma, ml, nc, program_1, program_2, res_1, res_2, shared_inputs, ut_genome =
            get_example_utgraph_2out()
        run_conf = runConf(3, 100_000, 2.2, 0.1)
        prev_state_3 = node_to_vector(ut_genome[1][1]) # 3,1
        prev_state_2 = node_to_vector(ut_genome[2][1]) # 4,2
        prev_state_1 = node_to_vector(ut_genome[1][3]) # 5,1
        prev_states = [prev_state_1, prev_state_2, prev_state_3]

        selected_nodes, sampled_idx =
            numbered_mutation!(ut_genome, run_conf, ma, ml, shared_inputs)
        prev_states = prev_states[sampled_idx]
        conds = []
        for (prv, mutated_node) in zip(prev_states, selected_nodes)
            @show prv
            @show node_to_vector(mutated_node)
            push!(conds, prv != node_to_vector(mutated_node))
        end

        @show sampled_idx
        @show conds
        all(conds)
    end
end
