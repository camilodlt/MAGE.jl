abstract type AbstractGenome end
abstract type AbstractMetaGenome end
abstract type AbstractGenomeInputs end


################
# SHARED INPUTS
################

"""
    SharedInput(inputs::Vector{InputNode})

The inputs of a program, shared by every chromosome of a [`UTGenome`](@ref).

Holding the inputs in one object is what lets several typed chromosomes read the
same values: an image input, for instance, can be consumed both by the image
chromosome and (after a reduction) by the float one.

Supports `length`, `size`, indexing and iteration over the underlying
[`InputNode`](@ref)s.

Between two evaluations the same object is reused and only its values are
swapped, with [`replace_shared_inputs!`](@ref).
"""
struct SharedInput <: AbstractGenomeInputs
    inputs::Vector{InputNode}
end

"""
    size(shared_inputs::AbstractGenomeInputs)

Returns the number of inputs in the internal vector.
"""
Base.size(shared_inputs::AbstractGenomeInputs) = length(shared_inputs.inputs)

"""
    length(shared_inputs::AbstractGenomeInputs)

Returns the number of inputs in the internal vector.
"""
Base.length(shared_inputs::AbstractGenomeInputs) = size(shared_inputs)

"""
Iterates over the inputs.
"""
Base.iterate(shared_inputs::AbstractGenomeInputs, state = 1) =
    state > length(shared_inputs.inputs) ? nothing :
    (shared_inputs.inputs[state], state + 1)

"""
Gets an input at a given index.
"""

Base.getindex(shared_inputs::AbstractGenomeInputs, i::Int) = shared_inputs.inputs[i]
"""
Gets multiple inputs at several indices.
"""
Base.getindex(shared_inputs::AbstractGenomeInputs, i::Vector{<:Int}) =
    shared_inputs.inputs[i]

"""
From a SharedInput obj, it replaces the inputs while keeping the same object. 
The new inputs must have the same size as the SharedInput
"""
function replace_shared_inputs!(si::SharedInput, new_inputs::Vector{InputNode})
    @assert length(si) == length(new_inputs) "There must be the same number of inputs it order to replace them. $(length(si)) vs $(length(new_inputs)) "
    empty!(si.inputs)
    return push!(si.inputs, new_inputs...)
end

"""
From a SharedInput obj, it replaces the inputs while keeping the same object. 
The `new_inputs` replace the values of the old inputs. 
"""
function replace_shared_inputs!(si::SharedInput, new_inputs::Vector{A}) where {A}
    @assert length(si) == length(new_inputs) "There must be the same number of inputs it order to replace them. $(length(si)) vs $(length(new_inputs)) "
    for (old_input, new_input) in zip(si.inputs, new_inputs)
        set_node_value!(old_input, new_input)
    end
    return
end

"""
    Base.similar(lazy_inputs::SharedInput)
"""
function Base.similar(lazy_inputs::SharedInput)
    ins = []
    for (input_ith, input) in enumerate(lazy_inputs.inputs)
        empty_node =
            InputNode(nothing, input.x_position, input.x_real_position, input.y_position)
        set_node_value!(empty_node, @view lazy_inputs.inputs[input_ith])
        push!(ins, empty_node)
    end
    return SharedInput(ins)
end

################
# SINGLE GENOME
################

"""
    SingleGenome(starting_point::Int, chromosome::Vector{<:AbstractEvolvableNode})

A SingleGenome is like an standard CGP vector representation. It holds a vector of nodes.

Also it has an `starting_point`, indicating that the first node has a `x_position` of `starting_point+1`.
The `starting_point` hence represents the number of inputs that should precede the genome.

It is supposed to reference functions that return only one defined type.
"""
struct SingleGenome <: AbstractGenome
    starting_point::Int
    chromosome::Vector{<:AbstractEvolvableNode}
end

"""
    size(genome::AbstractGenome)

Returns the size of the internal chromosome (a vector of nodes) 
"""
Base.size(genome::AbstractGenome) = length(genome.chromosome)

"""
    length(genome::AbstractGenome)

Returns the size of the internal chromosome (a vector of nodes) 
"""
Base.length(genome::AbstractGenome) = size(genome)

"""
Iterates the internal chromosome (a vector of nodes) .
"""
Base.iterate(genome::AbstractGenome, state = 1) =
    state > length(genome.chromosome) ? nothing : (genome.chromosome[state], state + 1)

"""
Indexes the internal vector of nodes at a given index.
"""
Base.getindex(genome::AbstractGenome, i::Int) = genome.chromosome[i]
"""
Indexes the internal vector of nodes at multiple indices.
"""
Base.getindex(genome::AbstractGenome, i::Vector{<:Int}) = genome.chromosome[i]

Base.setindex!(nodes::UTCGP.SingleGenome, v::UTCGP.AbstractGenomeNode, i::Int) = nodes.chromosome[i] = v

################
# UTGENOME
################
"""
    UTGenome(genomes::Vector{<:AbstractGenome}, output_nodes::Vector{AbstractOutputNode})

A multi-chromosome, type-aware genome: MAGE's individual.

`genomes` holds one [`SingleGenome`](@ref) per type declared in
`modelArchitecture.chromosomes_types` — chromosome `i` only ever produces values
of type `i`. `output_nodes` holds one [`OutputNode`](@ref) per program output,
each pinned to the chromosome carrying its type.

Because a node's `TYPE` element names the chromosome each of its arguments reads
from, a connexion can cross chromosomes while remaining type-correct. That is
what allows a single program to mix modalities.

Supports `length` (number of chromosomes), indexing and iteration, so
`ut_genome[1][2]` is the second node of the first chromosome and
`ut_genome[1][2][1]` its function element.

Build one with [`make_evolvable_utgenome`](@ref).
"""
struct UTGenome <: AbstractMetaGenome
    genomes::Vector{<:AbstractGenome}
    output_nodes::Vector{AbstractOutputNode}
end
"""
    size(genome::AbstractMetaGenome)

Returns the size of the internal chromosome (a vector of nodes) 
"""
Base.size(genome::AbstractMetaGenome) = length(genome.genomes)

"""
    length(genome::AbstractMetaGenome)

Returns the size of the internal chromosome (a vector of nodes) 
"""
Base.length(genome::AbstractMetaGenome) = size(genome)

"""
Iterates the internal chromosome (a vector of nodes) .
"""
Base.iterate(genome::AbstractMetaGenome, state = 1) =
    state > length(genome.genomes) ? nothing : (genome.genomes[state], state + 1)

"""
Indexes the internal vector of nodes at a given index.
"""
Base.getindex(genome::AbstractMetaGenome, i::Int) = genome.genomes[i]
"""
Indexes the internal vector of nodes at multiple indices.
"""
Base.getindex(genome::AbstractMetaGenome, i::Vector{<:Int}) = genome.genomes[i]
