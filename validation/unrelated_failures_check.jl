using Test, UTCGP
@testset "Independent unrelated failures (no cache calls)" begin
    include(joinpath(@__DIR__, "..", "test", "libraries", "test_llm_generated_functions.jl"))
    include(joinpath(@__DIR__, "..", "test", "problem_specific", "test_dice_game.jl"))
end
