# Shared node decode table.
#
# Decoding a node answers four questions: which function does it call, where does
# each input come from (a program input or another node), what is each input's
# type, and how many inputs does the selected method really use. The answers only
# depend on the node's genes, so children that share genes with their parents (the
# vast majority of nodes) can reuse the answers of a node decoded before.
#
# The table stores those answers as a `NodeRecipe`, keyed by the genes themselves.
# A hit then only has to bind the recipe to the current individual's own nodes,
# because an `Operation` must reference the nodes of the genome being decoded.
#
# Correctness relies on two invariants of MAGE genomes:
#   1. a node's `y_position` is the index of its chromosome (its type), so the
#      type of an input node is given by the TYPE gene that points to it;
#   2. all genomes decoded with one table share one `modelArchitecture`, hence the
#      same input types, chromosome types and chromosome starting points.
# PARAMETER genes are ignored, as in the default decoder.

"""
    NodeRecipeKey{N}

Every gene that the default decoder reads, as plain integers. `N` is the largest
number of connections of a node; unused connection slots are zero. Two nodes with
the same key decode to the same function, input locations and input types.

The library version is part of the key: editing a library (e.g. replacing an ADF
slot) bumps it, so recipes made with the old library are never hit again.
"""
struct NodeRecipeKey{N}
    library_version::UInt
    type_idx::Int                    # chromosome of the node, selects the library
    function_gene::Int
    n_connections::Int
    connections::NTuple{N,Int}       # CONNEXION genes, in material order
    connection_rows::NTuple{N,Int}   # TYPE gene paired with each connection
end
# The key is an isbits struct: the default `isequal` compares every field and the
# default `hash` hashes its content, so the Dict lookup itself is exact.

"""
    InputRecipe

Where one input of an operation comes from. `row == 0` means a program input at
`position`; otherwise the input is node `position` of chromosome `row`.
"""
struct InputRecipe
    row::Int
    position::Int
    type_idx::Int    # -1 for program inputs, as in the default decoder
    type::Type
end

"""
    NodeRecipe

How to build the `Operation` of a node: the function and its used inputs (inputs
beyond the method's arity are already dropped).
"""
struct NodeRecipe
    fn::FunctionWrapper
    inputs::Vector{InputRecipe}
end

# One part of the table, with its own lock so threads rarely wait for each other.
mutable struct _RecipeShard{N}
    lock::ReentrantLock
    recipes::Dict{NodeRecipeKey{N},NodeRecipe}
    lookups::Int
    hits::Int
end
_RecipeShard{N}() where {N} = _RecipeShard{N}(ReentrantLock(), Dict{NodeRecipeKey{N},NodeRecipe}(), 0, 0)

"""
    NodeDecodeTable(architecture, genome; shards = 64, capacity = 1_000_000)

Opt-in table of node recipes shared by all decodes of one run, safe to use from
several threads at once. Pass it to `decode_with_output_nodes(...; node_table)`.

- `architecture` is the run's `modelArchitecture`; decoding a genome of another
  architecture with this table throws an `ArgumentError`.
- `genome` is any genome of the run, used to size the keys (largest arity).
- `capacity` bounds the number of stored recipes; a shard that overflows its share
  is emptied. Decoded programs never depend on what the table holds.
"""
struct NodeDecodeTable{N}
    architecture::modelArchitecture
    shards::Vector{_RecipeShard{N}}
    shard_capacity::Int
end
function NodeDecodeTable(architecture::modelArchitecture, genome::UTGenome;
        shards::Integer = 64, capacity::Integer = 1_000_000)
    shards > 0 || throw(ArgumentError("shards must be positive"))
    capacity >= 0 || throw(ArgumentError("capacity must be nonnegative"))
    N = _max_connections(genome)
    NodeDecodeTable{N}(architecture, [_RecipeShard{N}() for _ in 1:shards], cld(Int(capacity), Int(shards)))
end

"""
    node_decode_stats(table)

Cumulative `lookups`, `hits`, `misses` and the current number of stored recipes
(`size`).
"""
function node_decode_stats(table::NodeDecodeTable)
    lookups = hits = size = 0
    for shard in table.shards
        lock(shard.lock) do
            lookups += shard.lookups
            hits += shard.hits
            size += length(shard.recipes)
        end
    end
    (; lookups, hits, misses = lookups - hits, size)
end

"""`clear!(table::NodeDecodeTable)` removes every recipe and keeps the counters."""
function clear!(table::NodeDecodeTable)
    for shard in table.shards
        lock(() -> empty!(shard.recipes), shard.lock)
    end
    table
end

# ---------------------------------------------------------------------------
# Keys
# ---------------------------------------------------------------------------

_count_connections(node) = count(e -> e.element_type == CONNEXION, node.node_material.material)

