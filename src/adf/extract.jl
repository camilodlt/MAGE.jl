@inline _typed_invoke(fn::ADFSlotFunction, xs) = fn(xs...)::fn.output_type

"""Return sorted original program input indices used by a step's dependency cone."""
function adf_step_input_indices(prog::SequentialProgram, step_index::Int)
    _, inputs = _adf_step_cone(prog,step_index)
    return inputs
end

function _adf_step_cone(prog::SequentialProgram, step_index::Int)
    checkbounds(prog.steps,step_index)
    nodes=Set{Int}()
    inputs=Set{Int}()
    function visit(k)
        k in nodes && return
        push!(nodes,k)
        step=prog.steps[k]
        if step isa SequentialCallStep
            for r in step.inputs
                if r isa SequentialProgramInputRef
                    push!(inputs,r.input_index)
                else
                    r.tmp_index < k || throw(ArgumentError("dependency must precede step"))
                    visit(r.tmp_index)
                end
            end
        end
    end
    visit(step_index)
    return sort!(collect(nodes)),sort!(collect(inputs))
end

"""
    adf_genome_from_step(prog::SequentialProgram, step_index::Int,
                         arch::modelArchitecture, ml::MetaLibrary; max_nodes::Int=8)

Copy a Float64 step's dependency cone into a UTGenome with exactly three
Float64 formal inputs. Call `adf_step_input_indices(prog, step_index)` to obtain
original input indices in formal-argument order; unused arguments are ignored.
Return `nothing` if the cone exceeds three inputs or `max_nodes` nodes.
Non-Float64 cones are currently unsupported (return nothing).

Install using SharedInput for three Float64 values and an architecture with
three Float64 inputs (all pointing to the Float64 chromosome), the original
chromosome types, and one Float64 output. The meta-library must be the original
library, with identical function indices. No original genome material is edited.

ADFSlotFunction's `which` reports `nargs = length(slot.input_types) + 2`.
The decoder subtracts two, so an arity-three CGP node passes exactly three
arguments to a three-input installed ADF, despite its Julia varargs call method.
Empty reserved slots declare one input until replacement.
"""
function adf_genome_from_step(prog::SequentialProgram, step_index::Int,
                              arch::modelArchitecture, ml::MetaLibrary; max_nodes::Int=8)
    max_nodes >= 0 || throw(ArgumentError("max_nodes must be nonnegative"))
    cone,inputs=_adf_step_cone(prog,step_index)
    (length(inputs)>3 || length(cone)>max_nodes) && return nothing
    all(i -> prog.input_types[i] === Float64,inputs) || return nothing
    all(k -> prog.steps[k].return_type === Float64,cone) || return nothing
    row=findfirst(==(Float64),arch.chromosomes_types)
    isnothing(row) && return nothing
    inputmap=Dict(i=>j for (j,i) in enumerate(inputs))
    nodemap=Dict(k=>j+3 for (j,k) in enumerate(cone))
    chromosomes=AbstractGenome[]
    for y in eachindex(arch.chromosomes_types)
        nodes=AbstractGenomeNode[]
        for (j,k) in enumerate(cone)
            node=make_evolvable_node(3,1,length(ml[y]),1,j+2,1,length(ml),j+3,j,y)
            for el in node
                el.value=el.lowest_bound
            end
            if y==row
                step=prog.steps[k]
                if step isa SequentialConstantStep
                    push!(nodes,ConstantNode(step.value,j+3,j,y))
                    continue
                end
                idx=findfirst(f -> f === step.fn,ml[y].library)
                isnothing(idx) && throw(ArgumentError("step wrapper is absent from original library"))
                set_node_function_index!(node,idx)
                length(step.inputs)<=3 || return nothing
                positions=Tuple{Int,Int}[(r isa SequentialProgramInputRef ? inputmap[r.input_index] : nodemap[r.tmp_index],row) for r in step.inputs]
                set_node_inputs_from_positions!(node,positions)
                # Unused slots also point to valid Float64 material.
                for t in extract_connexions_types_from_node(node)
                    t.value=row
                end
            end
            push!(nodes,node)
        end
        push!(chromosomes,SingleGenome(3,nodes))
    end
    output=make_output_node(1,1,length(cone)+3,row,length(cone)+4,1)
    output[1].value=1
    output[2].value=nodemap[step_index]
    output[3].value=row
    return UTGenome(chromosomes,AbstractOutputNode[output])
end

"""
    set_node_input_connection!(node::CGPNode, input_index::Int, position::Int, type_index::Int)

Connect one argument to an earlier input/node x-position and chromosome row.
Bounds and acyclicity are checked. The caller must ensure function type compatibility.
"""
function set_node_input_connection!(node::CGPNode, input_index::Int, position::Int, type_index::Int)
    c=extract_connexions_from_node(node)[input_index]
    t=extract_connexions_types_from_node(node)[input_index]
    1 <= position < node.x_position && c.lowest_bound <= position <= c.highest_bound || throw(ArgumentError("connection must be an allowed earlier position"))
    t.lowest_bound <= type_index <= t.highest_bound || throw(ArgumentError("type row outside bounds"))
    c.value=position
    t.value=type_index
    return node
end

"""
    set_output_node_connection!(output::OutputNode, node::CGPNode)

Reroute an output to a node in its fixed output chromosome, checking bounds.
For mutation of one selected node, use the existing exported overload
`new_material_mutation!(node::CGPNode, arch::modelArchitecture, library::Library,
                       genome::UTGenome, shared_inputs::SharedInput)`.
It mutates individual alleles until valid decoded active material changes,
with the same retry limit and semantics as whole-genome new-material mutation.
"""
function set_output_node_connection!(output::OutputNode, node::CGPNode)
    c=only(extract_connexions_from_node(output))
    t=only(extract_connexions_types_from_node(output))
    node.y_position==t.value || throw(ArgumentError("node must match fixed output chromosome"))
    c.lowest_bound <= node.x_position <= c.highest_bound || throw(ArgumentError("output connection outside bounds"))
    c.value=node.x_position
    return output
end
