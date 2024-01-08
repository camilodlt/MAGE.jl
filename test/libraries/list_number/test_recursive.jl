@testset "RECURSIVE" begin

    @test begin
        # bundle import
        using UTCGP: bundle_listnumber_recursive
        length(bundle_listnumber_recursive) == 3 &&
            _unique_names_in_bundle(bundle_listnumber_recursive)
    end
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

    # Recursive mult
    @test begin
        # recursive mult
        using UTCGP.listnumber_recursive: recmult
        v = 10
        res = recmult(v, 0.5, 4)
        should_res = Any[10, 5.0, 2.5, 1.25, 0.625]
        @show [a === b for (a, b) in zip(res, should_res)]
        all([a === b for (a, b) in zip(res, should_res)]) # same type (float)
    end

    # Range
    @test begin
        using UTCGP.listnumber_recursive: range_
        res = range_(5)
        should_res = collect(1:5)
        all([a === b for (a, b) in zip(res, should_res)]) # same type (float)
    end
    @test begin
        using UTCGP.listnumber_recursive: range_
        res = range_(5.0)
        should_res = collect(1:5.0)
        all([a === b for (a, b) in zip(res, should_res)]) # same type (float)
    end
end
