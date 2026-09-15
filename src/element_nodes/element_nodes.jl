"""
    NodeElementTypes

Role played by a [`CGPElement`](@ref) inside a node.

A MAGE node is a small vector of integers. `NodeElementTypes` says what each of
those integers means:

| Value       | Meaning                                                             |
|:------------|:--------------------------------------------------------------------|
| `FUNCTION`  | index of the function to call, inside the node's [`Library`](@ref)   |
| `CONNEXION` | index of the node/input this argument reads from                     |
| `PARAMETER` | a raw integer parameter handed to the function                       |
| `TYPE`      | index of the chromosome (i.e. the type) a `CONNEXION` reads from     |
| `INPUT`     | reserved for input nodes                                             |
| `OUTPUT`    | reserved for output nodes                                            |

`CONNEXION` and `TYPE` always come in pairs: together they answer "which
chromosome, and which node in it" for one argument of the function.
"""
@enum NodeElementTypes FUNCTION CONNEXION PARAMETER TYPE INPUT OUTPUT

"""
    FUNCTION

[`NodeElementTypes`](@ref) marking the element that holds the function index.
"""
FUNCTION

"""
    CONNEXION

[`NodeElementTypes`](@ref) marking an element that holds the position of the
node (or input) an argument reads from. Always paired with a `TYPE` element.
"""
CONNEXION

"""
    PARAMETER

[`NodeElementTypes`](@ref) marking an element that holds a raw integer
parameter passed to the node's function.
"""
PARAMETER

"""
    TYPE

[`NodeElementTypes`](@ref) marking an element that holds the chromosome index
(the type) that the paired `CONNEXION` element reads from.
"""
TYPE

"""
    INPUT

[`NodeElementTypes`](@ref) reserved for elements belonging to input nodes.
"""
INPUT

"""
    OUTPUT

[`NodeElementTypes`](@ref) reserved for elements belonging to output nodes.
"""
OUTPUT

##################
# ABSTRACT ELEMENT
##################

"""
    AbstractElement

Supertype of the smallest evolvable unit in MAGE. Concrete subtype:
[`CGPElement`](@ref).
"""
abstract type AbstractElement end

####################
# SPECIFC ELEMENTS #
####################


"""
    CGPElement(l_bound, h_bound, x_pos, x_real_pos, y_pos, is_freezed, element_type)

One integer of the genome, together with everything needed to mutate it safely.

# Fields
- `lowest_bound`, `highest_bound`: inclusive range the value may take. Mutation
  never samples outside it, which is how MAGE keeps connections legal by
  construction.
- `x_position`: position of the owning node counted from the start of the
  chromosome *including* the inputs (so the first evolvable node of a genome
  with `n` inputs sits at `n + 1`).
- `x_real_position`: position of the owning node ignoring the inputs.
- `y_position`: index of the chromosome the owning node belongs to.
- `is_freezed`: when `true` the value is written once and then never mutated.
  Output nodes freeze their `FUNCTION` and `TYPE` elements this way.
- `element_type`: the element's role, see [`NodeElementTypes`](@ref).
- `value`: the integer itself, `nothing` until initialised.

The value starts as `nothing`; [`initialize_node_element!`](@ref) fills it.

```julia
el = CGPElement(1, 10, 4, 1, 1, false, FUNCTION)
initialize_node_element!(el)
get_node_element_value(el)   # somewhere in 1:10
```
"""
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
"""
    get_node_element_value(node_element::CGPElement)

Return the integer currently held by `node_element`, or `NaN` if it has not been
initialised yet.
"""
function get_node_element_value(node_element::CGPElement)::Int
    v = node_element.value
    return !isnothing(v) ? v : NaN
end

"""
    set_node_lowest_bound(node_element::CGPElement, bound::Int)

Set the smallest value mutation may assign to `node_element`.
"""
set_node_lowest_bound(node_element::CGPElement, bound::Int) =
    node_element.lowest_bound = bound

"""
    set_node_highest_bound(node_element::CGPElement, bound::Int)

Set the largest value mutation may assign to `node_element`.

For a `CONNEXION` element this is what enforces the feed-forward property: the
bound is the position of the last node the owning node is allowed to read.
"""
set_node_highest_bound(node_element::CGPElement, bound::Int) =
    node_element.highest_bound = bound

"""
    set_node_position(node_element::CGPElement, x_pos::Int, x_real_pos::Int, y_pos::Int)
    set_node_position(node_element::CGPElement, positions::Tuple{Int,Int,Int})

Record where the node owning `node_element` sits in the genome.

`x_pos` counts the inputs, `x_real_pos` does not, and `y_pos` is the chromosome
index. See [`CGPElement`](@ref).
"""
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
"""
    set_node_freeze_state(node_element::CGPElement)

Freeze `node_element`: its value is kept as is by every later mutation.

Typical use is pinning the output of a run to a specific node:

```julia
set_node_element_value!(ut_genome.output_nodes[1][2], ut_genome.output_nodes[1][2].highest_bound)
set_node_freeze_state(ut_genome.output_nodes[1][2])
```
"""
set_node_freeze_state(node_element::CGPElement) = node_element.is_freezed = true

"""
    set_node_unfreeze_state(node_element::CGPElement)

Undo [`set_node_freeze_state`](@ref) and make `node_element` mutable again.
"""
set_node_unfreeze_state(node_element::CGPElement) = node_element.is_freezed = false

"""
    set_node_element_type(node_element::CGPElement, element_type::NodeElementTypes)

Change the role of `node_element`. See [`NodeElementTypes`](@ref).
"""
set_node_element_type(node_element::CGPElement, element_type::NodeElementTypes) =
    node_element.element_type = element_type

"""
    set_node_element_value!(node_element::CGPElement, value::Int)

Write `value` into `node_element`.

A frozen element keeps whatever it already holds and the write is dropped, with
one exception: a frozen element that was never given a value accepts this first
write, so that freezing before initialisation still yields a usable genome.
"""
function set_node_element_value!(node_element::CGPElement, value::Int)
    if node_element.is_freezed
        if node_element.value === nothing
            @info "Node is frozen but it has a nothing value. The new value will be set"
            node_element.value = value
        else
            @debug "Node is frozen. New value is omitted"
        end
    else
        node_element.value = value
    end
end

