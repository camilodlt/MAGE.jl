using Test

@testset "MAGE TEST" begin
    include("tests.jl")
    include("libraries/ski/runtests.jl")
end
