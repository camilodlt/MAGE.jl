# -*- coding: utf-8 -*-

# elbow = "└──"
# pipe = "│  "
# tee = "├──"
# blank = "   "

abstract type AbstractOperation end
abstract type AbstractProgram end
abstract type AbstractIndividualPrograms end
abstract type AbstractPopulationPrograms end



struct InputPromise
    input_list::Vector{InputNode}
    index_at::Int
end

struct OperationInput
    input::Union{CGPNode,InputPromise}
    type_idx::Int
    type::Type
end




function extract_input_node_from_operationInput(
    operation_input::OperationInput,
)::Union{CGPNode,InputNode}
    if operation_input.input isa CGPNode
        return operation_input.input
    elseif operation_input.input isa InputPromise
        input_promise = operation_input.input
        index_at = input_promise.index_at
        return input_promise.input_list[index_at]
    else
        throw(MethodError("Input Promise didn't have CGP_Node nor InputPromise"))
    end
end




struct Operation <: AbstractOperation
    fn::FunctionWrapper
    calling_node::CGPNode
    inputs::Vector{OperationInput}
end


# TODO
# function repr(op::Operation)
#         s = ""
#         fn_name = op.fn.name
#         s += tee + str(node_to_vector(self.calling_node)) + fn_name + "\n"
#         for operationInput in self.inputs:
#             node = extract_input_node_from_operationInput(operationInput)
#             n_vector = node_to_vector(node)
#             s += blank + tee + str(n_vector) + "\n"
#         return s
# end

struct Program <: AbstractProgram
    program::Vector{<:AbstractOperation}
end

Base.size(program::Program) = length(program.program)
Base.length(program::Program) = length(program.program)
Base.getindex(program::Program, i::Int) = program.program[i]
Base.setindex!(program::Program, value::UTGenome, i::Int) = (program.program[i] = value)
Base.iterate(program::Program, state = 1) =
    state > length(program.program) ? nothing : (program.program[state], state + 1)


struct IndividualPrograms <: AbstractIndividualPrograms
    programs::Vector{<:AbstractProgram}
end
Base.size(ind_progs::IndividualPrograms) = length(ind_progs.programs)
Base.length(ind_progs::IndividualPrograms) = length(ind_progs.programs)
Base.getindex(ind_progs::IndividualPrograms, i::Int) = ind_progs.programs[i]
Base.setindex!(ind_progs::IndividualPrograms, value::UTGenome, i::Int) =
    (ind_progs.programs[i] = value)
Base.iterate(ind_progs::IndividualPrograms, state = 1) =
    state > length(ind_progs.programs) ? nothing : (ind_progs.programs[state], state + 1)


struct PopulationPrograms <: AbstractPopulationPrograms
    population_programs::Vector{<:AbstractIndividualPrograms}
end
Base.size(pop_progs::PopulationPrograms) = length(pop_progs.population_programs)
Base.length(pop_progs::PopulationPrograms) = length(pop_progs.population_programs)
Base.getindex(pop_progs::PopulationPrograms, i::Int) = pop_progs.population_programs[i]
Base.setindex!(pop_progs::PopulationPrograms, value::UTGenome, i::Int) =
    (pop_progs.population_programs[i] = value)
Base.iterate(pop_progs::PopulationPrograms, state = 1) =
    state > length(pop_progs.population_programs) ? nothing :
    (pop_progs.population_programs[state], state + 1)

