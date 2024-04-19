@testset "SN Node Hasher" begin
    # HASHING BY GENOME ---
    @test begin # 2 individuals with the same genome
        d = sn_setup()
        ind1 = deepcopy(d["utgenome"])
        ind2 = deepcopy(d["utgenome"])
        p1 = UTCGP.decode_with_output_nodes(
            ind1,
            d["meta_library"],
            d["model_architecture"],
            d["shared_inputs"],
        )
        params = UTCGP.ParametersStandardEpoch(
            [1.0, 2.0],
            Population([ind1, ind2]),
            1,
            d["run_config"],
            d["model_architecture"],
            d["node_config"],
            d["meta_library"],
            d["shared_inputs"],
            UTCGP.PopulationPrograms(UTCGP.IndividualPrograms[]), # mocked
            1.0,
            p1,
            1,
        )
        hashes = sn_genotype_hasher(params)
        hashes[1] == hashes[2]
    end
    @test begin # 2 individuals with different genome (inactive part)
        d = sn_setup()
        ind1 = deepcopy(d["utgenome"])
        ind2 = deepcopy(d["utgenome"])
        ind2[2][1][1].value = 2 # this node is not in the active graph
        p1 = UTCGP.decode_with_output_nodes(
            ind1,
            d["meta_library"],
            d["model_architecture"],
            d["shared_inputs"],
        )
        params = UTCGP.ParametersStandardEpoch(
            [1.0, 2.0],
            Population([ind1, ind2]),
            1,
            d["run_config"],
            d["model_architecture"],
            d["node_config"],
            d["meta_library"],
            d["shared_inputs"],
            UTCGP.PopulationPrograms(UTCGP.IndividualPrograms[]), # mocked
            1.0,
            p1,
            1,
        )
        hashes = sn_genotype_hasher(params)
        hashes[1] != hashes[2]
    end

    # SOFT PHENOTYPE ---
    @test begin # The program is the same because a non active node was changed
        d = sn_setup()
        ind1 = deepcopy(d["utgenome"])
        ind2 = deepcopy(d["utgenome"])
        ind2[2][1][1].value = 2 # this node is not in the active graph
        p1 = UTCGP.decode_with_output_nodes(
            ind1,
            d["meta_library"],
            d["model_architecture"],
            d["shared_inputs"],
        )
        p2 = UTCGP.decode_with_output_nodes(
            ind2,
            d["meta_library"],
            d["model_architecture"],
            d["shared_inputs"],
        )
        params = UTCGP.ParametersStandardEpoch(
            [1.0, 2.0],
            Population([ind1, ind2]),
            1,
            d["run_config"],
            d["model_architecture"],
            d["node_config"],
            d["meta_library"],
            d["shared_inputs"],
            UTCGP.PopulationPrograms([p1, p2]),
            1.0,
            p1,
            1,
        )
        hashes = sn_softphenotype_hasher(params)
        hashes[1] == hashes[2]
    end
    @test begin # The program is different because we changed a node that 
        # is being used
        d = sn_setup()
        ind1 = deepcopy(d["utgenome"])
        ind2 = deepcopy(d["utgenome"])
        ind1.output_nodes[1][2].value = 1 # this changes the program
        p1 = UTCGP.decode_with_output_nodes(
            ind1,
            d["meta_library"],
            d["model_architecture"],
            d["shared_inputs"],
        )
        p2 = UTCGP.decode_with_output_nodes(
            ind2,
            d["meta_library"],
            d["model_architecture"],
            d["shared_inputs"],
        )
        params = UTCGP.ParametersStandardEpoch(
            [1.0, 2.0],
            Population([ind1, ind2]),
            1,
            d["run_config"],
            d["model_architecture"],
            d["node_config"],
            d["meta_library"],
            d["shared_inputs"],
            UTCGP.PopulationPrograms([p1, p2]),
            1.0,
            p1,
            1,
        )
        hashes = sn_softphenotype_hasher(params)
        hashes[1] != hashes[2]
    end

    # Fitness hasher # Just gives the fitness 

    @test begin # 
        d = sn_setup()
        ind1 = deepcopy(d["utgenome"])
        ind2 = deepcopy(d["utgenome"])
        ind3 = deepcopy(d["utgenome"])

        p1 = UTCGP.decode_with_output_nodes(
            ind1,
            d["meta_library"],
            d["model_architecture"],
            d["shared_inputs"],
        )

        params = UTCGP.ParametersStandardEpoch(
            [1.0, 2.0, 3.0], # it just returns this 
            Population([ind1, ind2, ind3]),
            1,
            d["run_config"],
            d["model_architecture"],
            d["node_config"],
            d["meta_library"],
            d["shared_inputs"],
            UTCGP.PopulationPrograms([p1]),
            1.0,
            p1,
            1,
        )
        hashes = sn_fitness_hasher(params)
        hashes == [1.0, 2.0, 3.0]
    end
end
