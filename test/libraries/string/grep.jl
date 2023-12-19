@testset "STR GREP LIB" begin
    @test begin
        # module is importable ... 
        using UTCGP: bundle_string_grep
        true
    end
    @test begin
        # module is importable ... 
        using UTCGP.str_grep
        true
    end
    @test begin
        # Length of the bundle... 
        using UTCGP.str_grep: bundle_string_grep
        length(bundle_string_grep) == 3
    end
    @test begin
        # Length of the bundle... 
        using UTCGP.str_grep: bundle_string_grep
        using UTCGP: _unique_names_in_bundle
        _unique_names_in_bundle(bundle_string_grep)
    end
    # REPLACE PATTERN
    @test begin # replace pattern 
        using UTCGP.str_grep: replace_pattern
        x = "CamelCase"
        from = "Case"
        to = "case"
        replace_pattern(x, from, to) == "Camelcase"
    end
    @test begin # replace pattern 
        using UTCGP.str_grep: replace_pattern
        x = "HelloHello"
        from = "Hello"
        to = "hello"
        replace_pattern(x, from, to) == "hellohello"
    end
    @test begin # pattern has no effect
        using UTCGP.str_grep: replace_pattern
        x = "Car"
        from = "wind"
        to = ""
        replace_pattern(x, from, to) == "Car"
    end
    @test begin # pattern as remove char
        using UTCGP.str_grep: replace_pattern
        x = "Car"
        from = "C"
        to = ""
        replace_pattern(x, from, to) == "ar"
    end
    # REPLACE FIRST PATTERN
    @test begin # replace pattern only 1 time 
        using UTCGP.str_grep: replace_first_pattern
        x = "HelloHello"
        from = "Hello"
        to = "hello"
        replace_first_pattern(x, from, to) == "helloHello"
    end
    # REMOVE PATTERN
    @test begin # replace pattern only 1 time 
        using UTCGP.str_grep: remove_pattern
        x = "kebab-case"
        pattern = "-"
        remove_pattern(x, pattern) == "kebabcase"
    end
    @test begin # replace pattern only 1 time 
        using UTCGP.str_grep: remove_pattern
        x = "CCC"
        pattern = "C"
        remove_pattern(x, pattern) == ""
    end
end
