```@meta
CurrentModule = UTCGP
```

# Crossover

Crossover recombines two parents into one child. In a multi-chromosome genome
that only makes sense between compatible individuals — same number of
chromosomes, same node layout — so the operator checks compatibility before
doing anything.

It is driven by [`RunConfCrossOverGA`](@ref), which carries both a crossover
probability and a mutation probability: each offspring is produced by drawing
one of the two operators.

```@contents
Pages = ["crossover.md"]
Depth = 2
```

## Entry point

```@docs
mage_crossover
```

## The operator

```@docs
UTCGP.mage_crossover_with_numbered_mutation
```

## Traits

Crossover arguments reach the operator through a trait on the run
configuration, so a configuration that does not describe crossover simply
reports [`MissingCrossOverArgs`](@ref UTCGP.MissingCrossOverArgs) and the
generic code keeps working.

```@docs
UTCGP.AbstractCrossOverArgs
UTCGP.CrossOverArgs
UTCGP.CrossOverMutRateArgs
UTCGP.MissingCrossOverArgs
UTCGP.runconf_trait_crossover
```

```@docs
numbered_mutation_trait(conf::UTCGP.CrossOverArgs)
```

## Helpers

```@docs
UTCGP._initialize_population
UTCGP._apply_truncation_selection!
UTCGP._apply_crossover_and_mutation!
UTCGP._check_genome_compatibility
UTCGP._draw_until_one_operator
```
