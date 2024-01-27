
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

    # LENGTH
    @test begin
        # length
        using UTCGP.number_reduce: reduce_length
        reduce_length([1, 2, 3]) === 3 && reduce_length([]) === 0
    end
    @test begin
        # length string
        reduce_length("") == 0 && reduce_length("aaa") === 3
    end
    @test begin
        # length string
        a = [1, 2, 3]
        d = []
        b = ""
        c = "aaa"

        UTCGP.evaluate_fn_wrapper(bundle_number_reduce[6], [a]) == 3 &&
            UTCGP.evaluate_fn_wrapper(bundle_number_reduce[6], [d]) == 0 &&
            UTCGP.evaluate_fn_wrapper(bundle_number_reduce[6], [b]) == 0 &&
            UTCGP.evaluate_fn_wrapper(bundle_number_reduce[6], [c]) == 3
    end
end
