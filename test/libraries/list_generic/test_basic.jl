# push!(LOAD_PATH, "/home/irit/Documents/Camilo/mage/mage_julia/mage")
# using Revise
using MAGE


"""
BAD FN to test dispatch. 

DO not use
"""
function new_list()
    return ""
end

@testset "Basic list generic Bundle" begin

    @test begin
        # bundle import
        using MAGE: bundle_listgeneric_basic
        length(bundle_listgeneric_basic) == 3 &&
            _unique_names_in_bundle(bundle_listgeneric_basic)
    end
    @test begin
        wrapper = bundle_listgeneric_basic[1] # Identity list
        a = []
        wrapper.fn(a) == a
    end
    @test begin
        wrapper = bundle_listgeneric_basic[1] # Identity list
        wrapper.name == :identity_list
    end
    @test begin
        wrapper = bundle_listgeneric_basic[1] # Identity list
        a = [123]
        wrapper.fn(a) == a
    end
    @test begin
        wrapper = bundle_listgeneric_basic[2] # new_list
        wrapper.fn() == []
    end
    @test begin
        wrapper = bundle_listgeneric_basic[2] # new_list
        m = methods(wrapper.fn)
        length(m) == 1
    end
    @test begin
        using MAGE.listgeneric_basic: reverse_list
        reverse_list([1, 2, 3]) == [3, 2, 1]
    end
end
