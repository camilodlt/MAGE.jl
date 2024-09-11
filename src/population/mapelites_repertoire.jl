# the MapelitesRepertoire should be created with the centroids ready but not with the pop / fitness_values
# a common trick is to initialize as "empty" the positions where stuff is not available
# fitness_values of those are initialized as infinity

struct MapelitesRepertoire <: AbstractPopulation
    pop::Vector{Union{UTGenome,Missing}}
    fitness_values::Vector{Union{Number,Missing}}
    descriptors::Vector{Union{Vector{Number},Missing}}
    centroids::Vector{Vector{Number}}
end

function insert!(rep::MapelitesRepertoire, genome::UTGenome, fitness::Number, descriptors::Vector{Number})
    idx = argmin([norm(descriptors .- centroid) for centroid in rep.centroids])
    if ismissing(fitness_values[idx]) || fitness <= fitness_values[idx]
        rep.pop[idx] = genome
        rep.fitness_values[idx] = fitness
        rep.descriptors[idx] = descriptors
    end
end

function batch_insert!(rep::MapelitesRepertoire, genomes::Vector{UTGenome}, fitness_values::Vector{Number}, descriptors::Vector{Vector{Number}})
    for ind_idx in 1:length(genomes)
        insert!(rep, genomes[ind_idx], fitness_values[ind_idx], descriptors[ind_idx])
    end
end

Base.size(pop::Population) = length(pop.pop)