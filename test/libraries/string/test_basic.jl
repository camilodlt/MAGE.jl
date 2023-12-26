@testset "Basic" begin

    @test begin
        # module is importable ... 
        using UTCGP: bundle_string_basic
        true
    end
    @test begin
        # module is importable ... 
        using UTCGP: bundle_string_basic
        length(bundle_string_basic) == 2
    end
    @test begin
        # module is importable ... 
        using UTCGP: bundle_string_basic
        using UTCGP: _unique_names_in_bundle
        _unique_names_in_bundle(bundle_string_basic)
    end

    @test begin
        using UTCGP.str_basic: identity_str
        identity_str("str") == "str"
    end
    @test begin
        using UTCGP.str_basic: number_to_string
        number_to_string(123) == "123"
    end
    @test begin
        using UTCGP.str_basic: number_to_string
        number_to_string(123.13131) == "123.13131"
    end
end
