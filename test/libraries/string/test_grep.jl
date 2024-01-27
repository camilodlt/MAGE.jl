using UTCGP.str_grep: match_with_overlap

@testset "Grep" begin

    @test begin
        s = "julia julia"
        # match_overlap
        match_with_overlap(s, "ju") == [1, 7]
    end
    @test begin
        s = "afazfazfazfaf"
        # match_overlap
        match_with_overlap(s, "ju") == []
    end

end
