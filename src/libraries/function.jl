
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


# OLD
mutable struct FunctionWrapperLegacy <: AbstractFunction
    name::Symbol
    parent_module::Symbol
    fn::Function
    caster::Union{Function,Nothing}
    fallback::Function
    function FunctionWrapperLegacy(
        fn::Function,
        caster::Union{Function,Nothing},
        fallback::Function,
    )
        return new(Symbol(fn), Symbol(parentmodule(fn)), fn, caster, fallback)
    end
    function FunctionWrapperLegacy(fn::Function, fallback::Function)
        return new(Symbol(fn), Symbol(parentmodule(fn)), fn, nothing, fallback)
    end
    function FunctionWrapperLegacy(
        fn::Function,
        name::Symbol,
        caster::Union{Function,Nothing},
        fallback::Function,
    )
        return new(name, Symbol(parentmodule(fn)), fn, caster, fallback)
    end
end

# from https://discourse.julialang.org/t/performance-of-hasmethod-vs-try-catch-on-methoderror/99827/23

const SafeFunctions = Dict{Type,IsGood}()
const SafeFunctionsLock = Threads.SpinLock()
println("RECORD OF FNS : $SafeFunctions")

function safe_call(f::F, x::T) where {F<:FunctionWrapper,T<:Tuple}
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
    return lock(SafeFunctionsLock) do
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
        if output[2]
            SafeFunctions[Tuple{F,T}] = Good
        else
            SafeFunctions[Tuple{F,T}] = Bad
        end
        return output
    end
end

# FASTER
function evaluate_fn_wrapper(fn_wrapper::FunctionWrapper, inputs_::Vector{<:Any})
    # inputs = deepcopy(inputs_) # safety
    output = safe_call(fn_wrapper, (inputs_...,))
    return output[1]
end

# NORMAL EVAL FN
function evaluate_fn_wrapper_legacy(fn_wrapper::FunctionWrapper, inputs_::Vector{<:Any})
    inputs = deepcopy(inputs_) # safety
    output = let output = nothing
        types = [typeof(i) for i in inputs]
        if Base.hasmethod(fn_wrapper.fn, types)
            try
                output = fn_wrapper.fn(inputs...)
                if !isnothing(fn_wrapper.caster)
                    output = fn_wrapper.caster(output)
                end
            catch e
                @info "Exception during fn eval. fn : $(fn_wrapper.name). inputs : $(inputs)"
                @info e
            end
        end
        if isnothing(output)
            output = fn_wrapper.fallback()
        end
        output
    end
    return output
end
