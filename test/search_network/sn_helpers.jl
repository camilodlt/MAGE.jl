using Base: Unordered
import DataStructures: OrderedDict
import SearchNetworks as sn
import UTCGP: SN_writer
import DataFrames: nrow

function sn_setup()
    vecint_bundles = UTCGP.get_listinteger_bundles()
    int_bundles = UTCGP.get_integer_bundles()
    run_config = runConf(1, 1, 0.1, 0.1)
    model_architecture = modelArchitecture([Int], [1], [Int, Vector{Int}], [Int], [1])
    node_config = nodeConfig(1, 1, 1, 1)
    meta_library = MetaLibrary([Library(int_bundles), Library(vecint_bundles)])
    shared_inputs, utgenome =
        make_evolvable_utgenome(model_architecture, meta_library, node_config)
    shared_inputs[1].value = 1
    utgenome[1][1][1].value = 1
    utgenome[2][1][1].value = 1
    utgenome[1][1][2].value = 1
    utgenome[2][1][2].value = 1
    utgenome[1][1][3].value = 1
    utgenome[2][1][3].value = 2
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
