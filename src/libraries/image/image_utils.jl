using ImageCore: rawview, Normed
using ImageCore: channelview
using Images
import Lazy:@forward

struct ImageSize{S}
    function ImageSize{s}() where {s}
        return new{s::Tuple{Vararg{Int}}}()
    end
end

function ImageSize(s::T) where {T<:Tuple{Vararg{Int}}}
    return ImageSize{s}()
end

function size_as_tuple(::ImageSize{S}) where {S}
    return Tuple{S...}
end

function _convert_image_to_channel_view(img)
    return collect(channelview(img))
end

"""

Type Stable
"""
function _positive_params(x::Vararg{Int,N}) where {N}
    return max.(x, 1)
end

"""

Type Stable
"""
function _ceil_positive_params(x::T...) where {T<:Int}
    global MAX_INT
    max_ = MAX_INT[]
    min_ = 1
    nbs = clamp.(x, min_, max_)
    return nbs
end


# SizedImage utils
function _get_image_tuple_size(img::A) where {A<:AbstractArray}
    sizes = size(img)
    ims = ImageSize{sizes}()
    if length(sizes) > 0
        return size_as_tuple(ims)
    else
        throw(ErrorException("Img with wrong dims"))
    end
end

# SizedImage #

# PIXEL TYPES

"""
    AbstractPixel{T}

Supertype of MAGE's pixel types: [`BinaryPixel`](@ref), [`IntensityPixel`](@ref)
and [`SegmentPixel`](@ref).

These exist so that *what an image means* is part of its type. Three images can
all be `10x10` arrays of numbers and still belong to three different
chromosomes: a mask, a greyscale image, and a label map. Morphology then only
offers itself to masks, thresholding only produces them, and so on — the type
system, not a runtime check, is what keeps an evolved pipeline sensible.

A pixel behaves like the number it wraps: arithmetic, comparisons, `sin`, `exp`,
`round`, `convert` and promotion all forward to the underlying value.
"""
abstract type AbstractPixel{T} <: Number end 
abstract type NonBinaryPixel{T} <: AbstractPixel{T} end

"""
    BinaryPixel(v::Bool)

Pixel of a mask. See [`AbstractPixel`](@ref).

Produced by binarization and boolean arithmetic, consumed by morphology.
"""
struct BinaryPixel{T<:Bool} <: AbstractPixel{T}
    pixel::T
end

"""
    SegmentPixel(v::Real)

Pixel of a label map: its value is a segment identifier, not an intensity. See
[`AbstractPixel`](@ref).
"""
struct SegmentPixel{T<:Real} <: NonBinaryPixel{T}
    pixel::T
end

"""
    IntensityPixel(v::Real)

Pixel of a greyscale image. See [`AbstractPixel`](@ref).

This is the type most image operators — filtering, morphology, transcendental
transforms, pooling — take and return.
"""
struct IntensityPixel{T<:Real} <: NonBinaryPixel{T}
    pixel::T
end

@forward AbstractPixel.pixel (Base.sin, Base.cos, Base.exp, Base.round, Base.ceil, Base.floor, Base.log, Base.log2, Base.log10, Base.float, Images.float64, Images.float32)
Base.convert(::Type{T}, p::AbstractPixel) where {T<:Number} = convert(T, p.pixel)
Base.promote_rule(::Type{<:AbstractPixel{T}}, ::Type{S}) where {T,S<:Number} = promote_type(T,S)
Base.broadcastable(p::AbstractPixel) = Ref(p)

function BinaryPixel{T}(v::BinaryPixel{T}) where T<:Bool
    v
end
function IntensityPixel{T}(v::IntensityPixel{T}) where T<:Real
    v
end
function SegmentPixel{T}(v::IntensityPixel{T}) where T<:Real
    v
end

function Base.reinterpret(img::Array{<:AbstractPixel{T}}) where T
    reinterpret.(T, img)
end

