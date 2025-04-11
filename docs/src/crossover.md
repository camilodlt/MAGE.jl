```@meta
CurrentModule = UTCGP
```

# Entry Point

```@docs
mage_crossover
```

# High Level

**Crossover Operator**

```@docs
UTCGP.mage_crossover_with_numbered_mutation
```

# Traits
```@docs 
UTCGP.AbstractCrossOverArgs 
UTCGP.CrossOverArgs
UTCGP.CrossOverMutRateArgs 
UTCGP.MissingCrossOverArgs
```

```@docs
UTCGP.runconf_trait_crossover
```
```@docs
UTCGP.numbered_mutation_trait
```

# Helper
```@docs 
UTCGP._initialize_population
UTCGP._apply_truncation_selection!
UTCGP._apply_crossover_and_mutation!
```

For Crossover : 

```@docs
UTCGP._check_genome_compatibility
UTCGP._draw_until_one_operator
```
