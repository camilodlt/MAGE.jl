@testset begin

    @test begin
        # Bundle 
        # bundle import
        using UTCGP: bundle_listtuple_combinatorics
        length(bundle_listtuple_combinatorics) == 2 &&
            _unique_names_in_bundle(bundle_listtuple_combinatorics)
    end
    @test begin
        # Bundle 
        using UTCGP.listtuple_combinatorics: vector_of_products
        a = ["1", "2"]
        b = ["3", "4"]
        vector_of_products(a, b) == [("1", "3"), ("2", "3"), ("1", "4"), ("2", "4")]
    end
    @test begin
        # Bundle 
        using UTCGP.listtuple_combinatorics: vector_of_products
        a = [1, 2]
        b = [3, 4]
        vector_of_products(a, b) == [(1, 3), (2, 3), (1, 4), (2, 4)]
    end
    @test_throws MethodError begin
        # Bundle 
        using UTCGP.listtuple_combinatorics: vector_of_products
        a = ["1", "2"]
        b = [3, 4]
        vector_of_products(a, b)
    end

    # COMBINATIONS
    @test begin
        using UTCGP.listtuple_combinatorics: vector_of_combinations
        vector_of_combinations([1, 2, 3]) == [(1, 2), (1, 3), (2, 3)]
    end
    @test_throws AssertionError begin
        # Throws error on multitype vector
        using UTCGP.listtuple_combinatorics: vector_of_combinations
        vector_of_combinations(Number[1, 2, 3.121])
    end
    @test_throws AssertionError begin
        # Throws error on empty 
        using UTCGP.listtuple_combinatorics: vector_of_combinations
        vector_of_combinations(Int[])
    end
end
