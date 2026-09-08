```@meta
CurrentModule = UTCGP
```

# Libraries

A MAGE node does not call a Julia function directly; it calls entry *n* of the
library belonging to its chromosome. Three levels build that up:

```
MetaLibrary            one Library per chromosome (i.e. per type)
 └── Library           the flat, indexable list of operators of one type
      └── FunctionBundle   a themed group of operators sharing a caster and a fallback
           └── FunctionWrapper   one operator, plus its caster, fallback and cache
```

The exhaustive list of what MAGE ships is on the [Bundle Catalogue](@ref) page.

```@contents
Pages = ["libraries.md"]
Depth = 2
```

## Function wrappers

A [`FunctionWrapper`](@ref) is the unit a node actually calls. It carries three
things beyond the function itself:

- a **caster**, applied to the result so that a chromosome declared `Float64`
  really does hold `Float64`;
- a **fallback**, returned when the call throws — this is what keeps an evolved
  program total, so a run never dies on a bad index or a division by zero;
- an optional **cache** ([`CacheConfig`](@ref)), for expensive operators whose
  arguments repeat across individuals and generations.

```@docs
FunctionWrapper
safe_call
NoTypeAssertion
CacheConfig
NoCacheConfig
```

### Dispatching anonymous methods

Bundles decide applicability with `hasmethod` and arity with `which`. Anonymous
functions produced by a factory do not carry usable method tables, so they are
wrapped in a [`ManualDispatcher`](@ref), which answers both questions itself.

```@docs
ManualDispatcher
```

## Bundles

A [`FunctionBundle`](@ref) is a themed group of operators — "morphology",
"string case", "region statistics" — and it is the unit you compose libraries
from. Bundles are shared package-level constants, so `deepcopy` one before
re-pointing its caster or fallback.

```@docs
FunctionBundle
update_caster!
update_fallback!
```

### Factory bundles

Bundles whose name ends in `_factory` hold *functions of a type* rather than
functions. Calling an entry with a concrete type returns the method specialised
for it, which is how one definition of `erosion_2D` serves intensity images,
masks and label maps alike.

The premade collections do that specialisation for you:

```julia
factories = [deepcopy(b) for b in [bundle_listgeneric_basic_factory]]
for bundle in factories, (i, wrapper) in enumerate(bundle)
    fn = wrapper.fn(Int)                       # specialise to Int
    bundle.functions[i] = FunctionWrapper(fn, wrapper.name, wrapper.caster, wrapper.fallback)
end
```

## Library

```@docs
AbstractLibrary
Library
Library(bundles::Vector{FunctionBundle})
add_bundle_to_library!
unpack_bundles_in_library!
```

A `Library` supports `length`, `size`, iteration, indexing by position and
indexing by name:

```@docs
Base.size
Base.length
Base.getindex
Base.iterate
```

## MetaLibrary

```@docs
AbstractMetaLibrary
MetaLibrary
MetaLibrary(libs::Vector{<:AbstractLibrary})
```

The i-th library of a `MetaLibrary` must correspond to the i-th entry of
`modelArchitecture.chromosomes_types`. That correspondence is the whole
type system: a node in chromosome `i` can only ever call an operator from
library `i`, and therefore can only ever produce a value of type `i`.

## Inspecting a library

```@docs
list_functions_names(library::Library;symbol::Bool = false)
print_function_table
write_function_table
```

```@docs
list_functions_names(meta_library::MetaLibrary)
```

## Restricting a library

A search does not have to see every operator. [`subset_metalibrary`](@ref)
builds a smaller `MetaLibrary` from a set of function names, and
[`remap_genome_to_library!`](@ref) rewrites a genome's function indices to match
it. This pair is what [GraphMAGE](@ref) uses to give each expansion a library
restricted to what its parents actually used.

```@docs; canonical = false
subset_metalibrary
used_function_names
used_function_names_genotype
merge_used_function_names
remap_genome_to_library!
```

## Casters

A caster coerces an operator's result into the chromosome's type. Bundles carry
one; [`update_caster!`](@ref) re-points it.

```@autodocs
Modules = [UTCGP]
Pages = ["libraries/casters.jl"]
```

## Premade libraries

Ready-made bundle collections, each returning fresh deep copies with their
casters and fallbacks already set for the target type.

| Function | Chromosome type |
|:--|:--|
| `UTCGP.get_sr_float_bundles` | `Float64`, trimmed for symbolic regression |
| `UTCGP.get_float_bundles` | `Float64` |
| `UTCGP.get_integer_bundles` | `Int` |
| `UTCGP.get_string_bundles` | `String` |
| `UTCGP.get_listinteger_bundles` | `Vector{Int}` |
| `UTCGP.get_listfloat_bundles` | `Vector{Float64}` |
| `UTCGP.get_liststring_bundles` | `Vector{String}` |
| `UTCGP.get_list_int_tuples_bundles` | `Vector{Tuple{Int,Int}}` |
| `UTCGP.get_list_string_tuples_bundles` | `Vector{Tuple{String,String}}` |
| `UTCGP.get_image2Dintensity_factory_bundles` | intensity images |
| `UTCGP.get_image2Dbinary_factory_bundles` | binary images (masks) |
| `UTCGP.get_image2Dsegment_factory_bundles` | segment images (label maps) |
| `UTCGP.get_float_bundles_atari` | `Float64`, Atari-oriented |
| `UTCGP.get_image2D_factory_bundles_atari` | images, Atari-oriented |

The `get_extension_*` functions add the cross-modal operators — image-to-scalar
statistics, pooling, orientation — on top of a base collection.

```@autodocs
Modules = [UTCGP]
Pages = ["libraries/pre_made_libraries.jl"]
```

## Modular functions

A modular function bundles a whole subprogram behind a single library entry.
This is the shared machinery under [Automatically Defined Functions](@ref) and
[Generated Functions](@ref).

```@autodocs
Modules = [UTCGP]
Pages = ["libraries/modular_function.jl", "libraries/modular_library.jl"]
```
