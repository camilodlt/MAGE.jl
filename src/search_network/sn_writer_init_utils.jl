# SN WRITER INSTANTIATION --- ---

"""
    _assert_keys_in_allowed(d::OrderedDict{K,V}, allowed::Vector{String}) where {K,V}

Asserts that the order of the columns is correct.
i.e. every key in `d` is the corresponding column at that index in `allowed`
"""
function _assert_keys_in_allowed(d::OrderedDict{K,V}, allowed::Vector{String}) where {K,V}
    for (a, b) in zip(collect(keys(d)), allowed)
        @assert a == b "The column name $b was expected but we received $a"
    end
end

"""
    _assert_enough_hashers(d::OrderedDict{K,V}, allowed::Vector{String}) where {K,V}

Asserts that the number of hashers correspond to the length of `allowed` (i.e nb of columns in the table).
"""
function _assert_enough_hashers(d::OrderedDict{K,V}, allowed::Vector{String}) where {K,V}
    @assert length(d) == (length(allowed)) "Length mismatch between the number of columns in the DB and the number of hashers"
end

"""
    _assert_sn_writer_consistency(con, hashers)

Checks that the `hashers` dict has:
    - The nb of functions == the number of cols that need a function (so no the mandatory ones) 
    - Keys that match the names and order of the columns in the corresponding table in `con`
    - The table : sn.Abstract_Edges, Abstract_Nodes

In other words, that the `hashers` have an item for all the columns in the table and also in the correct order. 

This function raises an AssertionError if the conditions are not met. 
"""
function _assert_sn_writer_consistency(
    con::DuckDB.DB,
    hashers::OrderedDict{String,<:Function},
    table_for_cols::Type{<:sn.Abstract_Table},
)
    table = sn.get_table_by_type(con, table_for_cols)
    cols = names(table)
    cols_without_hashes = sn.forbidden_cols_for_table(table_for_cols)
    extra_cols = filter(i -> i ∉ cols_without_hashes, cols)
    _assert_enough_hashers(hashers, extra_cols)
    _assert_keys_in_allowed(hashers, extra_cols)
end

"""

If there are no fns, the functions does nothing. It has nothing to verify
"""
function _assert_sn_writer_consistency(
    con::DuckDB.DB,
    hashers::Nothing,
    table_for_cols::Type{<:sn.Abstract_Table},
)
end


