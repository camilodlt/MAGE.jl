#################### FUNCTION WRAPPER ######################
# wraps a function with it's caster, fallback and cache

"""
    _invoke_fn(fn, inputs...)

Generic evaluation-path call: plain call syntax for everything except
`SourceBackedFunction`s (LLM-generated functions), which get a specialized
method added in `llm_generated_functions.jl` (included later, once that type
exists) routing through `_call_runtime_fn(fn, Val(false), inputs...)` --
`Val(false)` skips `invokelatest`'s per-call overhead, safe specifically for
this evaluation path (see that method's docstring for why it's only wired up
here and not for the load/validate call path, which still goes through
`SourceBackedFunction`'s default call operator, `Val(true)`).
"""
@inline _invoke_fn(fn, inputs...) = fn(inputs...)

function _get_parent_module_symbol(f::AbstractFunction)
    return typeof(f) |> parentmodule |> Symbol
end

function _get_parent_module_symbol(f::Function)
    return Symbol(parentmodule(f))
end

function _get_parent_module_symbol(f::AbstractManualDispatcher)
    return Symbol(parentmodule(f[1]))
end

function _get_name_from_likefn(f::Function)
    return Symbol(f)
end
function _get_name_from_likefn(dp::AbstractManualDispatcher)
    return dp.name
end

function _default_wrapper_description(name::Symbol)::String
    return "Performs $(name) on the provided inputs and returns the computed output."
end

function _sanitize_wrapper_description(name::Symbol, description::AbstractString)::String
    raw = strip(String(description))
    if isempty(raw)
        return _default_wrapper_description(name)
    end
    lines = [strip(line) for line in split(raw, '\n') if !isempty(strip(line))]
    if isempty(lines)
        return _default_wrapper_description(name)
    end
    return join(lines[1:min(length(lines), 3)], "\n")
end

function _runtime_arg_tuple_type(inputs_)
    return Tuple{map(typeof, inputs_)...}
end

function _declared_input_types_for_debug(fn_like)
    if hasfield(typeof(fn_like), :input_types)
        return try
            getfield(fn_like, :input_types)
        catch
            nothing
        end
    end
    return nothing
end

function _declared_argument_names_for_debug(fn_like)
    if hasfield(typeof(fn_like), :argument_names)
        return try
            getfield(fn_like, :argument_names)
        catch
            nothing
        end
    end
    return nothing
end

function _which_debug_string(fn_like, tuple_type)
    try
        return string(which(fn_like, tuple_type))
    catch err
        return "ERROR: " * sprint(showerror, err)
    end
end

function _hasmethod_debug_value(fn_like, tuple_type)
    try
        return Base.hasmethod(fn_like, tuple_type)
    catch err
        return "ERROR: " * sprint(showerror, err)
    end
end

function _method_signatures_for_debug(fn_like)
    try
        return sprint(show, methods(fn_like))
    catch err
        return "ERROR: " * sprint(showerror, err)
    end
end

mutable struct FunctionWrapper{T} <: AbstractFunction
    name::Symbol
    description::String
    parent_module::Symbol
    fn::LikeFunction
    caster::Union{Function, Nothing}
    fallback::Function
    cache::Union{Nothing, <:LRU}
    function FunctionWrapper(
            name::Symbol,
            description::AbstractString,
            parent_module::Symbol,
            fn::T,
            caster::Union{Function, Nothing},
            fallback::Function,
            cache::Union{Nothing, <:LRU}
        ) where {T <: LikeFunction}
        if !isnothing(cache)
            @info "Using Cache $cache for fn $name"
        end
        desc = _sanitize_wrapper_description(name, description)
        return new{T}(name, desc, parent_module, fn, caster, fallback, cache)
    end
end

"""
Function Wrapper with caster and fallback
"""
function FunctionWrapper(
        fn::T,
        name::Symbol,
        caster::Union{Function, Nothing},
        fallback::Function;
        cache_config::AbstractCacheConfig = NoCacheConfig(),
        description::AbstractString = "",
    ) where {T <: LikeFunction}
    p_mod = _get_parent_module_symbol(fn)
    cache = _create_fn_cache(cache_config) # nothing if NoCacheConfig
    return FunctionWrapper(name, description, p_mod, fn, caster, fallback, cache)
end

"""
Function Wrapper with caster and fallback
"""
function FunctionWrapper(
        fn::T,
        caster::Union{Function, Nothing},
        fallback::Function;
        cache_config::AbstractCacheConfig = NoCacheConfig(),
        description::AbstractString = "",
    ) where {T <: LikeFunction}
    name = _get_name_from_likefn(fn)
    return FunctionWrapper(fn, name, caster, fallback; cache_config, description = description)
end


"""
Function Wrapper with fallback (no caster)
"""
function FunctionWrapper(
        fn::T, fallback::Function;
        cache_config::AbstractCacheConfig = NoCacheConfig(),
        description::AbstractString = "",
    ) where {T <: LikeFunction}
    return FunctionWrapper(fn, nothing, fallback; cache_config, description = description)
end

"""
    NoTypeAssertion()

Readable sentinel for `safe_call(...; return_type=NoTypeAssertion())`. It keeps
the caster/fallback behavior active while skipping the final return-type check.
"""
struct NoTypeAssertion end

