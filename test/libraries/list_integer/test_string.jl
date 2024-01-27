using UTCGP.listinteger_string: match_with_overlap
using UTCGP: listinteger_string

@testset "String" begin
    # bundle
    @test begin
        # bundle import
        using UTCGP: bundle_listinteger_string
        length(bundle_listinteger_string) == 3 &&
            _unique_names_in_bundle(bundle_listinteger_string)
    end

    # MATCH OVERLAP
    @test begin
        s = "julia julia"
        # match_overlap
        match_with_overlap(s, "ju") == [1, 7]
    end
    @test begin
        s = "afazfazfazfaf"
        # match_overlap
        match_with_overlap(s, "ju") == []
    end

    # PARSE INT FROM LIST STRING
    @test begin
        using UTCGP.listinteger_string: parse_from_list_string
        parse_from_list_string(["1", "12", "123.12"]) == [1, 12, 123]
    end
    @test_throws ArgumentError begin
        using UTCGP.listinteger_string: parse_from_list_string
        parse_from_list_string(["1", "eefzef", "123.12"])
    end

    # LENGTH BROADCAST 
    @test begin
        listinteger_string.length_broadcast(["", "1", "12"]) == [0, 1, 2]
    end

end
