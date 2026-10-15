"""
Basic volume operators: identity, constant volumes and casts between volume
kinds.

# Bundles

- bundle_image3DIntensity_volume_basic_factory
- bundle_image3DBinary_volume_basic_factory

The order of the first two entries is a convention the search relies on, as
for the 2D basic bundles:

1. **identity** `(vol) -> vol`, used when a node is turned into a pass-through;
2. **a constant volume that takes no input** `() -> vol`, what node correction
   and mutation fall back to when no other function can produce the type.

Keep them first when adding operators. The exhaustive operator list is on the
Bundle Catalogue page.

# Example

```julia
using UTCGP, ImageCore
I = typeof(SImageND(IntensityPixel{N0f8}.(zeros(28, 28, 28))))   # the volume type to produce
bundle = bundle_image3DIntensity_volume_basic_factory

constant = bundle[2].fn(I)    # vol_ones specialised for I
constant()                    # a 28³ volume of ones, built from nothing
constant(42, "ignored")       # same: inputs are ignored

to_intensity = bundle[:vol_from_mask].fn(I)
to_intensity(mask)            # set voxels → 1.0, the others → 0.0 (mask: a 28³ binary volume)
```
"""
module image3D_volume_basic

using ..UTCGP: FunctionBundle, append_method!
using ..UTCGP:
    BinaryPixel,
    IntensityPixel,
    SImageND,
    SizedImage,
    SizedImage3D,
    _get_image_pixel_type,
    _get_image_tuple_size,
    _get_image_type,
    _validate_factory_type

# Returned by the bundles when no method matches the inputs (MAGE then skips the node).
fallback(args...) = return nothing

"""
    bundle_image3DIntensity_volume_basic_factory

Basic operators returning an intensity volume, in this order:

1. `vol_identity(vol)`: the volume unchanged.
2. `vol_ones()`: a volume of ones (accepts and ignores any arguments).
3. `vol_zeros()`: a volume of zeros (accepts and ignores any arguments).
4. `vol_from_mask(mask)`: a binary volume as `0`/`1` intensities.

Specialise it on an intensity volume type, e.g.
`SImage3D{28,28,28,IntensityPixel{N0f8}}`.
"""
const bundle_image3DIntensity_volume_basic_factory = FunctionBundle(fallback)

"""
    bundle_image3DBinary_volume_basic_factory

Basic operators returning a binary volume, in this order:

1. `vol_identity(mask)`: the mask unchanged.
2. `vol_ones()`: a mask with every voxel set (accepts and ignores any arguments).
3. `vol_zeros()`: an empty mask (accepts and ignores any arguments).

Specialise it on a binary volume type, e.g.
`SImage3D{28,28,28,BinaryPixel{Bool}}`. Binarising an intensity volume is
`vol_threshold` / `vol_otsu` in `bundle_image3DBinary_volume_factory`.
"""
const bundle_image3DBinary_volume_basic_factory = FunctionBundle(fallback)

# ---------------------------------------------------------------------------
# Constant voxels
# ---------------------------------------------------------------------------

"The voxel value `1` (intensity) or set (binary) of a pixel type."
_one_voxel(::Type{IntensityPixel{T}}) where {T} = IntensityPixel{T}(one(T))
_one_voxel(::Type{BinaryPixel{T}}) where {T} = BinaryPixel{T}(true)
"The voxel value `0` (intensity) or unset (binary) of a pixel type."
_zero_voxel(::Type{IntensityPixel{T}}) where {T} = IntensityPixel{T}(zero(T))
_zero_voxel(::Type{BinaryPixel{T}}) where {T} = BinaryPixel{T}(false)

# ---------------------------------------------------------------------------
# Factories
# ---------------------------------------------------------------------------

"""
    _factory_setup(I, operator) -> (pixel_type, size_type, dims, function_name)

Validate the output volume type `I` and return its pixel type, its size as a
tuple type and as a tuple of integers, and the name of the specialised
function.
"""
function _factory_setup(::Type{I}, operator::Symbol) where {I}
    _validate_factory_type(_get_image_type(I))         # throws for unsupported storage types
    size_type = _get_image_tuple_size(I)               # e.g. Tuple{28,28,28}; its parameters give (28, 28, 28)
    return _get_image_pixel_type(I), size_type, Tuple(size_type.parameters), Symbol(operator, :_, Symbol(I))
