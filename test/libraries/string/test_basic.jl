@testset "Basic" begin

    @test begin
        # module is importable ... 
        using MAGE: bundle_string_basic
        true
    end
    @test begin
        # module is importable ... 
        using MAGE: bundle_string_basic
        length(bundle_string_basic) == 3
    end
    @test begin
        # module is importable ... 
        using MAGE: bundle_string_basic
        using MAGE: _unique_names_in_bundle
        _unique_names_in_bundle(bundle_string_basic)
    end

    @test begin
        using MAGE.str_basic: identity_str
        identity_str("str") == "str"
    end
    @test begin
        import MAGE.str_basic
        str_basic.empty_string("", 12, "") == ""
    end
    @test begin
        using MAGE.str_basic: number_to_string
        number_to_string(123) == "123"
    end
    @test begin
        using MAGE.str_basic: number_to_string
        number_to_string(123.13131) == "123.13131"
    end
end
