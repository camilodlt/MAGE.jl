using UTCGP: all_eq_typed

@testset "Algebraic" begin
    @test begin
        # bundle import
        using UTCGP: bundle_listnumber_algebraic
        length(bundle_listnumber_algebraic) == 1 &&
            _unique_names_in_bundle(bundle_listnumber_algebraic)
    end

    @test begin # on int
        using UTCGP.listnumber_algebraic: abs_vector
        all_eq_typed(abs_vector([-1, 2, 0]), [1, 2, 0])
    end
    @test begin # on float 
        using UTCGP.listnumber_algebraic: abs_vector
        all_eq_typed(abs_vector([-1.0, 2.0, 0.0]), [1.0, 2.0, 0.0])
    end
end
