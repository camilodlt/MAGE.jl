# MAGE classical vision libraries plan

Temporary planning document. Remove it once the accepted operators and design
decisions have moved into the manual and issue tracker.

## Goals and contracts

Add deterministic, training-free classical vision operators that can be placed
directly in MAGE image chromosomes. Every public operator must:

1. accept a MAGE `SImageND` and trailing `args...`;
2. preserve the input height and width;
3. return the pixel category declared by its bundle;
4. have deterministic correctness and integration tests;
5. run in at most 0.5 seconds on a warmed 256x256 grayscale input on the
   development/CI-class CPU (compilation is measured separately); and
6. have a docstring, bundle-catalogue entry, and a worked manual example.

Documentation for every parameterized operator must show the input and rendered
outputs for representative parameter values: the default, at least one lower
and one higher setting, and useful boundary/degenerate behavior. Examples must
state how MAGE numbers are mapped or clamped to algorithm parameters. Operators
without public parameters still receive one canonical input/output example.

The first implementation targets grayscale `IntensityPixel` images. Internals
operate on named `Float64` feature channels and combine channel maps only at the
end. An RGB extension can therefore add luminance and color-opponency channels
without changing operator names or output types.

| Library | Public input | Public output | Purpose |
|:--|:--|:--|:--|
| Saliency fixation | intensity image | intensity image | Pixelwise fixation likelihood/saliency in `[0, 1]` |
| Salient-object detection | intensity image | intensity image | Pixelwise object-level saliency in `[0, 1]` |
| Foreground extraction, discrete | intensity image | binary image | Hard foreground mask |
| Foreground extraction, continuous | intensity image | intensity image | Soft foreground membership/alpha in `[0, 1]` |
| Blob extraction | binary mask, optionally plus intensity image | binary image | Select one connected foreground component |

The map-producing libraries remain separate even when they share private
pyramid, graph, normalization, seed, or connected-component helpers. This keeps
MAGE search spaces semantically typed and lets users opt into expensive bundles.

## Implemented bundle inventory

These are factory bundles. Each factory entry must be specialized with one
concrete output image type before it is inserted into a MAGE `Library`. The
specialization fixes both the output dimensions and its pixel/storage type.

| Bundle | Required specialization | Callable image inputs | Guaranteed output |
|:--|:--|:--|:--|
| `bundle_image2DIntensity_saliency_fixation_factory` | `I <: SizedImage2D{S1,S2,IntensityPixel{T}}` | One intensity image of type `I`, followed by up to two algorithm parameters | Exactly `I`: same dimensions and `IntensityPixel{T}`, normalized to `[0, 1]` |
| `bundle_image2DBinary_foreground_extraction_factory` | `I <: SizedImage2D{S1,S2,BinaryPixel{Bool}}` | One same-size intensity image; optionally a same-size intensity saliency map and/or algorithm parameters | Exactly the specialized binary category and dimensions: a hard 0/1 foreground mask |
| `bundle_image2DIntensity_foreground_extraction_factory` | `I <: SizedImage2D{S1,S2,IntensityPixel{T}}` | One same-size intensity image; optionally a same-size intensity saliency map and/or algorithm parameters | Exactly `I`: same dimensions and `IntensityPixel{T}`, containing soft foreground probabilities in `[0, 1]` |
| `bundle_image2DBinary_blob_extraction_factory` | `I <: SizedImage2D{S1,S2,BinaryPixel{Bool}}` | An intensity saliency map or binary mask with dimensions `(S1,S2)`; statistic selectors also receive a same-size source intensity image | Exactly the specialized binary category and dimensions: a selected-component 0/1 mask |
| `bundle_image2DIntensity_blob_extraction_factory` | `I <: SizedImage2D{S1,S2,IntensityPixel{T}}` | A source image of type `I` plus a same-size intensity saliency map or binary mask | Exactly `I`: source pixels inside the selection and typed zeros outside |
| `bundle_image2DIntensity_color_statistics_rgb_factory` | `I <: SizedImage2D{S1,S2,IntensityPixel{T}}` | One `SImage3D{S1,S2,3,IntensityPixel{ST}}` in last-axis `R,G,B` order | Exactly the specialized 2D intensity category and dimensions; a luminance, opponent, saturation, or chromaticity map in `[0,1]` |
| `bundle_image3DIntensity_rgb_factory` | `I <: SizedImage3D{S1,S2,3,IntensityPixel{T}}` | Zero, one, or two RGB images of type `I`, optionally one `Real` adjustment parameter, or one RGB image plus a same-size 2D `BinaryPixel` mask | Exactly `I`; leading `identity_rgb`/parameter-free `return_rgb`, channelwise arithmetic, unary color transforms, bounded brightness/contrast/saturation/gamma adjustment, or retained RGB pixels inside the mask and typed black outside |
| `bundle_image3DIntensity_spatial_rgb_factory` | `I <: SizedImage3D{S1,S2,3,IntensityPixel{T}}` | One RGB image of type `I` followed by zero, one, or two bounded `Real` parameters | Exactly `I`; channelwise edges, scale-space responses, sharpening, local statistics, or oriented texture energy in `[0,1]` |
| `bundle_image3DIntensity_rgb_composition_factory` | `I <: SizedImage3D{S1,S2,3,IntensityPixel{T}}` | Up to three same-size 2D intensity planes, RGB images of type `I`, or both | Exactly `I`; composed or replaced channels, continuously masked or alpha-blended RGB, or replaced luminance, all finite in `[0,1]` |

