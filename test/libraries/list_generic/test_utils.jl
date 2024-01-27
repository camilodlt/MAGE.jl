using UTCGP.listgeneric_utils: sort_list
using UTCGP.listgeneric_utils: append_to_list
using UTCGP.listgeneric_utils: unique_in_list

@testset "SORT" begin
    @test begin
        # bundle import
        using UTCGP.listgeneric_utils: bundle_listgeneric_utils
        length(bundle_listgeneric_utils) == 4 &&
            _unique_names_in_bundle(bundle_listgeneric_utils)

    end
    @test begin
        sort_list([2, 3, 1]) == [1, 2, 3] && sort_list(["4", "2", "3"]) == ["2", "3", "4"]
    end

    #  Append to list
    @test begin
        a = [1, 2, 3]
        append_to_list(a, 4) == [1, 2, 3, 4] && a == [1, 2, 3]
    end
    @test_throws MethodError begin # the type hast to be the same ..
        a = Int[1, 2, 3]
        append_to_list(a, 4.13)
    end

    # UNIQUE
    @test begin
        a = [1, 1, 3]
        using UTCGP: listgeneric_utils
        unique_in_list(a) == [1, 3] && a == [1, 1, 3]
    end
    @test begin
        a = ["1", "1", "3"]
        unique_in_list(a) == ["1", "3"] && a == ["1", "1", "3"]
    end

    # Replace by Mapping

    @test begin
        # Normal
        a = [1]
        m = [(1, 2)]
        m_2 = [(4, 2)]
        m_3 = [(1, 2), (1, 3)]
        listgeneric_utils.replace_by_mapping(a, m) == [2] &&# not changed
            listgeneric_utils.replace_by_mapping(a, m_2) == [1] &&  # not changed
            listgeneric_utils.replace_by_mapping(a, m_3) == [2] # Second mapping ignored since another exists
    end
    @test_throws MethodError begin
        # Wrong types
        a = ["1"]
        m = [(1, 2)]
        listgeneric_utils.replace_by_mapping(a, m)
    end
    # Factory
    @test_throws MethodError begin
        # Wrong types
        a = ["1"]
        m = [(1, 2)]
        z = listgeneric_utils.replace_by_mapping_factory(String)
        z(a, m)
    end
    @test begin
        # Wrong types
        a = ["1"]
        m = [("1", "2")]
        z = listgeneric_utils.replace_by_mapping_factory(String)
        z(a, m) == ["2"]
    end
end
