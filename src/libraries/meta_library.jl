####################
# LIBRARY
####################

"""
Parent of all concrete Libraries
"""
abstract type AbstractLibrary end

"""
A Library Holds ALL functions that return a 'type' for UTCGP

Callable functions come in bundles of FunctionWrappers.

So the Library first store the bundles and then unpacks them to create
the internal library.
"""
struct Library <: AbstractLibrary
    bundles::Vector{FunctionBundle}
    library::Vector{FunctionWrapper}

    @doc """
         Library(bundles::Vector{FunctionBundle})

     Creates a library adding all function bundles. 

     The vector of FunctionBundles is `deepcopy`ed so that changes to that vector 
     don't affect the Library. 

     The internal library of FunctionWrappers is empty.
     """
    function Library(bundles::Vector{FunctionBundle})
        return new(deepcopy(bundles), [])
    end
end

"""
    size(library::AbstractLibrary)

Returns the size of the internal library (that holds FunctionWrappers).
"""
Base.size(library::AbstractLibrary) = length(library.library)

"""
    length(library::AbstractLibrary)

Returns the size of the internal library (that holds FunctionWrappers).
"""
Base.length(library::AbstractLibrary) = length(library.library)


"""
Indexes the internal library at a given index.
"""
Base.getindex(library::AbstractLibrary, i::Int)::FunctionWrapper = library.library[i]


"""
Iterates the internal library.
"""
Base.iterate(library::AbstractLibrary, state = 1) =
    state > length(library.library) ? nothing : (library.library[state], state + 1)


"""
    add_bundle_to_library!(library::AbstractLibrary, bundle::FunctionBundle)::Int

Adds a bundle to the bundles of the Library.

Returns the length of the internal bundles after addition (nb of bundles in the Library).
"""
function add_bundle_to_library!(library::AbstractLibrary, bundle::FunctionBundle)::Int
    push!(library.bundles, bundle)
    return length(library.bundles)
end

"""
Index the library with the name of a function
"""
function Base.getindex(library::AbstractLibrary, name::Symbol)
    for fn in library
        if fn.name == name
            return fn
        end
    end
end

"""
From all the bundles in the Library, it *unpacks* them and adds ALL
functions to the internal list of functions.

It's a way of having all functions (comming from multiple bundles)
in the same place. 

This operation is meant to be run once, after all bundles have been added to the Library.

**Caveats**: 

- This functions will replace the previous (if any) content of the internal list of fns
 of the Library. A warning is given if the list of functions was not empty.
- A warning is also given if the bundles, after unpacking, resulted in an empty list of functions.


Returns the number of functions in Library (after unpacking).
"""
function unpack_bundles_in_library!(library::AbstractLibrary)::Int
    @info "Unpacking Functions"
    if length(library.library) > 0
        @warn "Library had functions in the library. Those will be replaced after bundle unpack"
    end
    new_lib = []
    for bundle in library.bundles
        for fn in bundle
            push!(new_lib, fn)
        end
    end
    n_fn = length(new_lib)
    if n_fn == 0
        @warn "The unpack of the bundles resulted in an empty list of functions"
    else
        empty!(library.library)
        push!(library.library, new_lib...) # Keep the same obj vector
    end
    return n_fn
end


"""
    list_functions_names(library::Library;symbol::Bool = false)

Returns the names of all the functions in the library.

Useful for reproducibility.

The vector can be asked as a vector of strings or a vector of symbols. 
"""
function list_functions_names(
    library::Library;
    symbol::Bool = false,
)::Union{Vector{Symbol},Vector{String}}
    names = []
    for fn in library.library
        name_ = fn.name
        if !symbol
            name_ = String(name_)
        end
        push!(names, name_)
    end
    return identity.(names)
end


# def wrap_fns_in_cache(lib: Library):  # TODO LIBRARY WITH CACHE ANOTHER CLASS
#     for ith_fn, fn in enumerate(lib.library):
#         lib.library[ith_fn].fn = big_cache(fn.fn)


# function get_fn_idx_from_lib(library::Library, name::Symbol)::Int
#     for (fn_idx, fn) in enumerate(library)
#         if fn.name == name
#             return fn_idx
#         end
#     end
#     throw(KeyError("Library does not have $name function"))
# end # TODO doc and test



####################
# METALIBRARY
####################

"""
Parent of all concrete MetaLibraries
"""
abstract type AbstractMetaLibrary end


"""
A MetaLibrary holds multiple Libraries. A Library holds functions.
"""
struct MetaLibrary <: AbstractMetaLibrary
    libraries::Vector{<:AbstractLibrary}

    @doc """
        MetaLibrary(libs::Vector{<:AbstractLibrary})

    From a vector of libraries, they will be unpacked and added to the MetaLibrary.


    **Caveats**: 

    - The vector of libraries can't be empty.
    - The libraries will be unpacked one by one
    - The libraries can't be empty

    """
    function MetaLibrary(libs::Vector{<:AbstractLibrary})
        @assert length(libs) > 0 "Lib has to have at least one bundle"
        for lib in libs
            n_fns = unpack_bundles_in_library!(lib)
            @assert n_fns > 0 "Lib can't be empty"
        end
        for lib in libs
            for fn in lib
                # @show fn.name
                _verify_last_arg_is_vararg!(fn.fn)
            end
        end
        return new(libs)
    end
end

"""
    list_functions_names(meta_library::MetaLibrary)

Returns a vector of vectors (one per library). Each vector is a list of functions inside
the library.
"""
function list_functions_names(meta_library::MetaLibrary)::Vector{Vector{String}}
    names_ = []
    for lib in meta_library.libraries
        push!(names_, list_functions_names(lib))
    end
    return names_
end


"""
    size(ml::AbstractMetaLibrary)

Returns the number of libraries in the MetaLibrary.
"""
Base.size(ml::AbstractMetaLibrary) = length(ml.libraries)

"""
    length(ml::AbstractMetaLibrary)

Returns the number of libraries in the MetaLibrary.
"""
Base.length(ml::AbstractMetaLibrary) = size(ml)


"""
Returns the library at a given index.
"""
Base.getindex(ml::AbstractMetaLibrary, i::Int) = ml.libraries[i]


"""

Iterates over all libraries in the MetaLibrary
"""
Base.iterate(ml::AbstractMetaLibrary, state = 1) =
    state > length(ml.libraries) ? nothing : (ml.libraries[state], state + 1)


