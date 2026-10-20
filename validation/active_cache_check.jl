using Test, Random, MAGE, ErrorTypes
const U = MAGE
function cache_fixture(; typed=false, n=100)
    types = typed ? [Float64, Int] : [Float64]
    arch = modelArchitecture(typed ? [Float64, Int] : [Float64, Float64], [1, typed ? 2 : 1], types,
        typed ? [Float64, Int, Float64] : [Float64, Float64], typed ? [1,2,1] : [1,1])
    bundles = deepcopy.([bundle_float_basic, bundle_number_arithmetic])
    update_caster!.(bundles, float_caster)
    update_fallback!.(bundles, ()->0.0)
    libs = [Library(bundles)]
    if typed
        ib = deepcopy.([bundle_integer_basic, bundle_number_arithmetic])
        update_caster!.(ib, integer_caster)
        update_fallback!.(ib, ()->0)
        push!(libs, Library(ib))
    end
    ml = MetaLibrary(libs)
    shared, genome = make_evolvable_utgenome(arch, ml, nodeConfig(n,1,2,2))
    initialize_genome!(genome)
    # A guaranteed two-node active chain, with the rest randomly initialized.
    for row in eachindex(types)
        genome[row][1][1].value = 1
        genome[row][1][2].value = row
        genome[row][2][1].value = 1
        genome[row][2][2].value = 3
        genome[row][2][3].value = row
    end
    for output in genome.output_nodes
        output[2].value = 4
    end
    correct_all_nodes!(genome,arch,ml,shared)
    return (; arch, ml, shared, genome)
end
cache_decode(f,g=f.genome) = U.decode_with_output_nodes(g,f.ml,f.arch,f.shared)
cache_outputs(g) = [U.node_to_vector(n) for n in g.output_nodes]
cache_values(g) = [[U.node_to_vector(n) for n in chr] for chr in g.genomes]
capture_bytes(e,g,p) = @allocated capture_active_nodes!(e,g,p)
copy_bytes(d,s) = @allocated copy_active_nodes!(d,s)
materialize_bytes(e,g,idx) = @allocated U._materialize_active_nodes!(e,g,idx)
# Allocation baseline has only the required sampler, zero-allocation resolution,
# and unchanged node-level mutation. Keep its returned tuple at a call boundary
# like the public API, so compiler elision of a discarded baseline return does
# not falsely count the API's existing 32-byte result tuple as cache overhead.
@noinline function cache_mutation_baseline!(g,e,f,conf)
    idx=U.sample_n(length(e.positions),floor(Int,conf.mutation_rate))
    nodes=U._materialize_active_nodes!(e,g,idx)
    U.new_material_mutation!(nodes,f.ml,f.arch,g,f.shared)
    return nodes,idx
end
function cache_mutation_bytes(g,e,f,conf)
    @allocated U.new_material_mutation!(g,conf,f.arch,f.ml,f.shared;active_positions=e)
