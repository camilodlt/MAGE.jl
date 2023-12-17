```@meta
CurrentModule = UTCGP
```

```@contents
```

# Functions Bundles, Libraries and MetaLibraries

## Bundles

## Library
```@docs
AbstractLibrary
Library
Library(bundles::Vector{FunctionBundle})
Base.size
Base.length
Base.getindex
Base.iterate
add_bundle_to_library!
unpack_bundles_in_library!
list_functions_names(library::Library;symbol::Bool = false)
```

## MetaLibrary
```@docs
AbstractMetaLibrary
MetaLibrary
MetaLibrary(libs::Vector{<:AbstractLibrary})
```

```@docs; canonical = false
list_functions_names(meta_library::MetaLibrary)
```
