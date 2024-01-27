@testset begin

    # BUNDLE 
    @test begin
        # bundle import
        using UTCGP.listgeneric_subset: bundle_listgeneric_subset
        length(bundle_listgeneric_subset) == 7 &&
            _unique_names_in_bundle(bundle_listgeneric_subset)
    end


    # PICK FROM INCLUSIVE GENERIC
    @test begin
        using UTCGP.listgeneric_subset: pick_from_inclusive_generic
        a = collect(1:10)
        pick_from_inclusive_generic(a, 1) == a
    end
    @test begin
        using UTCGP.listgeneric_subset: pick_from_inclusive_generic
        a = collect(1:10)
        pick_from_inclusive_generic(a, 2) == collect(2:10)
    end
    @test begin
        using UTCGP.listgeneric_subset: pick_from_inclusive_generic
        a = collect(1:10)
        pick_from_inclusive_generic(a, 10) == collect(10:10)
    end
    @test begin
        using UTCGP.listgeneric_subset: pick_from_inclusive_generic
        a = collect(1:10)
        pick_from_inclusive_generic(a, 11) == []
    end


    # PICK FROM INCLUSIVE GENERIC
    @test begin
        using UTCGP.listgeneric_subset: pick_from_exclusive_generic
        a = collect(1:10)
        pick_from_exclusive_generic(a, 1) == collect(2:10)
    end
    @test begin
        using UTCGP.listgeneric_subset: pick_from_exclusive_generic
        a = collect(1:10)
        pick_from_exclusive_generic(a, 9) == collect(10:10)
    end
    @test begin
        using UTCGP.listgeneric_subset: pick_from_exclusive_generic
        a = collect(1:10)
        pick_from_exclusive_generic(a, 10) == []
    end


    # PICK UNTIL INCLUSIVE GENERIC
    @test begin
        using UTCGP.listgeneric_subset: pick_until_inclusive_generic
        a = collect(1:10)
        pick_until_inclusive_generic(a, 1) == collect(1:1)
    end
    @test begin
        using UTCGP.listgeneric_subset: pick_until_inclusive_generic
        a = collect(1:10)
        pick_until_inclusive_generic(a, 5) == collect(1:5)
    end
    @test begin
        using UTCGP.listgeneric_subset: pick_until_inclusive_generic
        a = collect(1:10)
        pick_until_inclusive_generic(a, 11) == collect(1:10)
    end

    # PICK UNTIL EXCLUSIVE
    @test begin
        using UTCGP.listgeneric_subset: pick_until_exclusive_generic
        a = collect(1:10)
        pick_until_exclusive_generic(a, 1) == []
    end
    @test begin
        using UTCGP.listgeneric_subset: pick_until_exclusive_generic
        a = collect(1:10)
        pick_until_exclusive_generic(a, 2) == collect(1:1)
    end
    @test begin
        using UTCGP.listgeneric_subset: pick_until_exclusive_generic
        a = collect(1:10)
        pick_until_exclusive_generic(a, 10) == collect(1:9)
    end
    @test begin
        using UTCGP.listgeneric_subset: pick_until_exclusive_generic
        a = collect(1:10)
        pick_until_exclusive_generic(a, 11) == collect(1:10)
    end


    # SUBSET VECTOR OF TUPLES
    @test begin
        using UTCGP.listgeneric_subset: subset_list_of_tuples
        a = [(1, 2), (3, 4)]
        subset_list_of_tuples(a, 1) == [1, 2]
    end
    @test_throws BoundsError begin # wrong index
        using UTCGP.listgeneric_subset: subset_list_of_tuples
        a = [(1, 2), (3, 4)]
        subset_list_of_tuples(a, 3)
    end

    # SUBSET MASK
    @test begin
        using UTCGP.listgeneric_subset: subset_by_mask
        subset_by_mask([1, 1, 1], [1, 1, 1]) == [1, 1, 1]
    end
    @test begin # with bools as ints
        subset_by_mask([1, 1, 1], [0, 1, 1]) == [1, 1] &&
            subset_by_mask([1, 1, 1], [1, 0, 1]) == [1, 1] &&
            subset_by_mask([1, 1, 1], [1, 0, 1]) == [1, 1] &&
            subset_by_mask([1, 1, 1], [0, 0, 0]) == []
        subset_by_mask([1, 2, 3], [1, 0, 0]) == [1]
        subset_by_mask([1, 2, 3], [0, 1, 0]) == [2]
        subset_by_mask([1, 2, 3], [0, 0, 1]) == [3]
    end
    @test begin # with values that will be converted to 0,1
        subset_by_mask([1, 1, 1], [-1, 2, 2]) == [1, 1] &&
            subset_by_mask([1, 1, 1], [2, -1, 2]) == [1, 1] &&
            subset_by_mask([1, 1, 1], [2, -1, 2]) == [1, 1] &&
            subset_by_mask([1, 1, 1], [-1, -1, -1]) == []
        subset_by_mask([1, 2, 3], [2, -1, -1]) == [1]
        subset_by_mask([1, 2, 3], [-1, 2, -1]) == [2]
        subset_by_mask([1, 2, 3], [-1, -1, 2]) == [3]
    end

    # SUBSET AT INDICES

    @test begin
        using UTCGP.listgeneric_subset: subset_by_indices
        subset_by_indices([1, 2, 3], [1, 3]) == [1, 3] &&
            subset_by_indices([4, 5, 6], [1, 2, 3]) == [4, 5, 6]
    end
    @test_throws BoundsError begin
        subset_by_indices([1, 2, 3], [0])
    end
    @test_throws BoundsError begin
        subset_by_indices([1, 2, 3], [1, 2, 3, 4, 5])
    end
end
