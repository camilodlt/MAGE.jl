@testset "SN writer Internals" begin

    ### WRITER INTERNALS ### 
    @test begin # Creation of unique id_hash
        one, two, three, four = "one", "two", "three", "four"
        hashes = OrderedDict("h1" => [one, three], "h2" => [two, four])
        # Automatic calc
        id1 = MAGE._calc_individual_unique_hash(hashes, 1)
        id2 = MAGE._calc_individual_unique_hash(hashes, 2)
        # manual calc
        id1_manual = MAGE.general_hasher_sha([one, two])
        id2_manual = MAGE.general_hasher_sha([three, four])
        id1 == id1_manual && id2 == id2_manual
    end

    @test_throws AssertionError begin # there is not a hash for every individual so it errors
        one, two, three, four = "one", "two", "three", "four"
        hashes = OrderedDict("h1" => [three], "h2" => [two, four])
        # Automatic calc
        MAGE._assert_all_individuals_have_all_info(hashes)
    end

end

