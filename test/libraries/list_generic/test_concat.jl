@testset "Concat" begin
    @test begin
        # bundle import
        using UTCGP: bundle_listgeneric_concat
        length(bundle_listgeneric_concat) == 1 &&
            _unique_names_in_bundle(bundle_listgeneric_concat)
    end
    @test begin
        using UTCGP.listgeneric_concat: concat_two_lists
        concat_two_lists(["1"], ["1", "2"]) == ["1", "1", "2"]
    end
end
