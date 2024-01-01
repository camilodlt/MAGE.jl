using Debugger
using Test

@testset "Number arithmetic" begin

    @test begin
        # bundle import
        using UTCGP: bundle_number_arithmetic
        length(bundle_number_arithmetic) == 5 &&
            _unique_names_in_bundle(bundle_number_arithmetic)
    end

    @test begin # sum 
        using UTCGP: bundle_number_arithmetic
        fn_wrapped = bundle_number_arithmetic[1]

        UTCGP.evaluate_fn_wrapper(fn_wrapped, [1, 2]) == 3 &&
            UTCGP.evaluate_fn_wrapper(fn_wrapped, [1.0, 2]) == 3.0 &&
            UTCGP.evaluate_fn_wrapper(fn_wrapped, [1.0, 2.0]) == 3.0 &&
            UTCGP.evaluate_fn_wrapper(fn_wrapped, [1, 2.0]) == 3.0
    end
    @test begin # minus
        using UTCGP: bundle_number_arithmetic
        fn_wrapped = bundle_number_arithmetic[2]

        UTCGP.evaluate_fn_wrapper(fn_wrapped, [1, 2]) == -1 &&
            UTCGP.evaluate_fn_wrapper(fn_wrapped, [1.0, 2]) == -1.0 &&
            UTCGP.evaluate_fn_wrapper(fn_wrapped, [1.0, 2.0]) == -1.0 &&
            UTCGP.evaluate_fn_wrapper(fn_wrapped, [1, 2.0]) == -1.0
    end
    @test begin # mult
        using UTCGP: bundle_number_arithmetic
        fn_wrapped = bundle_number_arithmetic[3]

        UTCGP.evaluate_fn_wrapper(fn_wrapped, [1, 2]) == 2 &&
            UTCGP.evaluate_fn_wrapper(fn_wrapped, [1.0, 2]) == 2.0 &&
            UTCGP.evaluate_fn_wrapper(fn_wrapped, [1.0, 2.0]) == 2.0 &&
            UTCGP.evaluate_fn_wrapper(fn_wrapped, [1, 2.0]) == 2.0
    end
    @test begin # div
        using UTCGP: bundle_number_arithmetic
        fn_wrapped = bundle_number_arithmetic[4]

        UTCGP.evaluate_fn_wrapper(fn_wrapped, [1, 2]) == 0.5 &&
            UTCGP.evaluate_fn_wrapper(fn_wrapped, [1.0, 2]) == 0.5 &&
            UTCGP.evaluate_fn_wrapper(fn_wrapped, [1.0, 2.0]) == 0.5 &&
            UTCGP.evaluate_fn_wrapper(fn_wrapped, [1, 2.0]) == 0.5
    end
    @test begin # bad div, going to return fallback
        using UTCGP: bundle_number_arithmetic
        fn_wrapped = bundle_number_arithmetic[4]
        mock_fn = deepcopy(fn_wrapped)
        fb = 3
        mock_fn.fallback = () -> fb
        UTCGP.evaluate_fn_wrapper(mock_fn, [10, 0]) == fb
    end

    @test begin # safe div
        using UTCGP: bundle_number_arithmetic
        fn_wrapped = bundle_number_arithmetic[5]
        mock_fn = deepcopy(fn_wrapped)
        fb = 3
        mock_fn.fallback = () -> 3
        UTCGP.evaluate_fn_wrapper(mock_fn, [10, 0]) == 0 # the default, not the fallback
    end

    @test begin # div to int
        using UTCGP: bundle_number_arithmetic
        int_bundle = deepcopy(bundle_number_arithmetic)
        update_caster!(int_bundle, (x) -> floor(Int, x))
        fn_wrapped = int_bundle[4]
        UTCGP.evaluate_fn_wrapper(fn_wrapped, [1, 2]) === 0 &&
            UTCGP.evaluate_fn_wrapper(fn_wrapped, [1.0, 2]) === 0 &&
            UTCGP.evaluate_fn_wrapper(fn_wrapped, [1.0, 2.0]) === 0 &&
            UTCGP.evaluate_fn_wrapper(fn_wrapped, [1, 2.0]) === 0
    end
end
