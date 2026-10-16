# ADF bodies are inlined into native call frames rather than flattened into the
# population DAG: a body assertion or throwing fallback must abort the complete
# call, including all subsequent body steps. The generic IR remains the oracle.
struct NativeADFRef{K,I} end
struct NativeADFCall{F,C,B,R,P}
    fn::F
    caster::C
    fallback::B
    refs::R
    policy::P
    wrapper::FunctionWrapper
end
struct NativeADFConstant{T}
    value::T
end
struct NativeADFFrame{N,S,O} <: Function
    steps::S
    output::O
end
struct NativeADFIdentity <: Function end
@inline function (::NativeADFIdentity)(xs...)
    @assert length(xs) >= 1 "Empty ADF slot needs one input for identity behavior"
    xs[1]
end

# A nested ADF that could not become a native frame is still called as a slot;
# asserting its declared output type keeps the enclosing frame type-stable.
@inline _native_adf_apply(fn, xs) = fn(xs...)
@inline _native_adf_apply(fn::ADFSlotFunction, xs) = fn(xs...)::fn.output_type

@inline function _native_adf_call(s::NativeADFCall, xs)
    value = try
        _apply_caster(s.caster, _native_adf_apply(s.fn, xs))
    catch
        s.fallback()
    end
    # Outside catch: the enclosing ADF call catches this assertion, not this step.
    if !(s.policy isa NoTypeAssertion)
        @assert value isa s.policy "$(s.wrapper.name) returned $(typeof(value)); expected $(s.policy)"
    end
    value
end

# Encode ref positions in types, so the generated code consists solely of local
# assignments and concrete calls. No eval, world-age changes, Any arrays, or
# per-row graph traversal. Julia can inline nested frames and their primitives.
_native_adf_ref(r::SequentialProgramInputRef) = NativeADFRef{0,r.input_index}()
_native_adf_ref(r::SequentialTmpRef) = NativeADFRef{1,r.tmp_index}()
function _native_adf_ref_expr(::Type{NativeADFRef{K,I}}) where {K,I}
    K == 0 ? :(xs[$I]) : Symbol(:v,I)
end
@generated function (frame::NativeADFFrame{N,S,O})(xs...) where {N,S,O}
    body = Expr(:block, :(@assert length(xs) == $N "ADF input count mismatch"))
    for (i,T) in enumerate(S.parameters)
        step = :(frame.steps[$i])
        value = if T <: NativeADFConstant
            :($step.value)
        else
            refs = T.parameters[4]
            args = Expr(:tuple, (_native_adf_ref_expr(R) for R in refs.parameters)...)
            :(_native_adf_call($step, $args))
        end
        push!(body.args, :($(Symbol(:v,i)) = $value))
    end
    push!(body.args, Expr(:return, _native_adf_ref_expr(O)))
    body
end

const _NATIVE_ADF_CACHE = WeakKeyDict{ADFSlotFunction,Any}()
const _NATIVE_ADF_LOCK = ReentrantLock()
_population_native_function(fn) = fn
function _population_native_function(slot::ADFSlotFunction)
    lock(_NATIVE_ADF_LOCK)
    try
        _native_adf_function(slot, Base.IdSet{ADFSlotFunction}())
    finally
        unlock(_NATIVE_ADF_LOCK)
    end
end
function _native_adf_function(slot::ADFSlotFunction, visiting)
    slot in visiting && return slot # cyclic definitions retain the original path
    definition = slot.definition
    definition isa EmptyADFDefinition && return NativeADFIdentity()
    definition isa ActiveADFDefinition || return slot
    seq = definition.sequential_program
    (seq.backend == :ir && length(seq.outputs) == 1) || return slot
    source = only(seq.outputs).source
    (source isa SequentialProgramInputRef ? 1 <= source.input_index <= length(seq.input_types) :
        source isa SequentialTmpRef && 1 <= source.tmp_index <= length(seq.steps)) || return slot
    # Cached/SAFE_CALL wrappers use their original interpreter and method cache.
    SAFE_CALL[] && return slot
    push!(visiting,slot)
    steps = Any[]
    signature = Any[]
    try
        for (i,s) in enumerate(seq.steps)
            if s isa SequentialConstantStep
                push!(steps,NativeADFConstant(s.value))
                push!(signature,(s.value,))
            else
                isnothing(s.fn.cache) || return slot
                all(r -> r isa SequentialProgramInputRef ? 1 <= r.input_index <= length(seq.input_types) : 1 <= r.tmp_index < i,s.inputs) || return slot
                fn = s.fn.fn isa ADFSlotFunction ? _native_adf_function(s.fn.fn,visiting) : s.fn.fn
                # A nested unsupported/cyclic frame conservatively disables the
                # enclosing optimization, preserving all original semantics.
                fn isa ADFSlotFunction && return slot
                refs = Tuple(_native_adf_ref.(s.inputs))
                P = s.return_type_policy isa Type ? Type{s.return_type_policy} : typeof(s.return_type_policy)
                push!(steps,NativeADFCall{typeof(fn),typeof(s.fn.caster),typeof(s.fn.fallback),typeof(refs),P}(
                    fn,s.fn.caster,s.fn.fallback,refs,s.return_type_policy,s.fn))
                push!(signature,(fn,s.fn.caster,s.fn.fallback,refs,s.return_type_policy))
            end
        end
        output = _native_adf_ref(only(seq.outputs).source)
        sig = (seq,Tuple(signature),output,length(seq.input_types))
        cached = get(_NATIVE_ADF_CACHE,slot,nothing)
        cached !== nothing && isequal(cached[1],sig) && return cached[2]
        st = Tuple(steps)
        frame = NativeADFFrame{length(seq.input_types),typeof(st),typeof(output)}(st,output)
        _NATIVE_ADF_CACHE[slot] = (sig,frame)
        return frame
    finally
        delete!(visiting,slot)
    end
end
