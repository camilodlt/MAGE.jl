@testset "Basic" begin
    @test begin
        # bundle import
        using UTCGP: bundle_listnumber_basic
        length(bundle_listnumber_basic) == 2 &&
            _unique_names_in_bundle(bundle_listnumber_basic)
    end

    # ONES
    @test begin
        using UTCGP.listnumber_basic: ones_
        ones_([1, 1, 1]) == [1.0, 1.0, 1.0] && ones_(Int[]) == []
    end
    @test begin
        ones_(2) == [1.0, 1.0] && ones_(0) == []
    end
    @test_throws ArgumentError begin
        ones_(-1)
    end
    # ZEROS
    @test begin
        using UTCGP.listnumber_basic: zeros_
        zeros_([1, 1, 1]) == [0.0, 0.0, 0.0] && zeros_(Int[]) == []
    end
    @test begin
        zeros_(2) == [0.0, 0.0] && zeros_(0) == []

    end
    @test_throws ArgumentError begin
        zeros_(-1)
    end
end
