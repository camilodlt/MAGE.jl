

using UTCGP
using Test


@testset "MetaLibrary" begin
    #Normal 
    @test begin
        bundles_generic = [bundle_listgeneric_basic, bundle_listgeneric_basic]
        l_1 = Library(bundles_generic)
        l_2 = Library(bundles_generic)
        ml = MetaLibrary([l_1, l_2])
        length(ml.libraries) == 2 # Has 2 libraries
    end

    # Abnormal
    @test_throws AssertionError begin
        bundles_generic = [bundle_listgeneric_basic, bundle_listgeneric_basic]
        l_1 = Library(FunctionBundle[]) # empty library
        ml = MetaLibrary([l_1])
    end
    @test_throws AssertionError begin
        bundles_generic = [bundle_listgeneric_basic, bundle_listgeneric_basic]
        l_1 = Library(FunctionBundle[FunctionBundle(i -> i, i -> i)]) # empty bundle
        ml = MetaLibrary([l_1])
    end

    # List Functions names
    @test begin
        bundles_generic = [bundle_listgeneric_basic]
        l_1 = Library(bundles_generic)
        l_2 = Library(bundles_generic)
        ml = MetaLibrary([l_1, l_2])
        names_ = list_functions_names(ml)
        length(names_) == 2
    end
    @test begin
        bundles_generic = [bundle_listgeneric_basic]
        l_1 = Library(bundles_generic)
        l_2 = Library(bundles_generic)
        ml = MetaLibrary([l_1, l_2])
        names_ = list_functions_names(ml)
        names_[1] == ["identity_list", "new_list", "reverse_list"]
    end
    @test begin
        bundles_generic = [bundle_listgeneric_basic]
        l_1 = Library(bundles_generic)
        l_2 = Library(bundles_generic)
        ml = MetaLibrary([l_1, l_2])
        names_ = list_functions_names(ml)
        names_[2] == ["identity_list", "new_list", "reverse_list"]
    end
end
