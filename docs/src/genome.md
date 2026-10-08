```@meta
CurrentModule = UTCGP
```

# Genome and Nodes

A MAGE individual is a nest of four levels. From the outside in:

```
UTGenome                       one individual
 ├── genomes                   one SingleGenome (chromosome) per type
 │    └── chromosome           a vector of CGPNode
 │         └── node_material   a vector of CGPElement
 │              └── value      one Int
 └── output_nodes              one OutputNode per program output
```

and, alongside it, a [`SharedInput`](@ref) holding the input nodes that every
chromosome reads from.

```@contents
Pages = ["genome.md"]
Depth = 2
```

## Elements: the integers

Everything evolution touches is a [`CGPElement`](@ref): one integer, its legal
range, and its role. The role is a [`NodeElementTypes`](@ref) value, and it is
what makes MAGE's genome type-aware — each argument of a node carries both a
`CONNEXION` (which node do I read?) and a `TYPE` (in which chromosome?).

Because every element knows its own bounds, mutation is a draw inside a range
rather than a repair loop: an illegal connexion is simply not representable.

```@docs
CGPElement
AbstractElement
NodeElementTypes
FUNCTION
CONNEXION
PARAMETER
TYPE
INPUT
OUTPUT
```

### Reading and writing elements

```@docs
get_node_element_value
set_node_element_value!
random_element_value
initialize_node_element!
set_node_lowest_bound
set_node_highest_bound
set_node_position
set_node_element_type
set_node_freeze_state
set_node_unfreeze_state
```

## Nodes

A node groups the elements of one operation: a `FUNCTION` element followed by
`arity` `(CONNEXION, TYPE)` pairs, held in a [`NodeMaterial`](@ref).

```@docs
AbstractNode
NodeMaterial
CGPNode
InputNode
OutputNode
ConstantNode
```

### Building nodes

```@docs
make_evolvable_node
make_output_node
```

### Working with nodes

```@docs
initialize_node!
node_to_vector
get_node_value
set_node_value!
reset_node_value!
extract_function_from_node
extract_connexions_from_node
extract_connexions_types_from_node
extract_parameters_from_node
```

## Chromosomes and genomes

```@docs
SingleGenome
UTGenome
SharedInput
Population
```

### Building and resetting

```@docs
make_evolvable_utgenome
make_evolvable_single_genome
initialize_genome!
reset_genome!
replace_shared_inputs!
```

## The usual construction sequence

```julia
shared_inputs, ut_genome = make_evolvable_utgenome(model_arch, ml, node_config)
initialize_genome!(ut_genome)                                   # random values
correct_all_nodes!(ut_genome, model_arch, ml, shared_inputs)    # make them type-correct
```

[`initialize_genome!`](@ref) respects each element's bounds, so the genome is
*legal*; [`correct_all_nodes!`](@ref) then resamples any connexion whose type
does not match what the node's function expects, making it *type-correct*.

To pin an output to a specific node — a common way to force the search to use
the whole depth of the chromosome — set its connexion and freeze it:

```julia
set_node_element_value!(ut_genome.output_nodes[1][2],
                        ut_genome.output_nodes[1][2].highest_bound)
set_node_freeze_state(ut_genome.output_nodes[1][2])
```

Indexing follows the nesting: `ut_genome[1]` is the first chromosome,
`ut_genome[1][2]` its second node, and `ut_genome[1][2][1]` that node's function
element.

## Evolvable constants

[`ConstantNode`](@ref)s hold values that programs can read but mutation cannot
change. With the `MAGE_PYCMA` extension loaded they can instead be tuned by
CMA-ES, so the graph structure evolves discretely while its constants are
optimised numerically. See [Package Extensions](@ref).

```@docs; canonical = false
make_cma_nodes!
get_cma_nodes
mutate_cma!
```