end

"`vol_identity` for `I`: method `(vol::I, args...) -> vol`."
function vol_identity_image3D_factory(::Type{I}) where {S1,S2,S3,P,I<:SizedImage3D{S1,S2,S3,P}}
    _, _, _, name = _factory_setup(I, :vol_identity)    # only the function name is needed
    # Accepts exactly the volume type I (Source<:I), returns it untouched.
    return @eval function $name(vol::Source, args::Vararg{Any}) where {Source<:$I}
        return vol
    end
end

"""
`vol_ones` for `I`: method `(args...) -> volume of ones`, callable with no
argument at all. A new array is returned on each call, so programs may modify
it.
"""
function vol_ones_image3D_factory(::Type{I}) where {S1,S2,S3,P,I<:SizedImage3D{S1,S2,S3,P}}
    pixel_type, size_type, dims, name = _factory_setup(I, :vol_ones)
    voxel = _one_voxel(pixel_type)                      # computed once, spliced into the method as a constant
    # No required argument: `args` may be empty, so node correction can call it with nothing.
    return @eval function $name(args::Vararg{Any})
        return SImageND(fill($voxel, $dims), $size_type)
    end
end

"`vol_zeros` for `I`: method `(args...) -> volume of zeros`, callable with no argument."
function vol_zeros_image3D_factory(::Type{I}) where {S1,S2,S3,P,I<:SizedImage3D{S1,S2,S3,P}}
    pixel_type, size_type, dims, name = _factory_setup(I, :vol_zeros)
    voxel = _zero_voxel(pixel_type)
    # Same shape as vol_ones: callable with no argument.
    return @eval function $name(args::Vararg{Any})
        return SImageND(fill($voxel, $dims), $size_type)
    end
end

"""
`vol_from_mask` for an intensity volume type `I`: method `(mask, args...)`
for a binary volume of the same size, set voxels → `1`, the others → `0`.
"""
function vol_from_mask_image3D_factory(::Type{I}) where {S1,S2,S3,P,I<:SizedImage3D{S1,S2,S3,P}}
    pixel_type, size_type, _, name = _factory_setup(I, :vol_from_mask)
    pixel_type <: IntensityPixel || throw(ArgumentError("vol_from_mask returns an intensity volume, got $I"))
    one_voxel, zero_voxel = _one_voxel(pixel_type), _zero_voxel(pixel_type)
    # The mask must have the output's size ($size_type); each voxel maps set → 1, unset → 0.
    return @eval function $name(mask::Mask, args::Vararg{Any}) where {MaskBool,Mask<:SizedImage{$size_type,BinaryPixel{MaskBool}}}
        return SImageND(map(v -> v.pixel ? $one_voxel : $zero_voxel, mask.img), $size_type)
    end
end

# ---------------------------------------------------------------------------
# Registration (order matters: identity, then the input-free constant)
#
# For each bundle, a list of (factory, operator name, description), appended
# in this order: index 1 must stay the identity and index 2 the constant.
# ---------------------------------------------------------------------------

for (bundle, operators) in (
        (bundle_image3DIntensity_volume_basic_factory, (
            (vol_identity_image3D_factory, :vol_identity, "Returns the volume unchanged."),
            (vol_ones_image3D_factory, :vol_ones, "A volume of ones; takes no input."),
            (vol_zeros_image3D_factory, :vol_zeros, "A volume of zeros; takes no input."),
            (vol_from_mask_image3D_factory, :vol_from_mask, "A binary volume as 0/1 intensities."),
        )),
        (bundle_image3DBinary_volume_basic_factory, (
            (vol_identity_image3D_factory, :vol_identity, "Returns the mask unchanged."),
            (vol_ones_image3D_factory, :vol_ones, "A mask with every voxel set; takes no input."),
            (vol_zeros_image3D_factory, :vol_zeros, "An empty mask; takes no input."),
        )),
    )
    for (factory, name, description) in operators
        append_method!(bundle, factory, name; description = description)
    end
end

end
