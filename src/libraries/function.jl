abstract type AbstractFunction end

mutable struct FunctionWrapper <: AbstractFunction
    name::Symbol
    parent_module::Symbol
    fn::Function
    caster::Union{Function,Nothing}
    fallback::Function
    function FunctionWrapper(
        fn::Function,
        caster::Union{Function,Nothing},
        fallback::Function,
    )
        return new(Symbol(fn), Symbol(parentmodule(fn)), fn, caster, fallback)
    end
    function FunctionWrapper(fn::Function, fallback::Function)
        return new(Symbol(fn), Symbol(parentmodule(fn)), fn, nothing, fallback)
    end
end

function evaluate_fn_wrapper(fn_wrapper::FunctionWrapper, inputs::Vector{<:Any})
    output = let output = nothing
        try
            output = fn_wrapper.fn(inputs...) # TODO add possible node params? besides inputs
            if !isnothing(fn_wrapper.caster)
                output = fn_wrapper.caster(output)
            end
        catch
            @info "Exception during fn eval. fn : $(fn_wrapper.name). inputs : $(inputs)"
            try
                output = fn_wrapper.fallback()
            catch
                @warn "Exception during fallback call. fn : $(fn_wrapper.name)"
            end
        end
        output
    end
    return output
end
