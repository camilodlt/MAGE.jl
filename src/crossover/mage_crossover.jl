#~~~~~~~~~~~~~~ MAGE CROSSOVER: SWAP CHROMOSOMES  ~~~~~~~~~~~~#

# --- CrossOver Arguments Minimal API ---

"""
    AbstractCrossOverArgs

Abstract type for crossover configuration arguments.
"""
abstract type AbstractCrossOverArgs end

"""
    CrossOverArgs

Basic crossover configuration parameters.

# Fields
- `mutation_prob::Float64`: Probability of applying mutation.
- `mutation_n_active_nodes::Int64`: Number of active nodes used in mutation.
- `crossover_prob::Float64`: Probability of performing crossover.
"""
struct CrossOverArgs <: AbstractCrossOverArgs
    mutation_prob::Float64
    mutation_n_active_nodes::Int64
    crossover_prob::Float64
end

"""
    CrossOverMutRateArgs

Crossover configuration parameters using an explicit mutation rate.

# Fields
- `mutation_prob::Float64`: Probability of applying mutation.
- `mutation_rate::Int64`: The Probability for mutation rate (normally on each node).
- `crossover_prob::Float64`: Probability of performing crossover.
"""
struct CrossOverMutRateArgs <: AbstractCrossOverArgs
    mutation_prob::Float64
    mutation_rate::Int64
    crossover_prob::Float64
end

"""
    MissingCrossOverArgs

Represents missing crossover configuration parameters.
"""
struct MissingCrossOverArgs <: AbstractCrossOverArgs end

# --- Run Configuration Trait for Crossover ---
"""
If there is no method specialized
"""
runconf_trait_crossover(conf::AbstractRunConf) = MissingCrossOverArgs

"""
    runconf_trait_crossover(conf::UTCGP.RunConfCrossOverGA) -> CrossOverArgs

Extracts the minimal crossover arguments from a run configuration.
"""
runconf_trait_crossover(conf::UTCGP.RunConfCrossOverGA) =
    CrossOverArgs(conf.mutation_prob, conf.mutation_n_active_nodes, conf.crossover_prob)

"""
    numbered_mutation_trait(conf::CrossOverArgs) -> NumberedMutationArgs

Extracts the arguments for numbered mutation from the provided crossover configuration.
"""
numbered_mutation_trait(conf::CrossOverArgs) =
    NumberedMutationArgs(conf.mutation_n_active_nodes)


# --- Population-Level mage_crossover Functions ---
"""
    mage_crossover(inds::Population, run_config::AbstractRunConf, model_architecture::modelArchitecture,
                   meta_library::MetaLibrary, shared_inputs::SharedInput, fitness::Vector{Float64}; extras::Dict=Dict()) -> Population

Entry Point for using the standard `mage_crossover`.

Creates a new population by performing truncation selection and generating new individuals
via crossover (with subsequent mutation). The provided `run_config` is converted via the trait APIs
to extract crossover/mutation and ES parameters.

Lower fitness is considered better.

# Arguments
- `inds`: Current population (vector of `UTGenome`).
- `run_config`: Run configuration that supports the crossover trait and mutation trait.
- `model_architecture`: Genome architecture information.
- `meta_library`: Library of functions used during mutation.
- `shared_inputs`: Shared inputs required during mutation.
- `fitness`: Vector of fitness values.
- `extras`: Optional extra parameters.

# Returns
- A new population (`Vector{UTGenome}`).
"""
function mage_crossover(
    inds::Population,
    full_population::Population,
    run_config::AbstractRunConf,
    model_architecture::modelArchitecture,
    meta_library::MetaLibrary,
    shared_inputs::SharedInput,
    fitness::Vector{Float64};
    extras::Dict = Dict(),
    n_chromosomes_to_swap::Int = 1,
)
    mage_crossover(
        inds,
        full_population,
        runconf_trait_crossover(run_config),
        runconf_trait_evolutationary_strategy(run_config),
        model_architecture,
        meta_library,
        shared_inputs,
        fitness;
        extras = extras,
        n_chromosomes_to_swap = n_chromosomes_to_swap,
    )
end