function _max_connections(genome::UTGenome)
    n = 0
    for chromosome in genome.genomes, node in chromosome.chromosome
        node isa CGPNode && (n = max(n, _count_connections(node)))
    end
    for output_node in genome.output_nodes
        n = max(n, _count_connections(output_node))
    end
    n
end

# Value of the `k`-th gene of `element_type` in the material, or 0 when the node
# has fewer such genes (padding of the fixed-size key).
function _kth_gene(material, element_type::NodeElementTypes, k::Int)
    seen = 0
    for element in material
        element.element_type == element_type || continue
        seen += 1
        seen == k && return get_node_element_value(element)
    end
    0
end

"""
    _node_recipe_key(table, node, type_idx)

Reads the node's genes into a `NodeRecipeKey` without allocating. Connection `k`
is paired with TYPE gene `k`, the same pairing as the default decoder.
"""
function _node_recipe_key(::NodeDecodeTable{N}, node, type_idx::Int) where {N}
    material = node.node_material.material
    n_connections = count(e -> e.element_type == CONNEXION, material)
    n_connections <= N || throw(ArgumentError(
        "node has $n_connections connections but the NodeDecodeTable was built for at most $N"))
    NodeRecipeKey{N}(
        library_decode_version(),
        type_idx,
        _kth_gene(material, FUNCTION, 1),
        n_connections,
        ntuple(k -> _kth_gene(material, CONNEXION, k), Val(N)),
        ntuple(k -> _kth_gene(material, TYPE, k), Val(N)),
    )
end

_recipe_shard(table::NodeDecodeTable, key) = table.shards[mod1(hash(key) % Int, length(table.shards))]

# ---------------------------------------------------------------------------
# Lookup, recipe creation and binding
# ---------------------------------------------------------------------------

function _lookup_recipe(shard::_RecipeShard, key)
    lock(shard.lock) do
        shard.lookups += 1
        recipe = get(shard.recipes, key, nothing)
        recipe === nothing || (shard.hits += 1)
        recipe
    end
end

function _store_recipe!(table::NodeDecodeTable, shard::_RecipeShard, key, recipe::NodeRecipe)
    lock(shard.lock) do
        shard.recipes[key] = recipe
        length(shard.recipes) > table.shard_capacity && empty!(shard.recipes)
    end
    nothing
end

"""
    _recipe_from_operation(operation, key, genome)

Records where each input of an operation built by the default decoder comes from.
Input `k` of the operation comes from connection `k` of the key.
"""
function _recipe_from_operation(operation::Operation, key::NodeRecipeKey, genome::UTGenome)
    inputs = map(enumerate(operation.inputs)) do (k, input)
        row = key.connection_rows[k]
        connection = key.connections[k]
        starting_point = genome.genomes[row].starting_point
        if connection <= starting_point
            InputRecipe(0, connection, input.type_idx, input.type)
        else
            InputRecipe(row, connection - starting_point, input.type_idx, input.type)
        end
    end
    NodeRecipe(operation.fn, inputs)
end

"""
    _bind_recipe(recipe, node, genome)

Builds the node's `Operation` from a recipe, pointing at this genome's own nodes.
Each operation owns a fresh input vector, as with the default decoder.
"""
function _bind_recipe(recipe::NodeRecipe, node, genome::UTGenome)
    inputs = Vector{OperationInput}(undef, length(recipe.inputs))
    for (k, input) in enumerate(recipe.inputs)
        source = input.row == 0 ? InputPromise(input.position) :
            genome.genomes[input.row].chromosome[input.position]
        inputs[k] = OperationInput(source, input.type_idx, input.type)
    end
    Operation(recipe.fn, node, inputs)
end

"""
    _table_decode_operation(node, type_idx, ml, arch, genome, table, scratch)

Decodes one node through the table: on a hit the stored recipe is bound to this
genome; on a miss the default decoder builds the operation, which is returned
as is and recorded as a recipe for the next nodes with the same genes.
"""
function _table_decode_operation(node, type_idx::Int, ml::MetaLibrary, arch::modelArchitecture,
        genome::UTGenome, table::NodeDecodeTable, scratch)
    key = _node_recipe_key(table, node, type_idx)
    shard = _recipe_shard(table, key)
    recipe = _lookup_recipe(shard, key)
    recipe === nothing || return _bind_recipe(recipe, node, genome)

    operation = _decode_operation(node, type_idx, ml, arch, genome, scratch)
    _store_recipe!(table, shard, key, _recipe_from_operation(operation, key, genome))
    operation
end

"""Throws unless `table` was built for `architecture` (one table per run)."""
function _check_table_architecture(table::NodeDecodeTable, architecture::modelArchitecture)
    table.architecture === architecture || throw(ArgumentError(
        "this NodeDecodeTable was built for another modelArchitecture; use one table per architecture"))
    nothing
end
_check_table_architecture(::Nothing, ::modelArchitecture) = nothing
