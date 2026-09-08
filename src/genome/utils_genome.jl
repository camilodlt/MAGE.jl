
######################
# UTILS SINGLE GENOME 
######################

"""
    reset_genome!(genome::AbstractGenome)
    reset_genome!(meta_genome::AbstractMetaGenome)

Clear the cached node values of a chromosome, or of a whole
[`UTGenome`](@ref) and its output nodes.

The genome's *material* (the evolved integers) is untouched; only the values
computed by the last decoding are dropped.
"""
function reset_genome!(genome::AbstractGenome)
    for node in genome.chromosome
        reset_node_value!(node)
    end
end

"""
    initialize_genome!(genome::AbstractGenome)
    initialize_genome!(meta_genome::AbstractMetaGenome)

Give every element of a chromosome — or of a whole [`UTGenome`](@ref),
output nodes included — its first random value.

This is the step right after [`make_evolvable_utgenome`](@ref). Note that
initialising does not by itself make every node type-correct: follow it with
[`correct_all_nodes!`](@ref).
"""
function initialize_genome!(genome::AbstractGenome)
    for node in genome.chromosome
        initialize_node!(node)
    end
end

######################
# UTILS UT GENOME
######################

function reset_genome!(meta_genome::AbstractMetaGenome)
    for genome in meta_genome.genomes
        reset_genome!(genome)
    end
    for output_node in meta_genome.output_nodes
        reset_node_value!(output_node)
    end
end

function initialize_genome!(meta_genome::AbstractMetaGenome)
    for genome in meta_genome.genomes
        initialize_genome!(genome)
    end
    for output_node in meta_genome.output_nodes
        initialize_node!(output_node)
    end
end

# @overload
# def genome_to_matrix(genome: SingleGenome):
#     row = []
#     for node in genome.genome:
#         row.extend(node_to_vector(node))
#     return np.expand_dims(np.array(row, dtype="object"), 0)  # (1, n_nodes)


# @overload
# def genome_to_matrix(genome: UT_Genome):
#     rows = []
#     for chromosome in genome.genomes:
#         rows.append(genome_to_matrix(chromosome)[0])
#     return np.array(rows, dtype="object")  # (n_chomosomes, n_nodes)
