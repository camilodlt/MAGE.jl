# UTILS ---
function print_node__(io, node; kw...)
    theme::Term.Theme = Term.TERM_THEME[]
    styled = if (node isa AbstractString || node isa Number)
        Term.highlight(string(node), :string; theme = theme)
    else
        styled = Term.highlight(typeof(node); theme = theme)
    end
    reshaped = Term.reshape_text(styled, theme.tree_max_leaf_width)
    return print(io, reshaped)
end

# -------------------------------------------------#
# OPERATION: a function call to make in a program. #
# -------------------------------------------------#

abstract type AbstractOperation end

#~~~ Build an input for the operation ~~~#

"""
    InputPromise(index_at::Int)

Marks where we should index a `SharedInput` obj later, to get the input wanted.
"""
struct InputPromise
    index_at::Int
end

"""

    OperationInput(
        input::Union{CGPNode,InputPromise}
        type_idx::Int
        type::Type)
        
The Input of an Operation is either a CGPNode, or a InputPromise. 

In addition, the OperationInput should know the `type` of its input.
"""
struct OperationInput
    input::Union{CGPNode, ConstantNode, InputPromise}
    type_idx::Int
    type::Type
end

#~~~ Unwrap the operationInput ~~~#

"""
    _extract_input_node_from_operationInput(_::SharedInput, node::CGPNode)

Returns the `CGPNode`, as is.
"""
function _extract_input_node_from_operationInput(_::SharedInput, node::CGPNode)
    return some(node)
end

function _extract_input_node_from_operationInput(_::SharedInput, node::ConstantNode)
    return some(node)
end

"""
    _bad_opInput_extraction(i::Int)::Result{InputNode,Nothing}

Warns and returns none. 
"""
function _bad_opInput_extraction(i::Int)::ResultConstructor{Nothing, Err}
    @warn "Tried to index program input's at bad index ($i)"
    return none
end

"""

Indexes the program's inputs at `promise.index_at`.
Bounds are checked:

- Ok case : returns the corresponding  
"""
function _extract_input_node_from_operationInput(
        program_inputs::SharedInput,
        promise::InputPromise,
    )::Option{InputNode}
    A = program_inputs.inputs
    i = promise.index_at
    return checkbounds(Bool, A, i) ? some(A[i]) : _bad_opInput_extraction(i)
end

"""

Extract the real input holder from a `OperationInput`. The input holder might be : 

- InputNode
- CGPNode 
"""
function _extract_input_node_from_operationInput(
        program_inputs::SharedInput,
        operation_input::OperationInput,
    )::Option{Union{CGPNode, ConstantNode, InputNode}}
    return _extract_input_node_from_operationInput(program_inputs, operation_input.input)
end


#~~~ Build an Operation ~~~#

"""
    Operation(
        fn::FunctionWrapper
        calling_node::AbstractEvolvableNode
        inputs::Vector{OperationInput}
        )
        
Wraps the operation to be done. 

The `fn` and `inputs` should be those pointed by the calling_node. 

The function performs : `fn(inputs...)`. The result of that operation is the value of the calling_node.
"""
struct Operation <: AbstractOperation
    fn::FunctionWrapper
    calling_node::AbstractEvolvableNode
    inputs::Vector{OperationInput}
end

"""
Pretty print an operation.
"""
function Base.show(_::IO, op::Operation)
    # function _extract_id_from_R(, x::OperationInput)
    #     R_input = UTCGP._extract_input_node_from_operationInput(x)
    #     input = unwrap_or(x, throw("Could not unwrap the node"))
    #     input.id
    # end
    op_dict = Dict()
    node_name =
        "$(typeof(op.calling_node)) " *
        string(node_to_vector(op.calling_node)) *
        " at $(op.calling_node.id)"
    # ins = [_extract_id_from_R(inp) for inp in op.inputs]
    ins = []
    Base.insert!(ins, 1, string(op.fn.name))
    op_dict[node_name] = ins
    return println(Term.Tree(op_dict, print_node_function = print_node__))
