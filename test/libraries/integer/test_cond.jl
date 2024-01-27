@testset "Int Cond" begin
    @test begin
        # bundle import
        using UTCGP: bundle_integer_cond
        length(bundle_integer_cond) == 2 && _unique_names_in_bundle(bundle_integer_cond)
    end
    @test begin
        # two ints 
        using UTCGP.integer_cond
        integer_cond.is_eq_to(3, 3) == 1
    end
    @test begin
        # two floats
        integer_cond.is_eq_to(2.12, 2.12) == 1
    end
    @test begin
        # int float mix
        integer_cond.is_eq_to(2, 2.0) == 1 && integer_cond.is_eq_to(2.0, 2) == 1
    end
    @test begin
        # not eq
        integer_cond.is_eq_to(1, 2.0) == 0 && integer_cond.is_eq_to(2.0, 1) == 0
    end

    # EMPTY STRING
    @test begin
        # empty
        using UTCGP.integer_cond
        integer_cond.str_is_empty("") == 1
    end
    @test begin
        # not empty
        using UTCGP.integer_cond
        integer_cond.str_is_empty("1") == 0
    end

end
