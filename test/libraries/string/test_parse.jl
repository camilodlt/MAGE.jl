@testset "Parse" begin
    @test begin
        # bundle import
        using MAGE: bundle_string_parse
        length(bundle_string_parse) == 1 && _unique_names_in_bundle(bundle_string_parse)
    end

    @test begin # test parse nb
        using MAGE.str_parse: parse_number
        parse_number(1) == "1"
    end
    @test begin # test parse nb
        using MAGE.str_parse: parse_number
        parse_number(1.1) == "1.1"
    end
end
