#####################
# SN HASHERS        #
#####################

struct sn_genotype_hasher <: Abstract_Node_Hash_Function end
"""
    sn_genotype_hasher(params::UTCGP.ParametersStandardEpoch)

Applies `general_hasher_sha` to the whole population.
"""
function (::sn_genotype_hasher)(params::UTCGP.ParametersStandardEpoch)
    # Hashes the genomes with genotype_hasher for all pop
    hashes = general_hasher_sha.(params.population)
    return hashes
end

struct sn_genotype_hasher_except_last <: Abstract_Node_Hash_Function end
"""
    sn_genotype_hasher_except_last(params::UTCGP.ParametersStandardEpoch)

Applies `general_hasher_sha` to the whole population except the last element (Because it's the parent).
"""
function sn_genotype_hasher_except_last(params::UTCGP.ParametersStandardEpoch)
    # Hashes the genomes with genotype_hasher for all pop (except last)
    hashes = general_hasher_sha.(params.population[1:end-1])
    return hashes
end


# PHENOTYPE HASHER --- --- 
struct sn_softphenotype_hasher <: Abstract_Node_Hash_Function end

"""
    sn_softphenotype_hasher(params::UTCGP.ParametersStandardEpoch)

Applies `general_hasher_sha` to all programs.
"""
function (::sn_softphenotype_hasher)(params::UTCGP.ParametersStandardEpoch)
    # Hashes the genomes with genotype_hasher for all pop
    hashes = general_hasher_sha.(params.programs)
    return hashes
end

struct sn_softphenotype_hasher_except_last <: Abstract_Node_Hash_Function end
"""
    sn_softphenotype_hasher_except_last (params::UTCGP.ParametersStandardEpoch)

Applies `general_hasher_sha` to all programs except last
"""
function (::sn_softphenotype_hasher_except_last)(params::UTCGP.ParametersStandardEpoch)
    # Hashes the genomes with genotype_hasher for all pop
    hashes = general_hasher_sha.(params.programs[1:end-1])
    return hashes
end

# STRICT PHENOTYPE
struct sn_strictphenotype_hasher <: Abstract_Node_Hash_Function end

function (::sn_strictphenotype_hasher)(params::UTCGP.ParametersStandardEpoch)
    function individual_phen_hasher(p::IndividualPrograms)
        vec = []
        for prog in p
            for op in prog
                n_inputs = length(op.inputs) * 2 # inps + types
                push!(vec, node_to_vector(op.calling_node)[1:1+n_inputs]...) # the active part of the node
            end
        end
        return general_hasher_sha(vec)
    end
    return [individual_phen_hasher(p) for p in params.programs]
end

# BEHAVIOR HASHER --- --- 

struct sn_behavior_hasher <: Abstract_Node_Hash_Function
    example_set::Vector{<:Any}
end

function (obj::sn_behavior_hasher)(params::UTCGP.ParametersStandardEpoch)
    BEHAVIORS_PER_INDIVIDUAL = []
    for _ = 1:length(params.population)
        push!(BEHAVIORS_PER_INDIVIDUAL, [])
    end
    s_inputs = params.shared_inputs
    [reset_genome!(g) for g in params.population] # TODO TO A FN

    # rows = samples, cols = individuals
    results_per_sample = []
    for sample in obj.example_set
        # Mod the share inputs 
        input_nodes = [
            InputNode(value, pos, pos, params.model_architecture.inputs_types_idx[pos])
            for (pos, value) in enumerate(sample)
        ]
        # append input nodes to pop
        replace_shared_inputs!(s_inputs, input_nodes) # update 
        outputs = evaluate_population_programs(
            params.programs,
            params.model_architecture,
            params.meta_library,
        )

        push!(results_per_sample, outputs)
        [reset_genome!(g) for g in params.population] # TODO TO A FN
    end
    [reset_genome!(g) for g in params.population] # TODO TO A FN


    # PIVOT to have rows= ind cols = individuals 
    for ind_index = 1:length(params.population)
        for row in results_per_sample
            push!(BEHAVIORS_PER_INDIVIDUAL[ind_index], row[ind_index])
        end
    end
    # HASH BEHAVIORS
    HASHES_PER_INDIVIDUAL =
        [general_hasher_sha(ind_outputs) for ind_outputs in BEHAVIORS_PER_INDIVIDUAL]

    # println(BEHAVIORS_PER_INDIVIDUAL)
    # println(HASHES_PER_INDIVIDUAL)

    return HASHES_PER_INDIVIDUAL
end

struct sn_db_name_node <: Abstract_Node_Hash_Function
    db_name::String
end
"""
    sn_db_name_node(params::UTCGP.ParametersStandardEpoch)

Returns the db_name n times. 
n is the length of the population. 
"""
function (obj::sn_db_name_node)(params::UTCGP.ParametersStandardEpoch)
    return [obj.db_name for _ in params.population]
end

# EXPORT # 
export sn_genotype_hasher
export sn_genotype_hasher_except_last
export sn_softphenotype_hasher
export sn_softphenotype_hasher_except_last
export sn_strictphenotype_hasher
export sn_behavior_hasher
export sn_db_name_node
# export sn phenotype
# export sn strict phenotype
# export sn behavior 
