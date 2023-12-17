abstract type AbstractFunctionBundle end

"""
Because of multiple dispatch anb how we call functions,
methods with different number of arguments should have different names. 

For example: 
    - p(a, z...) = 1 
    - p(a,b,z...) = 2

When running the program, we will try to run p(all_inputs..., all_params...). Hence, 
we would always call the second p function. Because with that many arguments, p(2) obscures
p(1). 

Also because we pass all_params... . Functions should accept varargs at the end.

To accept a function at a given mutation, the applicable()/HASMETHOD fn is called. 
To make the graph, connections the which function is used. 
"""

struct FunctionBundle <: AbstractFunctionBundle
    functions::Vector{FunctionWrapper}
    caster::Function
    fallback::Function
    last_fallback::Function
    function FunctionBundle(caster::Function, fallback::Function, last_fallback::Function)
        return new(Vector{FunctionWrapper}(), caster, fallback, last_fallback)
    end
    function FunctionBundle(caster::Function, fallback::Function)
        return new(Vector{FunctionWrapper}(), caster, fallback, fallback)
    end
end
Base.size(bundle::FunctionBundle) = length(bundle.functions)
Base.length(bundle::FunctionBundle) = length(bundle.functions)
Base.getindex(bundle::FunctionBundle, i::Int) = bundle.functions[i]
Base.iterate(bundle::FunctionBundle, state = 1) =
    state > length(bundle.functions) ? nothing : (bundle.functions[state], state + 1)

append_method!(bundle::FunctionBundle, fn_wrapped::FunctionWrapper) =
    push!(bundle.functions, fn_wrapped)