"""
    mage_crossover(inds::Population, crossover_args::CrossOverArgs, evolutionary_strategy_args::GAWithTournamentArgs,
                   model_architecture::modelArchitecture, meta_library::MetaLibrary,
                   shared_inputs::SharedInput, fitness::Vector{Float64}; extras::Dict=Dict()) -> Population

Creates a new population using truncation selection and generating new individuals through crossover
(and mutation) using the GA with tournament selection strategy.

# Arguments
- `inds`: Current population.
- `crossover_args`: Minimal crossover arguments.
- `evolutionary_strategy_args`: GA-specific strategy arguments
- `model_architecture`: Genome architecture information.
- `meta_library`: Library used during mutation.
- `shared_inputs`: Shared inputs for mutation.
- `fitness`: Vector of fitness values.
- `extras`: Optional extra parameters.

# Returns
- A new population (`Vector{UTGenome}`).
"""
function mage_crossover(
    inds::Population,
    full_population::Population,
    crossover_args::CrossOverArgs,
    evolutionary_strategy_args::GAWithTournamentArgs,
    model_architecture::modelArchitecture,
    meta_library::MetaLibrary,
    shared_inputs::SharedInput,
    fitness::Vector{Float64};
    extras::Dict = Dict(),
    n_chromosomes_to_swap::Int = 1,
)
    new_pop, n_elite = _initialize_population(inds, evolutionary_strategy_args)
    for (ith_elite, elite_ind) in enumerate(inds)
        new_pop[ith_elite] = elite_ind
    end
    # sorted_idx = _apply_truncation_selection!(new_pop, inds, fitness, n_elite)
    _apply_crossover_and_mutation!(
        new_pop,
        full_population,
        evolutionary_strategy_args,
        crossover_args,
        model_architecture,
        meta_library,
        shared_inputs,
        fitness;
        n_chromosomes_to_swap = n_chromosomes_to_swap,
    )
    return new_pop
end

"""
    mage_crossover(inds::Population, crossover_args::CrossOverMutRateArgs, evolutionary_strategy_args::OnePlusLambda,
                   model_architecture::modelArchitecture, meta_library::MetaLibrary,
                   shared_inputs::SharedInput, fitness::Vector{Float64}; extras::Dict=Dict()) -> Population

Placeholder for a crossover method using a mutation rate strategy and OnePlus Lambda
"""
function mage_crossover(
    inds::Population,
    full_population::Population,
    crossover_args::AbstractCrossOverArgs,
    evolutionary_strategy_args::OnePlusLambda,
    model_architecture::modelArchitecture,
    meta_library::MetaLibrary,
    shared_inputs::SharedInput,
    fitness::Vector{Float64};
    extras::Dict = Dict(),
)
    error("Method not implemented for CrossOverMutRateArgs with OnePlusLambda strategy")
end

# --- Atomic Helper Functions ---

"""
    _initialize_population(inds::Population, evo_args::GAWithTournamentArgs, fitness::Vector{Float64}) -> (Vector{UTGenome}, Int)

Initializes a new population vector based on the evolutionary strategy arguments.

# Arguments
- `inds`: The current population (after selection).
- `evo_args`: Evolutionary strategy arguments.

# Returns
- A tuple `(new_pop, n_elite)` where `new_pop` is an uninitialized vector of `UTGenome` with size equal to `n_new + n_elite`,
  and `n_elite` is the number of elite individuals to preserve.
  
# Errors
- Throws an error if the expected population size (n_elite) does not match the length of `inds`.
"""
function _initialize_population(inds::Population, evo_args::GAWithTournamentArgs)
    n_new = evo_args.n_new       # Individuals to create via crossover + mutation
    n_elite = evo_args.n_elite   # Individuals to preserve via truncation
    pop_size = n_new + n_elite
    @assert length(inds) == n_elite "Population size mismatch: expected $n_elite, got $(length(inds))"
    new_pop = Vector{UTGenome}(undef, pop_size)
    return new_pop, n_elite
end

"""
    create_chromosome_swap_mask(n_chrom::Int, n_chromosomes_to_swap::Int = 1) -> BitVector

Creates a mask for chromosome swapping during crossover operations.

# Arguments
- `n_chrom::Int`: Total number of chromosomes in the genome
- `n_chromosomes_to_swap::Int`: Maximum number of chromosomes to swap (default: 1)

# Returns
- A BitVector where `true` indicates chromosomes to swap from parent2 to child

# Behavior
- Will swap at least 1 and at most `n_chromosomes_to_swap` chromosomes
- For this paper, `n_chromosomes_to_swap` will typically be 1
- Ensures we don't swap all chromosomes (at least one will remain from parent1)
"""
function create_chromosome_swap_mask(n_chrom::Int, n_chromosomes_to_swap::Int = 1)
    # Validate parameters
    @assert n_chrom > 1 "Need at least 2 chromosomes to perform meaningful swaps"
    @assert n_chromosomes_to_swap >= 1 "Must swap at least 1 chromosome"
    @assert n_chromosomes_to_swap < n_chrom "Can't swap all chromosomes (must keep at least 1)"

    # Determine how many chromosomes to actually swap
    actual_swaps = rand(1:min(n_chromosomes_to_swap, n_chrom - 1))

    # Create a mask with all false values
    mask = falses(n_chrom)

    # Select exactly actual_swaps chromosomes for swapping
    indices = sample(1:n_chrom, actual_swaps, replace = false)
    mask[indices] .= true

    @debug "Creating swap mask: n_chrom=$n_chrom, max_swaps=$n_chromosomes_to_swap, actual_swaps=$actual_swaps"
    @debug "Swap mask: $mask"

    return mask
