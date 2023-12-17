abstract type AbstractFunction end

struct FunctionWrapper <: AbstractFunction
    name::Symbol
    parent_module::Symbol
    fn::Function
    function FunctionWrapper(fn::Function)
        return new(Symbol(fn), Symbol(parentmodule(fn)), fn)
    end
end
