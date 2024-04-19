@testset "SN writer Internals" begin

    ### WRITER INTERNALS ### 
    @test begin # Creation of unique id_hash
        one, two, three, four = "one", "two", "three", "four"
        hashes = OrderedDict("h1" => [one, three], "h2" => [two, four])
        # Automatic calc
        id1 = UTCGP._calc_individual_unique_hash(hashes, 1)
        id2 = UTCGP._calc_individual_unique_hash(hashes, 2)
        # manual calc
        id1_manual = UTCGP.general_hasher_sha([one, two])
        id2_manual = UTCGP.general_hasher_sha([three, four])
        id1 == id1_manual && id2 == id2_manual
    end

    @test_throws AssertionError begin # there is not a hash for every individual so it errors
        one, two, three, four = "one", "two", "three", "four"
        hashes = OrderedDict("h1" => [three], "h2" => [two, four])
        # Automatic calc
        UTCGP._assert_all_individuals_have_all_info(hashes)
    end

end

