using Test, Random, MAGE
include(joinpath(@__DIR__, "fixtures/decode_helpers.jl"))

# Same Operations (function, calling node, input objects and types) in the same order.
function node_table_same(a, b)
    length(a) == length(b) || return false
    all(zip(a, b)) do (p, q)
        length(p) == length(q) || return false
        all(zip(p, q)) do (x, y)
            x.fn === y.fn && x.calling_node === y.calling_node &&
            length(x.inputs) == length(y.inputs) && all(zip(x.inputs, y.inputs)) do (i, j)
                i.input === j.input && i.type === j.type && i.type_idx == j.type_idx
            end
        end
    end
end

# Decodes `f.genome` with and without the table and checks every observable result.
function node_table_exact(f, table)
    a = MAGE.decode_with_output_nodes(f.genome, f.ml, f.arch, f.shared)
    b = MAGE.decode_with_output_nodes(f.genome, f.ml, f.arch, f.shared; node_table = table)
    @test node_table_same(a, b)
    @test MAGE.get_active_nodes(a) == MAGE.get_active_nodes(b)
    vectors = [o.inputs for p in b for o in p]
    @test length(unique(objectid.(vectors))) == length(vectors)   # no shared input vectors
    x = MAGE.ActiveNodeCacheEntry(); y = MAGE.ActiveNodeCacheEntry()
    MAGE.capture_active_nodes!(x, f.genome, a); MAGE.capture_active_nodes!(y, f.genome, b)
    @test x.positions == y.positions
    ca = MAGE.compile_program(a, f.arch, f.ml); cb = MAGE.compile_program(b, f.arch, f.ml)
    @test MAGE.sequential_source(ca) == MAGE.sequential_source(cb)
    for field in (:node_to_tmp, :operation_order, :skipped_duplicates, :input_types, :output_types)
        @test isequal(getfield(ca, field), getfield(cb, field))
    end
    values = Any[t === Int ? 2 : 2.0 for t in f.arch.inputs_types]
    @test isequal(ca(values...), cb(values...))
    b
end

# Randomizes 10% of the free genes of a copy of `genome`, then repairs types.
function node_table_mutant(f)
    g = deepcopy(f.genome)
    for chromosome in g.genomes, node in chromosome.chromosome, e in node.node_material.material
        !e.is_freezed && rand() < 0.1 && (e.value = random_element_value(e))
    end
    for output in g.output_nodes; output[2].value = rand(3:102); end
    correct_all_nodes!(g, f.arch, f.ml, f.shared)
    g
end

