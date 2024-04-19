using Base: Unordered
# Hash is done by hash/hash_genome/test
# This file test the callbacks, the calls to the DB logger
import DataStructures: OrderedDict
import SearchNetworks as sn
import UTCGP: SN_writer
import DataFrames: nrow

function sn_setup()
    vecint_bundles = UTCGP.get_listinteger_bundles()
    int_bundles = UTCGP.get_integer_bundles()
    run_config = runConf(1, 1, 0.1, 0.1) # indifferent
    model_architecture = modelArchitecture([Int], [1], [Int, Vector{Int}], [Int], [1]) # 1 input, 2 chromosomes, 1 output
    node_config = nodeConfig(1, 1, 1, 1) # smallest genome possible
    meta_library = MetaLibrary([Library(int_bundles), Library(vecint_bundles)])
    shared_inputs, utgenome =
        make_evolvable_utgenome(model_architecture, meta_library, node_config)
    # fix the input
    shared_inputs[1].value = 1
    # fix the parent
    utgenome[1][1][1].value = 1 # fn 1
    utgenome[2][1][1].value = 1 # fn 1
    # fix the connexion
    utgenome[1][1][2].value = 1 # to input node
    utgenome[2][1][2].value = 1 # to input node
    # fix the types
    utgenome[1][1][3].value = 1 # to its own type
    utgenome[2][1][3].value = 2 # to its own type

    utgenome.output_nodes[1][1].value = 1
    utgenome.output_nodes[1][2].value = 2
    utgenome.output_nodes[1][3].value = 1

    return Dict(
        "run_config" => run_config,
        "model_architecture" => model_architecture,
        "node_config" => node_config,
        "meta_library" => meta_library,
        "shared_inputs" => shared_inputs,
        "utgenome" => utgenome,
    )
end


edge_index_fn = UTCGP._mock_edge_prop_getter()
node_fn = UTCGP._mock_node_hash_function()
edge_fn = UTCGP._mock_edge_prop_getter()

include("test_hashers.jl")
include("test_edge_props.jl")
include("writer_instantiation.jl")
include("test_writer_internals.jl")
include("test_behavior_hasher.jl")
include("test_phen_hasher.jl")

