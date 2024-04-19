
@testset "SN writer Instantiation" begin
    ### WRITER INSTANTIATION ###

    # SN WRITER VERIFICATIONS
    @test_throws AssertionError begin # Wrong names 
        con = sn.create_DB()
        sn.create_SN_tables!(
            con,
            extra_nodes_cols = OrderedDict(
                "gen_hash_1" => sn.SN_col_type(string = true),
                "gen_hash_2" => sn.SN_col_type(string = true),
            ),
        )
        sn_writer_callback = SN_writer(
            con,
            edge_index_fn,
            OrderedDict("gen_hash" => node_fn, "gen_hash_2" => node_fn),
            nothing,
        )
    end

    @test_throws AssertionError begin # Wrong number of columns
        con = sn.create_DB()
        sn.create_SN_tables!(
            con,
            extra_nodes_cols = OrderedDict(
                "gen_hash_1" => sn.SN_col_type(string = true),
                "gen_hash_2" => sn.SN_col_type(string = true),
            ),
        )
        sn_writer_callback =
            SN_writer(con, edge_index_fn, OrderedDict("gen_hash_2" => node_fn), nothing)
    end

    @test begin # correct_creation passing only nodes fns :) 
        con = sn.create_DB()
        sn.create_SN_tables!(
            con,
            extra_nodes_cols = OrderedDict(
                "gen_hash_1" => sn.SN_col_type(string = true),
                "gen_hash_2" => sn.SN_col_type(string = true),
            ),
        )
        sn_writer_callback = SN_writer(
            con,
            edge_index_fn,
            OrderedDict("gen_hash_1" => node_fn, "gen_hash_2" => node_fn),
            nothing,
        ) # abstract callable
        nodes = sn.get_nodes_from_db(con)
        close(con)
        names(nodes) == ["id_hash", "gen_hash_1", "gen_hash_2"]
    end

    @test begin # correct_creation passing nodes and edges fns:) 
        con = sn.create_DB()
        sn.create_SN_tables!(
            con,
            extra_nodes_cols = OrderedDict(
                "gen_hash_1" => sn.SN_col_type(string = true),
                "gen_hash_2" => sn.SN_col_type(string = true),
            ),
            extra_edges_cols = OrderedDict("edge_info_1" => sn.SN_col_type(string = true)),
        )
        sn_writer_callback = SN_writer(
            con,
            edge_index_fn,
            OrderedDict("gen_hash_1" => node_fn, "gen_hash_2" => node_fn),
            OrderedDict("edge_info_1" => edge_fn),
        ) # abstract callable
        nodes = sn.get_nodes_from_db(con)
        edges = sn.get_edges_from_db(con)
        close(con)
        names(nodes) == ["id_hash", "gen_hash_1", "gen_hash_2"] &&
            "edge_info_1" in names(edges)
    end
end
