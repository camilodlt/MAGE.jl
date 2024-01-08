@testset "Capitalize list" begin
    @test begin
        # Length of the bundle... 
        using UTCGP.liststring_caps: bundle_liststring_caps
        length(bundle_liststring_caps) == 2 &&
            _unique_names_in_bundle(bundle_liststring_caps)
    end
    @test begin
        # capitalize every element
        using UTCGP.liststring_caps: capitalize_list_string
        capitalize_list_string(["julia", "julia"]) == ["Julia", "Julia"]
    end
    @test begin
        # capitalize every element
        using UTCGP.liststring_caps: capitalize_list_string
        capitalize_list_string(["julia julia", "julia"]) == ["Julia Julia", "Julia"]
    end
    @test begin
        # Uppercase first every element
        using UTCGP.liststring_caps: uppercasefirst_list_string
        uppercasefirst_list_string(["julia julia", "julia"]) == ["Julia julia", "Julia"]
    end
end
