using Test, Random, MAGE
# Frozen 4fc78de implementation, independent recursion and entry points.
Base.include(MAGE, joinpath(@__DIR__, "fixtures/decode_baseline.jl"))
include(joinpath(@__DIR__, "fixtures/decode_helpers.jl"))

function mutate_exact_fixture!(f)
    for chromosome in f.genome.genomes, node in chromosome.chromosome
        MAGE._mutate_all_alleles!(node.node_material.material)
    end
    for output in f.genome.output_nodes
        # Output identity wrappers require their declared chromosome type.
        # correct_all_nodes! repairs CGP nodes, not output connections.
        output[2].value = rand(3:length(f.genome[output.y_position]) + 2)
        for element in extract_connexions_types_from_node(output)
            element.value = output.y_position
        end
    end
    correct_all_nodes!(f.genome, f.arch, f.ml, f.shared)
end

decode_exact_pair(genome, ml, arch, shared) =
    (MAGE.baseline_decode_with_output_nodes(genome,ml,arch,shared),
     MAGE.decode_with_output_nodes(genome,ml,arch,shared))
decode_exact_check(genome, ml, arch, shared) =
    decode_exact_compare(decode_exact_pair(genome, ml, arch, shared)..., ml, arch, shared)
function decode_exact_compare(old, new, ml, arch, shared)
    @test length(old)==length(new)
    vectors=[o.inputs for p in new for o in p]
    @test length(unique(objectid.(vectors))) == length(vectors)
    for (a,b) in zip(old,new)
        @test a.program_inputs !== b.program_inputs
        @test a.program_inputs.inputs !== shared.inputs
        @test [(n.x_position,n.x_real_position,n.y_position,n.id) for n in a.program_inputs] ==
              [(n.x_position,n.x_real_position,n.y_position,n.id) for n in b.program_inputs]
    end
    for (a,b) in zip(old,new)
        @test a.is_reversed==b.is_reversed
        @test length(a)==length(b)
        for (x,y) in zip(a,b)
            @test x.fn === y.fn
            @test x.calling_node === y.calling_node
            @test length(x.inputs)==length(y.inputs)
            for (i,j) in zip(x.inputs,y.inputs)
                @test i.input === j.input
                @test i.type_idx == j.type_idx
                @test i.type === j.type
            end
        end
        @test MAGE.get_active_nodes(a)==MAGE.get_active_nodes(b)
    end
    @test MAGE.get_active_nodes(old)==MAGE.get_active_nodes(new)
    a=MAGE.compile_program(old,arch,ml); b=MAGE.compile_program(new,arch,ml)
    for name in (:node_to_tmp,:operation_order,:skipped_duplicates,:input_types,:output_types)
        hasfield(typeof(a),name) && @test getfield(a,name)==getfield(b,name)
    end
    @test MAGE.sequential_source(a)==MAGE.sequential_source(b)
    @test length(a.steps) == length(b.steps)
    # All IR fields, including keys and wrapper identity.
    for (x,y) in zip(a.steps,b.steps)
        @test typeof(x)===typeof(y)
        for name in fieldnames(typeof(x))
            xv,yv=getfield(x,name),getfield(y,name)
            @test isequal(xv,yv)
        end
    end
    values=Any[t===Int ? 2 : 2.0 for t in arch.inputs_types]
    @test isequal(a(values...),b(values...))
    return new
