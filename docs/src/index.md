```@meta
CurrentModule = UTCGP
```

# MAGE.jl

Documentation for [MAGE.jl](https://github.com/camilo/UTCGP.jl).

MAGE.jl is a type-safe extension of Cartesian Genetic Programming (CGP), 
designed for multimodal evolutionary computation. 
It introduces multiple chromosomes, each dedicated to a specific output type, 
enabling a structured and efficient search process.

Key features of MAGE.jl:

- Type-Safe Mutations – Mutations are type-aware, ensuring that connections are only made to inputs that match the function’s signature.
- Multi-Chromosome Representation – Each chromosome corresponds to a distinct output type, improving modularity and adaptability.
- Versatile Applications – Successfully applied to:
  - Symbolic Regression
  - Program Synthesis
  - Image Classification
  - Image Segmentation
  - Policy Search

MAGE.jl provides a robust framework for evolving adaptive, structured programs while maintaining type integrity.

```@index
```

