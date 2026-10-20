include("active_cache_check.jl")
using Statistics, Logging
# Copy into existing genome buffers, like a genome pool. Node values are reset
# as well as alleles so decoded values cannot leak between repeated trials.
function copy_genome_material!(dest, src)
    for row in eachindex(src.genomes), col in 1:length(src[row])
        d,s=dest[row][col],src[row][col]
        d.value=nothing
        for j in 1:length(s.node_material)
            d[j].value=s[j].value
        end
    end
    for i in eachindex(src.output_nodes)
        d,s=dest.output_nodes[i],src.output_nodes[i]
        d.value=nothing
        for j in 1:length(s.node_material)
            d[j].value=s[j].value
        end
    end
    return dest
end
function bench_loop!(children, cache, parent_entry, f, conf, cached)
    for i in eachindex(children)
        child=children[i]
        copy_genome_material!(child,f.genome)
        if cached
            copy_active_nodes!(cache[i],parent_entry)
            U.new_material_mutation!(child,conf,f.arch,f.ml,f.shared;active_positions=cache[i])
        else
            U.new_material_mutation!(child,conf,f.arch,f.ml,f.shared)
        end
    end
end
function benchmark_cache()
    Random.seed!(2026)
    f=cache_fixture()
    # A 20-node active cone among 100 nodes; identity functions make a valid
    # reproducible starting program while mutation can select all SR functions.
    for i in 1:20
        f.genome[1][i][1].value=1
        f.genome[1][i][2].value=i==1 ? 1 : i+1
        f.genome[1][i][3].value=1
    end
    for out in f.genome.output_nodes
        out[2].value=22
    end
    conf=runConf(2,10,2.0,0.0)
    e=ActiveNodeCacheEntry(); p=cache_decode(f)
    capture_active_nodes!(e,f.genome,p)
    println("active nodes = ",length(e.positions)); flush(stdout)
    # Allocation accounting keeps the mandated sampler separate from mutation.
    child=deepcopy(f.genome); ce=ActiveNodeCacheEntry()
    copy_active_nodes!(ce,e)
    idx=[1,2]
    U._materialize_active_nodes!(ce,child,idx)
    materialize_alloc(e,g,idx)=@allocated U._materialize_active_nodes!(e,g,idx)
    sampler_alloc(n,k)=@allocated U.sample_n(n,k)
    materialize_alloc(ce,child,idx); sampler_alloc(length(e.positions),2)
    println("warm capture bytes = ",capture_bytes(e,f.genome,p))
    println("warm copy bytes = ",copy_bytes(ce,e))
    println("warm materialize bytes = ",materialize_alloc(ce,child,idx))
    println("sample_n bytes = ",sampler_alloc(length(e.positions),2))
    for measure in (baseline_mutation_bytes,cache_mutation_bytes)
        copy_genome_material!(child,f.genome); copy_active_nodes!(ce,e)
        Random.seed!(9876); measure(child,ce,f,conf)
        copy_genome_material!(child,f.genome); copy_active_nodes!(ce,e)
        Random.seed!(9876)
        println(measure," bytes = ",measure(child,ce,f,conf))
    end
    println("lambda,uncached_ms,cached_ms,speedup,uncached_bytes,cached_bytes")
    for lambda in (256,1024,4096)
        children=[deepcopy(f.genome) for _ in 1:lambda]
        cache=ActiveNodeCache(lambda)
        for cached in (false,true)
            Random.seed!(123)
            bench_loop!(children,cache,e,f,conf,cached)
        end
        times=[Float64[],Float64[]]; bytes=zeros(Int,2)
        for repeat in 1:5, (j,cached) in enumerate((false,true))
            Random.seed!(1000+repeat)
            GC.gc()
            result=@timed bench_loop!(children,cache,e,f,conf,cached)
            push!(times[j],result.time*1000)
            bytes[j]=result.bytes
        end
        a,b=median.(times)
        println(join((lambda,a,b,a/b,bytes...),",")); flush(stdout)
    end
end
with_logger(NullLogger()) do
    benchmark_cache()
end
