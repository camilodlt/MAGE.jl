using UTCGP.listgeneric_where: replace_vec_at

@testset "Where" begin
    @test begin
        # bundle import
        using UTCGP: bundle_listgeneric_where
        length(bundle_listgeneric_where) == 1 &&
            _unique_names_in_bundle(bundle_listgeneric_where)
    end

    # REPLACE AT
    @test begin # replace all
        x = ones(Int, 2)
        b = [2, 2]
        replace_vec_at(x, b, [1, 1]) == b
    end
    @test begin # replace one
        x = ones(Int, 2)
        b = [2]
        replace_vec_at(x, b, [0, 1]) == [1, 2] && replace_vec_at(x, b, [1, 0]) == [2, 1]
    end
    @test begin # replace none
        x = ones(Int, 2)
        b = Int[]
        replace_vec_at(x, b, [0, 0]) == x
    end
    # REPLACE AT WRONG CASES 
    @test_throws MethodError begin # x and b of different types
        x = ones(Int, 2)
        b = [2.0, 2.0]
        replace_vec_at(x, b, [1, 1])
    end
    @test_throws AssertionError begin # mask of bad size 
        x = ones(Int, 2)
        b = [2, 2]
        replace_vec_at(x, b, [0, 1, 0])
    end
    @test_throws AssertionError begin # replacing vector of bad size
        x = ones(Int, 2)
        b = [2]
        replace_vec_at(x, b, [0, 0])
    end
end
