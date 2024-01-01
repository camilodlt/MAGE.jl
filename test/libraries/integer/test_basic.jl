@testset "Find" begin
    @test begin
        # bundle import
        using UTCGP: bundle_integer_basic
        length(bundle_integer_basic) == 1 && _unique_names_in_bundle(bundle_integer_basic)
    end
    @test begin # Correct findings 
        using UTCGP.integer_basic: identity_int
        identity_int(-1) == -1 && identity_int(1) == 1
    end
end


