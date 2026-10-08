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

How the graph is built from a **mask**: each object (connected component) is
a node placed at its centroid, and the nodes are joined by a Delaunay
triangulation, so each object is linked to its natural neighbours. A mask
needs at least three objects that are not on one line; otherwise there is no
triangulation and the operator returns its fallback `0.0`. The names are
`<reduction><measure>`, e.g. `meandegreecentrality` is the mean degree
centrality over all objects, and `xcoorargmaxdegreecentrality` the x coordinate (column, in pixels) of the
best-connected object.

```@example imagegraph
using UTCGP
m = falses(40, 40)
for (r, c) in ((5, 5), (5, 30), (20, 15), (33, 8), (30, 32), (15, 36))
    m[r:r+3, c:c+3] .= true                       # six 4×4 objects
end
mask = SImageND(BinaryPixel.(m))
for name in (:diameter, :clustering_coefficient, :meandegreecentrality, :maximumbetweennesscentrality)
    println(rpad(name, 30), bundle_float_imagegraph[name].fn(mask))
end
```

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
