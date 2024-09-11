
# the MapelitesRepertoire should be created with the centroids ready but not with the pop / fitness_values
abstract type Abstract_MapElitesRepertoire <: AbstractPopulation end

"""
"""
struct MapelitesRepertoire <: Abstract_MapElitesRepertoire
    pop::Vector{Union{UTGenome,Missing}}
    fitness_values::Vector{Union{Float64,Missing}}
    descriptors::Vector{Union{Vector{Float64},Missing}}
    centroids::Vector{Vector{Float64}}

    function MapelitesRepertoire(
        centroids::Vector{Vector{Float64}}
    )
        size = length(centroids)
        pop = Vector{Union{UTGenome,Missing}}(missing, size)
        fitness_values = Vector{Union{Float64,Missing}}(missing, size)
        descriptors = Vector{Union{Vector{Float64},Missing}}(missing, size)
        return new(
            pop,
            fitness_values,
            descriptors,
            centroids
        )
    end
end

function sample(rep::MapelitesRepertoire, n_samples::Int)
    non_missing_genomes = collect(skipmissing(rep.pop))
    return Population(rand(non_missing_genomes, n_samples))
end

function insert!(rep::MapelitesRepertoire, genome::UTGenome, fitness::Float64, descriptors::Vector{Float64})
    idx = argmin([norm(descriptors .- centroid) for centroid in rep.centroids])
    # check the strategy for replacement: new equal? new smaller? only if better fitness?
    if ismissing(rep.fitness_values[idx]) || fitness <= rep.fitness_values[idx]
        rep.pop[idx] = genome
        rep.fitness_values[idx] = fitness
        rep.descriptors[idx] = descriptors
    end
end

function batch_insert!(rep::MapelitesRepertoire, genomes::Vector{UTGenome}, fitness_values::Vector{Float64}, descriptors::Vector{Vector{Float64}})
    for ind_idx in 1:length(genomes)
        insert!(rep, genomes[ind_idx], fitness_values[ind_idx], descriptors[ind_idx])
    end
end

function coverage(rep::MapelitesRepertoire)
    return 1 - count(ismissing, rep.fitness_values) / length(rep.pop)
end

function best_fitness(rep::MapelitesRepertoire)
    return minimum(collect(skipmissing(rep.fitness_values)))
end

function best_individual(rep::MapelitesRepertoire)
    min_idx = argmin(collect(skipmissing(rep.fitness_values)))
    non_empty_pop = collect(skipmissing(rep.pop))
    return non_empty_pop[min_idx]
end

Base.size(rep::MapelitesRepertoire) = length(rep.pop)
