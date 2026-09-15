#############################################
# NODE MATERIAL (the vector repr of the node)
#############################################

# HOLDER OF NODE ELEMENrS

"""
    NodeMaterial()
    NodeMaterial(material_list::Vector{<:AbstractElement})

Holds the integers of a node.

A `NodeMaterial` is the ordered vector of [`CGPElement`](@ref)s that make up one
node: one `FUNCTION` element, then `arity` `(CONNEXION, TYPE)` pairs. It
supports `length`, `size`, and integer/vector indexing, so `node_material[1]` is
the function element.
"""
struct NodeMaterial
    material::Vector{<:AbstractElement}
    function NodeMaterial()
        return new(Vector{CGPElement}())
    end
    function NodeMaterial(material_list::Vector{<:AbstractElement})
        return new(material_list)
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

"""
    AbstractNode

Supertype of every node in a MAGE genome.

The hierarchy below it splits nodes by what mutation is allowed to touch:

- `AbstractEvolvableNode`: carries mutable material.
  - `AbstractGenomeNode`: [`CGPNode`](@ref) and [`ConstantNode`](@ref).
  - `AbstractOutputNode`: [`OutputNode`](@ref).
- `AbstractNonEvolvableNode`: [`InputNode`](@ref), which only carries a value.

Every node supports `length`, integer indexing and iteration over its
[`NodeMaterial`](@ref).
"""
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


"""
    initialize_node!(node::AbstractEvolvableNode)

Initialise every element of `node` (see [`initialize_node_element!`](@ref)).
"""
function initialize_node!(node::AbstractEvolvableNode)
    for node_element in node
        initialize_node_element!(node_element)
    end
    return
end

"""
    reset_node_value!(node::AbstractNode)

Drop the cached output value of `node`, so the next decoding recomputes it.

[`ConstantNode`](@ref)s are deliberately not reset.
"""
function reset_node_value!(node::AbstractNode)
    return node.value = nothing
end

"""
    set_node_value!(node::AbstractNode, val::Any)

Store `val` as the current output value of `node`.
"""
function set_node_value!(node::AbstractNode, val::Any)
    return node.value = val
end

"""
    get_node_value(node::AbstractNode)

Read the current output value of `node`, or `nothing` if it has not been
computed yet.

The method on [`ConstantNode`](@ref) dereferences the stored `Ref`, and the
method on a plain value returns it unchanged, so this can be called uniformly on
whatever a connexion resolves to.
"""
function get_node_value(node::AbstractNode)::Any
    return node.value
end

"""
    extract_connexions_from_node(node::AbstractEvolvableNode)

Return the `CONNEXION` elements of `node`, in argument order.
"""
function extract_connexions_from_node(node::AbstractEvolvableNode)::Vector{CGPElement}
    connexions = [
        element for
            element in node.node_material.material if element.element_type == CONNEXION
    ]
    return connexions
end

"""
    extract_parameters_from_node(node::AbstractEvolvableNode)

Return the `PARAMETER` elements of `node`, in order.
"""
function extract_parameters_from_node(node::AbstractEvolvableNode)::Vector{CGPElement}
    params = [
        element for
            element in node.node_material.material if element.element_type == PARAMETER
    ]
    return params
end

"""
    extract_connexions_types_from_node(node::AbstractEvolvableNode)

Return the `TYPE` elements of `node`, in argument order.

The i-th value says which chromosome the i-th connexion of the node reads from;
this is what makes a connexion type-correct.
"""
function extract_connexions_types_from_node(node::AbstractEvolvableNode)::Vector{CGPElement}
    connexions_types =
        [element for element in node.node_material.material if element.element_type == TYPE]
    return connexions_types
end


"""
    extract_function_from_node(node::AbstractEvolvableNode)

Return the single `FUNCTION` element of `node`.

Its value indexes the [`Library`](@ref) of the chromosome the node belongs to.
"""
function extract_function_from_node(node::AbstractEvolvableNode)::CGPElement
    function_element = [
        element for
            element in node.node_material.material if element.element_type == FUNCTION
    ]
    return function_element[1]
end

"""
    node_to_vector(node::AbstractNode)

Flatten `node` into the vector of its element values, with `NaN` for elements
that have not been initialised.

Used by the serialisation and hashing helpers that need a plain numeric view of
the genome.
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


"""
    InputNode(value, x_pos::Int, x_real_pos::Int, y_pos::Int)

A leaf of the graph holding one program input.

Input nodes have no evolvable material: only a value and a position. They live
in a [`SharedInput`](@ref) so that every chromosome of a genome reads the same
inputs.

`y_pos` is the index of the chromosome (i.e. the type) this input belongs to,
which is how a typed connexion can reach it.
"""
mutable struct InputNode <: AbstractNonEvolvableNode
    node_material::NodeMaterial
    value::Any
    x_position::Int
    x_real_position::Int
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

function get_node_value(x::InputNode)
    return get_node_value(x.value)
end
function get_node_value(x::SubArray{InputNode, 0})
    return x[1].value
end
function get_node_value(x::Any)
    return x
end

"""
    CGPNode(value, x_pos::Int, x_real_pos::Int, y_pos::Int)
    CGPNode(nm::NodeMaterial, value, x_pos::Int, x_real_pos::Int, y_pos::Int)

An evolvable node of a chromosome: a function index plus its typed connexions.

