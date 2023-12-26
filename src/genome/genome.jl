
abstract type AbstractGenome end
abstract type AbstractMetaGenome end
abstract type AbstractGenomeInputs end


################
# SHARED INPUTS
################

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

"""
function replace_shared_inputs!(si::SharedInput, new_inputs::Vector{InputNode})
    @assert length(si) == length(new_inputs) "There must be the same number of inputs it order to replace them. $(length(si)) vs $(length(new_inputs)) "
    empty!(si.inputs)
    push!(si.inputs, new_inputs...)
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

################
# UTGENOME 
################
struct UTGenome <: AbstractMetaGenome
    genomes::Vector{<:AbstractGenome}
    output_nodes::Vector{OutputNode}
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

