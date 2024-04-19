@testset "Bool Basic" begin
    @test begin
        # bundle import
        using UTCGP: bundle_bool_basic
        length(bundle_bool_basic) == 3 && _unique_names_in_bundle(bundle_bool_basic) # true, false, parse String
    end
    @test begin # true
        fnw = bundle_bool_basic[:ret_true]
        fnw.fn() && fnw.fn(1, 2, 3) # args  
    end
    @test begin # true
        fnw = bundle_bool_basic[:ret_false]
        !fnw.fn() && !fnw.fn(1, 2, 3) # args  
    end
    @test begin # true
        fnw = bundle_bool_basic[:parse_string]
        fnw.fn("true") &&
            !fnw.fn("false") &&
            fnw.fn("true&&true") &&
            !fnw.fn("true&&false") &&
            fnw.fn("true||true") &&
            fnw.fn("false||true") &&
            !fnw.fn("tefuheafioj") &&
            !fnw.fn("")
    end
end



