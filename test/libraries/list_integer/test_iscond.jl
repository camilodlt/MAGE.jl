@testset begin
    @test begin
        # bundle import
        using UTCGP: bundle_listinteger_iscond
        length(bundle_listinteger_iscond) == 6 &&
            _unique_names_in_bundle(bundle_listinteger_iscond)
    end
    @test begin
        using UTCGP.listinteger_iscond: is_sup_0
        is_sup_0([0, 1, 2]) == [0, 1, 1]
    end
    @test begin
        using UTCGP.listinteger_iscond: is_eq_0
        is_eq_0([0, 1, 2]) == [1, 0, 0]
    end
    @test begin
        using UTCGP.listinteger_iscond: is_less_0
        is_less_0([0, 1, 2]) == [0, 0, 0]
    end

    # FROM TUPLE 
    @test begin
        using UTCGP.listinteger_iscond: compare_tuple_a_gr_b
        compare_tuple_a_gr_b([(1, 0), (1, 1)]) == [1, 0]
    end
    @test begin
        using UTCGP.listinteger_iscond: compare_tuple_a_eq_b
        compare_tuple_a_eq_b([(1, 0), (1, 1)]) == [0, 1]
    end
    @test begin
        using UTCGP.listinteger_iscond: compare_tuple_a_less_b
        compare_tuple_a_less_b([(1, 0), (1, 1)]) == [0, 0]
    end
end


