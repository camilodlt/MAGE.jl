""" Segmentation functions

Exports :

- **bundle\\image2D\\_segmentation** :
    - `felzenswalb`
    - `unseeded_grow`
    - `Watershed` TODO
    - `mean_shift` TODO
    - `kmeans` TODO

"""
module image2D_segmentation

using ImageCore: Gray
using ImageSegmentation
using ..UTCGP: ManualDispatcher
using ..UTCGP: FunctionBundle, append_method!
import UTCGP:
    CONSTRAINED,
    MIN_INT,
    MAX_INT,
    MIN_FLOAT,
    MAX_FLOAT,
    _positive_params,
    _ceil_positive_params
using ImageCore: N0f8, Normed
using ..UTCGP:
    SizedImage,
    SImageND,
    _get_image_tuple_size,
    _get_image_type,
    _validate_factory_type,
    SizedImage2D
using Clustering
fallback(args...) = return nothing

bundle_image2D_segmentation_factory = FunctionBundle(fallback)

# ######################## #
# Felzenswalb Segmentation #
# ######################## #

"""
    felzenswalb_image2D_factory(i::Type{I}) where {I<:SizedImage}

Returns the methods specialized on the given type `CONT`.


    m1(img::I, k::Int, args...) where {I <: CONT}

- `k` is clamped between (1,`k`). if not, all pixels are its own class.

TODO 

    m2(img::I, k::Int, min_size ::Int,  args...) where {I <: CONT}

- `k` is clamped between (1,`k`). if not, all pixels are its own class.

- `min_size` is also clamped between (2, `min_size`) because a cluster has at least 2 pixel in it 

"""
function felzenswalb_image2D_factory(i::Type{I}) where {I<:SizedImage}
    TT = Base.unwrap_unionall(I).parameters[2]
    _validate_factory_type(TT)
    StorageType = TT.types[1] # UInt8, UInt16 ...

    m1 = @eval ((img::CONCT, k::Int, args::Vararg{Any}) where {CONCT<:$I}) -> begin
        S = CONCT.parameters[1] # Tuple{X,Y}
        k = clamp(k, 1, k)
        segments = felzenszwalb(img, k)
        seg = labels_map(segments)
        reinterpreted = reinterpret.($TT, convert.($StorageType, seg)) # convert Int64 to the correct Normed{StorageType}
        return SImageND(reinterpreted, S)
    end

    ManualDispatcher((m1,), :felzenswalb_2D)
end

# ################### #
# HC Segmentation     #
# ################### #
function _hc_segmentation(img, q_th)
    imsize = size(img)
    img_petite = imresize(img.img, (50, 50))
    v = img_petite[:]
    m = reshape(v, length(v), 1)
    d = pairwise(Euclidean(), float.(m), dims = 1)
    h = hclust(d)
    th = quantile(h.height, q_th) # 80 % of mergin heights are below
    imresize(reshape(cutree(h, h = th), (50, 50)), imsize)
end


# ####################### #
# Unseeded Region Growing #
# ####################### #

"""
    unseededgrow_image2D_factory(i::Type{I}) where {I<:SizedImage}

Exposes Two methods

    m1 = @eval ((img::CONCT, th::Float64, args::Vararg{Any}) where {CONCT<:\$I})

The threshold limits the assignment to an already growing region
Higher thresholds results in less instances. 
        
    m2 = @eval ((img::CONCT, args::Vararg{Any}) where {CONCT<:\$I})
    
The theshold is fixed at 0.3

Returns a ManualDispatcher with name `:unseededgrow_2D`
"""
function unseededgrow_image2D_factory(i::Type{I}) where {I<:SizedImage}
    TT = Base.unwrap_unionall(I).parameters[2]
    _validate_factory_type(TT) # N0f8, N0f16
    StorageType = TT.types[1] # UInt8, UInt16 ...

    # m1 (img, th::Float)

    m1 = @eval ((img::CONCT, th::Float64, args::Vararg{Any}) where {CONCT<:$I}) -> begin
        S = CONCT.parameters[1] # Tuple{X,Y}
        th = clamp(th, eps(Float64), th)
        gimg = Gray.(img)
        segments = unseeded_region_growing(gimg, th)
        seg = labels_map(segments)
        reinterpreted = reinterpret.($TT, convert.($StorageType, seg)) # convert Int64 to the correct Normed{StorageType}
        return SImageND(reinterpreted, S)
    end

    m2 = @eval ((img::CONCT, args::Vararg{Any}) where {CONCT<:$I}) -> begin
        S = CONCT.parameters[1] # Tuple{X,Y}
        gimg = Gray.(img)
        segments = unseeded_region_growing(gimg, 0.3)
        seg = labels_map(segments)
        reinterpreted = reinterpret.($TT, convert.($StorageType, seg)) # convert Int64 to the correct Normed{StorageType}
        return SImageND(reinterpreted, S)
    end
    ManualDispatcher((m1, m2), :unseededgrow_2D)
end


# Factory Methods
append_method!(
    bundle_image2D_segmentation_factory,
    felzenswalb_image2D_factory,
    :felzenswalb_2D,
)

append_method!(
    bundle_image2D_segmentation_factory,
    unseededgrow_image2D_factory,
    :unseededgrow_2D,
)

end
