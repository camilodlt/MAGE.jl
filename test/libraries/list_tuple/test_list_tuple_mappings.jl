@testset "Mappings" begin
    @test begin
        # Bundle 
        using UTCGP: bundle_listtuple_mappings
        length(bundle_listtuple_mappings) == 1 &&
            _unique_names_in_bundle(bundle_listtuple_mappings)
    end
    @test begin
        # Bundle 
        using UTCGP: bundle_listtuple_mappings_factory
        length(bundle_listtuple_mappings_factory) == 1 &&
            _unique_names_in_bundle(bundle_listtuple_mappings_factory)
    end
    @test begin
        # Normal 
        import UTCGP: listtuple_mappings
        listtuple_mappings.mappings_a_to_b([1, 2, 3], [4, 5, 6]) == [(1, 4), (2, 5), (3, 6)]
    end
    @test begin
        # Normal . Iterators are zipped
        listtuple_mappings.mappings_a_to_b([1], [4, 5, 6]) == [(1, 4)]
    end
    @test_throws MethodError begin
        # Wrong : not the same type
        listtuple_mappings.mappings_a_to_b([1, 2, "3"], [4, 5, 6])
    end
    @test_throws AssertionError begin
        # Wrong : too long
        listtuple_mappings.mappings_a_to_b(collect(1:2_000_000), [4, 5, 6])
    end
    # Factory
    @test begin
        # Normal 
        z = listtuple_mappings.mappings_a_to_b_factory(Float64)
        d = listtuple_mappings.mappings_a_to_b_factory(String)
        z([1.0, 2.0], [4.0, 5.0]) == [(1.0, 4.0), (2.0, 5.0)] &&
            d(["1.0", "2.0"], ["4.0", "5.0"]) == [("1.0", "4.0"), ("2.0", "5.0")]
    end
    @test_throws MethodError begin
        # Wrong concrete type
        z = listtuple_mappings.mappings_a_to_b_factory(Float64)
        z([1, 2], [4, 5])
    end
end
