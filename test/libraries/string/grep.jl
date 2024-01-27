using UTCGP.str_grep: bundle_string_grep
using UTCGP.str_grep: replace_pattern
using UTCGP.str_grep: replace_first_pattern
using UTCGP.str_grep: remove_pattern
using UTCGP: _unique_names_in_bundle

@testset "STR GREP LIB" begin
    @test begin
        # Length of the bundle... 
        length(bundle_string_grep) == 3 && _unique_names_in_bundle(bundle_string_grep)
    end
    # REPLACE PATTERN
    @test begin # replace pattern 
        x = "CamelCase"
        from = "Case"
        to = "case"
        replace_pattern(x, from, to) == "Camelcase"
    end
    @test begin # replace pattern 
        x = "HelloHello"
        from = "Hello"
        to = "hello"
        replace_pattern(x, from, to) == "hellohello"
    end
    @test begin # pattern has no effect
        x = "Car"
        from = "wind"
        to = ""
        replace_pattern(x, from, to) == "Car"
    end
    @test begin # pattern as remove char
        x = "Car"
        from = "C"
        to = ""
        replace_pattern(x, from, to) == "ar"
    end
    # REPLACE FIRST PATTERN
    @test begin # replace pattern only 1 time 
        x = "HelloHello"
        from = "Hello"
        to = "hello"
        replace_first_pattern(x, from, to) == "helloHello"
    end
    # REMOVE PATTERN
    @test begin # replace pattern only 1 time 
        x = "kebab-case"
        pattern = "-"
        remove_pattern(x, pattern) == "kebabcase"
    end
    @test begin # replace pattern only 1 time 
        x = "CCC"
        pattern = "C"
        remove_pattern(x, pattern) == ""
    end
end
