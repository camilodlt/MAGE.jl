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
    function EndpointBatchLevensthein(preds::Vector{Vector{String}}, y::Vector{String})
        res = Float64[]
        for ind_outputs in preds
            d = 0.0
            if length(ind_outputs) != length(y)
                d += 1000
            end
            for (pred, truth) in zip(ind_outputs, y)
                l = Levenshtein()(pred, truth)
                l = isnan(l) ? 1000 : l
                d += l
            end
            push!(res, d)
        end
        return new(res)
    end
end

##################
# ABS DIFFERENCE #
##################

struct EndpointBatchAbsDifference <: BatchEndpoint
    fitness_results::Vector{Float64}
    function EndpointBatchAbsDifference(preds::Vector{<:Vector{<:Number}}, y::Number)
        res = Float64[]
        for ind_outputs in preds
            pred = ind_outputs[1]
            dist = convert(Float64, abs(round(pred, digits = 12) - round(y, digits = 12)))
            push!(res, dist)
        end
        return new(res)
    end
    function EndpointBatchAbsDifference(
        preds::Vector{<:Vector{<:Number}},
        y::Vector{<:Number},
    )
        res = Float64[]
        for ind_outputs in preds
            ind_distances = Float64[]
            for i = 1:length(y)
                pred = ind_outputs[i]
                truth = y[i]
                dist = convert(
                    Float64,
                    abs(round(pred, digits = 12) - round(truth, digits = 12)),
                )
                push!(ind_distances, dist)
            end

            non_nan_preds = filter(!isnan, ind_distances)
            if length(non_nan_preds) == 0
                ind_mean_distance = 10_000
            else
                ind_mean_distance = sum(non_nan_preds)
            end
            push!(res, ind_mean_distance)
        end
        return new(res)
    end
    function EndpointBatchAbsDifference(
        preds::Vector{<:Vector{<:Bool}},
        y::Vector{<:Number},
    )
        preds_ = [[bool_to_int_caster(p) for p in ind] for ind in preds]
        return EndpointBatchAbsDifference(preds_, y)
    end
    function EndpointBatchAbsDifference(preds::Vector{BitVector}, y::Vector{<:Number})
        preds_ = [[bool_to_int_caster(p) for p in ind] for ind in preds]
        return EndpointBatchAbsDifference(preds_, y)
    end

end


######################
# VECTOR DIFFERENCES #
######################
struct EndpointBatchVecDiff <: BatchEndpoint
    fitness_results::Vector{Float64}
    function EndpointBatchVecDiff(
        preds::Vector{<:Vector{<:Vector{<:Number}}}, # pop[ ind1[ out1, out2 ], ind2... ]. Each out => [int]
        y::Vector{<:Vector{<:Number}},
    )
        PENALTY = 1000
        res = Float64[]
        n_vecs = length(preds[1]) # assume all are the same
        @assert n_vecs == length(y)
        for ind_preds in preds
            ind_losses = Float64[]
            for ith_vec = 1:length(y)
                pred_vec = ind_preds[ith_vec]
                true_vec = y[ith_vec]
                loss = 0.0
                # diff in length
                length_penalty = abs(length(pred_vec) - length(true_vec)) * PENALTY
                loss += length_penalty
                # element wise diff 
                for (t, p) in zip(true_vec, pred_vec)
                    loss += abs(round(t, digits = 12) - round(p, digits = 12))
                end
                push!(ind_losses, loss)
            end
            ind_mean_loss = sum(filter(!isnan, ind_losses))
            push!(res, ind_mean_loss)
        end
        return new(res)
    end
    function EndpointBatchVecDiff(
        preds::Vector{<:Vector{<:Vector{<:Number}}}, # pop[ ind1[ out1, out2 ], ind2... ]. Each out => [int]
        y::Vector{<:Number},
    )
        return EndpointBatchVecDiff(preds, [y])
    end
end



