# LOG FACILITIES --- --- 

"""
    _log_n_rows_view(rows::Vector{OrderedDict{String,Any}}, ::sn.Abstract_Nodes)
    _log_n_rows_view(rows::Vector{OrderedDict{String,Any}}, ::sn.Abstract_Edges)

Logs the number of rows.
"""
function _log_n_rows_view(
    rows::Vector{OrderedDict{String,T}},
    ::sn.Type{sn.Abstract_Nodes},
) where {T}
    n_rows = length(rows)
    @debug "$n_rows potential nodes where hashed."
end
function _log_n_rows_view(
    rows::Vector{OrderedDict{String,T}},
    ::Type{sn.Abstract_Edges},
) where {T}
    n_edges = length(rows)
    @debug "$n_edges edges with extra information."
end

# VALIDATE THE COLUMN VIEW --- --- 
"""
    _assert_all_individuals_have_all_info(extra_hashes::OrderedDict{String,Any})

Because extractor functions work on batch data, after applying them we have : 

A dict with : 
    - Keys : the col names in the DB
    - Values : A vector with hashes/properties for each individual

This is the column view. 

All vectors should have the same length. Because for each function, it should 
have hashed all individuals. 

As an example, suppose 
    - hasher1 gives the length of the individual
    - hasher2 gives the length of the active individual

If the population has 3 individuals. 
- The `column_view` dict should have 2 entries (names should match the DB) : `hasher1`, `hasher2`. 
- Each entry is a vector of length 3. One for every individual

This functions just ensures that all keys have vectors of the same length.
"""
function _assert_all_individuals_have_all_info(
    column_view::OrderedDict{String,Vector{T}},
) where {T}
    lengths = []
    for e in column_view
        push!(lengths, length(e[2]))
    end
    n_individuals = unique(lengths)
    @assert length(n_individuals) == 1
end

# ID HASH CALCULATION --- --- 
"""
    _calc_individual_unique_hash(
        extra_hashes::OrderedDict{String,Vector{T}},
        index_at::Int,
    ) where {T}

The `id_hash` is the sha256 of the union of all hashes for a given individual at position `index_at`.

Example :

The `column_view` has 2 keys "hash1" and "hash2". There are 2 individuals hashed.
{
    "hash1" => ["a","b"]
    "hash2" => ["1", "2"]
}

For `index_at` of 1, it will perform the sha algorithm of ["a", "1"], and for an `index_at` of 2, it will perform the hashing on ["b","2"].
"""
function _calc_individual_unique_hash(
    column_view::OrderedDict{String,Vector{T}},
    index_at::Int,
) where {T}
    n_individuals = column_view[column_view.keys[1]] |> length # supposes that a length verification was already performed, as _assert_all_individuals_have_all_info
    @assert index_at >= 1 && index_at <= n_individuals "Tried to index a hash at index $index_at but hashes are only available for $n_individuals individuals"
    return general_hasher_sha([e[2][index_at] for e in column_view]) # picks the `index_at` element for every hash fn. 
end



# COLUMN VIEW UTILS --- --- 

"""
    _nb_of_processed_individuals(d::OrderedDict{String,Vector{Any}})

Returns the number of individuals from the column view. 
"""
function _nb_of_processed_individuals(d::OrderedDict{String,Vector{Any}})
    first_key = d.keys[1]
    n_hashed_individuals = length(d[first_key]) # we can pick the first, and because of the last call we know it's the same for ther others
    return n_hashed_individuals
end

"""
    extract_row_pairs_from_column_dict(
        column_information::OrderedDict{String,Vector{Any}},
        row_index::Int,
    )

Extract row pairs from Column view. 

Example, if we want the second row : `row_index` = 2

Col view :{
    - col1 => [ind1, ind2, ...]
    - col2 => [ind1, ind2, ...]
}

Row pairs :
    - [col1 => value_col1, col2 =>value_col2, ...] # for ind2 
"""

function _extract_row_pairs_from_column_dict(
    column_information::OrderedDict{String,Vector{Any}},
    row_index::Int,
)
    return [e[1] => e[2][row_index] for e in column_information]
end

# RUN ALL NODES OR EDGES FNS => Column View  --- --- 

"""
    _run_each_function!(
        fns::OrderedDict{String,<:Abstract_Column_Function},
        params::UTCGP.ParametersStandardEpoch,
    )

Run the `fns` against the `params`. 

The result is an the column view, which is an OrderedDict with: 
    - keys : the name (key) for each function
    - values : the information extracted by running the respective function against the `params`  
"""
function _run_each_function!(
    fns::OrderedDict{String,<:Abstract_Column_Function},
    params::UTCGP.ParametersStandardEpoch,
)
    population_info_per_function = OrderedDict{String,Vector{Any}}()
    # get hashes done by every hasher for every col for every ind
    for (col_name, col_info_extractor) in fns
        pop_info = col_info_extractor(params)
        population_info_per_function[col_name] = pop_info
    end
    return population_info_per_function
