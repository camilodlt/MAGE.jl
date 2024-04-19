using Serialization
using DuckDB
import DataStructures: OrderedDict
import SearchNetworks as sn
using DataFrames
using SHA

##############################
#    SN WRITER CALLABLE      #
#                            #
# The whole population hasher#
##############################

"""
    SN_writer(con::DuckDB.DB, hashers::OrderedDict{String,<:Function})

SN Writer is an struct who will be responsible for the Search Network callbacks. 

This SN Writer is meant to store all the individuals in the population, that population is not
filtered in any way.

It accepts :
    - A function that returns the index of the edges relative to the population 
    - The functions that will hash the individuals
    - The functions that will provide information for the edges

See the call to the instantiation of this struct for more information
"""
struct SN_writer <: Abstract_SN_Writer
    con::DuckDB.DB
    edges_indices_fn::Abstract_Edge_Prop_Getter
    nodes_hashers::OrderedDict{String,<:Abstract_Node_Hash_Function}
    edges_prop_getters::Union{OrderedDict{String,<:Abstract_Edge_Prop_Getter},Nothing}
    function SN_writer(
        con::DuckDB.DB,
        edges_indices_fn::Abstract_Edge_Prop_Getter,
        nodes_hashers::OrderedDict{String,<:Abstract_Node_Hash_Function},
        edges_prop_getters::Union{OrderedDict{String,<:Abstract_Edge_Prop_Getter},Nothing},
    )
        _assert_sn_writer_consistency(con, nodes_hashers, sn.Abstract_Nodes)
        _assert_sn_writer_consistency(con, edges_prop_getters, sn.Abstract_Edges)
        return new(con, edges_indices_fn, nodes_hashers, edges_prop_getters)
    end
end

"""
The instantiated SN_writer writes : 
- The nodes 
- The edges between the parent and all the children

Hashes will depend on which hashers where passed to the SN_writer during initialization. 

All individuals are hashed with those hashers. 

Edges happen between the `id_hash` of the parent and that of every child. 
Extra cols for the EDGE table depend on the `edges_prop_getters` of the struct. 

Note: `id_hash` is the hash of the union of all extra hashes. 
"""
function (writer::SN_writer)(
    ind_performances::Union{Vector{<:Number},Vector{Vector{<:Number}}},
    population::Population,
    generation::Int,
    run_config::runConf,
    model_architecture::modelArchitecture,
    node_config::nodeConfig,
    meta_library::MetaLibrary,
    shared_inputs::SharedInput,
    programs::PopulationPrograms,
    best_loss::Float64,
    best_program::IndividualPrograms,
    elite_idx::Int,
)
    epoch_params = UTCGP.ParametersStandardEpoch(
        ind_performances,
        population,
        generation,
        run_config,
        model_architecture,
        node_config,
        meta_library,
        shared_inputs,
        programs,
        best_loss,
        best_program,
        elite_idx,
    )
    # Hash all individuals (NODES)
    all_hash_rows = _get_rows_by_running_all_fns(epoch_params, writer, sn.Abstract_Nodes)
    _log_n_rows_view(all_hash_rows, sn.Abstract_Nodes)

    # Get Info for all edges (EDGES)
    indices_for_edges = writer.edges_indices_fn(epoch_params)
    all_edges_info = _get_rows_by_running_all_fns(epoch_params, writer, sn.Abstract_Edges)
    _log_n_rows_view(all_edges_info, sn.Abstract_Edges)
    @assert length(indices_for_edges) == length(all_edges_info) "Mismatch between the number of edges rows and the indices of those edges : $(all_edges_info) vs $(indices_for_edges )"

    # write Nodes to DB
    r = sn.write_only_new_to_nodes!(writer.con, identity.(all_hash_rows))
    @assert r == 0 "DB result is 1, so writing failed"

    # Write Edges if any
    p_hash = all_hash_rows[end]["id_hash"] # pick the parent
    for (ith_child, child) in zip(indices_for_edges, all_edges_info)
        @debug "Edge from parent => $ith_child"
        _to = all_hash_rows[ith_child]["id_hash"] # ⚠ The ith child has to match with the length of the hashed rows. # make a fn that verif this ? # TODO
        r = sn.write_to_edges!(
            writer.con,
            OrderedDict(
                "_from" => p_hash,
                "_to" => _to,
                "iteration" => generation,
                child...,
            ),
        )
        @assert r == 0 "DB result is 1, so writing edge failed"
    end

    # CHECKPOINT EVERY 100 its
    if generation % 50 == 0
        println("Manual DB Checkpoint at generation $generation")
        sn._execute_command(writer.con, "CHECKPOINT")
    end
    #
end

# EXPORT # 
export SN_writer


# ##############################
# #    SN ELITE CALLABLE       #
# #                            #
# # The elite hasher           #
# ##############################


# """
#         SN_elite_writer(con::DuckDB.DB, hashers::OrderedDict{String,<:Function})

# SN Writer is an struct who will be responsible 
# for the Search Network callbacks. 

# This Writer will only write the edges from parent to elite. This more closely ressembles
# the SearchTrajectoryNetwork.

# See the call to the instantiation of this struct for more information
# """
# struct SN_elite_writer <: Abstract_SN_Writer
#     con::DuckDB.DB
#     hashers_per_col::OrderedDict{String,<:Function}
#     function SN_elite_writer(con::DuckDB.DB, hashers::OrderedDict{String,<:Function})
#         _assert_sn_writer_consistency(con, hashers)
#         return new(con, hashers)
#     end
# end




