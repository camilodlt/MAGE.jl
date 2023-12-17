using Random: AbstractRNG, default_rng

##########################
# 
##########################

"""
    where_to_mutate(length_::Int, threshold::Float64, rng::AbstractRNG)

This functions samples from [0:1] `length_` times.
Each sampled number is compared against a `threshold`.

**Example**

For a `threshold` of 0.4 and a `length_` of 10, it will, on average, return a vector 
with 6 0s and 4 1s.  

**Caveats**

- `length_` >= 1
 
**Returns** a Bool Vector telling whether or not the sampled number was less or equal 
than the threshold. 
"""
function where_to_mutate(
    length_::Int,
    threshold::Float64,
    rng::Union{AbstractRNG,Nothing},
)::Vector{Bool}
    @assert length_ >= 1
    if isnothing(rng)
        rng = default_rng()
    end
    candidates = rand(rng, Float64, length_)
    selected_candidates = candidates .<= threshold
    return selected_candidates
end

"""
    _bool_vector_to_idx_vector(bv::Vector{Bool})::Vector{Int}

Index where 1, not present otherwise.

Useful to then index a vector by positions.
"""
function _bool_vector_to_idx_vector(bv::Vector{Bool})::Vector{Int}
    selected_idx = [i for (i, v) in enumerate(bv) if v]
    return selected_idx
end


"""
Returns the argmax from `nb_of_elements` sampled numbers.
Useful for selecting **one** element out of a list of possible elements. 
"""
function _sample_one_node_element_idx(nb_of_elements::Int)
    rng = default_rng()
    return argmax(rand(rng, Float64, nb_of_elements))
end


"""
Replace all element values with a new `random_element_value`.

It uses `set_node_element_value!` so the frozen state of the elements is respected.
"""
function _mutate_all_alleles!(material_to_mutate::Vector{CGPElement})
    for node_element in material_to_mutate
        set_node_element_value!(node_element, random_element_value(node_element))
    end
end

# """ TODO 
# Replace all element values with a new `random_element_value`
# If the element is a connexion, apply `random`
# """
# function _mutate_all_alleles!(
#     material_to_mutate::Vector{CGPElement},
#     node_config::nodeConfig,
# )
#     for node_element in material_to_mutate
#         if node_element.element_type == CONNEXION

#             node_element.value = random_element_value_from_probs(node_element)
#         else

#             node_element.value = random_element_value(node_element)
#         end

#     end
# end


#########################
# Mutate node per allele #
##########################

"""
    mutate_per_allele!(node::OutputNode, run_config::runConf)

Uses the `runConf.output_mutation_rate` to decide whether to mutate each 
allele (element) of a node. An allele is mutated if a random float between 0 and 1 is inferior
than the mutation value. See [`where_to_mutate`](@ref) for more info. 

The mutation for each node element that ought to be mutated is done with `random_element_value`
Hence, a uniform mutation across min-max bounds. 

Returns the number of elements submitted to mutation.
"""
function mutate_per_allele!(node::OutputNode, run_config::runConf)::Int
    allele_decisions =
        where_to_mutate(length(node), run_config.output_mutation_rate, nothing)
    allele_idx = _bool_vector_to_idx_vector(allele_decisions)
    material_to_mutate = node[allele_idx]
    _mutate_all_alleles!(material_to_mutate)
    return length(material_to_mutate)
end

"""
    mutate_per_allele!(node::AbstractNode, run_config::runConf)

Uses the `runConf.mutation_rate` to decide whether to mutate each 
allele (element) of a node. An allele is mutated if a random float between 0 and 1 is inferior
than the mutation value. See [`where_to_mutate`](@ref) for more info. 

The mutation for each node element that ought to be mutated is done with `random_element_value`
Hence, a uniform mutation across min-max bounds. 

Returns the number of elements submitted to mutation.
"""
function mutate_per_allele!(node::AbstractNode, run_config::runConf)::Int
    allele_decisions = where_to_mutate(length(node), run_config.mutation_rate, nothing)
    allele_idx = _bool_vector_to_idx_vector(allele_decisions)
    material_to_mutate = node[allele_idx]
    _mutate_all_alleles!(material_to_mutate)
    return length(material_to_mutate)
end

################################
# Mutate one element in an node#
################################

"""
    mutate_one_element_from_node!(node::Union{OutputNode,CGPNode})

Uniformly picks one element out of all node's elements. 

That element is submitted to mutation by [`random_element_value`].

Returns 1
"""
function mutate_one_element_from_node!(node::Union{OutputNode,CGPNode})
    which_element = _sample_one_node_element_idx(length(node))
    material_to_mutate = [node.node_material[which_element]] # jsut one so wrap in a vec
    _mutate_all_alleles!(material_to_mutate) # Just one
    return length(material_to_mutate)
end

using Debugger
###################
# NODE CORRECTIONS
###################
"""
TODO
""" # TODO 
function check_functionning_node(
    node::CGPNode,
    library::Library,
    ut_genome::UTGenome,
    shared_inputs::SharedInput,
    model_architecture::modelArchitecture,
)
    try
        fn, connexions, connexions_types =
            extract_fn_connexions_types_from_node(node, library)
        inputs = inputs_for_node(
            connexions,
            connexions_types,
            ut_genome,
            shared_inputs,
            model_architecture,
        )
        @bp
        arg_types = tuple([op.type for op in inputs]...)
        # Get types from input
        return Base.hasmethod(fn.fn, arg_types)
    catch
        @warn "Problem checking the node functionning state. False returned"
        return false
    end
end


