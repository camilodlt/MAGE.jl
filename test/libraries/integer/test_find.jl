@testset "Find" begin
    @test begin
        # bundle import
        using UTCGP: bundle_integer_find
        length(bundle_integer_find) == 1 && _unique_names_in_bundle(bundle_integer_find)
    end
    @test begin # Correct findings 
        using UTCGP.integer_find: find_first
        find_first([0, 1, 2], 0) == 1 && find_first([0, 1, 2], 1) == 2
    end
    @test begin # Incorrect finding
        using UTCGP.integer_find: find_first
        find_first([0, 1, 2], 10) == 0
    end
    @test begin # returns the first find
        using UTCGP.integer_find: find_first
        find_first([0, 0, 1], 0) == 1
    end
end


