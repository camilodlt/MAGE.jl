```@meta
CurrentModule = UTCGP
DocTestSetup = quote
  using UTCGP
end
```

```@contents
Pages = ["float.md"]
```

# Float Operations

Operators whose *output* is a `Float64`. Most of the interesting ones read an
image: they are the bridge that lets a float chromosome consume the image
chromosome, and the scalar they produce can be fed straight back to an image
operator as a parameter.

The arithmetic that a float chromosome also needs — sums, products,
transcendental functions, reductions over lists — lives in the
[Number Lib](@ref "Number Operations") page.

## Basic float operators

### Module

```@docs
UTCGP.float_basic
```

### Bundle

```@docs
bundle_float_basic
```

## Orientation summaries

Scalar descriptions of an image's gradient orientations, computed from Sobel
derivatives. Worked examples, with the intermediate gradient images, are on the
[Number Lib](@ref "Orientation Summary From Image") page.

### Module

```@docs
UTCGP.float_orientation
```

### Bundle

```@docs
bundle_float_orientation
```

For the *map*-valued counterparts — gradient magnitude and orientation as
images rather than scalars — see
[`bundle_image2DIntensity_orientation_factory`](@ref).

## Image graph descriptors

An image is turned into a graph, node-level graph measures are computed, and
each is reduced to scalars. Eleven measures times nine reductions, plus four
whole-graph properties.

### Module

```@docs
UTCGP.imagegraph_basic
```

### Bundle

```@docs
bundle_float_imagegraph
```

## GLCM texture features

Grey-level co-occurrence matrix statistics, in the Haralick tradition. Ten
statistics aggregated five ways over the co-occurrence directions.

!!! warning "Experimental"
    The names and the aggregation scheme may change.

### Module

```@docs
UTCGP.experimental_GLCM
```

### Bundle

```@docs
experimental_bundle_float_glcm_factory
```
