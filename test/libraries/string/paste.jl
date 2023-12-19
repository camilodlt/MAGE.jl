@testset "STR PASTE LIB" begin
    @test begin
        # module is importable ... 
        using UTCGP: bundle_string_paste
        true
    end
    # @test begin
    #     # module is importable ... 
    #     using UTCGP: bundle_string_paste
    #     length(bundle_string_paste) == 4
    # end
    @test begin
        # module is importable ... 
        using UTCGP: bundle_string_paste
        using UTCGP: _unique_names_in_bundle
        _unique_names_in_bundle(bundle_string_paste)
    end

    # PASTE BASE 
    @test begin
        using UTCGP.str_paste: paste
        paste("", "", "sep") == "sep"
    end
    @test begin
        using UTCGP.str_paste: paste
        paste("Kebab", "case", " ") == "Kebab case"
    end
    # PASTE0
    @test begin
        using UTCGP.str_paste: paste0
        paste0("AC", "DC") == "ACDC"
    end
    # PASTE WITH SPACE
    @test begin
        using UTCGP.str_paste: paste_with_space
        paste_with_space("AC", "DC") == "AC DC"
    end
    # PASTE LIST STRING
    @test begin
        # module is importable ... 
        using UTCGP: bundle_string_concat_list_string
        using UTCGP: _unique_names_in_bundle
        _unique_names_in_bundle(bundle_string_concat_list_string)
    end
    @test begin
        using UTCGP.str_paste: paste_space_list_string
        paste_space_list_string(["AC", "DC"]) == "AC DC"
    end
    @test begin
        using UTCGP.str_paste: paste_list_string_sep
        paste_list_string_sep(["AC", "DC"], "-") == "AC-DC"
    end
    @test begin
        using UTCGP.str_paste: paste_list_string_sep
        paste_list_string_sep(["", ""], "_") == "_"
    end
    @test begin
        using UTCGP.str_paste: paste_list_string
        paste_list_string(["AC", "DC"]) == "ACDC"
    end
end
