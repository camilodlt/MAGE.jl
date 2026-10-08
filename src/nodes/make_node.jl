
######################
# MAKE OUTPUT NODE
######################

"""
    make_output_node(fixed_fn_idx, min_connexion, max_connexion,
                     fixed_con_type_idx, x_pos, y_pos)

Build an [`OutputNode`](@ref) reading from chromosome `fixed_con_type_idx`.

The `FUNCTION` element is pinned to `fixed_fn_idx` and the `TYPE` element to
`fixed_con_type_idx` (both frozen), so only the connexion — anywhere in
`min_connexion:max_connexion` — is left for evolution to choose.
"""
function make_output_node(
    # n_params::Int,
    fixed_fn_idx::Int,
    min_connexion::Int,
    max_connexion::Int,
    fixed_con_type_idx::Int,
    x_pos::Int, # x pos
    y_pos::Int, # y_pos
)::OutputNode
    @assert fixed_fn_idx >= 1 # TODO move this to CGPEL
    @assert min_connexion >= 1
    @assert min_connexion <= max_connexion
    @assert fixed_con_type_idx >= 1
    # @assert n_params >= 0
    # Node position
    pos = (x_pos, x_pos, y_pos)
    # Make node material 
    fn_el = CGPElement(fixed_fn_idx, fixed_fn_idx, pos[1], pos[2], pos[3], true, FUNCTION)
    con = CGPElement(min_connexion, max_connexion, pos[1], pos[2], pos[3], false, CONNEXION) # con type
    con_type = CGPElement(
        fixed_con_type_idx,
        fixed_con_type_idx,
        pos[1],
        pos[2],
        pos[3],
        true,
        TYPE,
    ) # con type 
    nm = NodeMaterial([fn_el, con, con_type])
    output_node = OutputNode(nm, nothing, pos[1], pos[2], pos[3])
    return output_node
end


######################
# MAKE CGPNODE
######################

"""
    make_evolvable_node(arity, min_fn, max_fn, min_connexion, max_connexion,
                        min_type, max_type, x_pos, x_real_pos, y_pos)

Build a [`CGPNode`](@ref) whose material is one `FUNCTION` element followed by
`arity` `(CONNEXION, TYPE)` pairs.

The bounds are what make the node safe to mutate: the function index stays
inside its library (`min_fn:max_fn`), the connexions stay behind the node
(`min_connexion:max_connexion`, normally `1:x_pos-1`) and the types stay inside
the set of chromosomes (`min_type:max_type`).

Callers normally go through [`make_evolvable_single_genome`](@ref) or
[`make_evolvable_utgenome`](@ref), which derive these bounds from a
[`nodeConfig`](@ref) and a [`MetaLibrary`](@ref).
"""
function make_evolvable_node(
    arity::Int,
    # fn bounds
    min_fn::Int,
    max_fn::Int,
    # con bounds
    min_connexion::Int,
    max_connexion::Int,
    # type bounds
    min_type::Int,
    max_type::Int,
    # n_params::Int,
    x_pos::Int, # x pos
    x_real_pos::Int,
    y_pos::Int, # y_pos
)::CGPNode
    @assert arity >= 1
    @assert min_fn <= max_fn
    @assert min_connexion <= max_connexion
    @assert min_type <= max_type
    # @assert n_params >= 0

    # MAKE NODE MATERIAL
    mat = Vector{CGPElement}()
    # - fn
    fn_el = fn_el = CGPElement(min_fn, max_fn, x_pos, x_real_pos, y_pos, false, FUNCTION)
    push!(mat, fn_el)

    # - cons, types 
    for _ = 1:arity
        con = CGPElement(
            min_connexion,
            max_connexion,
            x_pos,
            x_real_pos,
            y_pos,
            false,
            CONNEXION,
        ) # con type
        con_type = CGPElement(min_type, max_type, x_pos, x_real_pos, y_pos, false, TYPE) # con type 
        push!(mat, con, con_type)
    end
    nm = NodeMaterial(mat)
    output_node = CGPNode(nm, nothing, x_pos, x_real_pos, y_pos)
    return output_node
end

########################################
# PARAMETRIC ###########################
########################################

###############################
# MAKE OUTPUT NODE PARAMETRIC #
###############################

function make_output_nodeP(
    # n_params::Int,
    fixed_fn_idx::Int,
    min_connexion::Int,
    max_connexion::Int,
    fixed_con_type_idx::Int,
    x_pos::Int, # x pos
    y_pos::Int, # y_pos
    PT::T,
)::OutputNodeP{PT} where {T<:DataType}
    @show PT
    @show T
    @assert fixed_fn_idx >= 1 # TODO move this to CGPEL
    @assert min_connexion >= 1
    @assert min_connexion <= max_connexion
    @assert fixed_con_type_idx >= 1
    # Node position
    pos = (x_pos, x_pos, y_pos)
    # Make node material 
    fn_el = CGPElement(fixed_fn_idx, fixed_fn_idx, pos[1], pos[2], pos[3], true, FUNCTION)
    con = CGPElement(min_connexion, max_connexion, pos[1], pos[2], pos[3], false, CONNEXION) # con type
    con_type = CGPElement(
        fixed_con_type_idx,
        fixed_con_type_idx,
        pos[1],
        pos[2],
        pos[3],
        true,
        TYPE,
    ) # con type 
    nm = NodeMaterial([fn_el, con, con_type])
    output_node = OutputNodeP(nm, Ref{PT}(), pos[1], pos[2], pos[3])
    return output_node
end

