
@testset "REDUCE" begin
    @test begin
        # bundle import
        using UTCGP: bundle_number_reduce
        length(bundle_number_reduce) == 6 && _unique_names_in_bundle(bundle_number_reduce)
    end
    @test begin
        # sum
        using UTCGP.number_reduce: reduce_sum
        reduce_sum([1, 2, 3]) === 6
    end
    @test begin
        # min
        using UTCGP.number_reduce: reduce_min
        reduce_min([1, 2, 3]) === 1
    end
    @test begin
        # max
        using UTCGP.number_reduce: reduce_max
        reduce_max([1, 2, 3]) === 3
    end
    @test begin
        # argmin
        using UTCGP.number_reduce: reduce_argmin
        reduce_argmin([1, 2, 3]) === 1
    end
    @test begin
        # argmax
        using UTCGP.number_reduce: reduce_argmax
        reduce_argmax([1, 2, 3]) === 3
    end
    @test begin
        # recursive sum
        using UTCGP.number_reduce: reduce_recsum
        in = [1, 2, 3]
        res = reduce_recsum(in)
        should_res = [1, 3, 6]
        println(res)
        println(should_res)
        println(res |> typeof)
        println(should_res |> typeof)
        all([a === b for (a, b) in zip(res, should_res)]) # same type (int)
    end
    @test begin
        # recursive sum
        using UTCGP.number_reduce: reduce_recsum
        in = [1.0, 2.0, 3.0]
        res = reduce_recsum(in)
        should_res = [1.0, 3.0, 6.0]
        all([a === b for (a, b) in zip(res, should_res)]) # same type (float)
    end
end
