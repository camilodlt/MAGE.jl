function sn_behavior_hasher_set()
    examples = [
        # ex 1
        [
            [1, 2, 3], # input 1 => vec{int}
            1.0, # input 2 => float
        ],
        # ex 2 
        [[2, 3, 4], 2.0],
        # ex 3
        [[5, 6, 7], 3.0],
    ]
    return examples
end

function sn_behavior_epoch_mock()
    # Libraries
    float_bundles = UTCGP.get_float_bundles() # type 1
    vecint_bundles = UTCGP.get_listinteger_bundles() # type 2
    meta_library = MetaLibrary([Library(float_bundles), Library(vecint_bundles)])

    # mock the epoch and run 
    run_config = runConf(1, 1, 0.1, 0.1) # indifferent
    model_architecture = modelArchitecture(
        [Vector{Int}, Float64],
        [2, 1],
        [Float64, Vector{Int}],
        [Float64, Vector{Int}],
        [1, 2],
    ) # 2 input, 2 chromosomes, 2 outputs
    node_config = nodeConfig(5, 1, 2, 2)
    shared_inputs, utgenome =
        make_evolvable_utgenome(model_architecture, meta_library, node_config)

    # Fix the first parent # 
    shared_inputs[1].value = [1]
    shared_inputs[2].value = 0.0
    for c_index = 1:2
        for n_index = 1:5
            for al_index = 1:5
                # fix the parent
                utgenome[c_index][n_index][al_index].value =
                    utgenome[c_index][n_index][al_index].lowest_bound
            end
        end
    end
    utgenome.output_nodes[1][1].value = 1
    utgenome.output_nodes[1][2].value = 1
    utgenome.output_nodes[1][3].value = 1
    utgenome.output_nodes[2][1].value = 1
    utgenome.output_nodes[2][2].value = 1
    utgenome.output_nodes[2][3].value = 1

    return Dict(
        "run_config" => run_config,
        "model_architecture" => model_architecture,
        "node_config" => node_config,
        "meta_library" => meta_library,
        "shared_inputs" => shared_inputs,
        "utgenome" => utgenome,
    )
end

function make_same_pheno_diff_geno(parent)
    """
    The parent just identities the two inputs. 

    This child will do the same, we'll change an inactive part in the genotype. 

    So these should follow : 
        - hash for genotype != than that from parent
        - hash for phenotype == than that from parent
    """
    child = deepcopy(parent)
    child[1][1][1].value = parent[1][1][1].value + 1
    return child
end

function make_two_behaviors_the_same_but_diff_encoding(parent, d)
    """
    From the parent, we'll make two programs that yield the same results.
    But the genotype and phenotype are different. 

    The program returns : 
        - the vector of ints squared - the float value
        - the float squared

    So these should follow : 
        - hash for genotype != than that from parent & sibling
        - hash for phenotype != than that from parent & sibling
        - hash for behavior == than that from sibling 
        """
    libf = d["meta_library"][1]
    libvecint = d["meta_library"][2]

    child1 = deepcopy(parent)
    child2 = deepcopy(parent)

    # MAKE FIRST CHILD --- 
    child1.output_nodes[1][2].value = 7 # connects to last working node
    child1.output_nodes[1][3].value = 1 # float
    child1.output_nodes[2][2].value = 7 # connects to last working node
    child1.output_nodes[2][3].value = 2 # vec

    #   point last working node to first working node
    #   fn and type are ok 
    child1[1][5][2].value = 3

    #   mult the number by itself
    child1[1][1][1].value =
        [i for (i, fn) in enumerate(libf.library) if fn.name == :number_mult][1]
    child1[1][1][2].value = 2 # con to input, type is ignored
    child1[1][1][4].value = 2 # con to input, type is ignored

    #   last working node to 5th node
    #    fn is ok : identity 
    child1[2][5][2].value = 5 # con to input
    child1[2][5][3].value = 2 # vec type

    #    5th node to 3 (vec) and 3 (float)
    child1[2][3][1].value =
        [i for (i, fn) in enumerate(libvecint.library) if fn.name == :subtract_broadcast][1]
    child1[2][3][2].value = 3 # con to input
    child1[2][3][3].value = 2 # float type
    child1[2][3][4].value = 3 # con to input
    child1[2][3][5].value = 1 # float type

    #   3th node is mult between the vec and the vec 
    child1[2][1][1].value =
        [i for (i, fn) in enumerate(libvecint.library) if fn.name == :mult_vector][1]
    child1[2][1][2].value = 1 # con to input, type is ignored
    child1[2][1][4].value = 1 # con to input, type is ignored


    # MAKE SECOND CHILD --- 
    child2.output_nodes[1][2].value = 7 # connects to last working node
    child2.output_nodes[1][3].value = 1 # float
    child2.output_nodes[2][2].value = 7 # connects to last working node
    child2.output_nodes[2][3].value = 2 # vec

    #   point last working node to second working node which will do the identity
    #   fn and type are ok 
    child2[1][5][2].value = 4
    #   point the 4th node to the 3rth node 
    child2[1][2][2].value = 3

    #   mult the number by itself
    child2[1][1][1].value =
        [i for (i, fn) in enumerate(libf.library) if fn.name == :number_mult][1]
    child2[1][1][2].value = 2 # con to input, type is ignored
    child2[1][1][4].value = 2 # con to input, type is ignored

    #   last working node to 5th node
    #    fn is ok : identity 
    child2[2][5][2].value = 5 # con to input
    child2[2][5][3].value = 2 # vec type

    #    5th node to 3 (vec) and 3 (float)
    child2[2][3][1].value =
        [i for (i, fn) in enumerate(libvecint.library) if fn.name == :subtract_broadcast][1]
    child2[2][3][2].value = 3 # con to input
    child2[2][3][3].value = 2 # float type
    child2[2][3][4].value = 3 # con to input
    child2[2][3][5].value = 1 # float type

    #   3th node is mult between the vec and the vec 
    child2[2][1][1].value =
        [i for (i, fn) in enumerate(libvecint.library) if fn.name == :mult_vector][1]
    child2[2][1][2].value = 1 # con to input, type is ignored
    child2[2][1][4].value = 1 # con to input, type is ignored

    return child1, child2
