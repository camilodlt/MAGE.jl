"""Typed DAG interchange. Include at the end of UTCGP.jl; no existing API changes."""
module TypedGraphBridge
using SHA: sha256
const M = parentmodule(@__MODULE__)
export CallSpec, FunctionFamily, FunctionCatalog, GraphCall, TypedDAG, BridgeContext,
    make_bridge, build_catalog, encode_mage, extract_active_dag, validate_dag,
    active_dag, graph_key, input_count, output_count, value_type, value_column,
    padding_connection, call_fits, dispatch_descriptor

struct CallSpec
    types::Tuple{Vararg{Int}} # All fixed-width alleles, including ignored padding.
    arity::Int
    dispatch::String
end
struct FunctionFamily
    row::Int
    index::Int
    name::Symbol
    return_type::Int
    specs::Vector{CallSpec}
end
struct FunctionCatalog
    types::Vector{Type}
    families::Vector{FunctionFamily}
    family_index::Dict{Tuple{Int,Int},Int}
    input_types::Vector{Int}
    row_types::Vector{Int}
    arity::Int
    fingerprint::String
    exclusions::Vector{String}
end
struct GraphCall
    family::Int
    spec::Int
    args::Vector{Int} # Input IDs, then completed operation IDs; never future IDs.
    column::Int
    gateway::Int # 0 for ordinary nodes; otherwise the semantic output index.
end
struct TypedDAG
    calls::Vector{GraphCall}
    outputs::Vector{Int}
    catalog_hash::String
end
struct BridgeContext
    architecture::M.modelArchitecture
    library::M.MetaLibrary
    node_config::M.nodeConfig
    catalog::FunctionCatalog
    shared_inputs::M.SharedInput
    template::M.UTGenome
    output_row::Int
end
input_count(b::BridgeContext)=length(b.catalog.input_types)
output_count(b::BridgeContext)=length(b.architecture.outputs_types)

"""Resolve the supplied decoder's nargs-2 contract without executing a primitive."""
function dispatch_descriptor(f,types::Tuple)
    # Julia functions may throw from which() for incompatible or ambiguous
    # type tuples.
    signature=Tuple{types...}
    # MAGE's image factories generate methods with @eval while building a task.
    # Catalog construction occurs in the same call frame, so ordinary method
    # lookup can use an older world and incorrectly discard every image method.
    Base.invokelatest(hasmethod,f,signature) || return nothing
    method=try
        Base.invokelatest(which,f,signature)
    catch err
        err isa MethodError || err isa ArgumentError || err isa ErrorException || rethrow()
        return nothing
    end
    isnothing(method) && return nothing
    hasproperty(method,:nargs) || return nothing
    n=Int(method.nargs)-2
    0<=n<=length(types) || return nothing
    hasproperty(method,:isva) && !method.isva && return nothing
    sig=hasproperty(method,:sig) ? string(method.sig) : string(method)
    return (n,sig)
end
function build_catalog(ma,ml;arity::Int=3)
    1<=arity<=3 || throw(ArgumentError("fixed node arity must be 1..3"))
    types=Type[unique(vcat(ma.inputs_types,ma.chromosomes_types))...]
    all(isconcretetype,types) || throw(ArgumentError("use concrete task input/chromosome types"))
    typeid(t)=something(findfirst(==(t),types))
    inputs=typeid.(ma.inputs_types); rows=typeid.(ma.chromosomes_types)
    length(rows)==length(ml) || throw(DimensionMismatch("architecture/library"))
    families=FunctionFamily[]; lookup=Dict{Tuple{Int,Int},Int}(); exclusions=String[]
    tuples=collect(Iterators.product(ntuple(_->eachindex(types),arity)...))
    for row in eachindex(rows), (index,w) in enumerate(ml[row])
        specs=CallSpec[]
        for ids in tuples
            ts=Tuple(types[i] for i in ids)
            descriptor=dispatch_descriptor(w.fn,ts)
            isnothing(descriptor) && continue
            n,sig=descriptor
            # Decode dispatches on padded arguments, execution on trimmed ones.
            # Reject cases where trimming would silently select another method.
            dispatch_descriptor(w.fn,ts[1:n])==descriptor || continue
            push!(specs,CallSpec(Tuple(ids),n,sig))
        end
        if isempty(specs)
            push!(exclusions,"row=$row index=$index name=$(w.name): no supported dispatch")
        else
            push!(families,FunctionFamily(row,index,w.name,rows[row],specs))
            lookup[(row,index)]=length(families)
        end
    end
    isempty(families) && throw(ArgumentError("empty catalog"))
    desc=repr((string.(types),inputs,rows,arity,
        [(f.row,f.index,f.name,[(s.types,s.arity,s.dispatch) for s in f.specs]) for f in families]))
    FunctionCatalog(types,families,lookup,inputs,rows,arity,bytes2hex(sha256(desc)),exclusions)
