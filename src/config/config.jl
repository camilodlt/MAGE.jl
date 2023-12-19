"""
Specifies chromosomes/nodes properties


    n_nodes::Int(
        connection_temperature::Int
        arity::Int
        offset_by::Int)
"""
struct nodeConfig
    n_nodes::Int
    connection_temperature::Int
    arity::Int
    offset_by::Int
    function nodeConfig(
        n_nodes::Int,
        connection_temperature::Int,
        arity::Int,
        offset_by::Int,
    )
        @assert connection_temperature >= 1
        @assert arity >= 1
        @assert offset_by >= 1
        return new(n_nodes, connection_temperature, arity, offset_by)
    end
end

"""
Specifies the model types for :
- inputs
- program
- outputs

Outputs types should be a subset of program (chromosome) types.

In principle, input types could be different than program/outputs types although that 
case is rare


    modelArchitecture(
        inputs_types::Vector
        inputs_types_idx::Vector{Int}
        chromosomes_types::Vector{<:DataType}
        outputs_types::Vector
        outputs_types_idx::Vector{Int})
"""
struct modelArchitecture
    inputs_types::Vector
    inputs_types_idx::Vector{Int}
    chromosomes_types::Vector{<:DataType}
    outputs_types::Vector
    outputs_types_idx::Vector{Int}
end


"""
Specifies the experiment properties.


    runConf(lambda_::Int
        generations::Int
        mutation_rate::Float64
        output_mutation_rate::Float64)

"""
struct runConf
    lambda_::Int
    generations::Int
    mutation_rate::Float64
    output_mutation_rate::Float64
end