end

@testset "sn_behavior_hasher" begin
    sn_example_set = sn_behavior_hasher_set()

    # INIT 
    @test begin
        example_set = sn_behavior_hasher_set()
        example_set = sn_behavior_hasher(example_set)
        true
    end

    # HASH THE INDIVIDUALS
    @test begin # Complex example but the most realistic one
        """
        One parent and 4 children.
            - First child => same behavior bc same phenotype, same genotype
            - Second child => same behavior bc same phenotype but different genotype (inactive part mutated)
            - Thrid child => new behavior with an unique phenotype and genotype
            - Fourth child => same behavior as 3 with an unique phenotype and genotype

        """
        con = sn.create_DB()
        sn.create_SN_tables!(
            con,
            extra_nodes_cols = OrderedDict(
                "gen_hash" => sn.SN_col_type(string = true),
                "phen_hash" => sn.SN_col_type(string = true),
                "behavior_hash" => sn.SN_col_type(string = true),
            ),
            extra_edges_cols = OrderedDict("fitness" => sn.SN_col_type(float = true)),
        )
        example_set = sn_behavior_hasher_set()
        sn_writer_callback = SN_writer(
            con,
            all_edges(),
            OrderedDict(
                "gen_hash" => sn_genotype_hasher(),
                "phen_hash" => sn_softphenotype_hasher(),
                "behavior_hash" => sn_behavior_hasher(example_set),
            ),
            OrderedDict("fitness" => sn_fitness_hasher()),
        )

        d = sn_behavior_epoch_mock()
        parent = d["utgenome"]
        child1 = deepcopy(d["utgenome"])
        child2 = make_same_pheno_diff_geno(child1)
        child3, child4 = make_two_behaviors_the_same_but_diff_encoding(parent, d)
        progs = []
        for g in [child1, child2, child3, child4, parent]
            p = UTCGP.decode_with_output_nodes(
                g,
                d["meta_library"],
                d["model_architecture"],
                d["shared_inputs"],
            )
            push!(progs, p)

        end

        # call the callback with the 2 genomes
        sn_writer_callback(
            [4.0, 4.0, 2.0, 2.0, 4.0],
            Population([child1, child2, child3, child4, parent]),
            1,
            d["run_config"],
            d["model_architecture"],
            d["node_config"],
            d["meta_library"],
            d["shared_inputs"],
            UTCGP.PopulationPrograms(identity.(progs)),
            1.0,
            progs[3],
            1,
        )

        # Compare hashes against what was writtent to DB
        nodes = sn.get_nodes_from_db(con)
        edges = sn.get_edges_from_db(con)
        @show nodes

        @assert nrow(nodes) == 4 # parent copy and 3 unique children
        # The parent copy follows : 
        @assert nodes[1, "gen_hash"] != nodes[2, "gen_hash"] # a non active part is different
        @assert nodes[1, "phen_hash"] == nodes[2, "phen_hash"] # but the active graph is the same
        @assert nodes[1, "phen_hash"] != nodes[3, "phen_hash"] != nodes[4, "phen_hash"] # 1 & 2 have the same phenotype. but 1 != 3 != 4   
        @assert nodes[1, "behavior_hash"] == nodes[2, "behavior_hash"] # same bec same phen
        @assert nodes[1, "behavior_hash"] != nodes[3, "behavior_hash"] # it's behavior is very different

        # 2 graphs produce the same behavior 
        @assert nodes[3, "phen_hash"] != nodes[4, "phen_hash"]
        @assert nodes[3, "gen_hash"] != nodes[4, "gen_hash"] # they are diff encoding
        @assert nodes[3, "behavior_hash"] == nodes[4, "behavior_hash"] # but same behavior
        return true
    end
end


function math_known_algo(x)
    denominator = sqrt(2 * pi)
    numerator = exp((-x[1]^2) / 2)
    result = numerator / denominator
    return result
end

@testset "FP behavior hasher" begin
    @test begin
        inputs = [
            0.18735761587258179362368772172687168768728763762,
            1.28392863827983871798271,
            -0.12678273683131,
        ]
        OUTPUTS = []
        for ind = 1:100_000
            ind_outputs = []
            push!(OUTPUTS, ind_outputs)
            for input in inputs
                push!(ind_outputs, math_known_algo(input))
            end
        end
        HASHES_PER_INDIVIDUAL = [general_hasher_sha(ind_outputs) for ind_outputs in OUTPUTS]
        unique_hashes = unique(HASHES_PER_INDIVIDUAL)
        @show unique_hashes
        length(unique_hashes) == 1
    end
end