let saved_rng = copy(Random.default_rng())
try
@testset "Shared node decode table" begin
    Random.seed!(932)
    f = cache_fixture()

    @testset "construction and architecture guard" begin
        @test_throws ArgumentError NodeDecodeTable(f.arch, f.genome; shards = 0)
        @test_throws ArgumentError NodeDecodeTable(f.arch, f.genome; capacity = -1)
        @test isbitstype(MAGE.NodeRecipeKey{2})
        other = cache_fixture(; typed = true)
        table = NodeDecodeTable(other.arch, other.genome)
        @test_throws ArgumentError MAGE.decode_with_output_nodes(f.genome, f.ml, f.arch, f.shared; node_table = table)
    end

    @testset "exact on mutated populations (typed = $typed)" for typed in (false, true)
        g = cache_fixture(; typed, n = 100)
        table = NodeDecodeTable(g.arch, g.genome)
        # 25 generations of 80 mutants; the last mutant becomes the next parent.
        for generation in 1:25, child in 1:80
            mutant = merge(g, (genome = node_table_mutant(g),))
            node_table_exact(mutant, table)
            child == 80 && (g = mutant)
        end
        hits = node_decode_stats(table).hits
        node_table_exact(g, table)
        @test node_decode_stats(table).hits > hits

        # Decoding callback, including the ordered active-node cache.
        pop = MAGE.Population([deepcopy(g.genome) for _ in 1:256])
        cache = MAGE.ActiveNodeCache(256)
        default_decoding_callback(pop, 1, RunConfGA(1, 256, 1, 1.1, 0.1, 1), g.arch,
            nodeConfig(100, 1, 2, 2), g.ml, g.shared, table, cache)
        @test all(MAGE.check_active_nodes(cache[i], pop[i], g.ml, g.arch, g.shared) for i in 1:256)

        # Threaded decoding with one shared table.
        reference = [MAGE.decode_with_output_nodes(x, g.ml, g.arch, g.shared) for x in pop]
        actual = Vector{MAGE.IndividualPrograms}(undef, length(pop))
        Threads.@threads for i in eachindex(actual)
            actual[i] = MAGE.decode_with_output_nodes(pop[i], g.ml, g.arch, g.shared; node_table = table)
        end
        @test all(node_table_same(reference[i], actual[i]) for i in eachindex(actual))

        # Many migrating tasks inserting overlapping keys while others clear the table.
        stress = NodeDecodeTable(g.arch, g.genome; shards = 4, capacity = 40)
        tasks = [Threads.@spawn begin
            local genomes = [node_table_mutant(g) for _ in 1:12]
            for rep in 1:30, x in genomes
                p = MAGE.decode_with_output_nodes(x, g.ml, g.arch, g.shared; node_table = stress)
                q = MAGE.decode_with_output_nodes(x, g.ml, g.arch, g.shared)
                node_table_same(p, q) || error("concurrent mismatch")
                rep % 7 == 0 && clear!(stress)
                yield()
            end
            true
        end for _ in 1:32]
        @test all(fetch, tasks)
        @test node_decode_stats(stress).size <= 40
    end

    @testset "statistics, clear! and capacity" begin
        table = NodeDecodeTable(f.arch, f.genome)
        node_table_exact(f, table)
        s = node_decode_stats(table)
        @test s.lookups == s.hits + s.misses
        @test s.size == s.misses
        clear!(table)
        @test node_decode_stats(table).size == 0
        @test node_decode_stats(table).lookups == s.lookups
        tiny = NodeDecodeTable(f.arch, f.genome; shards = 1, capacity = 1)
        node_table_exact(f, tiny); node_table_exact(f, tiny)
        @test node_decode_stats(tiny).size <= 1
        none = NodeDecodeTable(f.arch, f.genome; capacity = 0)
        node_table_exact(f, none)
        @test node_decode_stats(none).size == 0
    end

    @testset "keys hold the genes, not the node position" begin
        g = deepcopy(f.genome)
        table = NodeDecodeTable(f.arch, g)
        first_node, copy_node = g[1][2], g[1][3]
        for (from, to) in zip(first_node.node_material.material, copy_node.node_material.material)
            to.value = from.value
        end
        @test MAGE._node_recipe_key(table, first_node, 1) == MAGE._node_recipe_key(table, copy_node, 1)
        # A different connection gives a different key and a correct, separate decode.
        key = MAGE._node_recipe_key(table, copy_node, 1)
        copy_node[2].value = copy_node[2].value == 1 ? 2 : 1
        @test MAGE._node_recipe_key(table, copy_node, 1) != key
        node_table_exact(merge(f, (genome = g,)), table)
    end

    @testset "context changes and malformed cache hits" begin
        g = cache_fixture(; n = 5)
        table = NodeDecodeTable(g.arch, g.genome)
        node_table_exact(g, table)
        # A distinct library with identical genes and no intervening version bump
        # is caught on the first hit; after a bump the table decodes exactly.
        other_ml = deepcopy(g.ml)
        @test_throws ErrorException MAGE.decode_with_output_nodes(g.genome, other_ml, g.arch, g.shared; node_table = table)
        MAGE.bump_library_decode_version!()
        node_table_exact(merge(g, (ml = other_ml,)), table)
        # Direct vector replacement bypasses mutator hooks: caught the same way.
        other_ml[1].library[1] = deepcopy(other_ml[1].library[1])
        @test_throws ErrorException MAGE.decode_with_output_nodes(g.genome, other_ml, g.arch, g.shared; node_table = table)
        MAGE.bump_library_decode_version!()
        node_table_exact(g, table)
        # The architecture object is unchanged while its input type vector changes.
        g.arch.inputs_types[1] = Int
        @test_throws ErrorException MAGE.decode_with_output_nodes(g.genome, g.ml, g.arch, g.shared)
        @test_throws ArgumentError MAGE.decode_with_output_nodes(g.genome, g.ml, g.arch, g.shared; node_table = table)
        g.arch.inputs_types[1] = Float64
        # Chromosome offsets belong to the genome, not to the architecture.
        shifted = deepcopy(g.genome)
        shifted.genomes[1] = MAGE.SingleGenome(3, shifted.genomes[1].chromosome)
        @test_throws ArgumentError MAGE.decode_with_output_nodes(shifted, g.ml, g.arch, g.shared; node_table = table)
        material = g.genome.output_nodes[1].node_material.material
        type_index = findfirst(e -> e.element_type == MAGE.TYPE, material)
        push!(material, deepcopy(material[type_index]))
        @test_throws AssertionError MAGE.decode_with_output_nodes(g.genome, g.ml, g.arch, g.shared)
        @test_throws AssertionError MAGE.decode_with_output_nodes(g.genome, g.ml, g.arch, g.shared; node_table = table)
        bounded = NodeDecodeTable(f.arch, f.genome; shards = 4, capacity = 3)
        node_table_exact(f, bounded)
        @test node_decode_stats(bounded).size <= 3
    end

    @testset "library edits invalidate recipes" begin
        table = NodeDecodeTable(f.arch, f.genome)
        node_table_exact(f, table)
        misses = node_decode_stats(table).misses
        unpack_bundles_in_library!(f.ml[1])
        node_table_exact(f, table)
        @test node_decode_stats(table).misses > misses
        misses = node_decode_stats(table).misses
        bump_library_decode_version!()
        node_table_exact(f, table)
        @test node_decode_stats(table).misses > misses
    end

    @testset "ADF slot replacement, including a new arity" begin
        adf = _install_deterministic_adf()
        genome, arch, shared = _adf_calling_genome(length(adf.ml[1]) - 1)
        af = (genome = genome, ml = adf.ml, arch = arch, shared = shared)
        table = NodeDecodeTable(arch, genome)
        node_table_exact(af, table)
        misses = node_decode_stats(table).misses
        replace_adf_slot!(adf.registry, adf.slots[1].slot_id, adf.genome, adf.inputs, adf.model_arch, adf.ml; name = :table_replaced)
        node_table_exact(af, table)
        @test node_decode_stats(table).misses > misses
        # The same slot now takes one input.
        one_arch = modelArchitecture([Int], [1], [Int], [Int], [1])
        one_shared, one_genome = make_evolvable_utgenome(one_arch, adf.ml, nodeConfig(1, 1, 3, 1))
        initialize_genome!(one_genome)
        one_genome[1][1][1].value = 1; one_genome[1][1][2].value = 1
        one_genome.output_nodes[1][1].value = 1; one_genome.output_nodes[1][2].value = 2
        correct_all_nodes!(one_genome, one_arch, adf.ml, one_shared)
        replace_adf_slot!(adf.registry, adf.slots[1].slot_id, one_genome, one_shared, one_arch, adf.ml)
        node_table_exact(af, table)
        @test which(adf.slots[1], Tuple{Int, Int, Int}).nargs - 2 == 1
    end
end
finally
    copy!(Random.default_rng(), saved_rng)
end
end
