
using UTCGP
using Test


bundles_generic = [bundle_listgeneric_basic]
@testset "Basic list generic Bundle" begin

    @test_throws MethodError begin
        Library()
    end

    # Lib has one wrapped bundle
    @test begin
        l = Library(bundles_generic)
        length(l.bundles) == length(bundles_generic)
    end
    @test begin
        l = Library(bundles_generic)
        length(l.bundles) == 1
    end

    # Lib is empty so length 0
    @test begin
        l = Library(bundles_generic)
        length(l) == 0
    end
    @test begin
        l = Library(bundles_generic)
        size(l) == 0
    end

    # add bundle to lib
    @test begin
        l = Library(bundles_generic)
        add_bundle_to_library!(l, bundle_listgeneric_basic)
        length(l.bundles) == 2
    end

    @test begin
        println(length(bundles_generic))
        l = Library(bundles_generic)
        feedback = add_bundle_to_library!(l, bundle_listgeneric_basic)
        feedback == 2
    end


    ### UNPACK ####

    #Normal 
    @test begin
        l = Library(bundles_generic)
        unpack_bundles_in_library!(l)
        length(l) == 3 # identity and new_list, reverse
    end
    @test begin
        bundles_generic = [bundle_listgeneric_basic, bundle_listgeneric_basic]
        l = Library(bundles_generic)
        unpack_bundles_in_library!(l)
        length(l) == 6 # identity, new_list, reverse_list x 2
    end
    @test begin
        bundles_generic = [bundle_listgeneric_basic]
        l = Library(bundles_generic)
        unpack_bundles_in_library!(l)
        names_fns = [fn_w.name for fn_w in l]
        names_fns == [:identity_list, :new_list, :reverse_list]
    end
    @test begin
        bundles_generic = [bundle_listgeneric_basic]
        l = Library(bundles_generic)
        unpack_bundles_in_library!(l)
        names_fns = list_functions_names(l)
        names_fns == ["identity_list", "new_list", "reverse_list"]
    end
    @test begin
        bundles_generic = [bundle_listgeneric_basic]
        l = Library(bundles_generic)
        unpack_bundles_in_library!(l)
        names_fns = list_functions_names(l; symbol = true)
        names_fns == [:identity_list, :new_list, :reverse_list]
    end
    # Abnormal
    @test_logs (:warn, r"Library had functions in the library.*") match_mode = :any begin
        # Library had already fns so the unpacking will override that lib.
        l = Library(bundles_generic)
        unpack_bundles_in_library!(l)
        unpack_bundles_in_library!(l)
    end

    @test_logs (:warn, r"empty list of functions") match_mode = :any begin
        # The bundles combined had 0 fns.
        l = Library(FunctionBundle[])
        unpack_bundles_in_library!(l)
    end
end
