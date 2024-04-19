###################################
# Determine which nodes are edges #
###################################

struct all_edges <: Abstract_Edge_Prop_Getter end

"""
    all_edges(params::UTCGP.ParametersStandardEpoch)

It returns the index of all individuals in all the population
"""
function (::all_edges)(params::UTCGP.ParametersStandardEpoch)
    return [i for (i, _) in enumerate(params.population)]
end

struct all_edges_except_last <: Abstract_Edge_Prop_Getter end

"""
    all_edges_except_last(params::UTCGP.ParametersStandardEpoch)

It returns the index of all individuals in all the population
"""
function (::all_edges_except_last)(params::UTCGP.ParametersStandardEpoch)
    return [i for (i, _) in enumerate(params.population.pop[1:end-1])]
end

#####################
# EDGE PROP GETTERS #
#####################
struct sn_fitness_hasher <: Abstract_Edge_Prop_Getter end

"""
    sn_fitness_hasher(params::UTCGP.ParametersStandardEpoch)

It just returns the `ind_performances` attribute in the `params` (which are the fitnesses per individual).
"""
function (::sn_fitness_hasher)(params::UTCGP.ParametersStandardEpoch)
    @assert params.ind_performances[1] isa Number "Multi Objective is not implemented"
    return params.ind_performances
end

struct sn_fitness_hasher_except_last <: Abstract_Edge_Prop_Getter end
"""
    sn_fitness_hasher_except_last(params::UTCGP.ParametersStandardEpoch)

It just returns the `ind_performances` attribute in the `params` (which are the fitnesses per individual).
The last element in the population is ignored because it's the parent. 
"""
function (::sn_fitness_hasher_except_last)(params::UTCGP.ParametersStandardEpoch)
    @assert params.ind_performances[1] isa Number "Multi Objective is not implemented"
    return params.ind_performances[1:end-1]
end


struct sn_elite_hasher <: Abstract_Edge_Prop_Getter end
"""
    sn_elite_hasher(params::UTCGP.ParametersStandardEpoch)

1. if its the elite, 0. otherwise
"""
function (::sn_elite_hasher)(params::UTCGP.ParametersStandardEpoch)
    is_elite = Int.(1:length(params.population) .== params.elite_idx)
    return convert.(Float64, is_elite)
end

struct sn_elite_hasher_except_last <: Abstract_Edge_Prop_Getter end
"""
    sn_elite_hasher_except_last (params::UTCGP.ParametersStandardEpoch)

1. if its the elite, 0. otherwise. 
The last element in the population is ignored because it's the parent. 
"""
function (::sn_elite_hasher_except_last)(params::UTCGP.ParametersStandardEpoch)
    is_elite = Int.(1:length(params.population.pop[1:end-1]) .== params.elite_idx)
    return convert.(Float64, is_elite)
end

# DB NAME 
struct sn_db_name_edge <: Abstract_Edge_Prop_Getter
    db_name::String
end
"""
    sn_db_name_edge(params::UTCGP.ParametersStandardEpoch)

Returns the db_name n times. 
n is the length of the population. 

"""
function (obj::sn_db_name_edge)(params::UTCGP.ParametersStandardEpoch)
    return [obj.db_name for i in params.population]
end


# EXPORT #
export all_edges
export all_edges_except_last
export sn_db_name_edge

# EXPORT #
export sn_fitness_hasher
export sn_fitness_hasher_except_last
export sn_elite_hasher
export sn_elite_hasher_except_last
