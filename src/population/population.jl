
abstract type AbstractPopulation end

"""
    Population(pop::Vector{UTGenome})

A generation of individuals.

Thin wrapper over a vector of [`UTGenome`](@ref)s supporting `length`, `size`,
integer and vector indexing, `setindex!` and iteration, so it can be used
wherever a vector of genomes is expected.

By convention the population callbacks put the elites first: see
[`ga_population_callback`](@ref) and [`default_population_callback`](@ref).
"""
struct Population <: AbstractPopulation
    pop::Vector{UTGenome}
end

Base.size(pop::Population) = length(pop.pop)
Base.length(pop::Population) = length(pop.pop)
Base.getindex(pop::Population, i::Int)::UTGenome = pop.pop[i]
Base.getindex(pop::Population, idx::Vector{Int})::Vector{UTGenome} = pop.pop[idx]
Base.setindex!(pop::Population, value::UTGenome, i::Int) = (pop.pop[i] = value)
Base.iterate(s::Population, state = 1) =
    state > length(s.pop) ? nothing : (s.pop[state], state + 1)