for op in (:+, :-, :*, :/, :<, :>, :(==), :(>=), :(<=),  :isless, :isequal, :isgreater)
    @eval Base.$op(a::AbstractPixel, b::Number) = $op(a.pixel, b)
    @eval Base.$op(a::Number, b::AbstractPixel) = $op(a, b.pixel)
    # @eval Base.$op(a::AbstractPixel{T}, b::T) where T <: Number = typeof(a)($op(a.pixel, b))
    # @eval Base.$op(a::T, b::AbstractPixel{T}) where T <: Number = typeof(b)($op(a, b.pixel))
    @eval Base.$op(a::AbstractPixel, b::AbstractPixel) = $op(a.pixel, b.pixel)
end

Base.Float64(pixel::AbstractPixel{T}) where T = convert(Float64, pixel.pixel)
Base.Float32(pixel::AbstractPixel{T}) where T = convert(Float32, pixel.pixel)
Base.Int(pixel::AbstractPixel{T}) where T = convert(Int, pixel)
N0f8(pixel::AbstractPixel{T}) where T = convert(N0f8, pixel)
AbstractFloat(pixel::AbstractPixel{T}) where T = AbstractFloat(Float64(pixel))

abstract type AbtractSizedImage{S<:Tuple,T<:AbstractPixel,N,IT} <: AbstractArray{T,N} end
"""
    SizedImage{S<:Tuple,T,N,IT}

Supertype of images whose dimensions live in their type.

`S` is a `Tuple` type carrying the sizes (e.g. `Tuple{10,10}`), `T` the pixel
type, `N` the number of dimensions and `IT` the concrete array backing it. The
sole concrete subtype is [`SImageND`](@ref).

Encoding the size in the type is what lets a MAGE chromosome be "28x28
intensity images" rather than "images": two images of different sizes are
different types, so an operator that would silently broadcast mismatched shapes
simply is not applicable.

Behaves as an `AbstractArray{T,N}`: `length`, `size` and indexing forward to the
wrapped array.
"""
abstract type SizedImage{S<:Tuple,T,N,IT} <: AbtractSizedImage{S,T,N,IT} end

"""
    SizedImage2D{S1,S2,T,IT}

Two-dimensional [`SizedImage`](@ref) of `S1 x S2` pixels of type `T`.
"""
const SizedImage2D{S1,S2,T,IT} =
    SizedImage{Tuple{S1,S2},T,2,IT} where {T,IT<:AbstractArray{T,2}}

"""
    SizedImage3D{S1,S2,S3,T,IT}

Three-dimensional [`SizedImage`](@ref) of `S1 x S2 x S3` pixels of type `T`.
"""
const SizedImage3D{S1,S2,S3,T,IT} =
    SizedImage{Tuple{S1,S2,S3},T,3,IT} where {T,IT<:AbstractArray{T,2}}

 
Base.length(a::T) where {T<:SizedImage} = length(a.img)
Base.size(a::T) where {T<:SizedImage} = size(a.img)
# Base.setindex(a::A, i) = setindex(a.x, i)
Base.getindex(a::SI, i) where {SI<:SizedImage{S,T,N}} where {S,T,N} = getindex(a.img, i)
Base.getindex(a::SizedImage, i::Vararg{Int,N}) where {N} = getindex(a.img, i...)