end

"""
    _run_all_hashers_on_epoch_params(
        params::UTCGP.ParametersStandardEpoch,
        writer::Abstract_SN_Writer,
    )

    _run_all_functions_on_epoch_params(
        params::UTCGP.ParametersStandardEpoch,
        writer::Abstract_SN_Writer,
        ::sn.Abstract_Nodes,
    )

The `writer` has a bunch of hash function, for each column in the DB.
Some functions will provide information for each edge (i.e. `edges_prop_getters`) and
some will provide information (a hash) for each node (i.e. `nodes_hashers`). 

This function executes all functions with the epoch `params` as input (either for edges or for nodes). It 
is up to the hash function to know which information it hashes. And, it is up
to the caller to modify the `params` if needed (selecting only the elite for example).

The function returns a column view which is an OrderedDict with :
    - keys : the keys in the `writer`
    - values : A vector with the hashed values (or properties) for all individuals 
"""
function _run_all_functions_on_epoch_params(
    params::UTCGP.ParametersStandardEpoch,
    writer::Abstract_SN_Writer,
    ::Type{sn.Abstract_Edges},
)
    population_info_per_function = _run_each_function!(writer.edges_prop_getters, params)
    return population_info_per_function

end

function _run_all_functions_on_epoch_params(
    params::UTCGP.ParametersStandardEpoch,
    writer::Abstract_SN_Writer,
    ::Type{sn.Abstract_Nodes},
)
    population_hash_per_hasher = _run_each_function!(writer.nodes_hashers, params)
    return population_hash_per_hasher

end

# COLUMN VIEW TO ROW VIEW --- --- 

"""
    _pivot_dict(
        column_information::OrderedDict{String,Vector{Any}},
        ::sn.Abstract_Edges,
    )

Changes from col view to row view. 

Col view :{
    - col1 => [ind1, ind2, ...]
    - col2 => [ind1, ind2, ...]
}

Row view : [
     {col1 => value_col1, col2 =>value_col2, ...} # for ind1 
     {col1 => value_col1, col2 =>value_col2, ...} # for ind2 
]
"""
function _pivot_dict(
    column_information::OrderedDict{String,Vector{Any}},
    ::Type{sn.Abstract_Edges},
)
    _assert_all_individuals_have_all_info(column_information)
    n_processed_individuals = _nb_of_processed_individuals(column_information)
    all_rows = Vector{OrderedDict{String,Any}}()
    for ith_hashed_ind = 1:n_processed_individuals
        row = OrderedDict(
            _extract_row_pairs_from_column_dict(column_information, ith_hashed_ind)...,
        )
        push!(all_rows, row)
    end
    return identity.(all_rows)
end

"""
    _pivot_dict(
        column_information::OrderedDict{String,Vector{Any}},
        ::sn.Abstract_Nodes,
    )

The same as `pivot_dict` with Abstract_Edges as a parameter but in this case
the first key of each row is the calculated `id_hash`. 

See 
    - `_calc_individual_unique_hash` for `id_hash` calculation.
    - `_extract_row_pairs_from_column_dict` for passing from column view to row view for each index
"""
function _pivot_dict(
    column_information::OrderedDict{String,Vector{Any}},
    ::Type{sn.Abstract_Nodes},
)
    _assert_all_individuals_have_all_info(column_information)
    n_processed_individuals = _nb_of_processed_individuals(column_information)
    all_rows = []
    for ith_hashed_ind = 1:n_processed_individuals
        id_hash = _calc_individual_unique_hash(column_information, ith_hashed_ind)
        row = OrderedDict(
            "id_hash" => id_hash,
            _extract_row_pairs_from_column_dict(column_information, ith_hashed_ind)...,
        )
        push!(all_rows, row)
    end
    return identity.(all_rows)
end


# ENTRY POINT : From fns to row view for nodes and edges.  --- --- 

"""
    function _get_rows_by_running_all_fns(
        params::UTCGP.ParametersStandardEpoch,
        writer::Abstract_SN_Writer,
    )

Runs the functions (either node/edge) against the epoch parameters. 

Those functions return a column view (col_name => [population info, ...])

That column view is transposed to have a row view: 
    - {col=> value, ...}  # row 1 relative to individual 1

For `sn.Abstract_Nodes`, the `id_hash` will be calculated and placed at the beginning of the row. 

"""
function _get_rows_by_running_all_fns(
    params::UTCGP.ParametersStandardEpoch,
    writer::Abstract_SN_Writer,
    which_fns::Type{<:sn.Abstract_Table},
)
    # DB colname => [all individuas info] view (col view)
    extra_info_column_view = _run_all_functions_on_epoch_params(params, writer, which_fns)
    # individual => info view. This is the ('row' view) 
    extra_info_row_view = _pivot_dict(extra_info_column_view, which_fns)
    return extra_info_row_view
end

