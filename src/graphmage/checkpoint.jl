############################
# GraphMAGE: checkpointing
############################

"""
    save_graphmage_archive(archive, path)

Save the full archive (graph structure, every node's genome/behavior/visit
counts, config, probes, roots) to `path` via JLD2. Genomes are index-based
(no `FunctionWrapper`/closures embedded), so they serialize as plain data;
reloading only needs the same canonical `MetaLibrary` the run used, rebuilt
by the caller exactly as it always is (matching how every other MAGE script
constructs its `MetaLibrary` from scratch on each run).

Writes to a temporary file first, then renames it into place, so a crash or
kill mid-write never corrupts (or even touches) whatever was previously at
`path` -- the rename is atomic on the same filesystem. Callers that
checkpoint repeatedly to the *same* `path` (e.g. `run_graphmage`'s periodic
checkpointing) therefore get both crash-safety and bounded disk usage for
free; callers wanting a history of distinct snapshots should still pass
distinct `path`s themselves.
"""
function save_graphmage_archive(archive::GraphMAGEArchive, path::AbstractString)::String
    @info "GraphMAGE: saving archive" path n_nodes = length(all_node_labels(archive.graph)) expansions_done = archive.expansions_done
    # JLD2/FileIO dispatch on the file extension, so the temp name must keep
    # ".jld2" (a plain ".tmp" suffix makes the format "UNKNOWN" and fails).
    base, ext = splitext(path)
    tmp_path = base * ".tmp" * ext
    JLD2.save(tmp_path, "archive", archive)
    mv(tmp_path, path; force = true)
    return path
end

"""
    load_graphmage_archive(path) -> GraphMAGEArchive
"""
function load_graphmage_archive(path::AbstractString)::GraphMAGEArchive
    archive = JLD2.load(path, "archive")
    @info "GraphMAGE: loaded archive" path n_nodes = length(all_node_labels(archive.graph)) expansions_done = archive.expansions_done
    return archive
end
