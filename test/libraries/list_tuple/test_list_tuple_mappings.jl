@testset "Mappings" begin
    @test begin
        # Bundle 
        using MAGE: bundle_listtuple_mappings
        length(bundle_listtuple_mappings) == 1 &&
            _unique_names_in_bundle(bundle_listtuple_mappings)
    end
    @test begin
        # Bundle 
        using MAGE: bundle_listtuple_mappings_factory
        length(bundle_listtuple_mappings_factory) == 1 &&
            _unique_names_in_bundle(bundle_listtuple_mappings_factory)
    end
    @test begin
        # Normal 
        import MAGE: listtuple_mappings
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
    let old_constrained = get(ENV, "MAGE_CONSTRAINED", nothing),
        old_small_array = get(ENV, "MAGE_SMALL_ARRAY", nothing),
        old_constrained_ref = MAGE.CONSTRAINED[],
        old_small_array_ref = MAGE.SMALL_ARRAY[]

        try
            ENV["MAGE_CONSTRAINED"] = "yes"
            ENV["MAGE_SMALL_ARRAY"] = "100"
            MAGE.__init__()

            @test_throws AssertionError begin
                # Wrong : too long in constrained mode
                listtuple_mappings.mappings_a_to_b(collect(1:2_000_000), [4, 5, 6])
            end
        finally
            if isnothing(old_constrained)
                delete!(ENV, "MAGE_CONSTRAINED")
            else
                ENV["MAGE_CONSTRAINED"] = old_constrained
            end
            if isnothing(old_small_array)
                delete!(ENV, "MAGE_SMALL_ARRAY")
            else
                ENV["MAGE_SMALL_ARRAY"] = old_small_array
            end
            MAGE.CONSTRAINED[] = old_constrained_ref
            MAGE.SMALL_ARRAY[] = old_small_array_ref
        end
    end
    # Factory
    @test begin
        # Normal 
        z = (@test_factory listtuple_mappings.mappings_a_to_b_factory(Float64))
        d = (@test_factory listtuple_mappings.mappings_a_to_b_factory(String))
        z([1.0, 2.0], [4.0, 5.0]) == [(1.0, 4.0), (2.0, 5.0)] &&
            d(["1.0", "2.0"], ["4.0", "5.0"]) == [("1.0", "4.0"), ("2.0", "5.0")]
    end
    @test_throws MethodError begin
        # Wrong concrete type
        z = (@test_factory listtuple_mappings.mappings_a_to_b_factory(Float64))
        z([1, 2], [4, 5])
    end
end