Build one with [`make_evolvable_node`](@ref) rather than by hand — that helper
computes the bounds that keep the graph feed-forward and type-correct.
"""
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
            nm, # empty node material
            value,
            x_pos,
            x_real_pos,
            y_pos,
            id,
        )
    end
end

"""
    OutputNode(value, x_pos::Int, x_real_pos::Int, y_pos::Int)
    OutputNode(nm::NodeMaterial, value, x_pos::Int, x_real_pos::Int, y_pos::Int)

The node that names one output of the genome.

Its material is `[FUNCTION, CONNEXION, TYPE]`, where the function and the type
are frozen: an output node only ever evolves *which* node it points at, never
what it computes or which chromosome it reads.

Use [`make_output_node`](@ref) to build one.
"""
mutable struct OutputNode <: AbstractOutputNode
    node_material::NodeMaterial
    value::Any
    x_position::Int
    x_real_position::Int
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


####################################
# CONSTANT NODE
####################################

"""
    ConstantNode(value::T, x_pos::Int, x_real_pos::Int, y_pos::Int)

A node holding a fixed value that programs can read but evolution cannot change.

The value is stored in a `Ref`, so it can be updated from the outside (this is
what the CMA-ES extension does, see [`make_cma_nodes!`](@ref)) while staying
invisible to mutation. Unlike other nodes it is *not* cleared by
[`reset_node_value!`](@ref).
"""
mutable struct ConstantNode <: AbstractGenomeNode
    node_material::NodeMaterial
    value::Ref
    x_position::Int
    x_real_position::Int
    y_position::Int
    id::String

    function ConstantNode(value::T, x_pos::Int, x_real_pos::Int, y_pos::Int) where {T}
        id = "nd ($x_pos,$y_pos)"
        return new(
            NodeMaterial(), # empty node material
            Ref{T}(value),
            x_pos,
            x_real_pos,
            y_pos,
            id,
        )
    end
end

function get_node_value(node::ConstantNode)
    return node.value[]
end

# constant nodes are not resetted
function reset_node_value!(node::ConstantNode)
    return
end

####################################
# PARAMETRIC NODES
####################################
abstract type AbstractParametricNode{T} <: AbstractEvolvableNode end
abstract type AbstractParametricInputNode{T} <: AbstractParametricNode{T} end # Genome nodes
abstract type AbstractParametricGenomeNode{T} <: AbstractParametricNode{T} end # Genome nodes
abstract type AbstractParametricOutputNode{T} <: AbstractParametricNode{T} end # Output Nodes

struct InputNodeP{T} <: AbstractParametricInputNode{T}
    node_material::NodeMaterial
    is_set::Ref{Bool}
    value::Ref{T}
    x_position::Int
    x_real_position::Int
    y_position::Int
    id::String

    function InputNodeP(
            value::Ref{T},
            x_pos::Int,
            x_real_pos::Int,
            y_pos::Int,
        ) where {T <: DataType}
        id = "inp ($x_pos,$y_pos)"
        return new{T}(
            NodeMaterial(), # empty node material
            Ref{Bool}(false),
            value,
            x_pos,
            x_real_pos,
            y_pos,
            id,
        )
    end
end

struct CGPNodeP{T} <: AbstractParametricGenomeNode{T}
    node_material::NodeMaterial
    is_set::Ref{Bool}
    value::Ref{T}
    x_position::Int
    x_real_position::Int
    y_position::Int
    id::String

    function CGPNodeP(
            nm::NodeMaterial,
            value::Ref{T},
            x_pos::Int,
            x_real_pos::Int,
            y_pos::Int,
        ) where {T}
        id = "nd ($x_pos,$y_pos)"
        return new{T}(
            nm, # empty node material
            Ref{Bool}(false),
            value,
            x_pos,
            x_real_pos,
            y_pos,
            id,
        )
    end

    function CGPNodeP(value::Ref{T}, x_pos::Int, x_real_pos::Int, y_pos::Int) where {T}
        nm = NodeMaterial()
        return CGPNodeP(nm, value, x_pos, x_real_pos, y_pos)
    end
end

struct OutputNodeP{T} <: AbstractParametricOutputNode{T}
    node_material::NodeMaterial
    is_set::Ref{Bool}
    value::Ref{T}
    x_position::Int
    x_real_position::Int
    y_position::Int
    id::String

    function OutputNodeP(
            nm::NodeMaterial,
            value::Ref{T},
            x_pos::Int,
            x_real_pos::Int,
            y_pos::Int,
        ) where {T}
        id = "node ($x_pos,$y_pos)"
        return new{T}(nm, Ref{Bool}(false), value, x_pos, x_real_pos, y_pos, id)
    end
    function OutputNodeP(value::Ref{T}, x_pos::Int, x_real_pos::Int, y_pos::Int) where {T}
        nm = NodeMaterial()
        return OutputNodeP(nm, value, x_pos, x_real_pos, y_pos)
    end
end

# API
function get_node_value(node::AbstractParametricNode{T})::T where {T}
    return node.is_set[] ? node.value[] : nothing
end

function get_node_value(x::SubArray{InputNodeP{T}, 0})::T where {T}
    return get_node_value(x[1])
end

function reset_node_value!(node::AbstractParametricNode{T}) where {T}
    return node.is_set[] = nothing
end

function set_node_value!(node::AbstractParametricNode{T}, val::T) where {T}
    return if node.is_set[]
        node.value[] = val
    else
        @warn "Node was set so set_node_value! was omitted"
    end
end
