#####################
# TYPES             #
#####################

abstract type Abstract_SN_Writer <: AbstractCallable end

# FUNCTIONS 
abstract type Abstract_Column_Function <: Function end
abstract type Abstract_Node_Hash_Function <: Abstract_Column_Function end
abstract type Abstract_Edge_Prop_Getter <: Abstract_Column_Function end

# MOCK for testing
struct _mock_column_function <: Abstract_Column_Function end
function (::_mock_column_function)(p...)
    ""
end
struct _mock_node_hash_function <: Abstract_Node_Hash_Function end
function (::_mock_node_hash_function)(params)
    return ["mock node fn" for i in params.population]
end
struct _mock_edge_prop_getter <: Abstract_Edge_Prop_Getter end
function (::_mock_edge_prop_getter)(params)
    return ["mock edge fn" for i in params.population]
end
