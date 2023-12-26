# -*- coding:: utf-8 -*-

function free_mutate!(
    node::CGPNode,
    model_architecture::modelArchitecture,
    library::Library,
    ut_genome::UTGenome,
    shared_inputs::SharedInput,
)
    max_calls = 1000
    call_nb = 0
    prev = node_to_vector(node)
    while node_to_vector(node) == prev
        mutate_one_element_from_node!(node)
        if call_nb > max_calls
            @warn "Can't find a correct mutation after $call_nb"
            # if force_fn
            #     node.node_material[1].value = 1  # Convention for default fn
            #     @warn "Node didn't find a functionning call after $max_calls iterations. Current call : $call_nb"
            # end
        end
        call_nb += 1
    end
end

function free_mutate!(
    genome::SingleGenome,
    run_config::runConf,
    model_architecture::modelArchitecture,
    library::Library,
    ut_genome::UTGenome,
    shared_inputs::SharedInput,
)
    # Sample a % of nodes to mutate
    nodes_decisions =
        where_to_mutate(length(genome.chromosome), run_config.mutation_rate, nothing)
    nodes_idx = _bool_vector_to_idx_vector(nodes_decisions)
    nodes = genome[nodes_idx]

    # mutate them
    for node in nodes
        free_mutate!(node, model_architecture, library, ut_genome, shared_inputs)
    end

end

"""
every allele of every node has the same prob of mutation.

Inside each allele, higher numbers have higher probs to be sampled.

::param genome:: _description_
::type genome:: UT_Genome
::param allele_mutation_rate:: _description_
::type allele_mutation_rate:: Float64
::param meta_library:: _description_
::type meta_library:: MetaLibrary
::param chromosomes_types:: _description_
::type chromosomes_types:: Vector[Type]
::param input_types:: For 2 inputs of type array ::
[index_of_array, index_of_array]
::type input_types:: Vector[Int]
"""
function free_mutate!(
    genome::UTGenome,
    run_config::runConf,
    model_architecture::modelArchitecture,
    meta_library::MetaLibrary,
    shared_inputs::SharedInput,
)
    @assert run_config.mutation_rate > 0 "No mutation ? "
    @assert length(model_architecture.inputs_types) > 0 "At least one input ? "
    @assert length(model_architecture.chromosomes_types) == length(genome.genomes) "Need to give all chromosome types (Int, Float64, ...) in order so we check that nodes function with available signatures"  # noqa :: 3501

    for (ith_chromosome, chromosome) in enumerate(genome.genomes)
        free_mutate!(
            chromosome,
            run_config,
            model_architecture,
            meta_library[ith_chromosome],
            genome,
            shared_inputs,
        )
    end
end