end

"""
    _apply_truncation_selection!(new_pop::Vector{UTGenome}, inds::Population, fitness::Vector{Float64}, n_elite::Int)

Performs truncation selection by copying the best `n_elite` individuals (with the lowest fitness values)
from the current population `inds` into the beginning of the new population vector `new_pop`.

# Arguments
- `new_pop`: The new population vector to be filled (modified in-place).
- `inds`: The current population (vector of `UTGenome`).
- `fitness`: Vector of fitness values (lower is better).
- `n_elite`: Number of elite individuals to preserve.

# Returns 
- The sorted indices of the whole population.

# Side Effects
- Modifies `new_pop` in-place by copying the elite individuals.
"""
function _apply_truncation_selection!(
    new_pop::Vector{UTGenome},
    inds::Population,
    fitness::Vector{Float64},
    n_elite::Int,
)
    sorted_idx = sortperm(fitness)  # ascending order: lower fitness is better
    @debug "Truncation selection: preserving indices $(sorted_idx[1:n_elite])"
    for i = 1:n_elite
        new_pop[i] = deepcopy(inds[sorted_idx[i]])
        @debug "Preserved individual at index $(sorted_idx[i]) with fitness $(fitness[sorted_idx[i]])"
    end
    sorted_idx
end


"""
    _select_two_parents_for_crossover(inds, tournament_size, fitness)

Selects two distinct parents from `inds` using tournament selection.

# Arguments
- `inds`: Population of individuals.
- `tournament_size::Int`: Tournament size for selection.
- `fitness`: Vector of fitness values.

# Returns
- `(parent1, parent2, ith1, ith2)`: Selected parents and their indices.
"""
function _select_two_parents_for_crossover(inds, tournament_size, fitness)
    p1 = tournament_selection(inds, tournament_size, fitness; return_idx = true)
    parent1 = @? p1[1] # unwrap or raise error
    ith1 = @? p1[2]
    # Ensure p2 is different from p1
    while true
        p2 = tournament_selection(inds, tournament_size, fitness; return_idx = true)
        parent2 = @? p2[1] # unwrap or raise error
        ith2 = @? p2[2]
        if ith1 != ith2
            return parent1, parent2, ith1, ith2
        end
    end

end

