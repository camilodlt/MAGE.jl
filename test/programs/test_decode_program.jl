function _deterministic_program()
    # A program that sums the first and second input then divides by x1. 
    # so for x1 = 1, y2 = 1 => identity((1+1)/1)
    model_arch = modelArchitecture([Int, Int], [1, 1], [Int], [Int], [1])
    bundles_int = [bundle_integer_basic, bundle_number_arithmetic]
    bundles_int = [deepcopy(b) for b in bundles_int]
    update_caster!.(bundles_int, integer_caster)
    update_fallback!.(bundles_int, () -> 0)
    mini_lib_int = Library(bundles_int)
    ml = MetaLibrary([mini_lib_int])
    nc = nodeConfig(3, 1, 3, 2)
    shared_inputs, ut_genome = make_evolvable_utgenome(model_arch, ml, nc)
    initialize_genome!(ut_genome)
    ut_genome[1][1][1].value = 3 # fn to number_sum
    ut_genome[1][1][2].value = 1 # connects to x1
    ut_genome[1][1][4].value = 2 # connects to x2 

    # Div (x4 = x3/x1)
    ut_genome[1][2][1].value = 6 # fn to number_div
    ut_genome[1][2][2].value = 3 # connects to x3
    ut_genome[1][2][4].value = 1 # connects to x1 

    # Div (x5 = id(x4))
    ut_genome[1][3][1].value = 1 # fn to identity
    ut_genome[1][3][2].value = 4 # connects to x3

    # out points to last node (5)
    ut_genome.output_nodes[1][1].value = 1 # identity
    ut_genome.output_nodes[1][2].value = 5 # last node

    (ut_genome, model_arch, ml, shared_inputs, nc)
end

@testset "Decode Program weak ref Inputs" begin
    genome, model_arch, ml, inputs, nc = _deterministic_program()
    dprogram = UTCGP.decode_with_output_nodes(genome, ml, model_arch, inputs)
    # Normal Program
    @test begin # create a prog that does identity(x4) where x4 = (x3)/x1 where x3 = x1+x2
        # append input nodes to pop
        replace_shared_inputs!(dprogram, [2, 2]) # update 
        outputs =
            UTCGP.evaluate_individual_programs(dprogram, model_arch.chromosomes_types, ml)
        reset_genome!(genome)
        length(outputs) == 1 && outputs[1] == 2
    end
    @test begin # Change the inputs for the program.
        # append input nodes to pop
        replace_shared_inputs!(dprogram, [3, 12]) # update 
        outputs =
            UTCGP.evaluate_individual_programs(dprogram, model_arch.chromosomes_types, ml)
        reset_genome!(genome)
        length(outputs) == 1 && outputs[1] == 5
    end

    # MODIFY THE ORIGINAL INPUTS HAS NO EFFECT
    @test begin
        # append input nodes to pop
        replace_shared_inputs!(dprogram, [1, 12]) # update 

        # Modify the original inputs has no effect
        # append input nodes to pop
        replace_shared_inputs!(inputs, [1, 1]) # update 

        # EVAL
        outputs =
            UTCGP.evaluate_individual_programs(dprogram, model_arch.chromosomes_types, ml)
        reset_genome!(genome)
        length(outputs) == 1 && outputs[1] == 13
    end

    @test begin
        # append input nodes to pop
        replace_shared_inputs!(inputs, [1, 1]) # with this inputs the output should be 2
        # The program has other inputs
        replace_shared_inputs!(dprogram, [1, 21]) # with this inputs the output should be 22
        outputs =
            UTCGP.evaluate_individual_programs(dprogram, model_arch.chromosomes_types, ml)
        reset_genome!(genome)
        length(outputs) == 1 && outputs[1] == 22
    end

    # LINK THE PROGRAM NODES TO THE SHARED INPUTS
    @test begin
        # append input nodes to pop
        replace_shared_inputs!(inputs, [1, 13]) # update the inputs in the shared_inputs
        replace_shared_inputs!(dprogram, inputs)
        # link_program_inputs!(dprogram, inputs) # And then link the inputs
        outputs =
            UTCGP.evaluate_individual_programs(dprogram, model_arch.chromosomes_types, ml)
        length(outputs) == 1 && outputs[1] == 14
    end
end
