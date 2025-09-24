# abstract type AbstractModularFunction <: AbstractFunction end

# # Holds a program that can be runned
# # It's a function, so it can be used in the library
# # The output of the program is the output of the ModularFunction
# mutable struct ModularFunction <: AbstractModularFunction
#     program::AbstractDecodedProgram
#     name::Symbol
#     arity::Int
#     id::String
#     chromosomes_types::Vector{<:Type}
#     metalibrary::MetaLibrary

#     function ModularFunction(
#             program::AbstractDecodedProgram,
#             name::Symbol,
#             chromosomes_types::Vector{<:Type},
#             metalibrary::MetaLibrary,
#         )
#         arity = length(program.program_inputs)
#         id = "modular_$(name)"
#         return new(program, name, arity, id, chromosomes_types, metalibrary)
#     end
# end

# function (modular_function::ModularFunction)(inputs...)
#     # In MAGE, the program inputs are replaced
#     replace_shared_inputs!(modular_function.program, [inputs...])

#     # When we evaluate a modular function, we need to reset its nodes values.
#     reset_program!(modular_function.program)

#     output = evaluate_program(
#         modular_function.program,
#         modular_function.chromosomes_types,
#         modular_function.metalibrary,
#     )
#     return output
# end


abstract type AbstractModularFunction <: AbstractFunction end

"""
    ModularFunction(
        program::AbstractDecodedProgram,
        name::Symbol,
        input_types::Vector{<:Type},
        output_type::Type,
        chromosomes_types::Vector{<:Type},
        metalibrary::MetaLibrary,
    )

Holds a decoded program that can be executed as if it were a single function.
It is type-aware and stores the expected input and output types.
"""
mutable struct ModularFunction <: AbstractModularFunction
    program::AbstractDecodedProgram
    name::Symbol
    arity::Int
    input_types::Vector{DataType}
    output_type::DataType
    id::String
    # For evaluation context
    chromosomes_types::Vector{<:Type}
    metalibrary::MetaLibrary

    function ModularFunction(
            program::AbstractDecodedProgram,
            name::Symbol,
            input_types::Vector{DataType},
            output_type::DataType,
            chromosomes_types::Vector{<:Type},
            metalibrary::MetaLibrary,
        )
        arity = length(program.program_inputs)
        id = "modular_$(name)"
        return new(
            program,
            name,
            arity,
            input_types,
            output_type,
            id,
            chromosomes_types,
            metalibrary,
        )
    end
end

"""
    (modular_function::ModularFunction)(inputs...)

Makes the ModularFunction callable. It takes the inputs, replaces the
placeholders in its internal program, and evaluates it.
"""
function (modular_function::ModularFunction)(inputs...)
    # In MAGE, the program inputs are replaced
    replace_shared_inputs!(modular_function.program, collect(inputs))

    # When we evaluate a modular function, we need to reset its nodes values.
    reset_program!(modular_function.program)

    # The last operation's result is the program's output
    output = evaluate_program(
        modular_function.program,
        modular_function.chromosomes_types,
        modular_function.metalibrary,
    )
    return output
end


"""
    Base.which(f::ModularFunction, t::Type{<:Tuple})

Overloads `which` for `ModularFunction` to allow the GP system to check for
type compatibility during mutation, as if it were a normal Julia function.
"""
function Base.which(f::ModularFunction, t::Type{<:Tuple})
    # `t` is a tuple of input types, e.g., Tuple{Int64, String}

    # 1. Check arity
    if length(t.parameters) != f.arity
        throw(MethodError(f, t))
    end

    # 2. Check types. The passed type must be a subtype of the expected type.
    expected_types = f.input_types
    for i in 1:f.arity
        if !(t.parameters[i] <: expected_types[i])
            throw(MethodError(f, t))
        end
    end

    # 3. Success. Return a mock object that looks like a `Method` instance.
    # The decoding logic in `decode.jl` only uses the `nargs` field to
    # determine how many inputs a function uses.
    return (nargs = f.arity + 2,) # +1 for the function itself, +1 for varargs convention
end
