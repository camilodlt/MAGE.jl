# Concrete type groups; abstract or uncertain graphs retain the Any IR.
struct TypedPopulationRef{G,T}
    kind::UInt8 # 0: input, 1: temporary (including constants)
    index::Int
end
abstract type AbstractTypedPopulationStep end
struct TypedPopulationCall{F,C,B,N,T,G,R,RP} <: AbstractTypedPopulationStep
    fn::F
    caster::C
    fallback::B
    refs::R
    policy::RP
    wrapper::FunctionWrapper
    index::Int
end
struct TypedPopulationConstant{T,G} <: AbstractTypedPopulationStep
    value::T
    index::Int
end
mutable struct TypedPopulationTile
    firstrow::Int
    count::Int
end
struct TypedPopulationWorkspace{V,O}
    program::PopulationSequentialProgram
    steps::Vector{AbstractTypedPopulationStep}
    outputs::O
    values::V # Ref to tuple of concrete matrices: avoid boxing at step dispatch
    batch_size::Int
    tile::TypedPopulationTile
end
@inline function _typed_read(r::TypedPopulationRef{G,T}, args, values, row) where {G,T}
    return (r.kind == 0 ? args[r.index] : values[][G][row,r.index])::T
end
@inline _typed_cast(::Nothing, x) = x
@inline _typed_cast(c, x) = c(x)
@inline function _typed_call(s::TypedPopulationCall{F,C,B,N,T,G,R,RP}, xs) where {F,C,B,N,T,G,R,RP}
    value = try
        _typed_cast(s.caster, _invoke_fn(s.fn, xs...))
    catch
        s.fallback()
    end
    # The assertion remains outside try/catch, exactly as in public safe_call.
    if !(s.policy isa NoTypeAssertion)
        @assert value isa s.policy "$(s.wrapper.name) returned $(typeof(value)); expected $(s.policy)"
    end
    return value::T
end
function _typed_batch!(s::TypedPopulationCall{F,C,B,N,T,G,R,RP}, values, samples, tile) where {F,C,B,N,T,G,R,RP}
    for row in 1:tile.count
        args = samples[tile.firstrow+row-1]
        xs = ntuple(i -> _typed_read(s.refs[i], args, values, row), Val(N))
        values[][G][row,s.index] = _typed_call(s,xs)
    end
end
function _typed_batch!(s::TypedPopulationConstant{T,G}, values, samples, tile) where {T,G}
    for row in 1:tile.count
        values[][G][row,s.index] = s.value
    end
end

"""
    TypedPopulationWorkspace(program; batch_size=128)

Prepare reusable typed storage, or return `nothing` when the graph cannot safely
use concrete type groups. Rebuild after changing the program or its wrappers.
A workspace is thread-local; do not share it between concurrent evaluations.
Cached wrappers and SAFE_CALL's method-status cache retain the generic path.
"""
function TypedPopulationWorkspace(g::PopulationSequentialProgram; batch_size::Int=128)
    batch_size > 0 || throw(ArgumentError("batch_size must be positive"))
    SAFE_CALL[] && return nothing
    types = unique(Type[g.input_types; [s.return_type for s in g.steps]])
    all(isconcretetype,types) || return nothing
    all(o -> length(o)==1,g.individual_outputs) || return nothing
    # Each reference carries its group and value type in its concrete isbits type.
    counts = zeros(Int,length(types))
    locations = Tuple{Int,Int}[]
    for s in g.steps
        group = findfirst(==(s.return_type),types)
        counts[group] += 1
        push!(locations,(group,counts[group]))
    end
    function ref(r)
        if r isa PopulationSequentialInputRef
            group = findfirst(==(r.type),types)
            group === nothing && return nothing
            return TypedPopulationRef{group,r.type}(0,r.input_index)
        end
        group,index = locations[r.step_index]
        types[group] === r.type || return nothing
        return TypedPopulationRef{group,r.type}(1,index)
    end
    steps = AbstractTypedPopulationStep[]
    for (k,s) in enumerate(g.steps)
        T = s.return_type
        group,index = locations[k]
        if s isa PopulationSequentialConstantStep
            typeof(s.value) === T || return nothing
            push!(steps,TypedPopulationConstant{T,group}(s.value,index))
        else
            isnothing(s.fn.cache) || return nothing
            input_types = [r.type for r in s.inputs]
            all(isconcretetype,input_types) || return nothing
            R = Core.Compiler.return_type(_invoke_fn,Tuple{typeof(s.fn.fn),input_types...})
            if !isnothing(s.fn.caster)
                isconcretetype(R) || return nothing
                R = Core.Compiler.return_type(s.fn.caster,Tuple{R})
            end
            R === T || return nothing
            Core.Compiler.return_type(s.fn.fallback,Tuple{}) === T || return nothing
            refs = Tuple(ref.(s.inputs))
            any(isnothing,refs) && return nothing
            push!(steps,TypedPopulationCall{typeof(s.fn.fn),typeof(s.fn.caster),typeof(s.fn.fallback),length(refs),T,group,typeof(refs),s.return_type_policy isa Type ? Type{s.return_type_policy} : typeof(s.return_type_policy)}(
                s.fn.fn,s.fn.caster,s.fn.fallback,refs,s.return_type_policy,s.fn,index))
        end
    end
    outputs = [ref(only(o)) for o in g.individual_outputs]
    any(isnothing,outputs) && return nothing
    # Direct-output dispatch uses a concrete output group; heterogeneous outputs
    # retain the generic API rather than introducing boxing per matrix element.
    isempty(outputs) || all(r -> typeof(r)===typeof(first(outputs)),outputs) || return nothing
    outputs = isempty(outputs) ? TypedPopulationRef{1,Float64}[] : typeof(first(outputs))[outputs...]
    values = Tuple(Matrix{T}(undef,batch_size,counts[i]) for (i,T) in enumerate(types))
    return TypedPopulationWorkspace(g,steps,outputs,Ref(values),batch_size,TypedPopulationTile(1,0))
