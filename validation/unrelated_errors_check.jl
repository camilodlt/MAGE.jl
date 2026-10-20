using Test, MAGE, ErrorTypes, DataStructures
import SearchNetworks as sn
@testset "Independent unrelated errors (no cache calls)" begin
    include(joinpath(@__DIR__, "..", "test", "problem_specific", "test_find_pair.jl"))
    include(joinpath(@__DIR__, "..", "test", "search_network", "sn_helpers.jl"))
    include(joinpath(@__DIR__, "..", "test", "search_network", "test_behavior_hasher.jl"))
end
