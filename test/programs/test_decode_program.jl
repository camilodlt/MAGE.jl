include(joinpath(@__DIR__, "fixtures/decode_helpers.jl"))

@testset "Decode Program weak ref Inputs" begin
    genome, model_arch, ml, inputs, nc = _deterministic_program()
    dprogram = MAGE.decode_with_output_nodes(genome, ml, model_arch, inputs)
    # Normal Program
    @test begin # create a prog that does identity(x4) where x4 = (x3)/x1 where x3 = x1+x2
        # append input nodes to pop
        replace_shared_inputs!(dprogram, [2, 2]) # update 
        outputs =
            MAGE.evaluate_individual_programs(dprogram, model_arch.chromosomes_types, ml)
        reset_genome!(genome)
        length(outputs) == 1 && outputs[1] == 2
    end
    @test begin # Change the inputs for the program.
        # append input nodes to pop
        replace_shared_inputs!(dprogram, [3, 12]) # update 
        outputs =
            MAGE.evaluate_individual_programs(dprogram, model_arch.chromosomes_types, ml)
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
            MAGE.evaluate_individual_programs(dprogram, model_arch.chromosomes_types, ml)
        reset_genome!(genome)
        length(outputs) == 1 && outputs[1] == 13
    end

    @test begin
        # append input nodes to pop
        replace_shared_inputs!(inputs, [1, 1]) # with this inputs the output should be 2
        # The program has other inputs
        replace_shared_inputs!(dprogram, [1, 21]) # with this inputs the output should be 22
        outputs =
            MAGE.evaluate_individual_programs(dprogram, model_arch.chromosomes_types, ml)
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
            MAGE.evaluate_individual_programs(dprogram, model_arch.chromosomes_types, ml)
        length(outputs) == 1 && outputs[1] == 14
    end
end