end
baseline_mutation_bytes(g,e,f,conf) = @allocated cache_mutation_baseline!(g,e,f,conf)
sample_cached_bytes(e,m,n) = @allocated U._sample_cached_indices!(e,m,n)
function run_active_cache_tests()
    @testset "Ordered active-node cache" begin
        @testset "Exact reusable sampling" begin
            e = ActiveNodeCacheEntry()
            for m in (1,2,3,10,40,100,501,1000), n in unique([1,cld(m,2),m]), seed in 1:20
                Random.seed!(seed)
                expected = U.sample_n(m,n)
                state = copy(Random.default_rng())
                following = rand(UInt64,4)
                Random.seed!(seed)
                @test U._sample_cached_indices!(e,m,n) == expected
                @test copy(Random.default_rng()) == state
                @test rand(UInt64,4) == following
                sample_cached_bytes(e,m,n)
                @test sample_cached_bytes(e,m,n) == 0
            end
        end
        for typed in (false,true), seed in 1:20
            Random.seed!(seed)
            f = cache_fixture(;typed)
            # Vary output roots to exercise random dormant nodes and type crossings.
            for output in f.genome.output_nodes
                output[2].value = rand(3:102)
            end
            p = cache_decode(f)
            e = ActiveNodeCacheEntry()
            capture_active_nodes!(e,f.genome,p)
            @test check_active_nodes(e,f.genome,f.ml,f.arch,f.shared)
            @test e.positions == [U.active_node_position(n,f.genome) for n in get_active_nodes(p)]
            capture_bytes(e,f.genome,p)
            @test capture_bytes(e,f.genome,p) == 0
            d = ActiveNodeCacheEntry()
            copy_active_nodes!(d,e); copy_bytes(d,e)
            @test copy_bytes(d,e) == 0
            @test d.positions !== e.positions && d.layout !== e.layout
            @test check_active_nodes(d,f.genome,f.ml,f.arch,f.shared)
        end
        for typed in (false,true), seed in 1:100
            Random.seed!(seed)
            f = cache_fixture(;typed)
            for output in f.genome.output_nodes
                output[2].value = rand(3:102)
            end
            a,b = deepcopy(f.genome),deepcopy(f.genome)
            e = ActiveNodeCacheEntry()
            capture_active_nodes!(e,b,cache_decode(f,b))
            conf = runConf(2,10,2.0,0.0)
            Random.seed!(seed)
            ra = U.new_material_mutation!(a,conf,f.arch,f.ml,f.shared)
            statea = copy(Random.default_rng())
            nexta = rand(UInt64,4)
            Random.seed!(seed)
            rb = U.new_material_mutation!(b,conf,f.arch,f.ml,f.shared;active_positions=e)
            stateb = copy(Random.default_rng())
            nextb = rand(UInt64,4)
            @test cache_values(a) == cache_values(b)
            @test cache_outputs(a) == cache_outputs(b)
            @test statea == stateb
            @test ra[2] == rb[2]
            @test nexta == nextb
            @test !e.valid
        end
        f=cache_fixture()
        e=ActiveNodeCacheEntry()
        capture_active_nodes!(e,f.genome,cache_decode(f))
        idx=[1,2]
        U._materialize_active_nodes!(e,f.genome,idx)
        materialize_bytes(e,f.genome,idx)
        @test materialize_bytes(e,f.genome,idx) == 0
        reverse!(e.positions)
        @test_throws AssertionError check_active_nodes(e,f.genome,f.ml,f.arch,f.shared)
        reverse!(e.positions)
        # Equivalent future growth: append a dormant time slice, leaving roots intact.
        push!(f.genome[1].chromosome, deepcopy(f.genome[1][length(f.genome[1])]))
        @test !active_cache_matches(e,f.genome)
        conf=runConf(2,10,2.0,0.0)
        U.new_material_mutation!(f.genome,conf,f.arch,f.ml,f.shared;active_positions=e)
        @test e.layout == [101,2] # fallback refreshed before invalidation
        @test !e.valid
        capture_active_nodes!(e,f.genome,cache_decode(f))
        pop!(f.genome.output_nodes)
        @test !active_cache_matches(e,f.genome)
        f=cache_fixture()
        parent=ActiveNodeCacheEntry()
        capture_active_nodes!(parent,f.genome,cache_decode(f))
        child=deepcopy(f.genome); child_entry=ActiveNodeCacheEntry()
        conf=runConf(2,10,2.0,0.0)
        # Isolate sampling plus materialisation from node mutation and tuple escape.
        copy_active_nodes!(child_entry,parent)
        U._sample_active_nodes!(child_entry,child,2)
        sample_bytes(n,k) = @allocated U.sample_n(n,k)
        prepare_bytes(e,g,n) = @allocated U._sample_active_nodes!(e,g,n)
        sample_bytes(length(parent.positions),2)
        prepare_bytes(child_entry,child,2)
        Random.seed!(9876)
        sb=sample_bytes(length(parent.positions),2)
        Random.seed!(9876)
        pb=prepare_bytes(child_entry,child,2)
        @test pb == 0
        @test !child_entry.valid
        @testset "Concurrent independent slots" begin
            count = 128
            fixtures = [cache_fixture(;typed=iseven(i)) for i in 1:8]
            sources = ActiveNodeCache(8)
            destinations = ActiveNodeCache(count)
            Threads.@threads for i in 1:8
                local f = fixtures[i]
                capture_active_nodes!(sources[i],f.genome,cache_decode(f))
                U._sample_cached_indices!(sources[i],length(sources[i].positions),1)
            end
            snapshots = deepcopy(sources)
            children = [deepcopy(fixtures[mod1(i,8)].genome) for i in 1:count]
            Threads.@threads for i in 1:count
                local parent = mod1(i,8)
                local f = fixtures[parent]
                local_shared = deepcopy(f.shared)
                copy_active_nodes!(destinations[i],sources[parent])
                U.new_material_mutation!(children[i],conf,f.arch,f.ml,local_shared;
                    active_positions=destinations[i])
                capture_active_nodes!(destinations[i],children[i],
                    U.decode_with_output_nodes(children[i],f.ml,f.arch,local_shared))
            end
            for i in 1:count
                f = fixtures[mod1(i,8)]
                @test check_active_nodes(destinations[i],children[i],f.ml,f.arch,f.shared)
            end
            for i in 1:8, field in fieldnames(ActiveNodeCacheEntry)
                @test getfield(sources[i],field) == getfield(snapshots[i],field)
            end
        end
        # Warm a small active cone, then expand it within the SAME layout.
        # Capture/copy must have reserved the layout capacity on their first use.
        expanding=cache_fixture()
        small=ActiveNodeCacheEntry(); copied=ActiveNodeCacheEntry()
        capture_active_nodes!(small,expanding.genome,cache_decode(expanding))
        copy_active_nodes!(copied,small)
        for i in 3:20
            expanding.genome[1][i][1].value=1
            expanding.genome[1][i][2].value=i+1
            expanding.genome[1][i][3].value=1
        end
        for output in expanding.genome.output_nodes
            output[2].value=22
        end
        expanded=cache_decode(expanding)
        @test capture_bytes(small,expanding.genome,expanded) == 0
        @test length(small.positions) == 20
        @test copy_bytes(copied,small) == 0
        # Unequal chromosome widths and lengths beyond Julia's boxed-Int cache.
        fwide=cache_fixture(;typed=true,n=600)
        pop!(fwide.genome[2].chromosome)
        wide=ActiveNodeCacheEntry()
        wp=cache_decode(fwide)
        capture_active_nodes!(wide,fwide.genome,wp)
        @test wide.layout == [600,599,3]
        @test check_active_nodes(wide,fwide.genome,fwide.ml,fwide.arch,fwide.shared)
        capture_bytes(wide,fwide.genome,wp)
        @test capture_bytes(wide,fwide.genome,wp) == 0
        # Change a dormant row, keeping the total size unchanged.
        push!(fwide.genome[2].chromosome,deepcopy(fwide.genome[2][599]))
        pop!(fwide.genome[1].chromosome)
        @test !active_cache_matches(wide,fwide.genome)
        # Evaluation and GA callbacks: preserve tournament RNG and elite validity.
        f=cache_fixture()
        pop=U.Population([deepcopy(f.genome),deepcopy(f.genome)])
        conf=RunConfGA(1,3,1,2.0,0.0,2)
        nc=nodeConfig(100,1,2,2)
        source=ActiveNodeCache(2); dest=ActiveNodeCache(4)
        programs=U.default_decoding_callback(pop,1,conf,f.arch,nc,f.ml,f.shared,source)
        @test all(active_cache_matches(source[i],pop[i]) for i in 1:2)
        args=U.GA_POP_ARGS(pop,1,conf,f.arch,nc,f.ml,[1.0,2.0],[1])
        parents=zeros(Int,4)
        Random.seed!(555)
        reference=@unwrap_or U.ga_population_callback(args) error("selection")
        nextr=rand(UInt64)
        Random.seed!(555)
        children=@unwrap_or U.ga_population_callback(args,dest,source,parents) error("selection")
        @test rand(UInt64)==nextr
        @test cache_values.(children.pop)==cache_values.(reference.pop)
        @test all(check_active_nodes(dest[i],children[i],f.ml,f.arch,f.shared) for i in 1:4)
        margs=U.GA_MUTATION_ARGS(children,1,conf,f.arch,nc,f.ml,f.shared)
        U.ga_numbered_new_material_mutation_callback(margs,dest,source,parents;check=true)
        @test dest[1].valid
        @test all(!dest[i].valid for i in 2:4)
        @test all(source[i].valid for i in 1:2)
    end
end
if abspath(PROGRAM_FILE) == @__FILE__
    run_active_cache_tests()
end
