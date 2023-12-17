# push!(LOAD_PATH, "/home/irit/Documents/Camilo/utcgp/utcgp_julia/utcgp")
# using Revise
using UTCGP
using Test


"""
BAD FN to test dispatch. 

DO not use
"""
function new_list()
    return ""
end

@testset "Basic list generic Bundle" begin
    @test begin
        wrapper = bundle_basic_generic_list[1] # Identity list
        a = []
        wrapper.fn(a) == a
    end
    @test begin
        wrapper = bundle_basic_generic_list[1] # Identity list
        println(wrapper.parent_module)
        wrapper.name == :identity_list
    end
    @test begin
        wrapper = bundle_basic_generic_list[1] # Identity list
        a = [123]
        wrapper.fn(a) == a
    end
    @test begin
        wrapper = bundle_basic_generic_list[2] # new_list
        wrapper.fn() == []
    end
    @test begin
        wrapper = bundle_basic_generic_list[2] # new_list
        m = methods(wrapper.fn)
        length(m) == 1
    end
end
