
abstract type AbstractEndpoint end
abstract type BatchEndpoint <: AbstractEndpoint end
abstract type Endpoint <: AbstractEndpoint end


# PROTOCOL THAT CONCRETE SHOULD FOLLOW 

function get_endpoint_results(e::AbstractEndpoint)
    return e.fitness_results
end
