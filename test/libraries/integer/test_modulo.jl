using Test

@testset begin

    @test begin
        # bundle
        using UTCGP
        length(bundle_integer_modulo) == 1 && _unique_names_in_bundle(bundle_integer_modulo)
    end

    @test begin
        # modulo correct
        using UTCGP.integer_modulo: modulo
        modulo(4, 2) == 0
    end
    @test begin
        # modulo correct
        using UTCGP.integer_modulo: modulo
        modulo(4, 3) == 1
    end
    @test_throws DivideError begin
        # modulo incorrect 
        using UTCGP.integer_modulo: modulo
        modulo(4, 0) == 1
    end




end
