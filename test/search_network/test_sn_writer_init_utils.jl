@testset "SN Writer init utils" begin
    # FAILS BECAUSE COLUMNS DONT MATCH --- ---  

    #   DB has no extra cols, so in principle
    #   we should not be able to provide hashers  
    @test_throws AssertionError begin
        con = sn.create_DB()
        sn.create_SN_tables!(con) # no extra cols
        UTCGP._assert_sn_writer_consistency(
            con,
            OrderedDict("a" => () -> 1),
            sn.Abstract_Nodes,
        )
    end

    #   DB has no extra cols, so in principle
    #   we should not be able to provide hashers  
    @test_throws AssertionError begin
        con = sn.create_DB()
        sn.create_SN_tables!(con) # no extra cols
        UTCGP._assert_sn_writer_consistency(
            con,
            OrderedDict("a" => () -> 1),
            sn.Abstract_Edges,
        )
    end

    #   DB has 2 cols but writer wants to have 3 
    @test_throws AssertionError begin
        con = sn.create_DB() # no extra cols
        sn.create_SN_tables!(
            con,
            extra_nodes_cols = OrderedDict(
                "a" => sn.SN_col_type(float = true),
                "b" => sn.SN_col_type(float = true),
            ),
        ) # memory
        UTCGP._assert_sn_writer_consistency(
            con,
            OrderedDict("a" => () -> 1, "b" => () -> 1, "c" => () -> 1),
            sn.Abstract_Nodes,
        )
    end
    #   DB has 3 cols, writer also has 3 but in wrong order 
    @test_throws AssertionError begin
        con = sn.create_DB() # no extra cols
        sn.create_SN_tables!(
            con,
            extra_edges_cols = OrderedDict(
                "a" => sn.SN_col_type(float = true),
                "c" => sn.SN_col_type(float = true),
                "b" => sn.SN_col_type(float = true),
            ),
        ) # memory
        UTCGP._assert_sn_writer_consistency(
            con,
            OrderedDict("a" => () -> 1, "b" => () -> 1, "c" => () -> 1),
            sn.Abstract_Edges,
        )
    end

    # CORRECT CREATION BECAUSE GOOD NB & GOOD ORDER --- ---  
    @test begin # For NODES
        con = sn.create_DB() # no extra cols
        sn.create_SN_tables!(
            con,
            extra_edges_cols = OrderedDict(
                "a" => sn.SN_col_type(float = true),
                "b" => sn.SN_col_type(float = true),
            ),
        ) # memory
        UTCGP._assert_sn_writer_consistency(
            con,
            OrderedDict("a" => () -> 1, "b" => () -> 1),
            sn.Abstract_Edges,
        )
        true
    end
    @test begin # For EDGES
        con = sn.create_DB() # no extra cols
        sn.create_SN_tables!(
            con,
            extra_edges_cols = OrderedDict(
                "a" => sn.SN_col_type(float = true),
                "c" => sn.SN_col_type(float = true),
            ),
        ) # memory
        UTCGP._assert_sn_writer_consistency(
            con,
            OrderedDict("a" => () -> 1, "c" => () -> 1),
            sn.Abstract_Edges,
        )
        true
    end
end

