using UTCGP.listinteger_iscond: even_indices_mask
using UTCGP.listinteger_iscond: odd_indices_mask
using UTCGP.listinteger_iscond: mask
using UTCGP.listinteger_iscond: inverse_mask


using UTCGP.listinteger_iscond: greater_than_broadcast
using UTCGP.listinteger_iscond: less_than_broadcast
using UTCGP.listinteger_iscond: eq_broadcast


using UTCGP.listinteger_iscond: compare_two_vectors



@testset begin
    @test begin
        # bundle import
        using UTCGP: bundle_listinteger_iscond
        length(bundle_listinteger_iscond) == 18 &&
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

    # EQ to something 

    @test begin
        using UTCGP.listinteger_iscond: is_eq_to
        is_eq_to([0, 1, 2], 2) == [0, 0, 1]
    end
    @test begin
        # since == is used
        using UTCGP.listinteger_iscond: is_eq_to
        is_eq_to([0, 1, 2], 2.0) == [0, 0, 1]
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


    # MORE THAN RIGHT
    @test begin
        using UTCGP.listinteger_iscond: is_more_than_right
        is_more_than_right([10, 5, 4]) == [1, 1, 1]
    end
    @test begin
        is_more_than_right([7, 3, 4]) == [1, 0, 1]
    end
    @test begin
        is_more_than_right([2, 2, 2]) == [0, 0, 1]
    end
    # MORE OR EQ THAN RIGHT
    @test begin
        using UTCGP.listinteger_iscond: is_more_eq_than_right
        is_more_eq_than_right([9, 5, 4]) == [1, 1, 1]
    end
    @test begin
        is_more_eq_than_right([7, 3, 4]) == [1, 0, 1]
    end
    @test begin
        is_more_eq_than_right([2, 2, 3]) == [0, 0, 1]
    end
    @test begin
        is_more_eq_than_right([2, 2, 2]) == [1, 1, 1]
    end

    # IS EQ TO PREV
    @test begin
        using UTCGP.listinteger_iscond: is_eq_to_prev
        is_eq_to_prev([1, 1, 2]) == [0, 1, 0] &&
            is_eq_to_prev([1, 2, 3]) == [0, 0, 0] &&
            is_eq_to_prev([1, 1, 1]) == [0, 1, 1]
    end
    # ODD AND EVEN MASK
    @test begin
        even_indices_mask(collect(1:10)) == [0, 1, 0, 1, 0, 1, 0, 1, 0, 1]
    end
    @test begin
        even_indices_mask([]) == [] &&
            even_indices_mask([1]) == [0] &&
            even_indices_mask([1, 1]) == [0, 1]
    end
    @test begin
        odd_indices_mask(collect(1:10)) == [1, 0, 1, 0, 1, 0, 1, 0, 1, 0]
    end
    @test begin
        odd_indices_mask([]) == [] &&
            odd_indices_mask([1]) == [1] &&
            odd_indices_mask([1, 1]) == [1, 0]
    end

    # MASK AND INVERSE MASK
    @test begin
        using UTCGP.listinteger_iscond: mask
        mask([1, 0, 12, 0.12]) == [1, 0, 1, 1] && mask([0, -1]) == [0, 0]
    end
    @test begin
        using UTCGP.listinteger_iscond: mask
        inverse_mask([1, 0, 12, 0.12]) == [0, 1, 0, 0] &&
            inverse_mask([0, -1]) == [1, 1] &&
            inverse_mask([1, 0, 1]) == [0, 1, 0]
    end

    # COMPARE VECTOR AGAINST NUMBER

    using UTCGP.listinteger_iscond: greater_than_broadcast
    using UTCGP.listinteger_iscond: less_than_broadcast
    using UTCGP.listinteger_iscond: eq_broadcast

    # --- GR THAN
    @test begin # int
        greater_than_broadcast([1, 2, 3], 1) == [0, 1, 1]
    end
    @test begin # int. All >
        greater_than_broadcast([1, 2, 3], 0) == [1, 1, 1]
    end
    @test begin # float
        greater_than_broadcast([1, 1.15, 3], 1.1) == [0, 1, 1]
    end
    @test begin # float. All <
        greater_than_broadcast([1, 1.15, 3], 10.0) == [0, 0, 0]
    end
    # --- LESS THAN
    @test begin # int None is less
        less_than_broadcast([1, 2, 3], 1) == [0, 0, 0]
    end
    @test begin # int. All <
        less_than_broadcast([1, 2, 3], 4) == [1, 1, 1]
    end
    @test begin # float
        less_than_broadcast([1, 1.15, 3], 1.1) == [1, 0, 0]
    end
    # --- EQ THAN
    @test begin # int. One is eq
        eq_broadcast([1, 2, 3], 1) == [1, 0, 0]
    end
    @test begin # int. None
        eq_broadcast([1, 2, 3], 4) == [0, 0, 0]
    end
    @test begin # float comparison
        eq_broadcast([1, 1.1, 3], 1.1) == [0, 1, 0]
    end

    # COMPARE 2 VECTORS
    @test begin
        # All 4 cases
        compare_two_vectors([1, 2], [1, 2]) == [1, 1] &&
            compare_two_vectors([1, 2], [3, 4]) == [0, 0] &&
            compare_two_vectors([1, 2], [0, 2]) == [0, 1] &&
            compare_two_vectors([1, 2], [1, 0]) == [1, 0]
    end
    @test begin
        # Works on string
        compare_two_vectors(["1", "2"], ["1", ""]) == [1, 0]
    end
    @test_throws MethodError begin
        # Does not work bc different types
        compare_two_vectors(["1", "2"], [1, ""])
    end
    @test_throws AssertionError begin
        # does not work bc wrong dims
        compare_two_vectors(["1", "2"], ["", "", ""])
    end
end




