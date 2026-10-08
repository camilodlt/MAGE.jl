```@meta
CurrentModule = UTCGP
```

# Image Types

MAGE puts two things in an image's *type* that are usually left to runtime
checks: its size, and what its pixels mean. That is what lets images be
first-class chromosome types.

```@contents
Pages = ["image_types.md"]
Depth = 2
```

## Pixels carry meaning

Three pixel types wrap the same underlying numbers but are distinct types:

| Type | Meaning | Typical producers |
|:--|:--|:--|
| [`IntensityPixel`](@ref) | greyscale value | filtering, morphology, arithmetic |
| [`BinaryPixel`](@ref) | mask | thresholding, boolean arithmetic |
| [`SegmentPixel`](@ref) | segment identifier | segmentation |

Because they are different types, they can be three different chromosomes. An
evolved program cannot accidentally erode a label map or apply Otsu to a mask —
not because a check rejects it, but because no such node exists.

A pixel behaves like the number it wraps: arithmetic, comparisons, `sin`, `exp`,
`round`, `convert` and promotion all forward through.

```@docs
AbstractPixel
IntensityPixel
BinaryPixel
SegmentPixel
```

## Sizes live in the type

```@docs
SizedImage
SizedImage2D
SizedImage3D
SImageND
SImage2D
SImage3D
```

Two images of different shapes are different types, so an operator that would
silently broadcast mismatched shapes is simply not applicable to the node. The
constructor taking `S` explicitly is type-stable and free, which is what library
code uses on hot paths:

```@example imgtypes
using UTCGP
using ImageCore: N0f8

img = SImageND(IntensityPixel{N0f8}.(rand(8, 8)))
typeof(img)
```

```@example imgtypes
mask = SImageND(BinaryPixel.(rand(Bool, 8, 8)))
size(mask), eltype(mask)
```

## RGB images

MAGE represents a true RGB input as a different chromosome type from its
individual red, green, and blue planes. It is a three-dimensional image whose
last axis has exactly three slices in `R, G, B` order:

```@example imgtypes
red = rand(8, 8)
green = rand(8, 8)
blue = rand(8, 8)
rgb = SImageND(IntensityPixel{N0f8}.(cat(red, green, blue; dims = 3)))

(rgb isa SImage3D{8,8,3,IntensityPixel{N0f8}}, size(rgb), eltype(rgb))
```

The pixel wrapper remains `IntensityPixel{N0f8}` because MAGE uses the wrapper
to encode image semantics. The extra dimension—not a change to raw channel
storage—is what makes RGB a separate node and chromosome type. A color dataset
can therefore expose four inputs simultaneously: three
`SImage2D{H,W,IntensityPixel{N0f8}}` planes followed by one
`SImage3D{H,W,3,IntensityPixel{N0f8}}` RGB image.

Ordinary `image2D` functions are specialized for a two-dimensional output type
and cannot dispatch on this RGB chromosome. The dimension-generic whole-image
reducers do accept it; their statistics cover all three channels. Dedicated
cross-type operators are described under
[RGB Images and Color Statistics](@ref).
