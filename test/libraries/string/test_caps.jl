@testset "STR CAPS LIB" begin
    @test begin
        # module is importable ... 
        using UTCGP: bundle_string_caps
        true
    end
    @test begin
        # module is importable ... 
        using UTCGP: bundle_string_caps
        length(bundle_string_caps) == 14
    end
    @test begin
        # module is importable ... 
        using UTCGP: bundle_string_caps
        using UTCGP: _unique_names_in_bundle
        _unique_names_in_bundle(bundle_string_caps)
    end

    # UPPERCASE 

    @test begin
        # uppercase
        using UTCGP.str_caps: uppercase_
        uppercase_("julia") == "JULIA"
    end

    # UPPERCASE AT 
    @test begin
        # uppercase
        using UTCGP.str_caps: uppercase_at
        uppercase_at("julia", 1) == "Julia"
    end
    @test begin
        # uppercase
        using UTCGP.str_caps: uppercase_at
        uppercase_at("julia", -1212) == "Julia"
    end
    @test begin
        # uppercase
        using UTCGP.str_caps: uppercase_at
        uppercase_at("julia", 1212.3) == "juliA"
    end

    # UPPERCASE AFTER

    @test begin
        # uppercase
        using UTCGP.str_caps: uppercase_after
        uppercase_after("julia", "u") == "juLIA"
    end
    @test begin
        # nothing to uppercase after a 
        using UTCGP.str_caps: uppercase_after
        uppercase_after("julia", "a") == "julia"
    end
    @test begin
        # checking bounds 
        using UTCGP.str_caps: uppercase_after
        uppercase_after("julia", "i") == "juliA"
    end
    @test begin
        # checking bounds 
        using UTCGP.str_caps: uppercase_after
        uppercase_after("julia", "j") == "jULIA"
    end
    @test begin
        # not a match
        using UTCGP.str_caps: uppercase_after
        uppercase_after("julia", "") == "julia"
    end
    @test begin
        # not a match
        using UTCGP.str_caps: uppercase_at
        uppercase_after("julia", " ") == "julia"
    end

    # UPPERCASE CHAR AFTER

    @test begin
        # uppercase after u
        using UTCGP.str_caps: uppercase_char_after
        uppercase_char_after("julia", "u") == "juLia"
    end
    @test begin
        # uppercase after u multiple times
        using UTCGP.str_caps: uppercase_char_after
        uppercase_char_after("julia julia ", "u") == "juLia juLia "
    end
    @test begin
        # uppercase after a complete match
        using UTCGP.str_caps: uppercase_char_after
        uppercase_char_after("julia julia ", "jul") == "julIa julIa "
    end
    @test begin
        # empty match
        using UTCGP.str_caps: uppercase_char_after
        uppercase_char_after("julia julia ", "") == "julia julia "
    end
    @test begin
        # not a match
        using UTCGP.str_caps: uppercase_char_after
        uppercase_char_after("julia julia ", "julian") == "julia julia "
    end
    @test begin
        # bounds
        using UTCGP.str_caps: uppercase_char_after
        uppercase_char_after("julia julia ", "j") == "jUlia jUlia "
    end
    @test begin
        # bounds
        using UTCGP.str_caps: uppercase_char_after
        uppercase_char_after("julia julia", "a") == "julia julia"
    end

    # UPPERCASE BEFORE

    @test begin
        # uppercase
        using UTCGP.str_caps: uppercase_before
        uppercase_before("julia", "lia") == "JUlia"
    end
    @test begin
        # nothing to uppercase before a 
        using UTCGP.str_caps: uppercase_before
        uppercase_before("julia", "j") == "julia"
    end
    @test begin
        # checking bounds 
        using UTCGP.str_caps: uppercase_before
        uppercase_before("julia", "a") == "JULIa"
    end
    @test begin
        # not a match
        using UTCGP.str_caps: uppercase_before
        uppercase_before("julia", "") == "julia"
    end
    @test begin
        # not a match
        using UTCGP.str_caps: uppercase_at
        uppercase_before("julia", "R") == "julia"
    end


    # UPPERCASE CHAR before

    @test begin
        # uppercase after u
        using UTCGP.str_caps: uppercase_char_before
        uppercase_char_before("julia", "l") == "jUlia"
    end
    @test begin
        # uppercase after u multiple times
        using UTCGP.str_caps: uppercase_char_before
        uppercase_char_before("julia julia ", "li") == "jUlia jUlia "
    end
    @test begin
        # empty match
        using UTCGP.str_caps: uppercase_char_before
        uppercase_char_before("julia julia ", "") == "julia julia "
    end
    @test begin
        # not a match
        using UTCGP.str_caps: uppercase_char_before
        uppercase_char_before("julia julia ", "julian") == "julia julia "
    end
    @test begin
        # bounds
        using UTCGP.str_caps: uppercase_char_before
        uppercase_char_before("julia julia ", "j") == "julia julia "
    end
    @test begin
        # bounds
        using UTCGP.str_caps: uppercase_char_before
        uppercase_char_before("julia julia", "a") == "julIa julIa"
    end

    # LOWERCASE #

    # lowercase 

    @test begin
        # lowercase
        using UTCGP.str_caps: lowercase_
        lowercase_("JULIA") == "julia"
    end

    # lowercase AT 
    @test begin
        # lowercase
        using UTCGP.str_caps: lowercase_at
        lowercase_at("JULIA", 1) == "jULIA"
    end
    @test begin
        # lowercase
        using UTCGP.str_caps: lowercase_at
        lowercase_at("JULIA", -1212) == "jULIA"
    end
    @test begin
        # lowercase
        using UTCGP.str_caps: lowercase_at
        lowercase_at("JULIA", 1212.3) == "JULIa"
    end
    @test begin
        # nothing to lowercase 
        using UTCGP.str_caps: lowercase_at
        lowercase_at("julia", 1212.3) == "julia"
    end

    # lowercase AFTER

    @test begin
        # lowercase
        using UTCGP.str_caps: lowercase_after
        lowercase_after("JULIA", "U") == "JUlia"
    end
    @test begin
        # nothing to lowercase after a 
        using UTCGP.str_caps: lowercase_after
        lowercase_after("JULIA", "A") == "JULIA"
    end
    @test begin
        # checking bounds 
        using UTCGP.str_caps: lowercase_after
        lowercase_after("JULIA", "I") == "JULIa"
    end
    @test begin
        # checking bounds 
        using UTCGP.str_caps: lowercase_after
        lowercase_after("JULIA", "J") == "Julia"
    end
    @test begin
        # not a match
        using UTCGP.str_caps: lowercase_after
        lowercase_after("JULIA", "") == "JULIA"
    end
    @test begin
        # not a match
        using UTCGP.str_caps: lowercase_at
        lowercase_after("JULIA", " ") == "JULIA"
    end

    # lowercase CHAR AFTER

    @test begin
        # lowercase after u
        using UTCGP.str_caps: lowercase_char_after
        lowercase_char_after("JULIA", "L") == "JULiA"
    end
    @test begin
        # lowercase after u multiple times
        using UTCGP.str_caps: lowercase_char_after
        lowercase_char_after("JULIA JULIA", "U") == "JUlIA JUlIA"
    end
    @test begin
        # lowercase after a complete match
        using UTCGP.str_caps: lowercase_char_after
        lowercase_char_after("JULIA JULIA", "JUL") == "JULiA JULiA"
    end
    @test begin
        # empty match
        using UTCGP.str_caps: lowercase_char_after
        lowercase_char_after("julia JULIA", "") == "julia JULIA"
    end
    @test begin
        # not a match
        using UTCGP.str_caps: lowercase_char_after
        lowercase_char_after("JULIA julia ", "julian") == "JULIA julia "
    end
    @test begin
        # bounds
        using UTCGP.str_caps: lowercase_char_after
        lowercase_char_after("JULIA JULIA", "J") == "JuLIA JuLIA"
    end
    @test begin
        # bounds
        using UTCGP.str_caps: lowercase_char_after
        lowercase_char_after("JULIA JULIA", "A") == "JULIA JULIA"
    end

    # lowercase BEFORE

    @test begin
        # lowercase
        using UTCGP.str_caps: lowercase_before
        lowercase_before("JULIA", "LIA") == "juLIA"
    end
    @test begin
        # nothing to lowercase before a 
        using UTCGP.str_caps: lowercase_before
        lowercase_before("JULIA", "J") == "JULIA"
    end
    @test begin
        # nothing to lowercase before a & respects upper/lower
        using UTCGP.str_caps: lowercase_before
        lowercase_before("JULIA jjlia", "J") == "JULIA jjlia"
    end
    @test begin
        # checking bounds 
        using UTCGP.str_caps: lowercase_before
        lowercase_before("julIA", "A") == "juliA"
    end
    @test begin
        # not a match
        using UTCGP.str_caps: lowercase_before
        lowercase_before("JULIA", "") == "JULIA"
    end
    @test begin
        # not a match
        using UTCGP.str_caps: lowercase_at
        lowercase_before("JULIA", "R") == "JULIA"
    end


    # lowercase CHAR before

    @test begin
        # lowercase after u
        using UTCGP.str_caps: lowercase_char_before
        lowercase_char_before("JULIA", "L") == "JuLIA"
    end
    @test begin
        # lowercase after u multiple times
        using UTCGP.str_caps: lowercase_char_before
        lowercase_char_before("JULIA JULIA", "LI") == "JuLIA JuLIA"
    end
    @test begin
        # empty match
        using UTCGP.str_caps: lowercase_char_before
        lowercase_char_before("JULIA JULIA", "") == "JULIA JULIA"
    end
    @test begin
        # not a match
        using UTCGP.str_caps: lowercase_char_before
        lowercase_char_before("JULIA", "JULIAN") == "JULIA"
    end
    @test begin
        # bounds
        using UTCGP.str_caps: lowercase_char_before
        lowercase_char_before("JULIA JULIA", "J") == "JULIA JULIA"
    end
    @test begin
        # bounds
        using UTCGP.str_caps: lowercase_char_before
        lowercase_char_before("JULIA JULIA", "A") == "JULiA JULiA"
    end

    ## CAPITALIZE
    @test begin
        using UTCGP.str_caps: capitalize_first
        capitalize_first("julia") == "Julia"
    end
    @test begin
        using UTCGP.str_caps: capitalize_first
        capitalize_first("julia julia") == "Julia julia"
    end
    @test begin
        using UTCGP.str_caps: capitalize_all
        capitalize_all("julia") == "Julia"
    end
    @test begin
        using UTCGP.str_caps: capitalize_first
        capitalize_all("julia julia") == "Julia Julia"
    end
    @test begin
        using UTCGP.str_caps: capitalize_first
        capitalize_all("julia-julia") == "Julia-Julia"
    end
end
