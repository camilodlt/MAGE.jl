
@testset "REDUCE" begin
    @test begin
        # bundle import
        using UTCGP: bundle_number_reduce
        length(bundle_number_reduce) == 5 && _unique_names_in_bundle(bundle_number_reduce)
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
end