# from https://discourse.julialang.org/t/performance-of-hasmethod-vs-try-catch-on-methoderror/99827/23
const SafeFunctions = Dict{Type, IsGood}()
const SafeFunctionsLock = Base.ReentrantLock()
println("RECORD OF FNS : $SafeFunctions")

# Base.@nospecializeinfer function safe_call( not available in 1.9.3
function safe_call(@nospecialize(f::FunctionWrapper), @nospecialize(x::Tuple))
    global SafeFunctions, SafeFunctionsLock

    F = typeof(f)
    T = typeof(x)
    status = get(SafeFunctions, Tuple{F, T}, Undefined)
    if status == Good
        try
            tmp = _invoke_fn(f.fn, x...)
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
        tmp = _invoke_fn(f.fn, x...)
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
            SafeFunctions[Tuple{F, T}] = Good
        else
            SafeFunctions[Tuple{F, T}] = Bad
        end
        @debug "Unlocking safe call lock for $(fn_name) by $(tid). $(now())"
        return output
    end
end

"""
    safe_call(fn, inputs...; return_type=NoTypeAssertion())

Public value-returning safe call used by sequential programs. It delegates
caster/fallback behavior to `evaluate_fn_wrapper`, then optionally checks the
returned value type so rendered sequential code and runtime semantics use the
same call shape.
"""
function safe_call(
        @nospecialize(f::FunctionWrapper),
        inputs...;
        return_type = NoTypeAssertion(),
    )
    output = evaluate_fn_wrapper(f, Any[inputs...])
    return safe_call_return_type_assertion(output, return_type, f, inputs)
end

function safe_call_return_type_assertion(
        @nospecialize(output),
        ::NoTypeAssertion,
        @nospecialize(::FunctionWrapper),
        @nospecialize(::Tuple),
    )
    return output
end

function safe_call_return_type_assertion(
        @nospecialize(output),
        @nospecialize(return_type::Type),
        @nospecialize(f::FunctionWrapper),
        @nospecialize(inputs::Tuple),
    )
    @assert output isa return_type "$(f.name) returned $(typeof(output)) for inputs $(typeof.(inputs)); expected $return_type"
    return output
end

# FASTER
# Base.@nospecializeinfer function evaluate_fn_wrapper( # not avail in 1.9.3
function evaluate_fn_wrapper(
        @nospecialize(fn_wrapper::FunctionWrapper),
        @nospecialize(inputs_::Vector{<:Any})
    )
    @timeit_debug to "Eval fn. fast" begin
        output, flag = (nothing, false)
        cast = !isnothing(fn_wrapper.caster)
        begin
            if SAFE_CALL[]
                output, flag = safe_call(fn_wrapper, (inputs_...,))
            else
                output = try
                    if !isnothing(fn_wrapper.cache)
                        get!(fn_wrapper.cache, hash(inputs_)) do
                            t = @elapsed @timeit_debug to "Eval fn Ok $(fn_wrapper.name)" res = call_fn_wrap(
                                fn_wrapper,
                                inputs_,
                                Val(cast),
                            )
                            if t > 0.5
                                @warn "Function $(fn_wrapper.name) took $t"
                            end
                            res
                        end
                    else
                        t = @elapsed @timeit_debug to "Eval fn Ok $(fn_wrapper.name)" res = call_fn_wrap(
                            fn_wrapper,
                            inputs_,
                            Val(cast),
                        )
                        if t > 0.5
                            @warn "Function $(fn_wrapper.name) took $t"
                        end
                        res
                    end
                catch e
                    if e isa MethodError
                        if isdefined(Main, :Infiltrator)
                            Main.infiltrate(@__MODULE__, Base.@locals, @__FILE__, @__LINE__)
                        end
                        tuple_type = _runtime_arg_tuple_type(inputs_)
                        @warn "$(fn_wrapper.name) got a MethodError with inputs of type $(typeof.(inputs_))" fn_name =
                            fn_wrapper.name parent_module =
                            fn_wrapper.parent_module real_input_types =
                            typeof.(inputs_) runtime_tuple_type =
                            tuple_type declared_argument_names =
                            _declared_argument_names_for_debug(fn_wrapper.fn) declared_input_types =
                            _declared_input_types_for_debug(fn_wrapper.fn) hasmethod_on_runtime_types =
                            _hasmethod_debug_value(fn_wrapper.fn, tuple_type) which_on_runtime_types =
                            _which_debug_string(fn_wrapper.fn, tuple_type) available_methods =
                            _method_signatures_for_debug(fn_wrapper.fn)
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
    @debug "Running fn : $(fn_wrapper.name)"
    pre = _invoke_fn(fn_wrapper.fn, inputs...)
    if isnothing(pre)
        if isdefined(Main, :Infiltrator)
            Main.infiltrate(@__MODULE__, Base.@locals, @__FILE__, @__LINE__)
        end
    end
    o = fn_wrapper.caster(pre)
    @debug "End Running fn : $(fn_wrapper.name)"
    return o
end
@inline function call_fn_wrap(
        @nospecialize(fn_wrapper::FunctionWrapper),
        @nospecialize(inputs),
        ::Val{false},
    )
    @debug "Running fn : $(fn_wrapper.name)"
    o = _invoke_fn(fn_wrapper.fn, inputs...)
    @debug "End Running fn : $(fn_wrapper.name)"
    return o
end