end

function show_program()
    # tree_dict = Dict()
    # for best_program in best_programs
    #     for (i, prog) in enumerate(best_program)
    #         name = "Program n $i"
    #         ops = OrderedDict()
    #         for op in prog
    #             node_name =
    #                 "$(typeof(op.calling_node)) " *
    #                 string(node_to_vector(op.calling_node)) *
    #                 " at $(op.calling_node.id)"
    #             op_dict = Dict()
    #             ins = [
    #                 UTCGP._extract_input_node_from_operationInput(inp).id for
    #                 inp in op.inputs
    #             ]
    #             insert!(ins, 1, string(op.fn.name))
    #             op_dict[node_name] = ins
    #             ops[op.calling_node.id] = op_dict
    #         end
    #         tree_dict[name] = ops
    #     end
    # end
    # println(Term.Tree(tree_dict, print_node_function = print_node__))
end

"""
    _reset_operation!(operation::AbstractOperation)

Resets the 
"""
function _reset_operation!(operation::AbstractOperation)
    return reset_node_value!(operation.calling_node)
end

# -------------------------------------#
# PROGRAM : A COLLECTION OF OPERATIONS #
# -------------------------------------#

abstract type AbstractProgram end
abstract type AbstractDecodedProgram <: AbstractProgram end
mutable struct Program <: AbstractDecodedProgram
    program::Vector{<:AbstractOperation}
    program_inputs::SharedInput
    is_reversed::Bool
    function Program(ops::Vector{<:AbstractOperation}, ins::SharedInput)
        new_ins = similar(ins)
        return new(ops, new_ins, false)
    end
    function Program(ins::SharedInput)
        new_ins = similar(ins)
        return new(AbstractOperation[], new_ins, false)
    end
end


#~~~ API ~~~#

"""
    Base.size(program::Program)

Number of operations.    
"""
Base.size(program::Program) = length(program.program)

"""
    Base.length(program::Program)
    
Number of operations.    
"""
Base.length(program::Program) = size(program)

"""
    Base.getindex(program::Program, i::Int)

Returns the `i`th operation in the program.   
"""
Base.getindex(program::Program, i::Int) = program.program[i]

"""
    Base.setindex!(program::Program, value::UTGenome, i::Int)

Replaces an operation at a given index in the program.    
"""
Base.setindex!(program::Program, value::UTGenome, i::Int) = (program.program[i] = value)

"""
    Base.iterate(program::Program, state = 1)

Iterate over `Operation`s in the program.    
"""
Base.iterate(program::Program, state = 1) =
    state > length(program.program) ? nothing : (program.program[state], state + 1)

"""
    Base.reverse!(decoded_program::Program)

Reverses the order of all operations (so to end with the OutputNode call). 

Flags the program as reversed (`is_reversed` field).
"""
function Base.reverse!(decoded_program::Program)
    @assert decoded_program.is_reversed == false "Tried reversing an already reversed program"
    reverse!(decoded_program.program)
    return decoded_program.is_reversed = true
end

#~~~ CHANGING THE PROGRAM INPUTS ~~~#


"""
    replace_shared_inputs!(program::Program, new_inputs::Vector{A}) where {A}

Replaces the inputs from a program with the new_inputs. 

This op mutates the `program_inputs` property inplace so that the `SharedInput` reference is kept (as well as the `InputNode`s), 
but the values inside the `InputNode`s are completely replaced.

Useful when we want all programs to point to a shared location.
"""
function replace_shared_inputs!(program::Program, new_inputs::Vector{A}) where {A}
    si = program.program_inputs
    @assert length(si) == length(new_inputs) "There must be the same number of inputs it order to replace them. $(length(si)) vs $(length(new_inputs)) "
    return replace_shared_inputs!(program.program_inputs, new_inputs)
