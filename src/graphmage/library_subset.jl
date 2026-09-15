############################
# GraphMAGE: function-library subsetting
############################

"""
    used_function_names(individual_programs) -> Dict{Int, Vector{Symbol}}

Names of the real functions one individual's decoded programs actually call,
grouped by chromosome/library index (`y_position`), deduplicated and sorted
for determinism. Stored as `Vector`, not `Set`: `GraphMAGENode` is JLD2
checkpointed, and JLD2's `Dict`-reconstruction has a known edge case with
`Set`-valued dicts nested deep in a large heterogeneous object graph (it can
misresolve the value type on read) -- `Vector` round-trips reliably.

The output node's own call is deliberately excluded: by construction (see
`make_evolvable_utgenome`), every output node always calls function index 1
of its library, frozen, as a fixed structural convention -- not a real
search-space choice a GA could ever change. Counting it here would just add
"the first function of every library" to every union with no differentiating
signal.
"""
function used_function_names(individual_programs::IndividualPrograms)::Dict{Int, Vector{Symbol}}
    used = Dict{Int, Set{Symbol}}()
    for program in individual_programs
        for operation in program
            operation.calling_node isa OutputNode && continue
            lib_idx = operation.calling_node.y_position
            names = get!(used, lib_idx, Set{Symbol}())
            push!(names, operation.fn.name)
        end
    end
    return Dict{Int, Vector{Symbol}}(lib_idx => sort!(collect(names)) for (lib_idx, names) in used)
end

"""
    used_function_names_genotype(genome, meta_library) -> Dict{Int, Vector{Symbol}}

The `:genotype` alternative to `used_function_names`: every function any node
in the raw genome carries, grouped by chromosome index -- active (on the
decoded execution path) or not. CGP genomes always carry dormant material
(nodes mutation could wire into the active path later but hasn't yet); the
`:phenotype` mode (`used_function_names`) only sees whichever functions
happen to be reachable right now, so a child's restricted library never gets
access to a parent's *unexpressed* material. This walks `genome.genomes`
(one `SingleGenome`/chromosome per entry) directly instead of a decoded
`IndividualPrograms`, so no `OutputNode` filtering is needed -- output nodes
live in the separate `genome.output_nodes` field and are never part of
`genome.genomes` iteration.
"""
function used_function_names_genotype(genome::UTGenome, meta_library::MetaLibrary)::Dict{Int, Vector{Symbol}}
    used = Dict{Int, Set{Symbol}}()
    for (chrom_idx, single_genome) in enumerate(genome.genomes)
        lib = meta_library.libraries[chrom_idx]
        names = get!(used, chrom_idx, Set{Symbol}())
        for node in single_genome
            fn_element = extract_function_from_node(node)
            idx = get_node_element_value(fn_element)
            push!(names, lib.library[idx].name)
        end
    end
    return Dict{Int, Vector{Symbol}}(lib_idx => sort!(collect(names)) for (lib_idx, names) in used)
end

"""
    merge_used_function_names(sets) -> Dict{Int, Vector{Symbol}}

Union several `used_function_names` results together, per chromosome index.
This is the "crossover of functions available" mechanism: when a node has
multiple parents, its child expansion searches over the union of everything
each parent actually used.
"""
function merge_used_function_names(sets::AbstractVector{Dict{Int, Vector{Symbol}}})::Dict{Int, Vector{Symbol}}
    merged = Dict{Int, Set{Symbol}}()
    for s in sets
        for (lib_idx, names) in s
            existing = get!(merged, lib_idx, Set{Symbol}())
            union!(existing, names)
        end
    end
    return Dict{Int, Vector{Symbol}}(lib_idx => sort!(collect(names)) for (lib_idx, names) in merged)
end

"""
    subset_metalibrary(ml_full, used_names) -> MetaLibrary

Build a restricted `MetaLibrary`, one library per chromosome index in
`ml_full`, containing, in this exact order: `ml_full`'s own library position
1 (the fixed output-node convention function, so output-node wiring stays
valid after subsetting) and position 2 (`correct_all_nodes!`'s hardcoded
last-resort fallback index -- must stay a real, in-bounds function in every
restricted library too), followed by every function named in
`used_names[lib_idx]` that isn't already there (a chromosome index missing
from `used_names` gets only those two).
"""
function subset_metalibrary(ml_full::MetaLibrary, used_names::Dict{Int, Vector{Symbol}})::MetaLibrary
    libs = Library[]
    for (lib_idx, lib_full) in enumerate(ml_full.libraries)
        wanted = Set{Symbol}(get(used_names, lib_idx, Symbol[]))
        template_bundle = first(lib_full.bundles)
        restricted_bundle = isnothing(template_bundle.caster) ?
            FunctionBundle(template_bundle.fallback) :
            FunctionBundle(template_bundle.caster, template_bundle.fallback)

        seen = Set{Symbol}()
        output_fn = lib_full.library[1]
        push!(restricted_bundle.functions, output_fn)
        push!(seen, output_fn.name)
        if length(lib_full.library) >= 2
            # correct_all_nodes! hardcodes function index 2 as its last-resort
            # fallback when it cannot find any valid mutation for a node (see
            # MAGE/src/mutations/correct_all_nodes.jl). Every restricted
            # library must keep a real function at position 2 too, matching
            # canonical exactly, or that fallback goes out of bounds.
            fallback_fn = lib_full.library[2]
            push!(restricted_bundle.functions, fallback_fn)
            push!(seen, fallback_fn.name)
        end

        for fnw in lib_full.library
            (fnw.name in wanted) || continue
            fnw.name in seen && continue
            push!(restricted_bundle.functions, fnw)
            push!(seen, fnw.name)
        end
        push!(libs, Library([restricted_bundle]))
    end
    return MetaLibrary(libs)
end

"""
    remap_genome_to_library!(genome, old_ml, new_ml, model_architecture, shared_inputs)

Rewrite every chromosome node's function-index element in `genome` (and its
bounds) so it refers to the equivalent function *by name* in `new_ml` instead
of `old_ml`. A node whose current function has no equivalent name in `new_ml`
(only possible for inactive, off-path nodes -- active-path functions are
always present by construction of the caller's function union) gets a fresh
random valid function index instead. `correct_all_nodes!` runs at the end as
a final safety net. Output nodes are untouched: their function index is
frozen at 1 in every genome, and `subset_metalibrary` preserves position 1
identically, so it never needs remapping.

Used in both directions: canonical -> restricted before an expansion's inner
GA, and restricted -> canonical after (which always succeeds with no
randomization, since every restricted library is a subset of canonical).
"""
function remap_genome_to_library!(
        genome::UTGenome,
        old_ml::MetaLibrary,
        new_ml::MetaLibrary,
        model_architecture::modelArchitecture,
        shared_inputs::SharedInput,
    )::UTGenome
    for (chrom_idx, single_genome) in enumerate(genome.genomes)
        old_lib = old_ml.libraries[chrom_idx]
        new_lib = new_ml.libraries[chrom_idx]
        n_new = length(new_lib)
        name_to_index = Dict{Symbol, Int}(fnw.name => i for (i, fnw) in enumerate(new_lib.library))
        for node in single_genome
            fn_element = extract_function_from_node(node)
            old_index = get_node_element_value(fn_element)
            old_name = old_lib.library[old_index].name
            new_index = get(name_to_index, old_name, rand(1:n_new))
            fn_element.lowest_bound = 1
            fn_element.highest_bound = n_new
            fn_element.value = new_index
        end
    end
    correct_all_nodes!(genome, model_architecture, new_ml, shared_inputs)
    return genome
end
