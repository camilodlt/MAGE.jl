@testset begin

    @test begin
        # Bundle 
        # bundle import
        using UTCGP: bundle_listtuple_combinatorics
        length(bundle_listtuple_combinatorics) == 1 &&
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
end
