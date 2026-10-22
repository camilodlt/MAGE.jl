```@meta
CurrentModule = MAGE
```

# Model Config

Three objects describe a MAGE run before anything is built:

| Object | Answers |
|:--|:--|
| [`modelArchitecture`](@ref) | which types exist, and where the inputs and outputs live |
| [`nodeConfig`](@ref) | how large each chromosome is |
| an [`AbstractRunConf`](@ref) | how the search is driven |

```@contents
Pages = ["config.md"]
Depth = 2
```

## Model architecture

`modelArchitecture` is where multimodality is declared. Its
`chromosomes_types` list is the set of types the evolved program is allowed to
produce, one chromosome each; `inputs_types_idx` and `outputs_types_idx` say
which chromosome each input and each output belongs to.

```@docs
modelArchitecture
```

## Node configuration

```@docs
nodeConfig
```

## Run configuration

The type of the run configuration selects the search strategy — and therefore
which fitter accepts it.

| Configuration | Fitter | Strategy |
|:--|:--|:--|
| [`runConf`](@ref) | [`fit`](@ref), [`fit_mt`](@ref) | `1 + λ` |
| [`RunConfGA`](@ref) | [`fit_ga`](@ref), [`fit_ga_mt`](@ref) | generational GA with tournament selection |
| [`RunConfCrossOverGA`](@ref) | [`mage_crossover`](@ref) | GA with crossover |
| `RunConfNSGA2` | `fit_nsga2` | multi-objective |
| `RunConfME` | `fit_me` | MAP-Elites |
| `RunConfSTN` | `fit_stn` | search-network tracing |

```@docs
AbstractRunConf
runConf
RunConfGA
RunConfCrossOverGA
MAGE.RunConfNSGA2
MAGE.RunConfME
MAGE.RunConfSTN
```

### Traits

Optional capabilities are discovered through traits rather than by inspecting
the concrete configuration type, so generic code works across strategies.

```@docs
runconf_trait
runconf_trait_evolutationary_strategy
GAWithTournamentArgs
```

```@docs; canonical = false
numbered_mutation_trait
NumberedMutationArgs
```

## Environment variables

A few knobs are read from the environment at load time (see `MAGE.__init__`),
which is convenient for sweeping them from a job script:

| Variable | Default | Effect |
|:--|:--|:--|
| `MAGE_CONSTRAINED` | unset | set to `yes` to clamp generated integer/float parameters |
| `MAGE_MIN_INT` / `MAGE_MAX_INT` | `-1000` / `1000` | bounds used when constraining integers |
| `MAGE_MIN_FLOAT` / `MAGE_MAX_FLOAT` | `-1000` / `1000` | bounds used when constraining floats |
| `MAGE_NANO_ARRAY` | `100` | small-array size limit used by list operators |
| `MAGE_SMALL_ARRAY` | `1000` | medium-array size limit |
| `MAGE_BIG_ARRAY` | `10000` | large-array size limit |
| `MAGE_SAFE_CALL` | unset | set to `yes` to route every call through [`safe_call`](@ref) |
| `MAGE_TEMPERATURE` | `0.3` | temperature of [`default_eliteDistribution_selection_callback`](@ref) |

`MAGE.show_constants_module()` prints the values actually in effect.
