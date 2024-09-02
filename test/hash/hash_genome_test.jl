# TODO RM in favor of sn tests


function get_test_env()
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
    return ma, ml, nc
end

@testset "Serialization Genome" begin
    # --- SINGLE GENOME ---
    @test begin # the same obj should serialize to the same 
        g1 = make_evolvable_single_genome(1, 1, 1, 1, 1, 2, 2)
        hash_by(g1, basic_serializer) == hash_by(g1, basic_serializer)
    end
    @test begin # to obj with the same params should be the same
        g1 = make_evolvable_single_genome(1, 1, 1, 1, 1, 2, 2)
        g2 = make_evolvable_single_genome(1, 1, 1, 1, 1, 2, 2)
        hash_by(g1, basic_serializer) == hash_by(g2, basic_serializer)
    end
    # --- FULL UT GENOME --- 
    @test begin # SAME  UTGENOME
        ma, ml, nc = get_test_env()
        shared_inputs, ut_genome = make_evolvable_utgenome(ma, ml, nc)
        initialize_genome!(ut_genome)
        shared_inputs.inputs[1].value = "b.e.g.i.n"
        shared_inputs.inputs[2].value = "."
        hash_by(ut_genome, basic_serializer) == hash_by(ut_genome, basic_serializer)
    end
    @test begin # 2 independent genome but they have the same values
        ma, ml, nc = get_test_env()
        shared_inputs, ut_genome_1 = make_evolvable_utgenome(ma, ml, nc) # genome 1 should be diff than genome 2
        shared_inputs, ut_genome_2 = make_evolvable_utgenome(ma, ml, nc) # bc of random init of values
        initialize_genome!(ut_genome_1)
        initialize_genome!(ut_genome_2)

        # SET ALL VALS to the minimum 
        # bc they where random for each allele
        for algo in [ut_genome_1, ut_genome_2]
            for genome in algo
                for node in genome
                    for el in node
                        el.value = el.lowest_bound
                    end
                end
            end
            for output_node in algo.output_nodes
                for el in output_node
                    el.value = el.lowest_bound
                end
            end
        end
        # Now they should be the same ...
        hash_by(ut_genome_1, basic_serializer) == hash_by(ut_genome_2, basic_serializer)
    end
    @test begin
        # 2 independent genomes. One has a value in a node that the other does not have => We test for inequality of the hashes
        # We then put that missing value in the other genome so that they are equal => we test for equal hashes 

        ma, ml, nc = get_test_env()
        shared_inputs, ut_genome_1 = make_evolvable_utgenome(ma, ml, nc) # genome 1 should be diff than genome 2
        shared_inputs, ut_genome_2 = make_evolvable_utgenome(ma, ml, nc) # bc of random init of values
        initialize_genome!(ut_genome_1)
        initialize_genome!(ut_genome_2)

        # SET ALL VALS to the minimum 
        # bc they where random for each allele
        for algo in [ut_genome_1, ut_genome_2]
            for genome in algo
                for node in genome
                    for el in node
                        el.value = el.lowest_bound
                    end
                end
            end
            for output_node in algo.output_nodes
                for el in output_node
                    el.value = el.lowest_bound
                end
            end
        end
        # Now they should be the same ...

        # If values are set for one of the genomes, it should not work
        # so they are not the same any longer
        ut_genome_1[1][2].value = "adazdzadazda"
        cond1 =
            hash_by(ut_genome_1, basic_serializer) != hash_by(ut_genome_2, basic_serializer)
        # But if we set the node value to the same in the other genome it should be the same again
        ut_genome_2[1][2].value = ut_genome_1[1][2].value
        cond2 =
            hash_by(ut_genome_1, basic_serializer) == hash_by(ut_genome_2, basic_serializer)
        cond1 && cond2
    end
end

