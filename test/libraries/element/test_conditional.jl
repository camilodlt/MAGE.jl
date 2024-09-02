@testset "Conditional" begin
    using UTCGP.element_conditional: if_else_multiplexer_factory

    @test begin
        # bundle import
        using UTCGP: bundle_element_conditional
        length(bundle_element_conditional) == 1 &&
            _unique_names_in_bundle(bundle_element_conditional)
    end
    @test begin
        # bundle import
        using UTCGP: bundle_element_conditional_factory
        length(bundle_element_conditional_factory) == 1 &&
            _unique_names_in_bundle(bundle_element_conditional_factory)
    end

    # IF ELSE MULTIPLEXER
    @test begin
        using UTCGP.element_conditional: if_else_multiplexer
        if_else_multiplexer(1, 122.12, 12.12) == 122.12 &&
            if_else_multiplexer(10, 122.12, 12.12) == 122.12 &&
            if_else_multiplexer(0.12, 122.12, 12.12) == 122.12 &&
            if_else_multiplexer(-1, 122.12, 12.12) == 12.12 &&
            if_else_multiplexer(0, 122.12, 12.12) == 12.12 &&
            if_else_multiplexer(0.0, 122.12, 12.12) == 12.12
    end

    @test_throws MethodError begin
        if_else_multiplexer(0, 122.12, 12) == 12.12
    end

    # IF ELSE MULTIPLEXER Factory
    @test begin
        fn = if_else_multiplexer_factory(Float64)
        fn(1, 122.12, 12.12) == 122.12 &&
            fn(10, 122.12, 12.12) == 122.12 &&
            fn(0.12, 122.12, 12.12) == 122.12 &&
            fn(-1, 122.12, 12.12) == 12.12 &&
            fn(0, 122.12, 12.12) == 12.12 &&
            fn(0.0, 122.12, 12.12) == 12.12
    end

    @test_throws MethodError begin
        fn = if_else_multiplexer_factory(Int)
        fn(0, 122.12, 12) # both have to be ints
    end
    @test_throws MethodError begin
        fn = if_else_multiplexer_factory(Int)
        fn(0, 122.12, 12.12) # both have to be ints
    end
end
