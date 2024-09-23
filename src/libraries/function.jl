
function _get_parent_module_symbol(f::Function)
    return Symbol(parentmodule(f))
end

function _get_parent_module_symbol(f::AbstractManualDispatcher)
    return Symbol(parentmodule(f[1]))
end

function _get_name_from_likefn(f::Function)
    Symbol(f)
end
function _get_name_from_likefn(dp::AbstractManualDispatcher)
    dp.name
end

mutable struct FunctionWrapper{T} <: AbstractFunction
    name::Symbol
    parent_module::Symbol
    fn::LikeFunction
    caster::Union{Function,Nothing}
    fallback::Function

    """
    Function Wrapper with caster and fallback
    """
    function FunctionWrapper(
        fn::T,
        name::Symbol,
        caster::Union{Function,Nothing},
        fallback::Function,
    ) where {T<:LikeFunction}
        p_mod = _get_parent_module_symbol(fn)
        return new{T}(name, p_mod, fn, caster, fallback)
    end
end

"""
Function Wrapper with caster and fallback
"""
function FunctionWrapper(
    fn::T,
    caster::Union{Function,Nothing},
    fallback::Function,
) where {T<:LikeFunction}
    name = _get_name_from_likefn(fn)
    return FunctionWrapper(fn, name, caster, fallback)
end


"""
Function Wrapper with fallback.
"""
function FunctionWrapper(fn::T, fallback::Function) where {T<:LikeFunction}
    return FunctionWrapper(fn, nothing, fallback)
end

# from https://discourse.julialang.org/t/performance-of-hasmethod-vs-try-catch-on-methoderror/99827/23
const SafeFunctions = Dict{Type,IsGood}()
const SafeFunctionsLock = Base.ReentrantLock()
println("RECORD OF FNS : $SafeFunctions")

# Base.@nospecializeinfer function safe_call( not available in 1.9.3
function safe_call(@nospecialize(f::FunctionWrapper), @nospecialize(x::Tuple))
    global SafeFunctions, SafeFunctionsLock

    F = typeof(f)
    T = typeof(x)
    status = get(SafeFunctions, Tuple{F,T}, Undefined)
    if status == Good
        try
            tmp = f.fn(x...)
            if !isnothing(f.caster)
                tmp = f.caster(tmp)
            end
            return (tmp, true) # types are ok but might still error out bc of other pbs
        catch
            return (f.fallback(), true)
        end
    end
    status == Bad && return (f.fallback(), false) # If types are nok, always return fallback
    output = try
        tmp = f.fn(x...)
        if !isnothing(f.caster)
            tmp = f.caster(tmp)
        end
        (tmp, true)
    catch e
        if !isa(e, MethodError)
            (f.fallback(), true) # The method produced another runtime error, but arguments where accepted
        else
            (f.fallback(), false)
        end
    end
    return lock(SafeFunctionsLock) do
        tid = Threads.threadid()
        fn_name = Symbol(f)
        @debug "Holding safe call lock for $(fn_name) by $(tid). $(now())"
        if output[2]
            SafeFunctions[Tuple{F,T}] = Good
        else
            SafeFunctions[Tuple{F,T}] = Bad
        end
        @debug "Unlocking safe call lock for $(fn_name) by $(tid). $(now())"
        return output
    end
end

# function safe_call(f::F, x::T) where {F<:FunctionWrapper,T<:Tuple}
#     global SafeFunctions, SafeFunctionsLock
#     status = get(SafeFunctions, Tuple{F,T}, Undefined)
#     if status == Good
#         try
#             tmp = f.fn(x...)
#             if !isnothing(f.caster)
#                 tmp = f.caster(tmp)
#             end
#             return (tmp, true) # types are ok but might still error out bc of other pbs
#         catch
#             return (f.fallback(), true)
#         end
#     end
#     status == Bad && return (f.fallback(), false) # If types are nok, always return fallback
#     output = try
#         tmp = f.fn(x...)
#         if !isnothing(f.caster)
#             tmp = f.caster(tmp)
#         end
#         (tmp, true)
#     catch e
#         if !isa(e, MethodError)
#             (f.fallback(), true) # The method produced another runtime error, but arguments where accepted
#         else
#             (f.fallback(), false)
#         end
#     end
#     return lock(SafeFunctionsLock) do
#         tid = Threads.threadid()
#         fn_name = Symbol(f)
#         @debug "Holding safe call lock for $(fn_name) by $(tid). $(now())"
#         if output[2]
#             SafeFunctions[Tuple{F,T}] = Good
#         else
#             SafeFunctions[Tuple{F,T}] = Bad
#         end
#         @debug "Unlocking safe call lock for $(fn_name) by $(tid). $(now())"
#         return output
#     end
# end

# FASTER
# Base.@nospecializeinfer function evaluate_fn_wrapper( # not avail in 1.9.3
function evaluate_fn_wrapper(
    @nospecialize(fn_wrapper::FunctionWrapper),
    @nospecialize(inputs_::Vector{<:Any})
)
    # slow
    # @timeit_debug to "Eval fn. slow" begin
    #     output, flag = (nothing, false)
    #     if SAFE_CALL[]
    #         output, flag = safe_call(fn_wrapper, (inputs_...,))
    #     else
    #         output, flag = try
    #             tmp = fn_wrapper.fn(inputs_...)
    #             if !isnothing(fn_wrapper.caster)
    #                 tmp = fn_wrapper.caster(tmp)
    #             end
    #             (tmp, true) # types are ok but might still error out bc of other pbs
    #         catch
    #             (fn_wrapper.fallback(), true)
    #         end
    #     end
    # end
    @timeit_debug to "Eval fn. fast" begin
        output, flag = (nothing, false)
        cast = !isnothing(fn_wrapper.caster)
        begin
            if SAFE_CALL[]
                output, flag = safe_call(fn_wrapper, (inputs_...,))
            else
                output = try
                    @timeit_debug to "Eval fn Ok $(fn_wrapper.name)" call_fn_wrap(
                        fn_wrapper,
                        inputs_,
                        Val(cast),
                    )
                catch e
                    if e isa MethodError
                        @warn "$(fn_wrapper.name) got a MethodError with inputs of type $(typeof.(inputs_))"
                        if isdefined(Main, :Infiltrator)
                            Main.infiltrate(@__MODULE__, Base.@locals, @__FILE__, @__LINE__)
                        end

                        # println(e)
                    end
                    @timeit_debug to "Eval fn Nok $(fn_wrapper.name)" fn_wrapper.fallback()
                end
            end
        end
    end
    return output
end

@inline function call_fn_wrap(
    @nospecialize(fn_wrapper::FunctionWrapper),
    @nospecialize(inputs),
    ::Val{true},
)
    fn_wrapper.caster(fn_wrapper.fn(inputs...))
end
@inline function call_fn_wrap(
    @nospecialize(fn_wrapper::FunctionWrapper),
    @nospecialize(inputs),
    ::Val{false},
)
    fn_wrapper.fn(inputs...)
end

# function evaluate_fn_wrapper(fn_wrapper::FunctionWrapper, inputs_::Vector{<:Any})
#     # inputs = deepcopy(inputs_) # safety
#     output = safe_call(fn_wrapper, (inputs_...,))
#     return output[1]
# end
