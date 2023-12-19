using StringDistances: Levenshtein
"""
PSB2 Paper :
'
    For each output data type, we use the following standard error
    functions for problems outputting that

    Data type:
    • Integer or float: absolute value of the difference between
    program output and correct output.
    • Boolean: 0 for correct and 1 for incorrect output.
    • String: Levenshtein string edit distance between the program
    output and correct output.
    • Vector of integers: add the difference in length between the program’s
    output vector and the correct vector times 1000 to the absolute difference
    between each integer and the corresponding integer in the correct vector.
'
"""

##################
# LEVENSTHEIN    #
##################

struct EndpointBatchLevensthein <: BatchEndpoint
    fitness_results::Vector{Float64}
    function EndpointBatchLevensthein(preds::Vector{Vector{String}}, y::String)
        res = Float64[]
        for ind_outputs in preds
            pred = ind_outputs[1]
            dist = Levenshtein()(pred, y)
            push!(res, dist)
        end
        return new(res)
    end
end

