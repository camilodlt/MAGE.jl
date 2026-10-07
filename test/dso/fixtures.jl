module BridgeFixtures
using UTCGP, Statistics
using UTCGP.TypedGraphBridge
export imagebridge, scalarbridge, call_at, branching, example_dag, execute
idfloat(x::Float64,args...)=x
onefloat(args...)=1.0
addfloat(x::Float64,y::Float64,args...)=x+y
mulfloat(x::Float64,y::Float64,args...)=x*y
triple(x::Float64,y::Float64,z::Float64,args...)=x+y+z
idimage(x::Vector{Float64},args...)=x
oneimage(args...)=ones(4)
erode_one(x::Vector{Float64},args...)=reverse(x)
erode_two(x::Vector{Float64},y::Float64,args...)=x.*y
blur_one(x::Vector{Float64},args...)=fill(mean(x),length(x))
blur_two(x::Vector{Float64},y::Float64,args...)=x.+y
meanimage(x::Vector{Float64},args...)=mean(x)
scale(x::Vector{Float64},y::Float64,args...)=x.*y
function bundle(entries,caster,fallback)
    b=UTCGP.FunctionBundle(fallback)
    for (name,fn) in entries
        push!(b.functions,UTCGP.FunctionWrapper(fn,name,caster,fallback))
    end
    b
end
function floats()
    bundle([:identity=>idfloat,:one=>onefloat,:sum=>addfloat,:mul=>mulfloat,
        :mean=>meanimage,:triple=>triple],x->Float64(x),()->0.0)
end
function imagebridge(;width=8,outputs=2)
    images=bundle([:identity_image=>idimage,:one_image=>oneimage,
        :erode=>UTCGP.ManualDispatcher((erode_two,erode_one),:erode),
        :blur=>UTCGP.ManualDispatcher((blur_two,blur_one),:blur),:scale=>scale],
        identity,()->zeros(4))
    ml=UTCGP.MetaLibrary([UTCGP.Library([images]),UTCGP.Library([floats()])])
    ma=UTCGP.modelArchitecture(Type[Vector{Float64},Float64],[1,2],
        Type[Vector{Float64},Float64],fill(Float64,outputs),fill(2,outputs))
    make_bridge(ma,ml,UTCGP.nodeConfig(width,1,3,2))
end
function scalarbridge(;width=8,outputs=1)
    ml=UTCGP.MetaLibrary([UTCGP.Library([floats()])])
    ma=UTCGP.modelArchitecture(Type[Float64],[1],Type[Float64],fill(Float64,outputs),fill(1,outputs))
    make_bridge(ma,ml,UTCGP.nodeConfig(width,1,3,1))
end
function call_at(b,calls,name,args,column,gateway=0)
    fid=something(findfirst(f->f.name==name,b.catalog.families))
    sid=something(findfirst(i->call_fits(b,calls,fid,i,args,column),eachindex(b.catalog.families[fid].specs)))
    GraphCall(fid,sid,args,column,gateway)
end
function branching(b)
    calls=GraphCall[]; w=b.node_config.n_nodes
    for (name,args,col,gate) in ((:erode,[1],1,0),(:mean,[3],2,0),
            (:identity,[4],w-1,2),(:sum,[4,5],w,1))
        push!(calls,call_at(b,calls,name,args,col,gate))
    end
    TypedDAG(calls,[6,5],b.catalog.fingerprint)
end
function example_dag(b)
    calls=GraphCall[]
    for (name,args,col,gate) in ((:erode,[1],1,0),(:blur,[3,2],2,0),
            (:mean,[4],3,0),(:sum,[5,5],b.node_config.n_nodes,1))
        push!(calls,call_at(b,calls,name,args,col,gate))
    end
    TypedDAG(calls,[6],b.catalog.fingerprint)
end
function execute(genome,b,args)
    decoded=UTCGP.decode_with_output_nodes(deepcopy(genome),b.library,b.architecture,deepcopy(b.shared_inputs))
    UTCGP.compile_program(decoded,b.architecture,b.library)(args...)
end
end
