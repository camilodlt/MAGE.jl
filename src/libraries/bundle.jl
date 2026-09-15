abstract type AbstractFunctionBundle end

"""
    FunctionBundle(fallback::Function)
    FunctionBundle(caster::Function, fallback::Function)
    FunctionBundle(caster::Function, fallback::Function, last_fallback::Function)

A themed group of operators, the unit libraries are assembled from.

A bundle owns a vector of [`FunctionWrapper`](@ref)s plus the two policies they
share: a `caster`, applied to a function's result to force it into the
chromosome's type, and a `fallback`, returned when a call throws. Populate it
with `append_method!` and combine bundles into a [`Library`](@ref).

Supports `length`, `size`, iteration, indexing by position (`bundle[1]`) and by
name (`bundle[:grad_magnitude]`, `nothing` if absent).

Both policies can be retargeted after the fact, which is how the premade
libraries reuse one bundle across several chromosome types:

```julia
b = deepcopy(bundle_number_arithmetic)
update_caster!(b, float_caster)
update_fallback!(b, () -> 0.0)
```

# Writing functions for a bundle

Because a node calls `fn(all_inputs..., all_params...)`, every function in a
bundle must accept a trailing `args...` and swallow the extra arguments:

```julia
number_sum(a::Number, b::Number, args...) = a + b
```

For the same reason, two methods of the *same* name that differ only in arity
cannot both live in a bundle: the widest one would always shadow the narrower.
Give them different names instead.

Whether a function is applicable to a node is decided with `hasmethod`, and the
decoder uses `which` to determine how many inputs the node consumes — see
[`ManualDispatcher`](@ref) for the escape hatch used by anonymous, factory-built
methods.

# Leading functions for a new output type

When a bundle is the first/basic bundle for a new chromosome output type, keep
the established leading-function convention used by the numeric, list, and 2D
image libraries:

1. Append a one-input identity/pass-through function first.
2. Append a parameter-free typed constructor second. The constructor must still
   accept trailing `args...`; examples are `ret_1`, `new_list`, and `ones_2D`.

This gives evolution both a way to preserve a value and a terminal-like way to
create a valid value without depending on an input of the same type. Extension
bundles do not need to repeat these functions when their output library already
starts with a basic bundle.
"""
struct FunctionBundle <: AbstractFunctionBundle
    functions::Vector{FunctionWrapper}
    caster::Union{Function, Nothing}
    fallback::Function
    last_fallback::Function # deprecate it TODO
    function FunctionBundle(caster::Function, fallback::Function, last_fallback::Function)
        return new(Vector{FunctionWrapper}(), caster, fallback, last_fallback)
    end
    function FunctionBundle(caster::Function, fallback::Function)
        return new(Vector{FunctionWrapper}(), caster, fallback, fallback)
    end
    function FunctionBundle(fallback::Function)
        return new(Vector{FunctionWrapper}(), nothing, fallback, fallback)
    end
end
Base.size(bundle::FunctionBundle) = length(bundle.functions)
Base.length(bundle::FunctionBundle) = length(bundle.functions)
Base.getindex(bundle::FunctionBundle, i::Int) = bundle.functions[i]
function Base.getindex(bundle::FunctionBundle, name::Symbol)
    for fnw in bundle.functions
        if fnw.name == name
            return fnw
        end
    end
    return
end

Base.iterate(bundle::FunctionBundle, state = 1) =
    state > length(bundle.functions) ? nothing : (bundle.functions[state], state + 1)

function _verify_last_arg_is_vararg!(fn::Function)
    ms = methods(fn)

    for m in ms
        sig = m.sig
        if sig isa UnionAll
            sig = Base.unwrap_unionall(sig)
            # sig = sig.body
        end
        @assert sig.types[end] == Vararg{Any} "$fn"
    end
    return
end
function _verify_last_arg_is_vararg!(m::Method)
    sig = m.sig
    if sig isa UnionAll
        sig = Base.unwrap_unionall(sig)
    end
    return @assert sig.types[end] == Vararg{Any} "$m"
end
function _verify_last_arg_is_vararg!(m::ManualDispatcher)
    fns = m.functions
    for fn in fns
        _verify_last_arg_is_vararg!(fn)
    end
    return
end
function _verify_last_arg_is_vararg!(m::AbstractFunction)
    methods_ = methods(m)
    _verify_last_arg_is_vararg!.(methods_)
    return
end

function append_method!(
        bundle::FunctionBundle,
        fn::LikeFunction;
        description::AbstractString = "",
    )
    fn_wrapped = FunctionWrapper(fn, bundle.caster, bundle.fallback; description = description)
    return push!(bundle.functions, fn_wrapped)
end
function append_method!(
        bundle::FunctionBundle,
        fn::LikeFunction,
        name::Symbol;
        description::AbstractString = "",
    )
    fn_wrapped =
        FunctionWrapper(fn, name, bundle.caster, bundle.fallback; description = description)
    return push!(bundle.functions, fn_wrapped)
end
function append_method!(
        bundle::FunctionBundle,
        dp::AbstractManualDispatcher;
        description::AbstractString = "",
    )
    fn_wrapped =
        FunctionWrapper(dp, dp.name, bundle.caster, bundle.fallback; description = description)
    return push!(bundle.functions, fn_wrapped)
end

"""
    _unique_names_in_bundle(b::FunctionBundle)

Check that no two functions in `b` share a name. Names are how bundles are
indexed and how used-function sets are computed, so duplicates are a bug.
"""
function _unique_names_in_bundle(b::FunctionBundle)::Bool
    n = [fw.name for fw in b.functions]
    return length(n) == length(Set(n))
end

"""
    update_caster!(b::FunctionBundle, new_caster::Function)

Point every function of `b` at `new_caster`.

The caster runs on each result and coerces it into the chromosome's type — for
instance [`float_caster`](@ref) for a `Float64` chromosome. Mutates the bundle
in place, so `deepcopy` a shared bundle first.
"""
function update_caster!(b::FunctionBundle, new_caster::Function)
    _validate_bundle(b)
    for fn in b.functions
        fn.caster = new_caster
    end
    return
end
"""
    update_fallback!(b::FunctionBundle, new_fallback::Function)

Point every function of `b` at `new_fallback`.

The fallback is what a node returns when its function throws, which is what
keeps an evolved program total: a division by zero yields the fallback rather
than killing the run. Mutates the bundle in place.
"""
function update_fallback!(b::FunctionBundle, new_fallback::Function)
    _validate_bundle(b)
    for fn in b.functions
        fn.fallback = new_fallback
    end
    return
end

function _validate_bundle(b::FunctionBundle)
    return @assert length(b) > 0 "Bundle is empty!"
end