"""
    SImageND(img::AbstractArray)
    SImageND(img::AbstractArray, S::Type{<:Tuple})
    SImageND{S,T,N}(img::AbstractArray{T,N})

The image type MAGE evolves over: an array whose shape is part of its type.

The one-argument form reads the sizes off the array at run time; passing `S`
explicitly (e.g. `Tuple{10,10}`) is type-stable and free, and is what library
code uses on hot paths.

```julia
using ImageCore: N0f8
img = SImageND(IntensityPixel{N0f8}.(rand(28, 28)))
typeof(img)   # SImageND{Tuple{28,28}, IntensityPixel{N0f8}, 2, ...}
```

See [`SizedImage`](@ref) for why the size is in the type, and
[`AbstractPixel`](@ref) for the pixel types that make masks, intensities and
label maps distinct chromosomes. Aliases: [`SImage2D`](@ref),
[`SImage3D`](@ref).
"""
struct SImageND{S<:Tuple,T,N,IT} <: SizedImage{S,T,N,IT}
    img::IT
    function SImageND{S,T,N}(img::AbstractArray{T,N}) where {S<:Tuple,T,N}
        # print("COSNTRUCTING $S $T $N")
        # TODO check S,T and N
        # todo check IT accordance with TN
        it = typeof(img)
        return new{S,T,N,it}(img)
    end

    function SImageND(img::AbstractArray{T,N}) where {T,N}
        # TODO check S,T and N
        S = _get_image_tuple_size(img)
        it = typeof(img)
        return new{S,T,N,it}(img)
    end

    """

    Accepts S with the sizes as type. Ex : Tuple{10,10}. 
    No overhead and type safe.
    """
    function SImageND(img::AbstractArray{T,N}, S::TS) where {T,N,TS<:Type{<:Tuple}}
        # TODO check S,T and N
        it = typeof(img)
        return new{S,T,N,it}(img)
    end
end

"""
    SImage2D{S1,S2,T}

Two-dimensional [`SImageND`](@ref) of `S1 x S2` pixels of type `T`.
"""
const SImage2D{S1,S2,T} = SImageND{Tuple{S1,S2},T,2,IT} where {IT<:AbstractArray{T,2}}

"""
    SImage3D{S1,S2,S3,T}

Three-dimensional [`SImageND`](@ref) of `S1 x S2 x S3` pixels of type `T`.
"""
const SImage3D{S1,S2,S3,T} = SImageND{Tuple{S1,S2,S3},T,3,IT} where {IT<:AbstractArray{T,2}}

@inline function _get_image_tuple_size(img::AbstractArray{T,1}) where {T}
    s = size(img)
    return Tuple{s[1]}
end
@inline function _get_image_tuple_size(img::AbstractArray{T,2}) where {T}
    s = size(img)
    return Tuple{s[1], s[2]}
end
@inline function _get_image_tuple_size(img::AbstractArray{T,3}) where {T}
    s = size(img)
    return Tuple{s[1], s[2], s[3]}
end
@inline function _get_image_tuple_size(img::AbstractArray{T,4}) where {T}
    s = size(img)
    return Tuple{s[1], s[2], s[3], s[4]}
end
@inline function _get_image_tuple_size(img::Type{<:SizedImage})
    t = Base.unwrap_unionall(img)
    return t.parameters[1]
end

@inline function _get_image_pixel_type(img::Type{<:SizedImage})
    t = Base.unwrap_unionall(img)
    t.parameters[2]
end
@inline function _get_image_pixel_type(img::SizedImage)
    return typeof(img).parameters[2]
end

@inline function _get_image_type(img::SizedImage)
    t = _get_image_pixel_type(img)
    return t.parameters[1]
end
@inline function _get_image_type(img::Type{<:SizedImage})
    pt = _get_image_pixel_type(img)
    return pt.parameters[1]
end

@inline function _validate_factory_type(TT::Type{N}) where {N}
    @assert TT != Any "The parametric type cannot be Any"
    @assert Base.isconcretetype(TT) "The parametric type cannot be Any"
    @assert !(TT isa Union) "The parametric type cannot be the Union of several types"
end

# FOR TESTING --- 
function _generate_test_image(PIXEL::Type{IntensityPixel{T}}, size=(10, 10)) where T
    return SImageND(PIXEL.(([i + j for i in 1:size[1], j in 1:size[2]] / (size[1] + size[2]))))
end

function _generate_test_image(::Type{BinaryPixel{T}}, size=(10, 10)) where T
    img = [Bool((i + j) % 2) for i in 1:size[1], j in 1:size[2]]
    return SImageND(BinaryPixel.(img))
end

function _generate_test_image(PIXEL::Type{SegmentPixel{T}}, size=(10, 10)) where T
    img = [T(mod1(i + j, 3)) for i in 1:size[1], j in 1:size[2]]
    # img = reinterpret.(N0f8, img)
    return SImageND(PIXEL.(img))
end

