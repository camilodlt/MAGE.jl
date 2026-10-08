```@meta
CurrentModule = UTCGP
```

# Automatically Defined Functions

An **ADF** is a subprogram promoted to a library operator. Once installed, every
chromosome can call it as a single node, so a useful three-node idiom stops
being something the search has to rediscover and becomes a primitive it can
compose with.

```@contents
Pages = ["adf.md"]
Depth = 2
```

## How it works

The whole design turns on keeping function *indices* stable while their
*meaning* changes:

1. **Reserve.** [`extend_fn_lib_adf!`](@ref) appends a number of empty slots to
   a [`Library`](@ref). An empty slot ([`EmptyADFDefinition`](@ref)) behaves as
   the identity on its first argument, so a genome may point at it from the
   very first generation without breaking.
2. **Fill.** When a subprogram looks worth keeping,
   [`replace_adf_slot!`](@ref) installs it as an
   [`ActiveADFDefinition`](@ref). Because the slot object
   ([`ADFSlotFunction`](@ref)) is mutable and stays in place, every genome
   already pointing at that index picks up the new behaviour without being
   rewritten.
3. **Track.** The [`ADFRegistry`](@ref) knows every slot, which lets the search
   ask which ADFs a program uses ([`direct_adf_usage`](@ref)), what an ADF
   itself depends on ([`recursive_adf_dependencies`](@ref)), and whether a
   replacement is safe ([`can_replace_adf_slot`](@ref)).
4. **Flatten.** [`flatten_adfs`](@ref) expands every ADF call back into ordinary
   CGP material, producing a genome that no longer needs the registry. This is
   what makes a final model portable and readable.

The definition of an active ADF is stored as a genome, not as compiled code:
that is what allows step 4. A [`SequentialProgram`](@ref) is cached alongside it
purely as a fast callable view.

## Slots and definitions

```@autodocs
Modules = [UTCGP]
Pages = ["adf/types.jl"]
```

## Reserving slots in a library

```@autodocs
Modules = [UTCGP]
Pages = ["adf/library_extension.jl"]
```

## Which ADFs does a program use?

```@autodocs
Modules = [UTCGP]
Pages = ["adf/usage.jl"]
```

## Flattening back to plain CGP

```@autodocs
Modules = [UTCGP]
Pages = ["adf/genome_flatten.jl"]
```

## Saving and loading

An ADF environment is a genome plus the definitions its slots hold, saved
together so a run can be resumed or an individual shipped elsewhere.

```@autodocs
Modules = [UTCGP]
Pages = ["adf/serialization.jl"]
```
