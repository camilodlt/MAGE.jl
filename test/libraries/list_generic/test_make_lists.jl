@testset "Make lists" begin
    # Test the bundle
    @test begin
        # bundle import
        using MAGE: bundle_listgeneric_makelist
        length(bundle_listgeneric_makelist) == 3 &&
            _unique_names_in_bundle(bundle_listgeneric_makelist)
    end
    # Make list from 1 element
    @test begin
        using MAGE.listgeneric_makelist: make_list_from_one_element
        make_list_from_one_element(2) == [2] && make_list_from_one_element("2") == ["2"]
    end
    # Make list from 2 elements
    @test begin
        using MAGE.listgeneric_makelist: make_list_from_two_elements
        make_list_from_two_elements(2, 2) == [2, 2]
    end
    @test_throws MethodError begin
        # Both elements should be of the same type
        using MAGE.listgeneric_makelist: make_list_from_two_elements
        make_list_from_two_elements(2, "2")
    end
    # Make list from 3 elements
    @test begin
        using MAGE.listgeneric_makelist: make_list_from_three_elements
        make_list_from_three_elements(2, 2, 2) == [2, 2, 2]
    end
    @test_throws MethodError begin
        # all elements should be of the same type
        using MAGE.listgeneric_makelist: make_list_from_three_elements
        make_list_from_three_elements(2, "2", 2)
    end
end
