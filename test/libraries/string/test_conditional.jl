@testset "STR CONDITIONAL LIB" begin
    @test begin
        # module is importable ... 
        using UTCGP: bundle_string_conditional
        true
    end
    @test begin
        # module is importable ... 
        using UTCGP: bundle_string_conditional
        length(bundle_string_conditional) == 5
    end
    @test begin
        # module is importable ... 
        using UTCGP: bundle_string_conditional
        using UTCGP: _unique_names_in_bundle
        _unique_names_in_bundle(bundle_string_conditional)
    end

    # IF STRING 
    @test begin
        # Int 0 returns ""
        using UTCGP.str_conditional: if_string
        if_string("YES", 0) == ""
    end
    @test begin
        # Int 1 returns the string
        using UTCGP.str_conditional: if_string
        if_string("YES", 1) == "YES"
    end
    @test begin
        # Floats are trunc to int
        using UTCGP.str_conditional: if_string
        if_string("YES", 0.0) == ""
    end
    @test begin
        # Floats are trunc to int
        using UTCGP.str_conditional: if_string
        if_string("YES", 0.999999) == ""
    end
    @test begin
        # float truc to 1
        using UTCGP.str_conditional: if_string
        if_string("YES", 1.1232413) == "YES"
    end
    @test begin
        # float trunc to != 0
        using UTCGP.str_conditional: if_string
        if_string("YES", 13242.1232413) == "YES"
    end

    # IF NOT STRING

    @test begin
        # Int 0 returns ""
        using UTCGP.str_conditional: if_not_string
        if_not_string("YES", 0) == "YES"
    end
    @test begin
        # Int 1 returns the string
        using UTCGP.str_conditional: if_not_string
        if_not_string("YES", 1) == ""
    end
    @test begin
        # Floats are trunc to int
        using UTCGP.str_conditional: if_not_string
        if_not_string("YES", 0.0) == "YES"
    end
    @test begin
        # Floats are trunc to int
        using UTCGP.str_conditional: if_not_string
        if_not_string("YES", 0.999999) == "YES"
    end
    @test begin
        # float truc to 1
        using UTCGP.str_conditional: if_not_string
        if_not_string("YES", 1.1232413) == ""
    end
    @test begin
        # float trunc to != 0
        using UTCGP.str_conditional: if_not_string
        if_not_string("YES", 13242.1232413) == ""
    end

    # IF Else String

    @test begin
        # Int 0 returns s2
        using UTCGP.str_conditional: if_else_string
        if_else_string("YES", "NO", 0) == "NO"
    end
    @test begin
        # Int 0 returns s2
        using UTCGP.str_conditional: if_else_string
        if_else_string("YES", "NO", 0.989) == "NO"
    end
    @test begin
        # Int diff than 0 returns s1
        using UTCGP.str_conditional: if_else_string
        if_else_string("YES", "NO", 1121.1) == "YES"
    end

    # LONGEST

    @test begin
        # Returns the longest
        using UTCGP.str_conditional: longest_string
        longest_string("YES", "NO") == "YES"
    end
    @test begin
        # Returns the longest
        using UTCGP.str_conditional: longest_string
        longest_string("YES", "NONO") == "NONO"
    end
    @test begin
        # Equal length return the first
        using UTCGP.str_conditional: longest_string
        longest_string("YE", "NO") == "YE"
    end

    # Shortest

    @test begin
        # Returns the shortest
        using UTCGP.str_conditional: shortest_string
        shortest_string("YES", "NO") == "NO"
    end
    @test begin
        # Returns the shortest
        using UTCGP.str_conditional: shortest_string
        shortest_string("YES", "NONO") == "YES"
    end
    @test begin
        # Equal length return the first
        using UTCGP.str_conditional: shortest_string
        shortest_string("YE", "NO") == "YE"
    end
end
