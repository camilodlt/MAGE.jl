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
    inputs_types::Vector{<:T} where {T<:Type}
    inputs_types_idx::Vector{Int}
    chromosomes_types::Vector{<:T} where {T<:Type}
    outputs_types::Vector{<:T} where {T<:Type}
    outputs_types_idx::Vector{Int}
end


# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ # 
# ################# RUN CONF ################### #
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ # 

abstract type AbstractRunConf end

"""
    runConf(lambda_::Int
        generations::Int
        mutation_rate::Float64
        output_mutation_rate::Float64)

Specifies the experiment properties.
"""
struct runConf <: AbstractRunConf
    lambda_::Int
    generations::Int
    mutation_rate::Float64
    output_mutation_rate::Float64
end

function _verif_config_ga(n_elite::Int, n_new::Int, tournament_size::Int)::Option{Int}
    @assert n_elite >= 1 "The elite truncation needs to involve more than 1 individual"
    @assert n_new >= 1 "The 'extra' population has to be > 1"
    @assert tournament_size <= n_elite "The tournament has to involve at most the number of elite individuals ($tournament_size should be <= $n_elite)"
    @assert tournament_size >= 1 "The tournament has to involve at least one elite individual"
    some(1)
end

function _info_config_ga(n_elite::Int, n_new::Int, tournament_size::Int)
    pop = n_elite + n_new
    @info "Run conf with a pop of $pop (Elite: $n_elite, Other : $n_new)."
    @info "Run conf with tournament size of $tournament_size"
end

"""
    RunConfGA( 
        n_elite::Int,
        n_new::Int,
        tournament_size::Int,
        mutation_rate::Float64,
        output_mutation_rate::Float64,
        generations::Int
        )
    
Specifies the experiment properties for GA.
"""
struct RunConfGA <: AbstractRunConf
    n_elite::Int
    n_new::Int
    tournament_size::Int
    mutation_rate::Float64
    output_mutation_rate::Float64
    generations::Int
    function RunConfGA(
        n_elite::Int,
        n_new::Int,
        tournament_size::Int,
        mutation_rate::Float64,
        output_mutation_rate::Float64,
        generations::Int,
    )
        _verif_config_ga(n_elite, n_new, tournament_size)
        _info_config_ga(n_elite, n_new, tournament_size)
        @assert generations >= 1 "At least one iteration"
        new(
            n_elite,
            n_new,
            tournament_size,
            mutation_rate,
            output_mutation_rate,
            generations,
        )
    end
end

"""
    RunConfNSGA2( 
        n_new::Int,
        tournament_size::Int,
        mutation_rate::Float64,
        output_mutation_rate::Float64,
        generations::Int
        )
    
Specifies the experiment properties for NSGA2.
"""
struct RunConfNSGA2 <: AbstractRunConf
    n_new::Int
    tournament_size::Int
    mutation_rate::Float64
    output_mutation_rate::Float64
    generations::Int
    function RunConfNSGA2(
        n_new::Int,
        tournament_size::Int,
        mutation_rate::Float64,
        output_mutation_rate::Float64,
        generations::Int,
    )
        # n elite faked to 1 for reusing methods
        _verif_config_ga(1, n_new, tournament_size)
        _info_config_ga(1, n_new, tournament_size)
        @assert generations >= 1 "At least one iteration"
        new(
            n_new,
            tournament_size,
            mutation_rate,
            output_mutation_rate,
            generations,
        )
    end
end


"""
    RunConfME( 
        centroids::Vector{Vector{Float64}}
        sample_size::Int
        mutation_rate::Float64
        output_mutation_rate::Float64
        generations::Int
        )
    
Specifies the experiment properties for GA.
"""
struct RunConfME <: AbstractRunConf
    centroids::Vector{Vector{Float64}}
    sample_size::Int
    mutation_rate::Float64
    output_mutation_rate::Float64
    generations::Int
    function RunConfME(
        centroids::Vector{Vector{Float64}},
        sample_size::Int,
        mutation_rate::Float64,
        output_mutation_rate::Float64,
        generations::Int,
    )
        @assert generations >= 1 "At least one iteration"
        new(centroids, sample_size, mutation_rate, output_mutation_rate, generations)
    end
end

struct RunConfSTN <: AbstractRunConf
    sample_size::Int
    behavior_col::String
    serialization_col::String
    mutation_rate::Float64
    output_mutation_rate::Float64
    generations::Int
    function RunConfSTN(
        sample_size::Int,
        behavior_col::String,
        serialization_col::String,
        mutation_rate::Float64,
        output_mutation_rate::Float64,
        generations::Int,
    )
        @assert generations >= 1 "At least one iteration"
        new(
            sample_size,
            behavior_col,
            serialization_col,
            mutation_rate,
            output_mutation_rate,
            generations,
        )
    end
end



