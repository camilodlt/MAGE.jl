
function get_fn_from_symbol(fn_name::Symbol)
    fn = getfield(Main, fn_name)
    if length(methods(fn)) > 1
        @warn "More than one method for $fn_name"
    end
    return fn
end

@inline function get_fn_from_symbol(fn::Function)
    fn
end
@inline function get_fn_from_symbol(fn::AbstractCallable)
    fn
end
