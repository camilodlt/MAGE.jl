```@meta
CurrentModule = MAGE
```

# Ski region properties

The `ski` library separates measuring objects, transforming their property
vectors, reducing to numbers, and selecting objects in an image. Runtime
operators are pure Julia. Python skimage is used only as a test oracle.

```julia
using MAGE
m = falses(12, 16)
m[2:4, 3:7] .= true
m[9, 12] = true
img = SImageND(BinaryPixel.(m))
areas = MAGE.ski.ski_area(img)       # values [15.0, 1.0], ids [1, 2]
MAGE.ski.ski_mean(areas)             # 8.0
MAGE.ski.ski_take_largest(areas, 1)  # values [15.0], ids [1]
```

Use `get_ski_bundles(SkiVector{Tuple{12,16}})` for the size-typed SkiVector
chromosome. The basic bundle specializes its input-free constructors for this
size; property and vector methods infer their result size from their inputs.
Scalar reductions are opt-in through `get_extension_ski_float()` and are absent
from `get_float_bundles()`. Image extensions come from
`get_extension_ski_binaryimg()` and `get_extension_ski_intensityimg()`;
specialize their factories with the concrete output image type as usual.
The [Bundle Catalogue](@ref) lists every generated operator.

## Coordinates, labeling and ROI

Foreground is 8-connected. Binary pixels use their stored truth value;
intensity images are thresholded at `>= 0.5`. Objects are ordered by their
first pixel in **row-major** order, matching `skimage.measure.label`.
Geometry has unit spacing. Coordinates are zero-based row/column values,
bbox minima are inclusive and maxima exclusive. Axis lengths use pixel
centres, without the existing object library's pixel-variance correction.
Orientation is in radians, measured from the row axis as in skimage.

Shape operators accept `(image)` or `(image, binary_roi)`. ROI intersects
foreground **before labeling**, so it can split objects. Intensity and
weighted operators accept `(binary, intensity)` or
`(binary, intensity, binary_roi)`, and also `(intensity[, binary_roi])`,
using that image for both thresholding and measurement. Shape and ROI sizes
must agree; intensity-source sizes must agree too.

## Properties

Operators are named `ski_<skimage_property>`. Tuple properties are split:
`bbox_min_row`, `bbox_min_col`, `bbox_max_row`, `bbox_max_col`;
`centroid_row`/`col`, `centroid_local_row`/`col`,
`centroid_weighted_row`/`col`, `centroid_weighted_local_row`/`col`;
and `inertia_tensor_eigval_0`/`1` (descending order).

Scalar shape properties include area, bbox/convex/filled area, both axis
lengths, eccentricity, equivalent diameter, Euler number, extent, maximum
Feret diameter, pixel count, orientation, perimeter, Crofton perimeter,
and solidity. Intensity properties are min, max, mean, median and population
std. Filled area uses 8-connected background; Euler uses the dual
4-connected background, exactly as skimage does.

Every moment entry with row and column powers from 0 through 3 is available:
`ski_moments_2_0`, `ski_moments_central_2_0`,
`ski_moments_normalized_2_0`, and the corresponding
`moments_weighted`, `moments_weighted_central`,
`moments_weighted_normalized` variants. Raw moments use bbox-local coordinates.
Normalized moments of total order below two are NaN. Each of the seven
Hu invariants is separate: `ski_moments_hu_1` through `_7`, plus
`ski_moments_weighted_hu_1` through `_7`. No signed logarithm is applied.
Zero total intensity gives undefined weighted centroids, following IEEE NaN.

## Vector operations and empty values

Identity and singleton one lead the basic bundle; singleton two and empty
are also available. Transformations include relu, log, log1p, square, sqrt,
abs, neg, exp, reciprocal, sin and cos. Sort and take/drop largest/smallest
use absolute counts, floored and clamped to the available length; nonfinite
counts mean zero. Filters compare against a number or inclusive interval.
Pairwise arithmetic uses the shared prefix; concat preserves complete inputs.

