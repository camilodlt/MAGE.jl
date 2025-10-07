abstract type AbstractManualDispatcher{T} <: Function end
abstract type AbstractSequentialManualDispatcher{T <: Tuple} <: AbstractManualDispatcher{T} end
abstract type AbstractFunctionLookup end
abstract type AbstractFunction end

@enum IsGood::Int8 begin
    Good
    Bad
    Undefined
end

LikeFunction = Union{Function, <:AbstractManualDispatcher, AbstractFunction}
# FunctionTypePair = Tuple{<:LikeFunction,<:Tuple{Vararg{Type}}}
ArgsTypes = Tuple{Vararg{<:Type}}

function _create_fn_lookup()
    SafeFunctions = Dict{Type, IsGood}()
    SafeFunctionsLock = Base.ReentrantLock()
    return (SafeFunctions, SafeFunctionsLock)
end

struct FunctionLookup <: AbstractFunctionLookup
    lookup::Dict{Type, IsGood}
    lock::Base.ReentrantLock
end

function FunctionLookup()
    lk, lock = _create_fn_lookup()
    return FunctionLookup(lk, lock)
end

function _exist_in_lookup(
        lk::FunctionLookup,
        fn::F,
        types::T,
    ) where {F <: LikeFunction, T <: ArgsTypes}
    tt = Tuple{types...}
    return get(lk.lookup, Tuple{F, tt}, Undefined)
end

function _exist_in_lookup(
        lk::AbstractFunctionLookup,
        fn::F,
        types::T,
    ) where {F <: LikeFunction, T <: Tuple}
    throw(ErrorException("Not implemented"))
end

function _pre_update_fn_lookup(
        lk::FunctionLookup,
        fn::F,
        types::T,
    ) where {F <: Function, T <: Tuple}

    type_acceptance_exists = _exist_in_lookup(lk, fn, types)
    if type_acceptance_exists == Undefined
        fn_would_work_on_types = Base.hasmethod(fn, types)
        tt = Tuple{types...}
        if fn_would_work_on_types
            lock(lk.lock) do
                lk.lookup[Tuple{F, tt}] = Good
            end
            return Good
        else
            lock(lk.lock) do
                lk.lookup[Tuple{F, tt}] = Bad
            end
            return Bad
        end
    end
    return type_acceptance_exists
end

function _pre_update_fn_lookup(
        lk::AbstractFunctionLookup,
        fn::F,
        types::T,
    ) where {F <: Function, T <: Tuple}
    throw(ErrorException("Not implemented"))
end

"""
ManualDispatcher

Dispatches on the first type matching functions inside the dispatcher.
"""
struct ManualDispatcher{T} <: AbstractSequentialManualDispatcher{T}
    functions::T
    name::Symbol
    lk::FunctionLookup
end

"""
    ManualDispatcher(fns::Tuple{Vararg{<:Function}}, name::Symbol)

Constructor
"""
function ManualDispatcher(fns::Tuple{Vararg{<:Function}}, name::Symbol)
    lk = FunctionLookup()
    new_fns = (fns..., error_fn)
    tt = Tuple{typeof.(new_fns)...}
    return ManualDispatcher{tt}(new_fns, name, lk)
end

Base.length(dp::ManualDispatcher) = length(dp.functions)
Base.getindex(dp::ManualDispatcher, i::Int) = dp.functions[i]
Base.iterate(dp::ManualDispatcher, state = 1) =
    state > length(dp.functions) ? nothing : (dp.functions[state], state + 1)
Symbol(dp::ManualDispatcher) = dp.name

"""

types: (Int, Int) for example
"""
function Base.which(dp::ManualDispatcher, types::T) where {T <: ArgsTypes}
    for fn in dp.functions
        type_acceptance = _pre_update_fn_lookup(dp.lk, fn, types)
        if type_acceptance == Good
            m = methods(fn)
            length(m) > 1 &&
                @warn "Function $fn in $(dp.name) with more than one method given types : $types"
            return m[1]
        end
    end
    return
end

error_fn(args...) = throw(error("No function with that signature found in ManualDispatcher"))

function is_ok(x, lk, types)
    type_acceptance = _pre_update_fn_lookup(lk, x, types)
    return type_acceptance == Good
end

roll(::Tuple{}, lk, types) = error_fn

function roll(tuple_of_fns, lk, types)
    if is_ok(tuple_of_fns[1], lk, types)
        return tuple_of_fns[1]
    else
        roll(Base.tail(tuple_of_fns), lk, types)
    end
end

function _which_fn_in_manual_dispatcher(dp::ManualDispatcher{TT}, types::T) where {TT, T <: ArgsTypes}
    return roll(dp.functions, dp.lk, types)
end

"""

types: (Int, Int) for example
"""
function Base.hasmethod(dp::ManualDispatcher, types::T) where {T <: ArgsTypes}
    for fn in dp.functions
        type_acceptance = _pre_update_fn_lookup(dp.lk, fn, types)
        type_acceptance == Good && return true
    end
    return false
end

function (dp::ManualDispatcher{FT})(inputs::T) where {T <: Tuple{Vararg{Any}}, FT}
    tt = tuple(T.parameters...)
    fn = _which_fn_in_manual_dispatcher(dp, tt)
    return fn(inputs...)
end

function (dp::ManualDispatcher{FT})(inputs::Vararg{Any}) where {FT}
    tt = typeof.(inputs)
    fn = _which_fn_in_manual_dispatcher(dp, tt)
    return fn(inputs...)
end
