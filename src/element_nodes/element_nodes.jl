@enum NodeElementTypes FUNCTION CONNEXION PARAMETER TYPE INPUT OUTPUT

##################
# ABSTRACT ELEMENT
##################

abstract type AbstractElement end

####################
# SPECIFC ELEMENTS #
####################


Base.@kwdef mutable struct CGPElement <: AbstractElement

    # BOUNDS
    lowest_bound::Int
    highest_bound::Int

    # POSITION (i,j)
    x_position::Int
    x_real_position::Int
    y_position::Int

    # STATE

    is_freezed::Bool
    element_type::NodeElementTypes
    value::Union{Int,Nothing}

    function CGPElement(
        l_bound::Int,
        h_bound::Int,
        x_pos::Int,
        x_real_pos::Int,
        y_pos::Int,
        is_freezed::Bool,
        element_type::NodeElementTypes,
    )

        return new(
            l_bound,
            h_bound,
            x_pos,
            x_real_pos,
            y_pos,
            is_freezed,
            element_type,
            nothing,
        )
    end
end

###########################
# METHOD CGP ELEMENT #
##########################
# GET VALUE
function get_node_element_value(node_element::CGPElement)::Int
    v = node_element.value
    return !isnothing(v) ? v : NaN
end

# BOUNDS
set_node_lowest_bound(node_element::CGPElement, bound::Int) =
    node_element.lowest_bound = bound
set_node_highest_bound(node_element::CGPElement, bound::Int) =
    node_element.highest_bound = bound

# POSITION
function set_node_position(
    node_element::CGPElement,
    x_pos::Int,
    x_real_pos::Int,
    y_pos::Int,
)
    node_element.x_position = x_pos
    node_element.x_real_position = x_real_pos
    node_element.y_position = y_pos
end

function set_node_position(node_element::CGPElement, positions::Tuple{Int,Int,Int})
    node_element.x_position = positions[1]
    node_element.x_real_position = positions[2]
    node_element.y_position = positions[3]
end
# STATE
set_node_freeze_state(node_element::CGPElement) = node_element.is_freezed = true
set_node_unfreeze_state(node_element::CGPElement) = node_element.is_freezed = false
set_node_element_type(node_element::CGPElement, element_type::NodeElementTypes) =
    node_element.element_type = element_type

function set_node_element_value!(node_element::CGPElement, value::Int)
    if node_element.is_freezed
        if node_element.value === nothing
            @info "Node is frozen but it has a nothing value. The new value will be set"
            node_element.value = value
        else
            @info "Node is frozen. New value is omitted"
        end
    else
        node_element.value = value
    end
end