end

"""
    replace_shared_inputs!(program::Program, new_inputs::Vector{InputNode})

Replaces the inputs from a program with the new_inputs. 

This op mutates the `program_inputs` property inplace so that the `SharedInput` reference is kept, but the `InputNode`s inside are completely replaced.

Useful when we want all programs to point to a shared location.
"""
function replace_shared_inputs!(program::Program, new_inputs::Vector{InputNode})
    return replace_shared_inputs!(program.program_inputs, new_inputs)
end


"""
    replace_shared_inputs!(program::Program, ref_inputs::SharedInput)

Replaces the internal sharedInput with another one, thereby, linking them. 

Useful when we want all programs to point to a unique location.
"""
function replace_shared_inputs!(program::Program, ref_inputs::SharedInput)
    return program.program_inputs = ref_inputs
end

"""
    reset_program!(program::Program)

Resets all the `calling_nodes` values inside the program.
"""
function reset_program!(program::Program)
    return _reset_operation!.(program)
end


# ------------------------------------------------------------------------#
# INDIVIDUAL PROGRAMS : A COLLECTION OF PROGRAMS FOR A SINGLE INDIVIDUAL  #
# ------------------------------------------------------------------------#

abstract type AbstractIndividualPrograms end
abstract type AbstractPopulationPrograms end

"""
    IndividualPrograms(programs::Vector{<:AbstractProgram})
    
An individual has one or multiple programs, each gives a single output.
"""
struct IndividualPrograms <: AbstractIndividualPrograms
    programs::Vector{<:AbstractProgram}
end

#~~~ API ~~~#
Base.size(ind_progs::IndividualPrograms) = length(ind_progs.programs)
Base.length(ind_progs::IndividualPrograms) = length(ind_progs.programs)
Base.getindex(ind_progs::IndividualPrograms, i::Int) = ind_progs.programs[i]
Base.setindex!(ind_progs::IndividualPrograms, value::UTGenome, i::Int) =
    (ind_progs.programs[i] = value)
Base.iterate(ind_progs::IndividualPrograms, state = 1) =
    state > length(ind_progs.programs) ? nothing : (ind_progs.programs[state], state + 1)
function Base.reverse!(individual_programs::IndividualPrograms)
    for program in individual_programs
        reverse!(program)
    end
    return
end


"""
    replace_shared_inputs!(
        programs::IndividualPrograms,
        new_inputs::Vector{A},
    ) where {A}

As `replace_shared_inputs!` for a single `Program`. It applies the function to all Programs inside that constitute the `IndividualPrograms`.
"""
function replace_shared_inputs!(
        programs::IndividualPrograms,
        new_inputs::Vector{A},
    ) where {A}
    return replace_shared_inputs!.(programs, Ref(new_inputs))
end

"""
    replace_shared_inputs!(programs::IndividualPrograms, new_inputs::Vector{InputNode})

As `replace_shared_inputs!` for a single `Program`. It applies the function to all Programs inside that constitute the `IndividualPrograms`.
"""
function replace_shared_inputs!(programs::IndividualPrograms, new_inputs::Vector{InputNode})
    return replace_shared_inputs!.(programs, Ref(new_inputs))
end


"""
    replace_shared_inputs!(programs::IndividualPrograms, ref_inputs::SharedInput)

As `replace_shared_inputs!` for a single `Program`. It applies the function to all Programs inside that constitute the `IndividualPrograms`.
"""
function replace_shared_inputs!(programs::IndividualPrograms, ref_inputs::SharedInput)
    return replace_shared_inputs!.(programs, Ref(ref_inputs))
end

"""
    reset_programs!(ind_programs::IndividualPrograms)

Resets all the `calling_nodes` values inside all programs.
"""
function reset_programs!(ind_programs::IndividualPrograms)
    return reset_program!.(ind_programs)
end


