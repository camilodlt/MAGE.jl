```@meta
CurrentModule = UTCGP
```

# Core image bundle reference

Module and bundle documentation for the core image operators. See
[Image Lib](image.md) for saliency, orientation and pooling galleries, and
[Core image operators: gallery](image_core.md) for arithmetic, filtering,
morphology, thresholding and segmentation effects. The [Bundle Catalogue](catalogue.md)
lists every registered operator by output type.

## Basics, casts and arithmetic

```@docs
UTCGP.image2D_basic
bundle_image2DIntensity_basic_factory
bundle_image2DBinary_basic_factory
bundle_image2DSegment_basic_factory
```

```@docs
UTCGP.image2D_arithmetic
bundle_image2DIntensity_arithmetic_factory
bundle_image2DBinary_arithmetic_factory
```

```@docs
UTCGP.image2D_barithmetic
bundle_image2DIntensity_barithmetic_factory
```

```@docs
UTCGP.image2D_transcendental
bundle_image2DIntensity_transcendental_factory
```

## Filtering

```@docs
UTCGP.image2D_filtering
bundle_image2DIntensity_filtering_factory
bundle_image2DBinary_filtering_factory
```

## Morphology

```@docs
UTCGP.image2D_morph
bundle_image2DIntensity_morph_factory
bundle_image2DBinary_morph_factory
```

## Orientation

```@docs
UTCGP.image2D_orientation
bundle_image2DIntensity_orientation_factory
```

## Fixation saliency

```@docs
UTCGP.image2D_saliency_fixation
bundle_image2DIntensity_saliency_fixation_factory
```

## Thresholding

```@docs
UTCGP.image2D_binarize
bundle_image2DBinary_binarize_factory
```

## Segmentation

```@docs
UTCGP.image2D_segmentation
bundle_image2DSegment_segmentation_factory
```

## Pooling

```@docs
UTCGP.image_pool
bundle_image2DIntensity_pool_factory
bundle_image2DBinary_pool_factory
bundle_image2DSegment_pool_factory
```

```@docs
UTCGP.image_pooler
bundle_image2DIntensity_pooler_factory
bundle_image2DBinary_pooler_factory
bundle_image2DSegment_pooler_factory
```
