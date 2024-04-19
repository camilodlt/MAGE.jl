@testset "Strict Phenotype Hasher" begin
    @test begin # The same phenotype gives the same hash
        d = sn_setup()
        ind1 = deepcopy(d["utgenome"])
        ind2 = deepcopy(d["utgenome"])
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
        hasher = sn_strictphenotype_hasher()
        hashes = hasher(params)
        hashes[1] == hashes[2]
    end
    @test begin # the hash is = hash(the active part of all callling nodes)
        d = sn_setup()
        ind1 = deepcopy(d["utgenome"])
        p1 = UTCGP.decode_with_output_nodes(
            ind1,
            d["meta_library"],
            d["model_architecture"],
            d["shared_inputs"],
        )
        params = UTCGP.ParametersStandardEpoch(
            [1.0],
            Population([ind1]),
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
        hasher = sn_strictphenotype_hasher()
        hashes = hasher(params)
        hashes[1] == UTCGP.general_hasher_sha(Any[1.0, 2.0, 1.0, 1.0, 1.0, 1.0])
    end
end