The new bundles are deliberately absent from `get_extension_intensityimg()` and
`get_extension_binaryimg()`. Use `get_extension_saliency_intensityimg()`,
`get_extension_foreground_intensityimg()`,
`get_extension_foreground_binaryimg()`, `get_extension_blob_intensityimg()`, or
`get_extension_blob_binaryimg()` to opt into one domain and output category.
Use `get_extension_color_statistics_rgb_intensityimg()` for RGB-to-intensity
maps and `get_extension_rgbimg()` for RGB-output operators.
Use `get_extension_spatial_rgbimg()` to opt into the separate fixed spatial RGB
feature bundle after the basic RGB bundle.
Use `get_extension_rgb_compositionimg()` to opt into the cross-chromosome
2D-intensity-to-RGB bridge, also after the basic RGB bundle.

The continuous foreground bundle contains `random_walker_foreground`, with
internal spectral-residual seeds or an explicit same-size saliency input, and
`closed_form_matting`, with an automatic saliency-derived trimap or an explicit
same-size trimap.
The fixation bundle currently contains `itti_koch_saliency` and
`spectral_residual_saliency`. The discrete foreground bundle contains
`boykov_jolly_foreground` and `grabcut_foreground`, each with internal
spectral-residual seeds or an explicit same-size saliency input. The binary blob bundle contains the 16
single-component `*_blob` selectors plus
`blob_extraction_size_between_blob`; the intensity blob bundle contains the
corresponding 16 unsuffixed masked-image selectors. Bundle placement therefore
never makes a masked intensity image appear in a binary chromosome, or a
component mask appear in an intensity chromosome.

## Automatic seeds and trimaps

Seeded algorithms receive seeds derived deterministically from a saliency map:

- confident foreground: high-saliency core around one or more persistent local
  maxima;
- confident background: low-saliency pixels plus a conservative image-border
  prior;
- unknown region: every remaining pixel;
- cleanup: remove undersized seed components, guarantee disjoint foreground and
  background sets, and use deterministic fallbacks when a threshold is empty.

The initial seed generator will use fixed quantiles and component-size rules,
not learned thresholds. Each seeded operator will have private explicit-seed or
explicit-trimap helpers so its numerical algorithm can be tested independently
from automatic seed quality. A later public seeded API is possible, but the
MAGE bundle entry remains image-only.

## Delivery sequence

### 1. Saliency fixation (`Intensity -> Intensity`)

- **Itti-Koch-Niebur (1998):** implement first. Grayscale intensity and four
  orientation channels, dyadic Gaussian pyramids, multiscale center-surround
  differences, conspicuity normalization, and full-resolution output. Add RGB
  color-opponency channels later. The map operator intentionally omits the
  paper's temporal winner-take-all and inhibition-of-return network.
- **Spectral residual (2007):** FFT log-amplitude residual, inverse FFT, squared
  magnitude, Gaussian smoothing.
- **Image Signature / phase-only transform (2012):** sign of the DCT, inverse
  DCT, square, smooth.
- **AIM and SUN:** defer unless a redistributable ICA basis with clear provenance
  and licensing is selected. Shipping learned constants is acceptable only with
  reproducible fitting code, metadata, checksums, and artifact/version handling.

### 2. Salient-object detection (`Intensity -> Intensity`)

- Frequency-tuned saliency (Achanta 2009).
- Region contrast (Cheng 2011), sharing a deterministic graph-segmentation
  helper.
- Geodesic saliency (Wei 2012), using border-source shortest paths.
- Boundary connectivity (Zhu 2014).
- Minimum barrier distance (Zhang 2015), using deterministic raster scans.

