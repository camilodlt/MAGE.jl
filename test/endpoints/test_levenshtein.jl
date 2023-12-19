@testset "Levenshtein" begin
    @test begin
        preds = [["CamelCase"], ["Camel-Case"]]
        y = "CamelCase"
        res = [0.0, 1.0]
        fitness = EndpointBatchLevensthein(preds, y)
        fitness.fitness_results == [0.0, 1.0]
    end
    @test begin
        preds = [["CamelCase"], ["Camel-Case"]]
        y = "CamelCase"
        res = [0.0, 1.0]
        fitness = EndpointBatchLevensthein(preds, y)
        get_endpoint_results(fitness) == [0.0, 1.0]
    end
end
