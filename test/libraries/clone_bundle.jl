using UTCGP

@testset "Clone Bundle" begin

    @test begin
        # FROM INT TO INT
        # COPY BUNDLE
        generic_bundle = UTCGP.bundle_number_reduce
        bundle_int = deepcopy(generic_bundle)
        bundle_float = deepcopy(generic_bundle)
        # Update caster
        update_caster!(bundle_int, x -> floor(Int, x))
        update_fallback!(bundle_int, () -> 0)
        update_caster!(bundle_float, x -> floor(Float64, x))
        update_fallback!(bundle_float, () -> 0.0)
        # eval int => int
        reduce_sum = bundle_int[1]
        UTCGP.evaluate_fn_wrapper(reduce_sum, [[1, 2, 3]]) === 6
    end
    @test begin
        # FROM INT TO FLOAT
        # COPY BUNDLE
        generic_bundle = UTCGP.bundle_number_reduce
        bundle_int = deepcopy(generic_bundle)
        bundle_float = deepcopy(generic_bundle)
        # Update caster
        update_caster!(bundle_int, x -> convert(Float64, x))
        update_fallback!(bundle_int, () -> 0)
        update_caster!(bundle_float, x -> floor(Float64, x))
        update_fallback!(bundle_float, () -> 0.0)
        # eval int => int
        reduce_sum = bundle_int[1]
        UTCGP.evaluate_fn_wrapper(reduce_sum, [[1, 2, 3]]) === 6.0
    end
    @test begin
        # FROM FLOAT TO INT
        # COPY BUNDLE
        generic_bundle = UTCGP.bundle_number_reduce
        bundle_int = deepcopy(generic_bundle)
        bundle_float = deepcopy(generic_bundle)
        # Update caster
        update_caster!(bundle_int, x -> floor(Int32, x))
        update_fallback!(bundle_int, () -> 0)
        update_caster!(bundle_float, x -> floor(Int, x))
        update_fallback!(bundle_float, () -> 0.0)
        # eval int => int
        reduce_sum = bundle_float[1]
        UTCGP.evaluate_fn_wrapper(reduce_sum, [[1.0, 2.0, 3.0]]) === 6
    end
    @test begin
        # FROM FLOAT TO FLOAT
        # COPY BUNDLE
        generic_bundle = UTCGP.bundle_number_reduce
        bundle_int = deepcopy(generic_bundle)
        bundle_float = deepcopy(generic_bundle)
        # Update caster
        update_caster!(bundle_int, x -> convert(Float64, x))
        update_fallback!(bundle_int, () -> 0)
        update_caster!(bundle_float, x -> convert(Float64, x))
        update_fallback!(bundle_float, () -> 0.0)
        # eval int => int
        reduce_sum = bundle_float[1]
        UTCGP.evaluate_fn_wrapper(reduce_sum, [[1.0, 2.0, 3.0]]) === 6.0
    end

end
