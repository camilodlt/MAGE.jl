@testset "Number transcendental" begin
    using UTCGP: bundle_number_transcendental
    @test begin
        # bundle import
        length(bundle_number_transcendental) == 4 &&
            UTCGP._unique_names_in_bundle(bundle_number_transcendental)
    end

    @test begin # pi
        fn_wrapped = bundle_number_transcendental[1]
        UTCGP.evaluate_fn_wrapper(fn_wrapped, [collect(1:10)...]) == pi
    end
    @test begin # exp
        fn_wrapped = bundle_number_transcendental[2]
        UTCGP.evaluate_fn_wrapper(fn_wrapped, [0]) == 1.0 &&
            UTCGP.evaluate_fn_wrapper(fn_wrapped, [1]) == exp(1) &&
            UTCGP.evaluate_fn_wrapper(fn_wrapped, [-1000]) == 0.0
    end
    @test begin # log
        fn_wrapped = bundle_number_transcendental[3]

        UTCGP.evaluate_fn_wrapper(fn_wrapped, [1]) == 0.0 &&
            isapprox(UTCGP.evaluate_fn_wrapper(fn_wrapped, [-12]), -23.025850929940457) && # clipped to = 0 + 1/(10^10)  
            isapprox(UTCGP.evaluate_fn_wrapper(fn_wrapped, [10]), 2.302585092994046)

    end

    @test begin # log 10
        fn_wrapped = bundle_number_transcendental[4]
        UTCGP.evaluate_fn_wrapper(fn_wrapped, [1]) == 0.0 &&
            isapprox(UTCGP.evaluate_fn_wrapper(fn_wrapped, [-12]), -10.0) && # clipped to = 0 + 1/(10^10)  
            isapprox(UTCGP.evaluate_fn_wrapper(fn_wrapped, [1000]), 3.0)
    end
end
