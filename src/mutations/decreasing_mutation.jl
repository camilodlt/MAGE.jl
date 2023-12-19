# -*- coding:: utf-8 -*-

# function mutate!(node::OutputNode, run_config::runConf)
#     probs_for_each_allele = length(node)
#     where_to_mutate = probs_for_each_allele .> (1.0 - run_config.output_mutation_rate)
#     material_to_mutate = node.node_material[where_to_mutate]
#     for node_element in material_to_mutate
#         node_element.value = random_element_value(node_element)
#     end
#     return length(material_to_mutate) > 0
# end

# function mutate!(node::AbstractNode, run_config::runConf)::Bool
#     probs_for_each_allele = length(node)
#     where_to_mutate = probs_for_each_allele .> (1.0 - run_config.mutation_rate)
#     material_to_mutate = node.node_material[where_to_mutate]
#     for node_element in material_to_mutate
#         set_node_value!(node, random_element_value(node_element))
#     end
#     # if true, at least something was randomly modified.
#     return where_to_mutate |> any
#     # And such, we should test if the modification ↓
#     # produced a different and functionning node.
#     # correct_node(node, inputs_type)
# end

# function forced_mutate!(
#     node::CGPNode,
#     run_config::runConf,
#     model_architecture::modelArchitecture,
#     library::Library,
#     ut_genome::UTGenome,
#     shared_inputs::SharedInput,
# )::nothing
#     current_genome_values = node_to_vector(node)
#     at_least_one_mutation = mutate!(node, run_config)  # do a mutation first
#     # correct_node!(node, inputs_type)
#     next_genome_values = node_to_vector(node)
#     max_calls = 100
#     call_nb = 0
#     force_fn = false # TODO

#     while !check_functionning_node(
#         node,
#         library,
#         ut_genome,
#         shared_inputs,
#         model_architecture,
#     ) && ((current_genome_values == next_genome_values) && at_least_one_mutation)
#         at_least_one_mutation = mutate!(node, run_config)
#         # correct_node(node, inputs_type)
#         #
#         # correct_node(node, inputs_type)
#         if call_nb > max_calls
#             if force_fn
#                 node.node_material[1].value = 1  # Convention for default fn
#                 @warn "Node didn't find a functionning call after $max_calls iterations. Current call : $call_nb"
#             end
#         end
#         # correct_node_types(node, library, chromosomes_types)
#         at_least_one_mutation = true
#         # allele_mutation_rate = 0.9
#         force_fn = true
#     end
#     # correct_node(node, inputs_type)
#     next_genome_values = node_to_vector(node)
#     call_nb += 1
# end

# function forced_mutate!(
#     genome::SingleGenome,
#     run_config::runConf,
#     model_architecture::modelArchitecture,
#     library::Library,
#     ut_genome::UTGenome,
#     shared_inputs::SharedInput,
# )
#     for (node_index, node) in enumerate(genome.chromosome)
#         forced_mutate!(
#             node,
#             run_config,
#             model_architecture,
#             library,
#             ut_genome,
#             shared_inputs,
#         )
#     end

# end

# """
# every allele of every node has the same prob of mutation.

# Inside each allele, higher numbers have higher probs to be sampled.

# ::param genome:: _description_
# ::type genome:: UT_Genome
# ::param allele_mutation_rate:: _description_
# ::type allele_mutation_rate:: Float64
# ::param meta_library:: _description_
# ::type meta_library:: MetaLibrary
# ::param chromosomes_types:: _description_
# ::type chromosomes_types:: Vector[Type]
# ::param input_types:: For 2 inputs of type array ::
# [index_of_array, index_of_array]
# ::type input_types:: Vector[Int]
# """
# function forced_mutate!(
#     genome::UTGenome,
#     run_config::runConf,
#     model_architecture::modelArchitecture,
#     meta_library::MetaLibrary,
#     shared_inputs::SharedInput,
# )
#     @assert run_config.mutation_rate > 0 "No mutation ? "
#     @assert length(model_architecture.inputs_types) > 0 "At least one input ? "
#     @assert length(model_architecture.chromosomes_types) == length(genome.genomes) "Need to give all chromosome types (Int, Float64, ...) in order so we check that nodes function with available signatures"  # noqa :: 3501

#     for (ith_chromosome, chromosome) in enumerate(genome.genomes)
#         forced_mutate!(
#             chromosome,
#             run_config,
#             model_architecture,
#             meta_library[ith_chromosome],
#             genome,
#             shared_inputs,
#         )
#     end
# end