@testset "SN Simulate Epoch" begin
    ### WRITER INTEGRATION ### 
    @test begin
        """
        Parent: GENOME ONLY
        No children, pop of 1

        Since all_edges is used => edge between the parent and the parent itself
        """
        con = sn.create_DB()
        sn.create_SN_tables!(
            con,
            extra_nodes_cols = OrderedDict(
                "gen_hash_1" => sn.SN_col_type(string = true),
                "gen_hash_2" => sn.SN_col_type(string = true),
            ),
            extra_edges_cols = OrderedDict("fitness" => sn.SN_col_type(float = true)),
        )
        sn_writer_callback = SN_writer(
            con,
            all_edges(),
            OrderedDict(
                "gen_hash_1" => sn_genotype_hasher(),
                "gen_hash_2" => UTCGP._mock_node_hash_function(),
            ),
            OrderedDict("fitness" => sn_fitness_hasher()),
        )
        # MOCK THE EPOCK
        setup = sn_setup()
        ind1 = deepcopy(setup["utgenome"])
        p1 = UTCGP.decode_with_output_nodes(
            ind1,
            setup["meta_library"],
            setup["model_architecture"],
            setup["shared_inputs"],
        )
        # call the callback
        sn_writer_callback(
            [1],
            Population([setup["utgenome"]]),
            1,
            setup["run_config"],
            setup["model_architecture"],
            setup["node_config"],
            setup["meta_library"],
            setup["shared_inputs"],
            UTCGP.PopulationPrograms(UTCGP.IndividualPrograms[]), # mocked
            1.0,
            p1,
            1,
        )
        # Manually calculate the hashes
        h1 = general_hasher_sha(setup["utgenome"]) # the first hasher should be this for the genome
        h2 = "mock node fn" # the second hasher is constant
        id = UTCGP._calc_individual_unique_hash(# the sha(union(hashes))
            OrderedDict("_" => [h1], "__" => [h2]),
            1,
        )

        # Compare hashes against what was writtent to DB
        nodes = sn.get_nodes_from_db(con)
        edges = sn.get_edges_from_db(con)
        #   Nodes
        cond1 = nodes[1, "gen_hash_1"] == h1
        cond2 = nodes[1, "gen_hash_2"] == h2
        cond3 = nodes[1, "id_hash"] == id
        #   Edges
        cond4 = nrow(edges) == 1 # Only one parent so no edges
        cond5 = edges[1, "_from"] == id
        cond6 = edges[1, "_to"] == id
        close(con)
        cond1 && cond2 && cond3 && cond4 && cond5 && cond6
    end

    @test begin
        """
        Parent: GENOME ONLY
        No children, pop of 1

        since we use all_edges_except_last. There are no edges
        """
        con = sn.create_DB()
        sn.create_SN_tables!(
            con,
            extra_nodes_cols = OrderedDict(
                "gen_hash_1" => sn.SN_col_type(string = true),
                "gen_hash_2" => sn.SN_col_type(string = true),
            ),
            extra_edges_cols = OrderedDict("fitness" => sn.SN_col_type(float = true)),
        )
        sn_writer_callback = SN_writer(
            con,
            all_edges_except_last(),
            OrderedDict(
                "gen_hash_1" => sn_genotype_hasher(),
                "gen_hash_2" => UTCGP._mock_node_hash_function(),
            ),
            OrderedDict("fitness" => sn_fitness_hasher_except_last()),
        )
        # MOCK THE EPOCK
        setup = sn_setup()
        ind1 = deepcopy(setup["utgenome"])
        p1 = UTCGP.decode_with_output_nodes(
            ind1,
            setup["meta_library"],
            setup["model_architecture"],
            setup["shared_inputs"],
        )
        # call the callback
        sn_writer_callback(
            [1],
            Population([setup["utgenome"]]),
            1,
            setup["run_config"],
            setup["model_architecture"],
            setup["node_config"],
            setup["meta_library"],
            setup["shared_inputs"],
            UTCGP.PopulationPrograms(UTCGP.IndividualPrograms[]), # mocked
            1.0,
            p1,
            1,
        )
        # Manually calculate the hashes
        h1 = general_hasher_sha(setup["utgenome"]) # the first hasher should be this for the genome
        h2 = "mock node fn" # the second hasher is constant
        id = UTCGP._calc_individual_unique_hash(# the sha(union(hashes))
            OrderedDict("_" => [h1], "__" => [h2]),
            1,
        )

        # Compare hashes against what was writtent to DB
        nodes = sn.get_nodes_from_db(con)
        edges = sn.get_edges_from_db(con)
        #   Nodes
        cond1 = nodes[1, "gen_hash_1"] == h1
        cond2 = nodes[1, "gen_hash_2"] == h2
        cond3 = nodes[1, "id_hash"] == id
        #   Edges
        cond4 = nrow(edges) == 0 # Only one parent so no edges
        close(con)
        cond1 && cond2 && cond3 && cond4
    end


    @test begin
        """
        One children but its the exact same (by genome and phenotype) 
            => Only one record created in the nodes (only one node)
            => an edge to itself (only one edge)
        """
        con = sn.create_DB()
        sn.create_SN_tables!(
            con,
            extra_nodes_cols = OrderedDict(
                "gen_hash_1" => sn.SN_col_type(string = true),
                "gen_hash_2" => sn.SN_col_type(string = true),
            ),
            extra_edges_cols = OrderedDict("fitness" => sn.SN_col_type(float = true)),
        )
        sn_writer_callback = SN_writer(
            con,
            all_edges_except_last(),
            OrderedDict(
                "gen_hash_1" => sn_genotype_hasher(),
                "gen_hash_2" => sn_softphenotype_hasher(),
            ),
            OrderedDict("fitness" => sn_fitness_hasher_except_last()),
        )

        # MOCK THE EPOCK
        setup = sn_setup()
        ind1 = deepcopy(setup["utgenome"]) # 2 identical genomes
        ind2 = deepcopy(setup["utgenome"]) # One parent, one child
        p1 = UTCGP.decode_with_output_nodes(
            ind1,
            setup["meta_library"],
            setup["model_architecture"],
            setup["shared_inputs"],
        )
        p2 = UTCGP.decode_with_output_nodes(
            ind2,
            setup["meta_library"],
            setup["model_architecture"],
            setup["shared_inputs"],
        )
        # call the callback with the 2 genomes
        sn_writer_callback(
            [1.0, 2.0],
            Population([ind1, ind2]),
            1,
            setup["run_config"],
            setup["model_architecture"],
            setup["node_config"],
            setup["meta_library"],
            setup["shared_inputs"],
            UTCGP.PopulationPrograms([p1, p2]), # mocked
            1.0,
            p1,
            1,
        )
        # Manually calculate the hashes
        h1 = general_hasher_sha(setup["utgenome"]) # the first hasher should be this for the genome
        h2 = general_hasher_sha(p1) # the second hasher hashes the program
        id = UTCGP._calc_individual_unique_hash(# the sha(union(hashes))
            OrderedDict("_" => [h1, "does_not_matter"], "__" => [h2, "ignored"]),
            1,
        )
        # Compare hashes against what was writtent to DB
        nodes = sn.get_nodes_from_db(con)
        edges = sn.get_edges_from_db(con)
        #   Nodes
        cond1 = nodes[1, "gen_hash_1"] == h1 # the genome hashed
        cond2 = nodes[1, "gen_hash_2"] == h2 # the program hashed
        cond3 = nodes[1, "id_hash"] == id # the hash of the union
        cond4 = nrow(nodes) == 1 # Since it's the exact same individual, one one line should be recorded
        #   Edges
        cond5 = nrow(edges) == 1 # 1 edge. Parent to identical child
        cond6 = edges[1, "_from"] == edges[1, "_to"] == id
        close(con)
        cond1 && cond2 && cond3 && cond4 && cond5 && cond6
    end

    @test begin
        """
        One children but its not the exact same 
        It has the same phenotype but not the same genotype
            => So two nodes records because two unique ids
            => an edge from parent to child
        """
        con = sn.create_DB()
        sn.create_SN_tables!(
            con,
            extra_nodes_cols = OrderedDict(
                "gen_hash_1" => sn.SN_col_type(string = true),
                "gen_hash_2" => sn.SN_col_type(string = true),
            ),
            extra_edges_cols = OrderedDict("fitness" => sn.SN_col_type(float = true)),
        )
        sn_writer_callback = SN_writer(
            con,
            all_edges_except_last(),
            OrderedDict(
                "gen_hash_1" => sn_genotype_hasher(),
                "gen_hash_2" => sn_softphenotype_hasher(),
            ),
            OrderedDict("fitness" => sn_fitness_hasher_except_last()),
        )

        # MOCK THE EPOCK
        setup = sn_setup()
        ind1 = deepcopy(setup["utgenome"]) # One genome
        ind2 = deepcopy(setup["utgenome"]) # Another genotype, BUT it will produce the same phenotype because that node is inactive
        ind2[2][1][1].value = 2 # this node is not in the active graph
        p1 = UTCGP.decode_with_output_nodes(
            ind1,
            setup["meta_library"],
            setup["model_architecture"],
            setup["shared_inputs"],
        )
        p2 = UTCGP.decode_with_output_nodes(
            ind2,
            setup["meta_library"],
            setup["model_architecture"],
            setup["shared_inputs"],
        )
        # call the callback with the 2 genomes
        sn_writer_callback(
            [1.0, 2.0],
            Population([ind1, ind2]),
            1,
            setup["run_config"],
            setup["model_architecture"],
            setup["node_config"],
            setup["meta_library"],
            setup["shared_inputs"],
            UTCGP.PopulationPrograms([p1, p2]), # mocked
            1.0,
            p1,
            1,
        )
        # Manually calculate the hashes
        #   Ind 1 
        ind1_h1 = general_hasher_sha(ind1) # this is unique 
        ind1_h2 = general_hasher_sha(p1) # this is the same as that for ind2
        #   Ind 2 
        ind2_h1 = general_hasher_sha(ind2) # this is unique 
        ind2_h2 = general_hasher_sha(p2) # the same as ind1
        hashes = OrderedDict("_" => [ind1_h1, ind2_h1], "__" => [ind1_h2, ind2_h2])
        ind1_id = UTCGP._calc_individual_unique_hash(hashes, 1)
        ind2_id = UTCGP._calc_individual_unique_hash(hashes, 2)

        # Compare hashes against what was writtent to DB
        nodes = sn.get_nodes_from_db(con)
        edges = sn.get_edges_from_db(con)

        #   Nodes => We should have 2 nodes
        c1 = nodes[1, "id_hash"] == ind1_id
        c2 = nodes[2, "id_hash"] == ind2_id

        c3 = nodes[1, "gen_hash_1"] == ind1_h1 != ind2_h1
        c4 = nodes[2, "gen_hash_1"] == ind2_h1 != ind1_h1

        c5 = nodes[1, "gen_hash_2"] == ind1_h2 == ind2_h2 # phenotypes are the same
        c6 = nodes[2, "gen_hash_2"] == ind2_h2 == ind1_h2 # phenotypes are not the same

        #   EDGES => We should have one edge
        c7 = edges[1, "_from"] == ind2_id # the last in the population is the parent
        c8 = edges[1, "_to"] == ind1_id # the first in the population is the child
        @assert nrow(edges) == 1
        close(con)
        c1 && c2 && c3 && c4 && c5 && c6 && c7 && c8
    end

    @test begin # Complex example but the most realistic one
        """
        Parent: Parent and 3 Children
        Genotype and phenotype hasher

        Except last is used for edges.
        
        One children with the same genotype and phenotype
        One children but with the same phenotype but different genotype
        One children with different genotype and phenotype
       """
        con = sn.create_DB()
        sn.create_SN_tables!(
            con,
            extra_nodes_cols = OrderedDict(
                "gen_hash_1" => sn.SN_col_type(string = true),
                "gen_hash_2" => sn.SN_col_type(string = true),
            ),
            extra_edges_cols = OrderedDict("fitness" => sn.SN_col_type(float = true)),
        )
        sn_writer_callback = SN_writer(
            con,
            all_edges_except_last(),
            OrderedDict(
                "gen_hash_1" => sn_genotype_hasher(),
                "gen_hash_2" => sn_softphenotype_hasher(),
            ),
            OrderedDict("fitness" => sn_fitness_hasher_except_last()),
        )

        # SETUP THE TEST 
        setup = sn_setup()
        ind1 = deepcopy(setup["utgenome"]) # The parent
        ind2 = deepcopy(setup["utgenome"]) # will be exactly the same
        ind3 = deepcopy(setup["utgenome"]) # diff genotype but same phenotype 
        ind4 = deepcopy(setup["utgenome"]) # everything is different
        ind3[2][1][1].value = 2 # this node is not in the active graph. So the genotype will change but not the phenotype
        ind4.output_nodes[1][2].value = 1 # This changes the genotype and phenotype
        p1 = UTCGP.decode_with_output_nodes(
            ind1,
            setup["meta_library"],
            setup["model_architecture"],
            setup["shared_inputs"],
        ) # == p2 
        p3 = UTCGP.decode_with_output_nodes(
            ind3,
            setup["meta_library"],
            setup["model_architecture"],
            setup["shared_inputs"],
        )
        p4 = UTCGP.decode_with_output_nodes(
            ind4,
            setup["meta_library"],
            setup["model_architecture"],
            setup["shared_inputs"],
        )

        # call the callback with the 2 genomes
        sn_writer_callback(
            [1.0, 2.0, 3.0, 4.0],
            Population([ind2, ind3, ind4, ind1]),
            1,
            setup["run_config"],
            setup["model_architecture"],
            setup["node_config"],
            setup["meta_library"],
            setup["shared_inputs"],
            UTCGP.PopulationPrograms([p1, p3, p4, p1]),
            1.0,
            p1,
            1,
        )
        # Manually calculate the hashes #
        #   Ind 1 && Ind 2 
        ind1_h1 = general_hasher_sha(ind1) # same as that for ind2
        ind1_h2 = general_hasher_sha(p1) # this is the same as that for ind2
        #   Ind 3 
        ind3_h1 = general_hasher_sha(ind3) # unique 
        ind3_h2 = general_hasher_sha(p3) # same as ind1_h2
        #   Ind 4
        ind4_h1 = general_hasher_sha(ind4) # unique 
        ind4_h2 = general_hasher_sha(p4) # unique

        hashes = OrderedDict(
            "hash1" => [ind1_h1, ind1_h1, ind3_h1, ind4_h1],
            "hash2" => [ind1_h2, ind1_h2, ind3_h2, ind4_h2],
        )
        ind1_id = UTCGP._calc_individual_unique_hash(hashes, 1)
        ind3_id = UTCGP._calc_individual_unique_hash(hashes, 3)
        ind4_id = UTCGP._calc_individual_unique_hash(hashes, 4)

        # Compare hashes against what was writtent to DB
        nodes = sn.get_nodes_from_db(con)
        edges = sn.get_edges_from_db(con)

        #   Nodes => We should have 3 nodes. Bc out of the 4 individuals, 1 is exactly the same (ind1 & ind2)
        @assert nrow(nodes) == 3
        @assert ind1_id != ind3_id # they cannot have the same id because they are different
        @assert ind1_id != ind4_id # they cannot have the same id 
        @assert ind1_h2 == ind3_h2 # even if they have diff ids, they have the same genotype 
        @assert ind3_id != ind4_id # they cannot have the same id 

        # --- each node has its corresponding id
        c1 = nodes[1, "id_hash"] == ind1_id # ind2_id was not written because it's the same as ind1_id
        c2 = nodes[2, "id_hash"] == ind3_id
        c3 = nodes[3, "id_hash"] == ind4_id

        # --- each node has its corresponding genome hash
        c4 = nodes[1, "gen_hash_1"] == ind1_h1
        c5 = nodes[2, "gen_hash_1"] == ind3_h1
        c6 = nodes[3, "gen_hash_1"] == ind4_h1

        # --- each node has its corresponding phenotype hash
        c7 = nodes[1, "gen_hash_2"] == ind1_h2
        c8 = nodes[2, "gen_hash_2"] == ind1_h2 # because this individual has a different genotype but the same phenotype
        c9 = nodes[3, "gen_hash_2"] == ind4_h2


        #   EDGES => We should have 3 edges 
        @assert nrow(edges) == 3 # because of except_last, the parent=> parent edge was not written
        parent_id = ind1_id
        e1_ok = edges[1, "_from"] == parent_id && edges[1, "_to"] == ind1_id
        e2_ok = edges[2, "_from"] == parent_id && edges[2, "_to"] == ind3_id
        e3_ok = edges[3, "_from"] == parent_id && edges[3, "_to"] == ind4_id
        close(con)
        @assert edges[1, "fitness"] == 1.0
        @assert edges[2, "fitness"] == 2.0
        @assert edges[3, "fitness"] == 3.0
        c1 && c2 && c3 && c4 && c5 && c6 && c7 && c8 && c9 && e1_ok && e2_ok && e3_ok
    end
end
