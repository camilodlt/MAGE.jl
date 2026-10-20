
"""
    AbstractEndpoint

Supertype of the objects that turn program outputs into fitness.

An endpoint is how a problem is stated to MAGE. The fitter calls it once per
batch with the outputs of every individual and the expected value, and it
returns one number per individual — lower is better, MAGE minimises.

`BatchEndpoint` is the subtype the fitters use: its constructor receives
`(preds, y)` where `preds[i]` is the vector of outputs of individual `i`, and it
stores one score per individual in a `fitness_results` field.

Defining a problem is therefore just defining a struct:

```julia
struct EndpointMAE <: UTCGP.BatchEndpoint
    fitness_results::Vector{Float64}
    function EndpointMAE(preds::Vector{<:Vector{<:Number}}, y::Number)
        res = [isnan(p[1]) ? 2.0 : abs(p[1] - y) for p in preds]
        return new(res)
    end
end
```

and handing the *type* to [`fit`](@ref). Ready-made ones:
[`EndpointBatchAbsDifference`](@ref), [`EndpointBatchLevensthein`](@ref),
[`EndpointBatchVecDiff`](@ref).
"""
abstract type AbstractEndpoint end
abstract type BatchEndpoint <: AbstractEndpoint end
abstract type Endpoint <: AbstractEndpoint end


# PROTOCOL THAT CONCRETE SHOULD FOLLOW 

"""
    get_endpoint_results(e::AbstractEndpoint)

Return the per-individual fitness vector computed by the endpoint.

This is the one method every [`AbstractEndpoint`](@ref) must support; the
default implementation reads the `fitness_results` field.
"""
function get_endpoint_results(e::AbstractEndpoint)
    return e.fitness_results
end