end
# Keep this randomized regression from changing later tests' random streams.
let saved_rng = copy(Random.default_rng())
try
@testset "Exact decode preserves expanded DFS" begin
    Random.seed!(617)
    for typed in (false,true), n in (5,25,100), rep in 1:40
        f=cache_fixture(;typed,n)
        # Random active graph, including repeated edges and multiple shared outputs.
        for o in f.genome.output_nodes
            o[2].value=rand(3:n+2)
        end
        decode_exact_check(f.genome,f.ml,f.arch,f.shared)
    end
    @testset "Mutation, inactive nodes, and input-only outputs" begin
        for typed in (false, true)
            f = cache_fixture(; typed, n=8)
            decode_exact_check(f.genome, f.ml, f.arch, f.shared)
            for rep in 1:12
                mutate_exact_fixture!(f)
                decode_exact_check(f.genome, f.ml, f.arch, f.shared)
            end
            # Every output reads a shared input; malformed inactive nodes are ignored.
            for o in f.genome.output_nodes
                o[2].value = typed && o.y_position == 2 ? 2 : 1
            end
            f.genome[1][8][1].value = typemax(Int)
            decode_exact_check(f.genome, f.ml, f.arch, f.shared)
            empty!(f.genome.output_nodes)
            @test isempty(MAGE.decode_with_output_nodes(f.genome, f.ml, f.arch, f.shared))
            @test isempty(MAGE.baseline_decode_with_output_nodes(f.genome, f.ml, f.arch, f.shared))
        end
    end
    @testset "Zero-arity active node" begin
        f = cache_fixture(; n=5)
        push!(f.ml[1].library, FunctionWrapper((args...) -> 3.0,
            :exact_constant, nothing, () -> 0.0))
        f.genome[1][1][1].value = length(f.ml[1])
        for o in f.genome.output_nodes
            o[2].value = 3
        end
        programs = decode_exact_check(f.genome, f.ml, f.arch, f.shared)
        @test isempty(first(first(programs)).inputs)
    end
    @testset "Malformed active node rejects extra or missing types" begin
        for extra in (false, true)
            f = cache_fixture(; n=5)
            material = f.genome.output_nodes[1].node_material.material
            type_index = findfirst(e -> e.element_type == MAGE.TYPE, material)
            if extra
                push!(material, deepcopy(material[type_index]))
            else
                deleteat!(material, type_index)
            end
            @test_throws AssertionError MAGE.baseline_decode_with_output_nodes(f.genome, f.ml, f.arch, f.shared)
            @test_throws AssertionError MAGE.decode_with_output_nodes(f.genome, f.ml, f.arch, f.shared)
        end
    end
    @testset "Concurrent decodes use independent metadata" begin
        f = cache_fixture(; typed=true, n=25)
        # Same read-only genome/library across tasks, then independent mutated genomes.
        # Tasks only decode; results are compared on this task, since recording
        # into a testset from several tasks is not thread-safe.
        jobs = map(1:8) do task
            Threads.@spawn begin
                decoded = []
                for rep in 1:5
                    push!(decoded, (decode_exact_pair(f.genome, f.ml, f.arch, f.shared)..., f))
                end
                Random.seed!(900 + task)
                for rep in 1:5
                    # A fresh copy per decode: later mutations must not touch
                    # the nodes that earlier programs reference.
                    local_f = deepcopy(f)
                    for _ in 1:rep
                        mutate_exact_fixture!(local_f)
                    end
                    push!(decoded, (decode_exact_pair(local_f.genome, local_f.ml, local_f.arch, local_f.shared)..., local_f))
                end
                decoded
            end
        end
        for job in jobs, (old, new, g) in fetch(job)
            decode_exact_compare(old, new, g.ml, g.arch, g.shared)
        end
    end
    # Explicit exponential duplicate paths.
    f=cache_fixture(;n=10)
    for k in 1:10
        node=f.genome[1][k]
        node[1].value=findfirst(i -> f.ml[1][i].name == :number_sum, 1:length(f.ml[1]))
        node[2].value=k==1 ? 1 : k+1
        node[4].value=node[2].value
    end
    for o in f.genome.output_nodes; o[2].value=12; end
    p=decode_exact_check(f.genome,f.ml,f.arch,f.shared)
    @test length(first(p))>100
    # No cross-decode state, including wrapper/ADF replacement.
    f=_install_deterministic_adf()
    g,arch,shared=_adf_calling_genome(length(f.ml[1])-1)
    decode_exact_check(g,f.ml,arch,shared)
    replace_adf_slot!(f.registry,f.slots[1].slot_id,f.genome,f.inputs,f.model_arch,f.ml;name=:replaced_exact)
    decode_exact_check(g,f.ml,arch,shared)
    # Replace the SAME mutable ADF slot with a different required arity.
    one_arch=modelArchitecture([Int],[1],[Int],[Int],[1])
    one_shared,one_genome=make_evolvable_utgenome(one_arch,f.ml,nodeConfig(1,1,3,1))
    initialize_genome!(one_genome)
    one_genome[1][1][1].value=1
    one_genome[1][1][2].value=1
    one_genome.output_nodes[1][1].value=1
    one_genome.output_nodes[1][2].value=2
    correct_all_nodes!(one_genome,one_arch,f.ml,one_shared)
    replace_adf_slot!(f.registry,f.slots[1].slot_id,one_genome,one_shared,one_arch,f.ml;name=:one_argument)
    @test which(f.slots[1],Tuple{Int,Int,Int}).nargs-2==1
    decode_exact_check(g,f.ml,arch,shared)
end
finally
    copy!(Random.default_rng(), saved_rng)
end
end
