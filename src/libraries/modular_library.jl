mutable struct ModularLibrary <: AbstractLibrary
    bundles::Vector{FunctionBundle} # empty, for compatibility
    library::Vector{FunctionWrapper}
    name_to_index::Dict{Symbol, Int}

    function ModularLibrary()
        return new(FunctionBundle[], FunctionWrapper[], Dict{Symbol, Int}())
    end
end

function add_to_library!(mod_lib::ModularLibrary, mod_fn::ModularFunction)
    @warn "No caster or callback"
    fw = FunctionWrapper(mod_fn, mod_fn.name, nothing, () -> nothing)
    push!(mod_lib.library, fw)
    new_idx = length(mod_lib.library)
    mod_lib.name_to_index[mod_fn.name] = new_idx
    return new_idx
end

# We need to implement the AbstractLibrary interface.
Base.size(library::ModularLibrary) = length(library.library)
Base.length(library::ModularLibrary) = length(library.library)
Base.getindex(library::ModularLibrary, i::Int)::FunctionWrapper = library.library[i]
Base.iterate(library::ModularLibrary, state = 1) =
    state > length(library.library) ? nothing : (library.library[state], state + 1)

function Base.getindex(library::ModularLibrary, name::Symbol)
    idx = get(library.name_to_index, name, 0)
    if idx != 0
        return library.library[idx]
    end
    return nothing
end

function unpack_bundles_in_library!(library::ModularLibrary)::Int
    # Does nothing, modular functions are added dynamically.
    return length(library.library)
end
