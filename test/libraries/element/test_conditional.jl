@testset "Conditional" begin
    @test begin
        # bundle import
        using UTCGP: bundle_element_conditional
        length(bundle_element_conditional) == 1 &&
            _unique_names_in_bundle(bundle_element_conditional)

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
end
