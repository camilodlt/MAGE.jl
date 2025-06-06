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
    mutate_per_allele!(node::AbstractEvolvableNode, run_config::runConf)

Uses the `runConf.mutation_rate` to decide whether to mutate each 
allele (element) of a node. An allele is mutated if a random float between 0 and 1 is inferior
than the mutation value. See [`where_to_mutate`](@ref) for more info. 

The mutation for each node element that ought to be mutated is done with `random_element_value`
Hence, a uniform mutation across min-max bounds. 

Returns the number of elements submitted to mutation.
"""
function mutate_per_allele!(node::AbstractEvolvableNode, run_config::runConf)::Int
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
    model_architecture::modelArchitecture;
    current_call::Int = 0,
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
        arg_types = tuple([op.type for op in inputs]...)
        return Base.hasmethod(fn.fn, arg_types)
    catch e
        @show e
        @warn "Problem checking the node functionning state. False returned"
        return false
    end
end



##############################################
# Get Active Nodes from a Individual Programs
#############################################

function get_active_nodes(ind_programs::IndividualPrograms)::Vector{<:AbstractGenomeNode}
    active_nodes = AbstractGenomeNode[]
    for program in ind_programs
        prog_nodes = get_active_nodes(program)
        push!(active_nodes, prog_nodes...)
    end
    active_nodes_with_type = identity.(active_nodes)
    return unique(active_nodes_with_type)
    # return active_nodes
end


function get_active_nodes(program::Program)
    active_nodes = []
    for operation in program
        active_node = get_active_node(operation)
        if !isnothing(active_node)
            push!(active_nodes, active_node)
        end
    end
    return active_nodes
end


function get_active_node(op::Operation)
    if typeof(op.calling_node) <: AbstractGenomeNode
        return op.calling_node
    end
    return nothing
end


############
# SAMPLE N 
############

function sample_n(max_nb::Int, n::Int)
    @assert max_nb > 0 "max_nb should be at least 1"
    @assert n > 0 "n to sample should be at least 1"
    @assert n <= max_nb "At most, we can sample $max_nb from $max_nb. Asked: $n"
    rng = Random.default_rng()
    idx = collect(1:max_nb)
    w = Weights(ones(length(idx)))
    samples = sample(rng, idx, w, n, replace = false)
    return samples
end

#################################
# GET ONLY ACTIVE NODE MATERIAL #
#################################

"""
    get_active_node_material(
        node::AbstractEvolvableNode,
        library::Library,
        ut_genome::UTGenome,
        shared_inputs::SharedInput,
        model_architecture::modelArchitecture,
    )

Returns a vector of integers of the actual used pointers in the node. 

A function is always used, so the first element in the vector will be the index of the function. 
Then, for each input that the function uses, the index (horizontal) of the input and the type index (vertical) are appended to the vector. 

One exception concerns the direct connexion to an input node (on in `shared_inputs`), in that case, only the index (horizontal) is appended since
its type index is resolved dynamically. 

This fn will raise an error if the node does not work, so it's better to use it after an if shorcircuit.

"""
function get_active_node_material(
    node::AbstractEvolvableNode,
    library::Library,
    ut_genome::UTGenome,
    shared_inputs::SharedInput,
    model_architecture::modelArchitecture,
)
    fn, connexions, connexions_types = extract_fn_connexions_types_from_node(node, library)
    inputs = inputs_for_node(
        connexions,
        connexions_types,
        ut_genome,
        shared_inputs,
        model_architecture,
    )
    arg_types = tuple([op.type for op in inputs]...)
    m = which(fn.fn, arg_types)
    fn_arity = m.nargs - 2 # - fn, - args...
    material = [node[1].value] # the fn
    for (con_pos, i) in enumerate(1:fn_arity)
        push!(material, connexions[con_pos].value) # always add the horizontal pos
        if typeof(inputs[con_pos].input) <: AbstractEvolvableNode
            push!(material, connexions_types[con_pos].value) # only add the vertical pos in case of CGPNode
        end
    end
    params = extract_parameters_from_node(node)
    if length(params) > 0
        throw(ErrorException("No test for params in active material"))
    end
    return material
end
