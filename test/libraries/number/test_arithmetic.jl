@testset "Number arithmetic" begin

    @test begin
        # bundle import
        using MAGE: bundle_number_arithmetic
        length(bundle_number_arithmetic) == 6 &&
            _unique_names_in_bundle(bundle_number_arithmetic)
    end

    @test begin # sum 
        using MAGE: bundle_number_arithmetic
        fn_wrapped = bundle_number_arithmetic[1]

        MAGE.evaluate_fn_wrapper(fn_wrapped, [1, 2]) == 3 &&
            MAGE.evaluate_fn_wrapper(fn_wrapped, [1.0, 2]) == 3.0 &&
            MAGE.evaluate_fn_wrapper(fn_wrapped, [1.0, 2.0]) == 3.0 &&
            MAGE.evaluate_fn_wrapper(fn_wrapped, [1, 2.0]) == 3.0
    end
    @test begin # minus
        using MAGE: bundle_number_arithmetic
        fn_wrapped = bundle_number_arithmetic[2]

        MAGE.evaluate_fn_wrapper(fn_wrapped, [1, 2]) == -1 &&
            MAGE.evaluate_fn_wrapper(fn_wrapped, [1.0, 2]) == -1.0 &&
            MAGE.evaluate_fn_wrapper(fn_wrapped, [1.0, 2.0]) == -1.0 &&
            MAGE.evaluate_fn_wrapper(fn_wrapped, [1, 2.0]) == -1.0
    end
    @test begin # mult
        using MAGE: bundle_number_arithmetic
        fn_wrapped = bundle_number_arithmetic[3]

        MAGE.evaluate_fn_wrapper(fn_wrapped, [1, 2]) == 2 &&
            MAGE.evaluate_fn_wrapper(fn_wrapped, [1.0, 2]) == 2.0 &&
            MAGE.evaluate_fn_wrapper(fn_wrapped, [1.0, 2.0]) == 2.0 &&
            MAGE.evaluate_fn_wrapper(fn_wrapped, [1, 2.0]) == 2.0
    end
    @test begin # div
        using MAGE: bundle_number_arithmetic
        fn_wrapped = bundle_number_arithmetic[4]

        MAGE.evaluate_fn_wrapper(fn_wrapped, [1, 2]) == 0.5 &&
            MAGE.evaluate_fn_wrapper(fn_wrapped, [1.0, 2]) == 0.5 &&
            MAGE.evaluate_fn_wrapper(fn_wrapped, [1.0, 2.0]) == 0.5 &&
            MAGE.evaluate_fn_wrapper(fn_wrapped, [1, 2.0]) == 0.5
    end
    @test begin # bad div, going to return fallback
        using MAGE: bundle_number_arithmetic
        fn_wrapped = bundle_number_arithmetic[4]
        mock_fn = deepcopy(fn_wrapped)
        fb = 3
        mock_fn.fallback = () -> fb
        MAGE.evaluate_fn_wrapper(mock_fn, [10, 0]) == fb
    end

    @test begin # safe div
        using MAGE: bundle_number_arithmetic
        fn_wrapped = bundle_number_arithmetic[5]
        mock_fn = deepcopy(fn_wrapped)
        fb = 3
        mock_fn.fallback = () -> 3
        MAGE.evaluate_fn_wrapper(mock_fn, [10, 0]) == 0 # the default, not the fallback
    end

    @test begin # div to int
        using MAGE: bundle_number_arithmetic
        int_bundle = deepcopy(bundle_number_arithmetic)
        update_caster!(int_bundle, (x) -> floor(Int, x))
        fn_wrapped = int_bundle[4]
        MAGE.evaluate_fn_wrapper(fn_wrapped, [1, 2]) === 0 &&
            MAGE.evaluate_fn_wrapper(fn_wrapped, [1.0, 2]) === 0 &&
            MAGE.evaluate_fn_wrapper(fn_wrapped, [1.0, 2.0]) === 0 &&
            MAGE.evaluate_fn_wrapper(fn_wrapped, [1, 2.0]) === 0
    end

    @test begin
        using MAGE: number_arithmetic
        number_arithmetic.power_of(2, 2) == 4 && number_arithmetic.power_of(25, 0.5) === 5.0
    end
end
