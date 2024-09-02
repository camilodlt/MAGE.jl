
abstract type AbstractPopulation end

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