@testset "Serialization Phenotype" begin
    # --- FULL UT GENOME DECODED --- 
    @test begin # 2 genome shave the same genometype
        # so they should have the same phenotype => the same decoded program
        ma, ml, nc = get_test_env()
        shared_inputs, ut_genome_1 = make_evolvable_utgenome(ma, ml, nc)
        shared_inputs, ut_genome_2 = make_evolvable_utgenome(ma, ml, nc)
        initialize_genome!(ut_genome_1)
        initialize_genome!(ut_genome_2)
        shared_inputs.inputs[1].value = "b.e.g.i.n"
        shared_inputs.inputs[2].value = "."

        # SET ALL VALS to the minimum 
        # bc they where random for each allele
        for algo in [ut_genome_1, ut_genome_2]
            for genome in algo
                for node in genome
                    for el in node
                        el.value = el.lowest_bound
                    end
                end
            end
            for output_node in algo.output_nodes
                for el in output_node
                    el.value = el.lowest_bound
                end
            end
        end

        # DECODE UT 1
        program_1_ut1 = decode_with_output_node(
            ut_genome_1,
            ut_genome.output_nodes[1],
            ml,
            ma,
            shared_inputs,
        )

        # DECODE UT 2
        program_1_ut2 = decode_with_output_node(
            ut_genome_2,
            ut_genome.output_nodes[1],
            ml,
            ma,
            shared_inputs,
        )

        # BOTH PROGRAMS SHOULD BE THE SAME
        hash_by(program_1_ut1, basic_serializer) == hash_by(program_1_ut2, basic_serializer)
    end

    @test begin # 2 genomes don't have the same genotype, but they have the same phenotype
        # so their decoded repr should be the same
        ma, ml, nc = get_test_env()
        shared_inputs, ut_genome_1 = make_evolvable_utgenome(ma, ml, nc)
        shared_inputs, ut_genome_2 = make_evolvable_utgenome(ma, ml, nc)
        initialize_genome!(ut_genome_1)
        initialize_genome!(ut_genome_2)
        shared_inputs.inputs[1].value = "b.e.g.i.n"
        shared_inputs.inputs[2].value = "."

        # SET ALL VALS to the minimum 
        # bc they where random for each allele
        for algo in [ut_genome_1, ut_genome_2]
            for genome in algo
                for node in genome
                    for el in node
                        el.value = el.lowest_bound
                    end
                end
            end
            for output_node in algo.output_nodes
                for el in output_node
                    el.value = el.lowest_bound
                end
            end
        end # Now the genomes are the same

        # Now we change an inactive part of the genome 
        # So that genotypes are not longer equal ...
        ut_genome_1[2][1].value = 2
        ut_genome_2[2][1].value = 3
        genotypes_not_equal =
            hash_by(ut_genome_1, basic_serializer) !=
            basic_serializer(ut_genome_2, basic_serializer)

        # The phenotype should remain unchanged
        # So they should be equal
        # DECODE UT 1
        program_1_ut1 = decode_with_output_node(
            ut_genome_1,
            ut_genome.output_nodes[1],
            ml,
            ma,
            shared_inputs,
        )

        # DECODE UT 2
        program_1_ut2 = decode_with_output_node(
            ut_genome_2,
            ut_genome.output_nodes[1],
            ml,
            ma,
            shared_inputs,
        )

        # BOTH PROGRAMS SHOULD BE THE SAME
        phenotypes_equal =
            hash_by(program_1_ut1, basic_serializer) ==
            hash_by(program_1_ut2, basic_serializer)
        genotypes_not_equal && phenotypes_equal
    end

end

# @testset "Serialize By Behavior" begin # TODO V2
#     @test begin
# two identical phenotypes should produce the same behavior
# behavior_serializer = BehaviorSerializer(set, library, etc , ... )
# hash_by(genome, behavior_serializer)
#     end
#     @test begin
# two diff phenotypes but that produce the same results should be identical by behavior
# behavior_serializer = BehaviorSerializer(set, library, etc , ... )
# hash_by(genome, behavior_serializer)
#     end
#     @test begin
# Different phenotypes should produce different behavior
# behavior_serializer = BehaviorSerializer(set, library, etc , ... )
# hash_by(genome, behavior_serializer)
#     end
# end