end
value_type(b,calls,id::Int)=id<=input_count(b) ? b.catalog.input_types[id] :
    b.catalog.families[calls[id-input_count(b)].family].return_type
value_column(b,calls,id::Int)=id<=input_count(b) ? 0 : calls[id-input_count(b)].column

"""Padding can refer to a dormant cell; ignored alleles are not active DAG edges."""
function padding_connection(b,tid,column)
    i=findfirst(==(tid),b.catalog.input_types)
    !isnothing(i) && return (b.architecture.inputs_types_idx[i],i)
    row=findfirst(==(tid),b.catalog.row_types)
    return isnothing(row) || column<=1 ? nothing : (row,input_count(b)+1)
end
function call_fits(b,calls,fid,sid,args,col)
    1<=col<=b.node_config.n_nodes || return false
    spec=b.catalog.families[fid].specs[sid]
    length(args)==spec.arity || return false
    for (i,id) in enumerate(args)
        1<=id<=input_count(b)+length(calls) || return false
        value_type(b,calls,id)==spec.types[i] && value_column(b,calls,id)<col || return false
    end
    all(!isnothing(padding_connection(b,spec.types[i],col)) for i in (spec.arity+1):b.catalog.arity)
end
function _put!(e,v::Int)
    e.lowest_bound<=v<=e.highest_bound || throw(ArgumentError("allele outside its bounds"))
    e.is_freezed && !isnothing(e.value) && e.value != v && throw(ArgumentError("changing a frozen allele"))
    e.value=v
end
function _write_call!(node,b,calls,c)
    f=b.catalog.families[c.family]; spec=f.specs[c.spec]
    _put!(M.extract_function_from_node(node),f.index)
    cons=M.extract_connexions_from_node(node); rows=M.extract_connexions_types_from_node(node)
    for i in 1:b.catalog.arity
        row,con=if i<=spec.arity
            id=c.args[i]
            if id<=input_count(b)
                (b.architecture.inputs_types_idx[id],id)
            else
                p=calls[id-input_count(b)]
                (b.catalog.families[p.family].row,input_count(b)+p.column)
            end
        else
            something(padding_connection(b,spec.types[i],c.column))
        end
        _put!(cons[i],con); _put!(rows[i],row)
    end
end
function fix_gateways!(genome,b)
    for (o,node) in enumerate(genome.output_nodes)
        _put!(M.extract_function_from_node(node),1)
        con=only(M.extract_connexions_from_node(node))
        _put!(con,input_count(b)+b.node_config.n_nodes+1-o)
        con.is_freezed=true
        _put!(only(M.extract_connexions_types_from_node(node)),b.output_row)
    end
    genome
end
function _fill_template!(b)
    calls=GraphCall[]
    for col in 1:b.node_config.n_nodes, row in eachindex(b.catalog.row_types)
        chosen=nothing
        for (fid,f) in enumerate(b.catalog.families)
            f.row==row || continue
            for sid in sortperm([s.arity for s in f.specs])
                spec=f.specs[sid]; args=Int[]
                for tid in spec.types[1:spec.arity]
                    id=findfirst(i->value_type(b,calls,i)==tid && value_column(b,calls,i)<col,
                                 1:(input_count(b)+length(calls)))
                    isnothing(id) && break
                    push!(args,id)
                end
                call_fits(b,calls,fid,sid,args,col) || continue
                chosen=GraphCall(fid,sid,args,col,0); break
            end
            isnothing(chosen) || break
        end
        isnothing(chosen) && throw(ArgumentError("cannot fill row $row column $col; provide a base constructor/input"))
        _write_call!(b.template.genomes[row].chromosome[col],b,calls,chosen)
        push!(calls,chosen)
    end
    fix_gateways!(b.template,b)
    b
end
function make_bridge(ma,ml,nc)
    k=length(ma.outputs_types)
    0<k<=nc.n_nodes || throw(ArgumentError("output gateways do not fit"))
    all(==(Float64),ma.outputs_types) || throw(ArgumentError("initial profile needs Float64 outputs"))
    row=only(unique(ma.outputs_types_idx))
    catalog=build_catalog(ma,ml;arity=nc.arity)
    shared,template=M.make_evolvable_utgenome(ma,ml,nc)
    desc=dispatch_descriptor(ml[row][1].fn,(Float64,))
    !isnothing(desc) && first(desc)==1 || throw(ArgumentError("index 1 must be a unary Float64 output wrapper"))
    _fill_template!(BridgeContext(ma,ml,nc,catalog,shared,template,row))