Empty sum, length, filtered counts and rank sums return zero. Other empty
statistics and pairwise distances/correlations return NaN. Std is population
std; mode ties choose the smallest value. Percentile uses linear interpolation
and percentages in `[0,100]`, clamped, with nonfinite input meaning 50.
Length ratio uses IEEE division (zero denominator yields Inf or NaN).

## Provenance and storage

`SkiVector{S}` stores `values`, parallel Int32 `ids`, an owned `own::SkiRegions{S}`
buffer and the `regions::SkiRegions{S}` reference it currently uses. Size `S`
is encoded exactly as in `SImageND`: `Tuple{height,width}`. A region id of zero
means that an element has no associated region. Geometry owns its Int32 label
map, bboxes and counts, and references the labeled image and optional intensity
source. Labels referenced by a vector never live in task-local scratch.

Property calls label into the output's `own`, set `regions = own`, and return
ids `1:n`. Unary, filter, sort and rank operators preserve or permute ids with
their values. Pairwise operators retain the first input's ids and geometry over
the shared length. Concat retains the first input's geometry and preserves the
second input's ids only when both inputs share that exact regions object;
otherwise appended ids are zero. Constructors one/two/empty have no region ids.
Derived calls share geometry and images by reference and never copy them.

Each evaluator step gets a distinct pooled `SkiVector{S}` for the evaluator's
lifetime. Labels have size S, while values, ids, bboxes and counts start empty
and grow with `resize!` (no
`sizehint!`). Every call rewrites its complete active output and resets its
geometry reference, even when the pool slot belonged to another program in a
previous generation.
Acyclic DAG execution keeps the referenced upstream buffers valid during one
evaluation, including branches with several property extractions. A vector
retained as a program output or cache **may see its referenced regions or images
overwritten by a later evaluation**. `copy(v)` copies values/ids and retains the
same geometry reference; it is not an archival snapshot. To retain geometry or
source images, explicitly copy those arrays while they are valid.

Direct property calls without `out` allocate fresh owned geometry. All property
and vector operators support an appropriately size-typed `out`. TLS is used only
for temporary queues, hulls, sorting and selection arrays, never persistent
provenance. No tests depend on wall-clock performance.

## Image selection

Each image-output bundle contains **16** factories: object/bbox × eight criteria.
Each specialized callable supports two forms, for **64 input forms** across both
output bundles. Operators are `ski_keep_objects_<criterion>` and
`ski_keep_bbox_<criterion>`; measurement is a separate preceding SkiVector step.

- Comparisons `lt`, `lte`, `gt`, `gte` and `top_percentile`, `bottom_percentile`
  require `(image, ski, amount)` or `(ski, amount)`.
- Extrema `max`, `min` accept `(image, ski)` or `(ski)` without an amount.

An explicit image must have the vector's source size S; its pixels may come from
a different same-size image. Geometry always comes from `ski.regions`, with no
relabeling. Reference forms use the referenced intensity source when present.
Without an intensity source, intensity reference output is **1.0 wherever
selected**, including filled bbox pixels. Binary output always marks selection.

A region is selected if any of its elements satisfies the criterion. Id zero is
ignored for selecting regions, but all vector values contribute to extrema and
percentile thresholds. Top 20 retains values >= the 80th percentile; bottom 20
retains <= the 20th. All ties are kept. ROI is applied only at property extraction;
selectors take no ROI argument. Bboxes fill their full rectangles, including
holes or pixels excluded by the extraction ROI. Image operators support pooled
`out` storage and do not copy or recompute the vector's region map.

```julia
v = MAGE.ski.ski_area(img)
f = bundle_image2DBinary_ski_factory[:ski_keep_objects_gt].fn(typeof(img))
Base.invokelatest(f, v, 2.0) # keeps the 15-pixel object from the earlier scene
```

## API

```@docs
SkiRegions
SkiVector
bundle_ski_basic
bundle_ski_properties
bundle_ski_vector
bundle_float_ski
bundle_image2DBinary_ski_factory
bundle_image2DIntensity_ski_factory
get_ski_bundles
get_extension_ski_float
get_extension_ski_binaryimg
get_extension_ski_intensityimg
```