"""
    _apply_crossover_and_mutation!(new_pop::Vector{UTGenome},
                                     inds::Population,
                                     offset::Int64,
                                     tournament_size::Int64,
                                     n_new::Int64,
                                     crossover_args::CrossOverArgs,
                                     model_architecture::modelArchitecture,
                                     meta_library::MetaLibrary,
                                     shared_inputs::SharedInput,
                                     fitness::Vector{Float64};
                                     crossover_operator::Function = mage_crossover_with_numbered_mutation)

Generates new individuals by applying crossover (and mutation) to selected parent pairs and inserts them into 
the new population vector `new_pop`, starting at the given `offset`.

This function performs the following steps:
  1. For each new individual to be created (total `n_new`):
      - Selects two parents from the current population `inds` using tournament selection with the specified 
        `tournament_size` and based on the provided `fitness` (lower fitness is better). Not possible to select the same ind twice. 
      - Applies the given `crossover_operator` (default is `mage_crossover_with_numbered_mutation`) to the selected
        parents to produce a new individual.
      - Inserts the new individual into `new_pop` at the corresponding position (starting at `offset+1`).
  2. Debug messages are logged at key steps to trace the selection and generation process.

# Arguments
- `new_pop::Vector{UTGenome}`: The preallocated population vector where new individuals will be stored.
- `inds::Population`: The current population from which parents are selected.
- `offset::Int64`: The starting index in `new_pop` where new individuals should be placed (typically equal to the number of elite individuals preserved).
- `tournament_size::Int64`: The size of the tournament used for parent selection.
- `n_new::Int64`: The number of new individuals to generate via crossover.
- `crossover_args::CrossOverArgs`: Crossover configuration parameters.
- `model_architecture::modelArchitecture`: Information about the genome architecture.
- `meta_library::MetaLibrary`: Library of functions used during mutation.
- `shared_inputs::SharedInput`: Shared inputs required for mutation operations.
- `fitness::Vector{Float64}`: A vector of fitness values for the current population (lower is better).
- `crossover_operator::Function` (keyword): The function used to perform crossover and mutation on two parents. 
  Defaults to `mage_crossover_with_numbered_mutation`.

# Side Effects
- Modifies `new_pop` in-place by inserting new individuals at indices `offset+1` to `offset+n_new`.
"""
function _apply_crossover_and_mutation!(
    new_pop::Vector{UTGenome},
    full_population::Population,
    offset::Int64,
    tournament_size::Int64,
    n_new::Int64,
    crossover_args::CrossOverArgs,
    model_architecture::modelArchitecture,
    meta_library::MetaLibrary,
    shared_inputs::SharedInput,
    fitness::Vector{Float64};
    crossover_operator::Function = mage_crossover_with_numbered_mutation,
    n_chromosomes_to_swap::Int = 1,
)
    @assert length(full_population) > 1 && tournament_size > 1 "With only one parent there is no point for crossover."
    for ith_ind_to_create = 1:n_new
        parent1, parent2, ith1, ith2 =
            _select_two_parents_for_crossover(full_population, tournament_size, fitness)
        @debug "Selected parents for crossover: indices $(ith1) and $(ith2)"
        new_ind = crossover_operator(
            parent1,
            parent2,
            crossover_args,
            model_architecture,
            meta_library,
            shared_inputs;
            p1_fitness = fitness[ith1],
            p2_fitness = fitness[ith2],
            n_chromosomes_to_swap = n_chromosomes_to_swap,
        )
        new_pop[offset+ith_ind_to_create] = new_ind
        @debug "New individual generated at population position $(offset + ith_ind_to_create)"
    end
end

"""
    _apply_crossover_and_mutation!(new_pop::Vector{UTGenome},
                                     inds::Population,
                                     ga_strategy::GAWithTournamentArgs,
                                     crossover_args::CrossOverArgs,
                                     model_architecture::modelArchitecture,
                                     meta_library::MetaLibrary,
                                     shared_inputs::SharedInput,
                                     fitness::Vector{Float64};
                                     crossover_operator::Function = mage_crossover_with_numbered_mutation)

Convenience wrapper that extracts parameters from a GA strategy configuration and calls the more general 
`_apply_crossover_and_mutation!` function.

This function uses the fields from `ga_strategy` as follows:
  - `ga_strategy.n_elite` is used as the `offset` in `new_pop`.
  - `ga_strategy.tournament_size` is used for tournament selection.
  - `ga_strategy.n_new` is the number of new individuals to generate.

# Side Effects
- Calls the general `_apply_crossover_and_mutation!` function with parameters extracted from `ga_strategy`.
"""
function _apply_crossover_and_mutation!(
    new_pop::Vector{UTGenome},
    full_population::Population,
    ga_strategy::GAWithTournamentArgs,
    crossover_args::CrossOverArgs,
    model_architecture::modelArchitecture,
    meta_library::MetaLibrary,
    shared_inputs::SharedInput,
    fitness::Vector{Float64};
    crossover_operator::Function = mage_crossover_with_numbered_mutation,
    n_chromosomes_to_swap::Int = 1,
)
    _apply_crossover_and_mutation!(
        new_pop,
        full_population,
        ga_strategy.n_elite,
        ga_strategy.tournament_size,
        ga_strategy.n_new,
        crossover_args,
        model_architecture,
        meta_library,
        shared_inputs,
        fitness;
        crossover_operator = crossover_operator,
        n_chromosomes_to_swap = n_chromosomes_to_swap,
    )
end


"""
    _check_genome_compatibility(p1::UTGenome, p2::UTGenome) -> Int

Ensures that both parent genomes have the same number of chromosomes and that the genome
is not a single-chromosome (CGP) genome. Returns the number of chromosomes.

# Errors
- Throws an error if genomes have different lengths or if there is only one chromosome.
"""
function _check_genome_compatibility(p1::UTGenome, p2::UTGenome)
    n_chrom = length(p1.genomes)
    @assert n_chrom == length(p2.genomes) "Genomes are not of the same length ($n_chrom vs $(length(p2.genomes)))"
    if n_chrom == 1
        error("Crossover cannot be applied to genomes with only one chromosome.")
    end
    return n_chrom
end