end
function validate_dag(dag,b)
    dag.catalog_hash==b.catalog.fingerprint || throw(ArgumentError("catalog mismatch"))
    length(dag.outputs)==output_count(b) || throw(DimensionMismatch("outputs"))
    seen=GraphCall[]; occupied=Set{Tuple{Int,Int}}()
    for (i,c) in enumerate(dag.calls)
        1<=c.family<=length(b.catalog.families) || throw(ArgumentError("unknown family"))
        f=b.catalog.families[c.family]
        1<=c.spec<=length(f.specs) || throw(ArgumentError("unknown signature"))
        call_fits(b,seen,c.family,c.spec,c.args,c.column) || throw(ArgumentError("illegal call $i"))
        key=(f.row,c.column)
        key in occupied && throw(ArgumentError("two operations in one cell"))
        push!(occupied,key)
        if c.gateway != 0
            1<=c.gateway<=output_count(b) || throw(ArgumentError("gateway index"))
            f.row==b.output_row && c.column==b.node_config.n_nodes+1-c.gateway || throw(ArgumentError("gateway placement"))
            dag.outputs[c.gateway]==input_count(b)+i || throw(ArgumentError("gateway/output mismatch"))
        elseif f.row==b.output_row && c.column>b.node_config.n_nodes-output_count(b)
            throw(ArgumentError("reserved gateway cell"))
        end
        push!(seen,c)
    end
    for (o,id) in enumerate(dag.outputs)
        input_count(b)<id<=input_count(b)+length(dag.calls) || throw(ArgumentError("incomplete output"))
        dag.calls[id-input_count(b)].gateway==o || throw(ArgumentError("missing gateway"))
    end
    dag
end
function encode_mage(dag::TypedDAG,b::BridgeContext)
    validate_dag(dag,b)
    genome=deepcopy(b.template)
    for c in dag.calls
        row=b.catalog.families[c.family].row
        _write_call!(genome.genomes[row].chromosome[c.column],b,dag.calls,c)
    end
    genome
end
function extract_active_dag(genome,b::BridgeContext)
    ni=input_count(b); width=b.node_config.n_nodes
    length(genome.genomes)==length(b.catalog.row_types) || throw(DimensionMismatch("chromosomes"))
    all(length(g.chromosome)==width && g.starting_point==ni for g in genome.genomes) || throw(DimensionMismatch("genome shape"))
    length(genome.output_nodes)==output_count(b) || throw(DimensionMismatch("outputs"))
    active=Dict{Tuple{Int,Int},Tuple{Int,Int,Vector{Tuple{Int,Int}}}}()
    function visit(row,col)
        key=(row,col); haskey(active,key) && return
        node=genome.genomes[row].chromosome[col]
        fid=get(b.catalog.family_index,(row,M.extract_function_from_node(node).value),0)
        fid>0 || throw(ArgumentError("active function outside catalog"))
        cons=M.extract_connexions_from_node(node); rows=M.extract_connexions_types_from_node(node)
        length(cons)==b.catalog.arity || throw(DimensionMismatch("arity"))
        refs=Tuple{Int,Int}[]; tids=Int[]
        for (con,rt) in zip(cons,rows)
            r=rt.value; c=con.value
            !isnothing(r) && 1<=r<=length(b.catalog.row_types) || throw(ArgumentError("type allele"))
            !isnothing(c) && 1<=c<ni+col || throw(ArgumentError("non-backward connection"))
            push!(refs,c<=ni ? (0,c) : (r,c-ni))
            push!(tids,c<=ni ? b.catalog.input_types[c] : b.catalog.row_types[r])
        end
        sid=findfirst(s->s.types==Tuple(tids),b.catalog.families[fid].specs)
        isnothing(sid) && throw(ArgumentError("unsupported padded dispatch"))
        args=refs[1:b.catalog.families[fid].specs[sid].arity]
        for (r,c) in args
            r==0 || visit(r,c)
        end
        active[key]=(fid,sid,args)
    end
    for (o,node) in enumerate(genome.output_nodes)
        M.extract_function_from_node(node).value==1 || throw(ArgumentError("output wrapper changed"))
        only(M.extract_connexions_types_from_node(node)).value==b.output_row || throw(ArgumentError("output row changed"))
        only(M.extract_connexions_from_node(node)).value==ni+width+1-o || throw(ArgumentError("output wiring changed"))
        visit(b.output_row,width+1-o)
    end
    sorted=sort!(collect(keys(active));by=k->(k[2],k[1]))
    ids=Dict(k=>ni+i for (i,k) in enumerate(sorted)); calls=GraphCall[]
    for key in sorted
        fid,sid,refs=active[key]
        gateway=key[1]==b.output_row && key[2]>width-output_count(b) ? width+1-key[2] : 0
        push!(calls,GraphCall(fid,sid,[r==0 ? c : ids[(r,c)] for (r,c) in refs],key[2],gateway))
    end
    validate_dag(TypedDAG(calls,[ids[(b.output_row,width+1-o)] for o in 1:output_count(b)],b.catalog.fingerprint),b)
end
active_dag(dag,b)=extract_active_dag(encode_mage(dag,b),b)
function graph_key(dag,b)
    d=active_dag(dag,b)
    material=[(c.family,b.catalog.families[c.family].specs[c.spec].dispatch,c.args,c.gateway) for c in d.calls]
    bytes2hex(sha256(repr((d.catalog_hash,material,d.outputs))))
end
end