end

function _typed_population_into!(P,g,samples,w::TypedPopulationWorkspace)
    w.program === g && length(w.steps)==length(g.steps) && length(w.outputs)==length(g) || throw(ArgumentError("workspace does not match program"))
    for firstrow in 1:w.batch_size:length(samples)
        count = min(w.batch_size,length(samples)-firstrow+1)
        w.tile.firstrow = firstrow
        w.tile.count = count
        for k in eachindex(w.steps)
            _typed_batch!(w.steps[k],w.values,samples,w.tile)
        end
        for row in 1:count
            args = samples[firstrow+row-1]
            for i in eachindex(w.outputs)
                P[i,firstrow+row-1] = _typed_read(w.outputs[i],args,w.values,row)
            end
        end
    end
    P
end
function _generic_population_into!(P,g,samples)
    w = PopulationSequentialWorkspace(g)
    for (j,args) in enumerate(samples)
        outputs = evaluate_population_sequential_program(g,args...;workspace=w)
        for i in eachindex(outputs)
            P[i,j] = only(outputs[i])
        end
    end
    P
end
"""
    evaluate_population_into!(P::Matrix, program, samples; workspace=nothing,
                              batch_size=128, check=false)

Write one scalar output per individual to `P[individual, sample]`. Concrete
graphs use typed tuple calls and tiled storage; unsupported graphs
use the unchanged generic interpreter. Pass a prepared `TypedPopulationWorkspace`
for allocation-free evaluation of allocation-free primitives (`batch_size=1`
selects scalar execution). `check=true` asserts `===` against generic outputs,
including signed zeros and NaNs. Multi-output graphs require the old API.
"""
function evaluate_population_into!(P::Matrix,g::PopulationSequentialProgram,samples::AbstractVector{<:Tuple};workspace=nothing,batch_size::Int=128,check::Bool=false)
    size(P)==(length(g),length(samples)) || throw(DimensionMismatch("expected individuals × samples"))
    g.has_input_layout || throw(ArgumentError("empty population"))
    all(o -> length(o)==1,g.individual_outputs) || throw(ArgumentError("matrix API requires one output per individual"))
    all(a -> length(a)==length(g.input_types),samples) || throw(DimensionMismatch("sample input count"))
    w = isnothing(workspace) ? TypedPopulationWorkspace(g;batch_size) : workspace
    compatible = !SAFE_CALL[] && !isnothing(w) && all(a -> all(i -> typeof(a[i])===g.input_types[i],eachindex(a)),samples)
    if compatible
        _typed_population_into!(P,g,samples,w)
    else
        _generic_population_into!(P,g,samples)
    end
    if check
        expected = similar(P)
        _generic_population_into!(expected,g,samples)
        for i in eachindex(P)
            @assert P[i] === expected[i] "population evaluator mismatch at linear index $i"
        end
    end
    return P
end
