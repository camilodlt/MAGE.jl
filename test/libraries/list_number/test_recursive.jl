@testset "RECURSIVE" begin
    @test begin
        # recursive sum
        using UTCGP.listnumber_recursive: recsum
        in = [1, 2, 3]
        res = recsum(in)
        should_res = [1, 3, 6]
        all([a === b for (a, b) in zip(res, should_res)]) # same type (int)
    end
    @test begin
        # recursive sum
        using UTCGP.listnumber_recursive: recsum
        in = [1.0, 2.0, 3.0]
        res = recsum(in)
        should_res = [1.0, 3.0, 6.0]
        all([a === b for (a, b) in zip(res, should_res)]) # same type (float)
    end
end