# ---------------------------------------------------------#
# POPULATION PROGRAMS: A COLLECTION OF INDIVIDUAL PROGRAMS #
# ---------------------------------------------------------#

"""
    PopulationPrograms(
        population_programs::Vector{<:AbstractIndividualPrograms}
    )

Group the programs for the whole population.

Each individual is represented by an `IndividualPrograms` struct. Each `IndividualPrograms` struct has one or more `Programs` (one for each output).    
"""
struct PopulationPrograms <: AbstractPopulationPrograms
    population_programs::Vector{<:AbstractIndividualPrograms}
end

"""
    Base.size(pop_progs::PopulationPrograms)

Number of `IndividualPrograms` inside the population.

Usually the number of individuals    
"""
Base.size(pop_progs::PopulationPrograms) = length(pop_progs.population_programs)

"""
    Base.length(pop_progs::PopulationPrograms)

Number of `IndividualPrograms` inside the population.

Usually the number of individuals    
"""
Base.length(pop_progs::PopulationPrograms) = length(pop_progs.population_programs)

"""
    Base.getindex(pop_progs::PopulationPrograms, i::Int)
    
Index an `IndividualPrograms`    
"""
Base.getindex(pop_progs::PopulationPrograms, i::Int) = pop_progs.population_programs[i]

"""
    Base.getindex(pop_progs::PopulationPrograms, idx::Vector{Int})
    
Index an `IndividualPrograms`    
"""
Base.getindex(pop_progs::PopulationPrograms, idx::Vector{Int}) =
    pop_progs.population_programs[idx]

"""
    Base.setindex!(pop_progs::PopulationPrograms, value::IndividualPrograms, i::Int) =

Set an `IndividualPrograms` at the position `i`.
"""
Base.setindex!(pop_progs::PopulationPrograms, value::IndividualPrograms, i::Int) =
    (pop_progs.population_programs[i] = value)

"""
    Base.iterate(pop_progs::PopulationPrograms, state = 1)

Iterate over `IndividualPrograms`.
"""
Base.iterate(pop_progs::PopulationPrograms, state = 1) =
    state > length(pop_progs.population_programs) ? nothing :
    (pop_progs.population_programs[state], state + 1)

"""
    replace_shared_inputs!(
        pop_programs::PopulationPrograms,
        new_inputs::Vector{A},
    ) where {A}

As `replace_shared_inputs!` for a single `IndividualPrograms`. 

It applies the function to all Programs inside that constitute the `PopulationPrograms`.
"""
function replace_shared_inputs!(
        pop_programs::PopulationPrograms,
        new_inputs::Vector{A},
    ) where {A}
    return replace_shared_inputs!.(pop_programs, Ref(new_inputs))
end

"""
    replace_shared_inputs!(pop_programs::PopulationPrograms, new_inputs::Vector{InputNode})

As `replace_shared_inputs!` for a single `IndividualPrograms`. 

It applies the function to all Programs inside that constitute the `PopulationPrograms`.
"""
function replace_shared_inputs!(
        pop_programs::PopulationPrograms,
        new_inputs::Vector{InputNode},
    )
    return replace_shared_inputs!.(pop_programs, Ref(new_inputs))
end


"""
    replace_shared_inputs!(pop_programs::PopulationPrograms, ref_inputs::SharedInput)

As `replace_shared_inputs!` for a single `IndividualPrograms`. 

It applies the function to all Programs inside that constitute the `PopulationPrograms`.
"""
function replace_shared_inputs!(pop_programs::PopulationPrograms, ref_inputs::SharedInput)
    return replace_shared_inputs!.(pop_programs, Ref(ref_inputs))
end

"""
    reset_programs!(pop_programs::PopulationPrograms)

Resets all the `calling_nodes` values inside all programs.
"""
function reset_programs!(pop_programs::PopulationPrograms)
    return reset_programs!.(pop_programs)
end
