"""
    nodeConfig(n_nodes::Int, connection_temperature::Int, arity::Int, offset_by::Int)

Shape of every chromosome in the genome.

# Arguments
- `n_nodes`: number of evolvable nodes per chromosome. This is the search
  budget for graph size: more nodes means more dormant material a mutation can
  reactivate, at the cost of a larger genome.
- `connection_temperature`: bias applied when sampling a connexion; `1` samples
  uniformly among the reachable nodes. Must be `>= 1`.
- `arity`: number of `(CONNEXION, TYPE)` pairs per node, i.e. the largest number
  of arguments a node can feed its function. A function needing fewer simply
  ignores the extra ones.
- `offset_by`: number of inputs sitting in front of each chromosome. Must equal
  the number of input types in the [`modelArchitecture`](@ref).

```julia
node_config = nodeConfig(40, 1, 2, n_inputs)  # 40 nodes, binary, n_inputs inputs
```

Every chromosome of a genome shares one `nodeConfig`.
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
    modelArchitecture(inputs_types, inputs_types_idx, chromosomes_types,
                      outputs_types, outputs_types_idx)

The types a model is built from: what goes in, what the program may compute,
and what comes out.

# Arguments
- `chromosomes_types`: one entry per chromosome, in order. This is the list of
  types the evolved program is allowed to produce; chromosome `i` only ever
  holds values of `chromosomes_types[i]`.
- `inputs_types`: type of each input node, in order.
- `inputs_types_idx`: for each input, the index into `chromosomes_types` it is
  seen as. This is what lets a typed connexion reach an input.
- `outputs_types`: type of each program output.
- `outputs_types_idx`: for each output, the index of the chromosome it reads
  from.

Output types should be a subset of the chromosome types. Input types could in
principle differ from the chromosome types, although that case is rare.

# Examples

Symbolic regression — one type, `n` float inputs, one float output:

```julia
modelArchitecture(
    [Float64 for _ in 1:n], [1 for _ in 1:n],   # inputs, all seen as chromosome 1
    [Float64],                                  # one chromosome
    [Float64], [1],                             # one output, read from chromosome 1
)
```

A multimodal model — an image input, three chromosomes, a float output:

```julia
modelArchitecture(
    [ImageType], [1],                           # the input is an image (chromosome 1)
    [ImageType, Float64, Int],                  # image / float / integer chromosomes
    [Float64], [2],                             # the output is the float chromosome
)
```

The second case is what makes MAGE multimodal: a node in the float chromosome
can read from the image chromosome, so a blur can feed a mean which can feed
back into an image operator as a parameter.

The number of chromosomes must match the number of libraries in the
[`MetaLibrary`](@ref), and the number of inputs must match
`nodeConfig.offset_by`.
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

"""
    AbstractRunConf

Supertype of the run configurations, one per search strategy:
[`runConf`](@ref) (`1 + λ`), [`RunConfGA`](@ref) (genetic algorithm),
[`RunConfCrossOverGA`](@ref) (GA with crossover), `RunConfNSGA2`,
`RunConfME` (MAP-Elites) and `RunConfSTN`.

The fitter a configuration belongs to is fixed by its type: [`fit`](@ref) takes
a `runConf`, [`fit_ga`](@ref) a `RunConfGA`, and so on. Optional features are
discovered through traits — see [`runconf_trait`](@ref) and
[`runconf_trait_evolutationary_strategy`](@ref).
"""
abstract type AbstractRunConf end
abstract type AbstractRunConfTrait end
struct MissingRunConfTrait <: UTCGP.AbstractRunConfTrait end

# Default trait: if no specialization is provided for a type T, we return a MissingRunConfTrait.
"""
    runconf_trait(::Type{T})

Trait hook letting a run configuration advertise an optional capability.

The fallback returns `MissingRunConfTrait()`, meaning "this configuration does
not opt in". Specialising it is how, for instance,
[`RunConfCrossOverGA`](@ref) declares its crossover arguments — see
[`runconf_trait_crossover`](@ref).
"""
runconf_trait(::Type{T}) where {T} = MissingRunConfTrait()

"""
    runConf(lambda_::Int, generations::Int, mutation_rate::Float64,
            output_mutation_rate::Float64)

Run configuration for the `1 + λ` strategy driven by [`fit`](@ref).

- `lambda_`: number of offspring generated from the single parent each
  generation.
- `generations`: number of generations to run.
- `mutation_rate`: how much of an individual to mutate. Read as a per-allele
  probability by [`standard_mutate!`](@ref), and as a *number* of alleles
  (`ceil(mutation_rate)` and friends) by the numbered mutations — which is why
  values above `1.0`, such as `1.1`, are common here.
- `output_mutation_rate`: probability that each output node is redirected.

```julia
run_conf = runConf(10, 100, 1.1, 0.1)   # 1 + 10, 100 generations
```

For a real population with tournament selection, use [`RunConfGA`](@ref) with
[`fit_ga`](@ref).
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

Run configuration for the generational genetic algorithm driven by
[`fit_ga`](@ref).

The population holds `n_elite + n_new` individuals. Each generation keeps the
`n_elite` best and refills the remaining `n_new` slots by tournaments of
`tournament_size` among them; only the non-elite slots are then mutated.

- `mutation_rate`: passed to the mutation callback, as in [`runConf`](@ref).
- `output_mutation_rate`: probability of redirecting each output node.
- `generations`: number of generations to run.

```julia
run_conf = RunConfGA(5, 15, 3, 1.1, 0.1, 200)   # 20 individuals, 5 elites
```

Constructing one logs the resulting population layout, and asserts that
`n_elite >= 1`, `n_new >= 1`, `tournament_size >= 1` and `generations >= 1`.
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
    GAWithTournamentArgs(n_elite, n_new, tournament_size)

The tournament-GA parameters a run configuration exposes through
[`runconf_trait_evolutationary_strategy`](@ref).

Run configurations have to adapt to this GA api: a configuration that returns
one of these can be driven by the generic GA machinery whatever else it
carries.
"""
struct GAWithTournamentArgs <: AbstractGAArgs
    n_elite::Int64
    n_new::Int64
    tournament_size::Int64
end
struct MissingGAArgs <: AbstractGAArgs end

"""
    runconf_trait_evolutationary_strategy(conf::AbstractRunConf)

Return the evolutionary-strategy parameters of `conf`, as a
[`GAWithTournamentArgs`](@ref), or `MissingGAArgs` when the configuration does
not describe a tournament GA.

This is what lets generic code ask "how many elites, how many new, what
tournament size?" without knowing the concrete configuration type.
"""
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

"""
    RunConfSTN(
        sample_size::Int,
        behavior_col::String,
        serialization_col::String,
        mutation_rate::Float64,
        output_mutation_rate::Float64,
        generations::Int
        )

Specifies the experiment properties for a search-network traced run.

`behavior_col` and `serialization_col` name the database columns the
[search network](@ref "Search Networks") writer uses for an individual's
behaviour and its serialised genome; `sample_size` is how many samples the
behaviour is measured on.
"""
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
