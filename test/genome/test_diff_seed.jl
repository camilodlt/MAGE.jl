@testset "Genome Diff Seed" begin
    @test begin
        """
        4 individuals: 
            1, 3, 4 => init with the same seed
            2 => init after the 1, so the internal state of the RNG should provide another genome
        1 = 3 = 4 && 1 != 2 
        """

        model_arch = modelArchitecture([Float64], [1], [Float64], [Float64], [1])
        float_bundles = get_sr_float_bundles()
        lib_float = Library(float_bundles)
        ml = MetaLibrary([lib_float])
        node_config = nodeConfig(5, 1, 2, 1)

        # Make two times without restarting seed
        Random.seed!(123)
        shared_inputs, ut_genome_1 = make_evolvable_utgenome(model_arch, ml, node_config)
        initialize_genome!(ut_genome_1) # the randomness
        shared_inputs, ut_genome_2 = make_evolvable_utgenome(model_arch, ml, node_config)
        initialize_genome!(ut_genome_2) # the randomness

        Random.seed!(123) # the same state as genome 1
        shared_inputs, ut_genome_3 = make_evolvable_utgenome(model_arch, ml, node_config)
        initialize_genome!(ut_genome_3) # the randomness

        Random.seed!(123) # the same state as genome 1
        shared_inputs, ut_genome_4 = make_evolvable_utgenome(model_arch, ml, node_config)
        initialize_genome!(ut_genome_4) # the randomness
        correct_all_nodes!(ut_genome_4, model_arch, ml, shared_inputs)

        cond1 = general_hasher_sha(ut_genome_1) != general_hasher_sha(ut_genome_2)
        cond2 =
            general_hasher_sha(ut_genome_1) ==
            general_hasher_sha(ut_genome_3) ==
            general_hasher_sha(ut_genome_4)
        cond1 && cond2
    end
end
