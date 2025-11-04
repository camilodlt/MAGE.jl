module MAGE_PYCMA_EXT

import UTCGP
using ImageCore: N0f8, Normed, float64
using UTCGP:
    SizedImage, SImageND, _get_image_tuple_size, _get_image_type, _validate_factory_type, ConstantNode, SingleGenome, CGPNode, UTGenome
using MAGE_PYCMA

# API
function UTCGP.make_cma_nodes!(ind::UTCGP.UTGenome, how_many::Int, at_index::Int)
    @debug "Putting $how_many Constant Nodes init at rand. Index of genome $at_index"
    old_genome = ind[at_index]
    old_chromosome = old_genome.chromosome
    origT = typeof(old_chromosome)
    n_nodes = length(old_chromosome)
    @assert how_many <= n_nodes "Chromosome has $n_nodes. Can't place $how_many constant nodes"
    @assert how_many >= 1 "At least one ConstantNode has to be asked, currently $how_many"
    @assert origT == Vector{CGPNode} "Chromosome had more than only CGPNodes ? $origT"

    # Make new chromosome placing constant nodes at the beginning
    T = how_many == n_nodes ? ConstantNode : Union{ConstantNode, CGPNode}
    new_chromosome = T[]
    for i in 1:how_many
        old_node = old_chromosome[i]
        new_node = ConstantNode(rand(), old_node.x_position, old_node.x_real_position, old_node.y_position)
        push!(new_chromosome, new_node)
    end

    # Fill the remaining of the vector with the old nodes
    if how_many != n_nodes
        push!(new_chromosome, old_chromosome[(how_many + 1):end]...)
    end
    @assert length(new_chromosome) == length(old_chromosome)

    # Replace the single genome => the float one.
    ind.genomes[at_index] = SingleGenome(
        old_genome.starting_point, new_chromosome
    )
    return ind
end

"""
Returns the list of ConstantNodes (no functions)
"""
function UTCGP.get_cma_nodes(ind::UTGenome, at_index::Int)
    v = ind[at_index].chromosome
    return filter(x -> x isa ConstantNode, v)
end

"""
Constant Nodes in each ind in the pop will be mutated by asking to cma for new values
"""
function UTCGP.mutate_cma!(pop::AbstractArray{T, 1}, cma::CMAEvolutionStrategyWrapper, at_index::Int) where {T <: UTGenome}
    n_pop = length(pop)
    new_vals = ask(cma)
    n_new_vals = length(new_vals)
    @assert n_pop == n_new_vals "Pop size $n_pop is not equal to cma ask return $n_new_vals (cma's pop size)"

    for (ind, sampled_vals) in zip(pop, new_vals)
        nodes = UTCGP.get_cma_nodes(ind, at_index)
        n_nodes = length(nodes)
        n_dim_cma = length(sampled_vals)
        @assert n_nodes >= n_dim_cma "More CMA dimensions than constant nodes in ind $n_dim_cma vs $n_nodes"
        for (node, val) in zip(nodes, sampled_vals)
            node.value[] = val
        end
    end

    return new_vals

end
#
export make_cma_nodes!
end