### 3. Discrete foreground extraction (`Intensity -> Binary`)

- **Boykov-Jolly graph cuts:** implemented with automatic spectral-residual
  seeds or a supplied saliency map, deterministic histogram appearance terms,
  a scale-space saliency prior, contrast-sensitive four-neighbor regularization,
  and an exact max-flow cut.
- **GrabCut:** implemented with automatic spectral-residual seeds or a
  supplied saliency map, deterministic per-image five-component grayscale
  GMMs, one or two EM/cut refinement rounds, contrast-sensitive regularization,
  and the shared exact max-flow cut. The GMM boundary is ready to accept color
  vectors when RGB image specialization is added.
- Lazy Snapping only if a useful noninteractive seeded form remains distinct
  from graph cuts.
- Intelligent Scissors is probably inapplicable as a MAGE image-to-image
  operator because its primary output is an interactive path; defer unless a
  deterministic closed-contour formulation is specified.

### 4. Continuous foreground extraction (`Intensity -> Intensity`)

- **Random Walker:** implemented with automatic spectral-residual seeds or a
  supplied saliency map, a contrast-weighted four-neighbor Laplacian, one
  deterministic sparse Dirichlet solve, and same-size soft foreground
  probabilities. The scalar intensity feature boundary can be widened to RGB
  vectors without changing the public output contract.
- **Closed-form matting:** implemented with an automatic saliency-derived
  trimap or an explicit same-size trimap, the grayscale 3×3 matting Laplacian,
  a deterministic sparse solve, exact restoration of hard constraints, and a
  bounded multiscale working grid for the 0.5-second runtime contract. The local
  scalar feature model can be widened to RGB vectors without changing output.
- KNN matting and information-flow matting after the simpler matting baseline.
- Spectral matting only after its component-selection heuristic has explicit,
  testable deterministic rules.
- Chan-Vese level sets with a deterministic saliency-derived initial contour;
  retain a no-saliency geometric fallback for flat inputs.

### 5. Blob extraction (`Intensity/Mask -> Binary/Intensity`)

Implemented with 8-connected components and deterministic row-major tie breaks.
The return-type contract is split across two opt-in bundles:

- binary `*_blob` operators return same-size component masks;
- intensity operators return the same-size source image masked by the selected
  component;
- geometry selectors cover area and horizontal/vertical bounding-box span;
- source-statistic selectors cover both extrema of mean, median, population
  standard deviation, maximum, and minimum; and
- `blob_extraction_size_between_blob` retains all components inside inclusive
  pixel-area bounds.

Intensity maps use a clamped threshold; binary masks require none. Geometry
selectors expose a minimum-area guard whenever the three-input MAGE limit leaves
room. Empty selections return typed zero images. Source-statistic interval
selectors remain deferred because image, saliency, and two scalar bounds require
four effective inputs; add them only with a range-valued MAGE parameter type.

## Implementation and verification checklist per operator

1. Write a small algorithm note: paper variant, deliberate deviations,
   parameters, output semantics, and degeneracies.
2. Implement pure `Float64` matrix helpers, then a typed MAGE factory wrapper.
3. Test constant, impulse, edge, translated-object, non-square, tiny, and seeded
   degeneracies as applicable.
4. Test MAGE factory specialization, `which`/decode compatibility, input
   immutability, shape, pixel category, finite range, determinism, and fallback.
5. Warm the callable once and assert the minimum of several timings is at most
   0.5 seconds on a deterministic 256x256 fixture. Keep allocations visible in
   benchmark output even when they are not a hard gate yet.
6. Add manual input/output images, including a side-by-side parameter sweep for
   every parameterized operator; list the bundle in the catalogue group and keep
   `checkdocs = :exports`.
7. Run focused tests, package doctests/docs, and then the full test suite against
   the recorded baseline before committing.

## Current milestone

- [x] Define library/output contracts and RGB-ready internal boundary.
- [x] Implement and verify grayscale Itti-Koch-Niebur fixation saliency.
- [x] Implement and verify grayscale spectral-residual fixation saliency.
- [x] Implement and verify return-type-separated blob extraction bundles.
- [x] Implement and verify Boykov-Jolly discrete foreground extraction.
- [x] Implement and verify Random Walker continuous foreground extraction.
- [x] Implement and verify GrabCut discrete foreground extraction.
- [x] Review the first operator and settle naming/performance conventions.
- [ ] Review the spectral-residual results before implementing Image Signature.