"""
    _draw_until_one_operator(crossover_prob::Float64, mutation_prob::Float64) -> (Float64, Float64)

Draws random numbers repeatedly until either the crossover or mutation condition is met.
Returns a tuple `(r_c, r_m)` representing the drawn random values.

# Side Effects
- Logs the drawn random values.
"""
function _draw_until_one_operator(crossover_prob::Float64, mutation_prob::Float64)
    local r_c, r_m
    while true
        r_c = rand()
        r_m = rand()
        if (r_c <= crossover_prob) || (r_m <= mutation_prob)
            break
        end
    end
    @debug "Drawn random numbers: crossover random=$(r_c), mutation random=$(r_m)"
    return r_c, r_m
end

"""
    mage_crossover_with_numbered_mutation(p1::UTGenome, p2::UTGenome, crossover_args::CrossOverArgs,
                                          model_architecture::modelArchitecture, meta_library::MetaLibrary,
                                          shared_inputs::SharedInput; p1_fitness, p2_fitness) -> UTGenome

Performs individual-level crossover between two parent genomes, with a numbered mutation applied
if triggered. Uses a binary mask to swap whole chromosomes.

# Behavior
- If the drawn random number for crossover is below `crossover_args.crossover_prob`, a crossover is performed.
- Otherwise, the fitter parent (or a random parent) is chosen.
- Mutation is applied if the random draw is within `crossover_args.mutation_prob`.

# Caveats
- Ensures that at least one genetic operator (crossover and/or mutation) is applied.
- Prevents a complete swap of all chromosomes to avoid simply exchanging individuals.

# Arguments
- `p1`: First parent genome.
- `p2`: Second parent genome.
- `crossover_args`: Minimal crossover configuration.
- `model_architecture`: Genome architecture information.
- `meta_library`: Library for mutation operations.
- `shared_inputs`: Shared inputs for mutation.
- `p1_fitness`: Fitness of parent1 (optional).
- `p2_fitness`: Fitness of parent2 (optional).

# Returns
- A new `UTGenome` produced by crossover and mutation.
"""
function mage_crossover_with_numbered_mutation(
    p1::UTGenome,
    p2::UTGenome,
    crossover_args::CrossOverArgs,
    model_architecture::modelArchitecture,
    meta_library::MetaLibrary,
    shared_inputs::SharedInput;
    p1_fitness::Union{Float64,Nothing} = nothing,
    p2_fitness::Union{Float64,Nothing} = nothing,
    n_chromosomes_to_swap::Int = 1,
)
    local child
    @assert sum(isnothing.((p1_fitness, p2_fitness))) in (0, 2) "For crossover either both fitnesses must be nothing or both provided"
    crossover_prob = crossover_args.crossover_prob
    mutation_prob = crossover_args.mutation_prob
    @debug "Starting crossover: crossover_prob=$(crossover_prob), mutation_prob=$(mutation_prob)"
    r_c, r_m = _draw_until_one_operator(crossover_prob, mutation_prob)

    # --- Crossover Operation ---
    if r_c <= crossover_prob
        n_chrom = _check_genome_compatibility(p1, p2)
        @debug "Crossover will be performed."
        child = deepcopy(p1)
        @debug "Child copied from parent1; number of chromosomes: $(n_chrom)"
        mask = create_chromosome_swap_mask(n_chrom, n_chromosomes_to_swap)
        for i = 1:n_chrom
            if mask[i]
                @debug "Swapping chromosome $(i) from parent2 into child"
                child.genomes[i] = deepcopy(p2.genomes[i])
            end
        end
    else
        @debug "Crossover skipped; selecting one parent based on fitness or at random."
        if p1_fitness !== nothing && p2_fitness !== nothing
            # For minimization, lower fitness is better.
            if p1_fitness <= p2_fitness
                @debug "Selected parent1 as fitter (fitness: $(p1_fitness) vs $(p2_fitness))"
                child = deepcopy(p1)
            else
                @debug "Selected parent2 as fitter (fitness: $(p2_fitness) vs $(p1_fitness))"
                child = deepcopy(p2)
            end
        else
            child = rand(Bool) ? deepcopy(p1) : deepcopy(p2)
            @debug "Randomly selected parent for copy"
        end
    end

    # --- Mutation Operation ---
    if r_m <= mutation_prob
        @debug "Mutation will be applied to the child."
        numbered_mutation!(
            child,
            numbered_mutation_trait(crossover_args),
            model_architecture,
            meta_library,
            shared_inputs,
        )
    else
        @debug "Mutation skipped for the child."
    end

    return child
end

export mage_crossover
