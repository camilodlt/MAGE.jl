#############################################
# NODE MATERIAL (the vector repr of the node)
#############################################

# HOLDER OF NODE ELEMENrS
struct NodeMaterial
    material::Vector{<:AbstractElement}
    function NodeMaterial()
        return new(Vector{CGPElement}())
    end
    function NodeMaterial(material_list::Vector{<:AbstractElement})
        new(material_list)
    end
end

Base.size(node_elements::NodeMaterial) = length(node_elements.material)
Base.length(node_elements::NodeMaterial) = length(node_elements.material)
Base.getindex(node_elements::NodeMaterial, i::Int) = node_elements.material[i]
Base.getindex(node_elements::NodeMaterial, i::Vector{<:Int}) = node_elements.material[i]
Base.setindex!(node_elements::NodeMaterial, value, i::Int) =
    (node_elements.material[i] = value)


################
# ABSTRACT NODE 
################

abstract type AbstractNode end #All nodes
abstract type AbstractEvolvableNode <: AbstractNode end # Everything that evolves
abstract type AbstractNonEvolvableNode <: AbstractNode end # what doesn't evolves
abstract type AbstractGenomeNode <: AbstractEvolvableNode end # Genome nodes
abstract type AbstractOutputNode <: AbstractEvolvableNode end # Output Nodes


# Must Override Methods "class methods"
function initialize(::AbstractNode)
    throw(ErrorException("Not Implemented"))
end

function get_node_id(::AbstractNode)
    throw(ErrorException("Not Implemented"))
end


###############################################################
# METHODS OVER ABSTRACTNODE : EXTRACT CONNEXTIONS, TYPES & FN
###############################################################


function initialize_node!(node::AbstractEvolvableNode)
    for node_element in node
        initialize_node_element!(node_element)
    end
end

function reset_node_value!(node::AbstractNode)
    node.value = nothing
end

function set_node_value!(node::AbstractNode, val::Any)
    node.value = val
end
function get_node_value(node::AbstractNode)::Any
    return node.value
end

function extract_connexions_from_node(node::AbstractEvolvableNode)::Vector{CGPElement}
    connexions = [
        element for
        element in node.node_material.material if element.element_type == CONNEXION
    ]
    return connexions
end

function extract_parameters_from_node(node::AbstractEvolvableNode)::Vector{CGPElement}
    params = [
        element for
        element in node.node_material.material if element.element_type == PARAMETER
    ]
    return params
end


function extract_connexions_types_from_node(node::AbstractEvolvableNode)::Vector{CGPElement}
    connexions_types =
        [element for element in node.node_material.material if element.element_type == TYPE]
    return connexions_types
end


function extract_function_from_node(node::AbstractEvolvableNode)::CGPElement
    function_element = [
        element for
        element in node.node_material.material if element.element_type == FUNCTION
    ]
    return function_element[1]
end

# TODO 
"""
"""
function node_to_vector(node::AbstractNode)::Vector{<:Number}
    vec_repr = Float64[]
    for node_element in node
        v = node_element.value
        v = !isnothing(v) ? v : NaN
        push!(vec_repr, v)
    end
    return vec_repr
end
Base.size(s::AbstractNode) = length(s.node_material)
Base.length(s::AbstractNode) = length(s.node_material)
Base.getindex(s::AbstractNode, i::Int) = s.node_material[i]
Base.getindex(s::AbstractNode, i::Vector{<:Int}) = s.node_material[i]
Base.setindex!(s::AbstractNode, value, i::Int) = (s.node_material[i] = value)
"""
Iterates over the internal node elements. 

It iterates over the node_meterial vector.
"""
Base.iterate(n::AbstractNode, state = 1) =
    state > length(n.node_material) ? nothing : (n.node_material[state], state + 1)


###############
# SPECIAL NODES
###############


mutable struct InputNode <: AbstractNonEvolvableNode
    node_material::NodeMaterial
    value::Any
    x_postion::Int
    x_real_postion::Int
    y_position::Int
    id::String

    function InputNode(value::Any, x_pos::Int, x_real_pos::Int, y_pos::Int)
        id = "inp ($x_pos,$y_pos)"
        return new(
            NodeMaterial(), # empty node material
            value,
            x_pos,
            x_real_pos,
            y_pos,
            id,
        )
    end
end

mutable struct CGPNode <: AbstractGenomeNode
    node_material::NodeMaterial
    value::Any
    x_position::Int
    x_real_position::Int
    y_position::Int
    id::String

    function CGPNode(value::Any, x_pos::Int, x_real_pos::Int, y_pos::Int)
        id = "nd ($x_pos,$y_pos)"
        return new(
            NodeMaterial(), # empty node material
            value,
            x_pos,
            x_real_pos,
            y_pos,
            id,
        )
    end
    function CGPNode(nm::NodeMaterial, value::Any, x_pos::Int, x_real_pos::Int, y_pos::Int)
        id = "nd ($x_pos,$y_pos)"
        return new(
            nm,# empty node material
            value,
            x_pos,
            x_real_pos,
            y_pos,
            id,
        )
    end
end

mutable struct OutputNode <: AbstractOutputNode
    node_material::NodeMaterial
    value::Any
    x_postion::Int
    x_real_postion::Int
    y_position::Int
    id::String

    function OutputNode(value::Any, x_pos::Int, x_real_pos::Int, y_pos::Int)
        id = "node ($x_pos,$y_pos)"
        return new(
            NodeMaterial(), # empty node material
            value,
            x_pos,
            x_real_pos,
            y_pos,
            id,
        )
    end
    function OutputNode(
        nm::NodeMaterial,
        value::Any,
        x_pos::Int,
        x_real_pos::Int,
        y_pos::Int,
    )
        id = "node ($x_pos,$y_pos)"
        return new(nm, value, x_pos, x_real_pos, y_pos, id)
    end
end
