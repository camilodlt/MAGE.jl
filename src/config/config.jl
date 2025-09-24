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
    inputs_types::Vector{<:T} where {T <: Type}
    inputs_types_idx::Vector{Int}
    chromosomes_types::Vector{<:T} where {T <: Type}
    outputs_types::Vector{<:T} where {T <: Type}
    outputs_types_idx::Vector{Int}
end


# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ #
# ################# RUN CONF ################### #
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ #

abstract type AbstractRunConf end
abstract type AbstractRunConfTrait end
struct MissingRunConfTrait <: UTCGP.AbstractRunConfTrait end

# Default trait: if no specialization is provided for a type T, we return a MissingRunConfTrait.
runconf_trait(::Type{T}) where {T} = MissingRunConfTrait()

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
    # @assert tournament_size <= n_elite "The tournament has to involve at most the number of elite individuals ($tournament_size should be <= $n_elite)"
    @assert tournament_size >= 1 "The tournament has to involve at least one elite individual"
    return some(1)
end

function _info_config_ga(n_elite::Int, n_new::Int, tournament_size::Int)
    pop = n_elite + n_new
    @info "Run conf with a pop of $pop (Elite: $n_elite, Other : $n_new)."
    return @info "Run conf with tournament size of $tournament_size"
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
        return new(
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
    RunConfCrossOverGA(n_elite, n_new, tournament_size, mutation_n_active_nodes,
                       mutation_prob, crossover_prob, output_mutation_rate, generations)

Configuration for a Genetic Algorithm (GA) using crossover and mutation.

# Arguments
- `n_elite::Int`: Number of elite individuals to preserve each generation.
- `n_new::Int`: Number of new individuals to create via genetic operators.
- `tournament_size::Int`: Size of the tournament used for selection.
- `mutation_n_active_nodes::Float64`: Mutation rate relative to the number of active nodes.
- `mutation_prob::Float64`: Probability of applying mutation (must be between 0 and 1).
- `crossover_prob::Float64`: Probability of applying crossover (must be between 0 and 1).
- `output_mutation_rate::Float64`: Mutation rate for output genes.
- `generations::Int`: Number of generations to run (must be at least 1).

Configuration is verified via `_verif_config_ga` and logged using `_info_config_ga`.
"""
struct RunConfCrossOverGA <: AbstractRunConf
    n_elite::Int
    n_new::Int
    tournament_size::Int
    mutation_n_active_nodes::Int
    mutation_prob::Float64
    crossover_prob::Float64
    output_mutation_rate::Float64
    generations::Int
    function RunConfCrossOverGA(
            n_elite::Int,
            n_new::Int,
            tournament_size::Int,
            mutation_n_active_nodes::Int,
            mutation_prob::Float64,
            crossover_prob::Float64,
            output_mutation_rate::Float64,
            generations::Int,
        )
        _verif_config_ga(n_elite, n_new, tournament_size)
        _info_config_ga(n_elite, n_new, tournament_size)
        @assert 0.0 < mutation_prob <= 1.0 "Mutation Prob has to be greater than 0 and at most 1. Got $mutation_prob "
        @assert mutation_n_active_nodes >= 1 "Mutation_n_active_nodes has to be greater than 1. Got $(mutation_n_active_nodes)"
        @assert 0.0 < crossover_prob <= 1.0 "Crossover Prob has to be greater than 0 and at most 1. Got $(crossover_prob)"
        @assert generations >= 1 "At least one iteration"
        return new(
            n_elite,
            n_new,
            tournament_size,
            mutation_n_active_nodes,
            mutation_prob,
            crossover_prob,
            output_mutation_rate,
            generations,
        )
    end
end

abstract type AbstractGAArgs end

"""
RunConfs have to adapt to this GA api
"""
struct GAWithTournamentArgs <: AbstractGAArgs
    n_elite::Int64
    n_new::Int64
    tournament_size::Int64
end
struct MissingGAArgs <: AbstractGAArgs end

runconf_trait_evolutationary_strategy(conf::AbstractRunConf) = MissingGAArgs
runconf_trait_evolutationary_strategy(conf::UTCGP.RunConfCrossOverGA) =
    GAWithTournamentArgs(conf.n_elite, conf.n_new, conf.tournament_size)

# TODO
abstract type AbstractOnePlusLambda end
struct OnePlusLambda <: AbstractOnePlusLambda end

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
    pop_size::Int
    tournament_size::Int
    mutation_rate::Float64
    output_mutation_rate::Float64
    generations::Int
    function RunConfNSGA2(
            pop_size::Int,
            tournament_size::Int,
            mutation_rate::Float64,
            output_mutation_rate::Float64,
            generations::Int,
        )
        @assert tournament_size >= 1 "The tournament has to involve at least one individual"
        @assert tournament_size < pop_size "Tournament size must be smaller than population size"
        @assert generations >= 1 "At least one iteration"
        @info "Run conf with a pop of $pop_size"
        @info "Run conf with tournament size of $tournament_size"
        return new(pop_size, tournament_size, mutation_rate, output_mutation_rate, generations)
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
        return new(centroids, sample_size, mutation_rate, output_mutation_rate, generations)
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
        return new(
            sample_size,
            behavior_col,
            serialization_col,
            mutation_rate,
            output_mutation_rate,
            generations,
        )
    end
end

export runconf_trait, runconf_trait_evolutationary_strategy
export RunConfCrossOverGA, GAWithTournamentArgs
