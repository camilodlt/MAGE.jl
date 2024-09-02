""" Segmentation functions

Exports :

- **bundle\\image2D\\_segmentation** :
    - `felzenswalb`
    - `unseeded_grow`
    - `Watershed`
    - `mean_shift` TODO
    - `kmeans` TODO

"""
module image2D_segmentation

using ImageCore: Gray
using ImageSegmentation
using ImageMorphology
using ..UTCGP: ManualDispatcher
using ..UTCGP: FunctionBundle, append_method!
using LRUCache
import UTCGP:
    CONSTRAINED,
    MIN_INT,
    MAX_INT,
    MIN_FLOAT,
    MAX_FLOAT,
    _positive_params,
    _ceil_positive_params,
    to
using TimerOutputs
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
    DefaultTH = 0.3
    # m1 (img, th::Float)

    m1 = @eval ((img::CONCT, th::Float64, args::Vararg{Any}) where {CONCT<:$I}) -> begin
        S = CONCT.parameters[1] # Tuple{X,Y}
        th = isnan(th) ? $DefaultTH : th
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
        segments = unseeded_region_growing(gimg, $DefaultTH)
        seg = labels_map(segments)
        reinterpreted = reinterpret.($TT, convert.($StorageType, seg)) # convert Int64 to the correct Normed{StorageType}
        return SImageND(reinterpreted, S)
    end
    ManualDispatcher((m1, m2), :unseededgrow_2D)
end


# # ######################## #
# # MeanShift Segmentation   #
# # ######################## #

# """
#     meanshift_image2D_factory(i::Type{I}) where {I<:SizedImage}


# """
# function meanshift_image2D_factory(i::Type{I}) where {I<:SizedImage}
#     TT = Base.unwrap_unionall(I).parameters[2]
#     _validate_factory_type(TT)
#     StorageType = TT.types[1] # UInt8, UInt16 ...

#     m1 = @eval ((img::CONCT, args::Vararg{Any}) where {CONCT<:$I}) -> begin
#         S = CONCT.parameters[1] # Tuple{X,Y}
#         segments = meanshift(img, 16, 8 / 255) # as per documentation
#         seg = labels_map(segments)
#         reinterpreted = reinterpret.($TT, convert.($StorageType, seg)) # convert Int64 to the correct Normed{StorageType}
#         return SImageND(reinterpreted, S)
#     end
#     ManualDispatcher((m1,), :meanshift_2D)
# end

# ############################ #
# Fast scanning Segmentation   #
# ############################ #

"""
    fastscanning_image2D_factory(i::Type{I}) where {I<:SizedImage}

TODO TEST
"""
function fastscanning_image2D_factory(i::Type{I}) where {I<:SizedImage}
    TT = Base.unwrap_unionall(I).parameters[2]
    _validate_factory_type(TT)
    StorageType = TT.types[1] # UInt8, UInt16 ...

    m1 = @eval ((img::CONCT, th::Float64, args::Vararg{Any}) where {CONCT<:$I}) -> begin
        S = CONCT.parameters[1] # Tuple{X,Y}
        th = isnan(th) ? 0.1 : th
        th = clamp(th, eps(Float64), th)
        segments = fast_scanning(img, th)
        seg = labels_map(segments)
        reinterpreted = reinterpret.($TT, convert.($StorageType, seg)) # convert Int64 to the correct Normed{StorageType}
        return SImageND(reinterpreted, S)
    end
    m2 = @eval ((img::CONCT, args::Vararg{Any}) where {CONCT<:$I}) -> begin
        S = CONCT.parameters[1] # Tuple{X,Y}
        segments = fast_scanning(img, 0.1) # as per documentation
        seg = labels_map(segments)
        reinterpreted = reinterpret.($TT, convert.($StorageType, seg)) # convert Int64 to the correct Normed{StorageType}
        return SImageND(reinterpreted, S)
    end
    ManualDispatcher((m1, m2), :fastscanning_2D)
end

"""

TODO TEST
"""
function watershed_image2D_factory(i::Type{I}) where {I<:SizedImage}

    TT = Base.unwrap_unionall(I).parameters[2]
    WS_ARGS = Tuple{Float64,Float64,I,Vararg{Any}}
    _validate_factory_type(TT)
    StorageType = TT.types[1] # UInt8, UInt16 ...
    @timeit_debug to "Cr LRU watershed" lru = LRU{WS_ARGS,I}(maxsize = 100_000)

    m1 = @eval (
        (
            img::CONCT,
            th_background_foreground::Float64,
            th_distance::Float64,
            args::Vararg{Any},
        ) where {CONCT<:$I}
    ) -> begin
        global to
        @timeit_debug to "Watershed. info" begin
            @debug cache_info($lru)
            # Base.summarysize($lru) / 1e+9
            # @debug "Watershed LRU size in GB : $s"
        end

        # Example with cellpose img
        t = @elapsed @timeit_debug to "Watershed. LRU get!" res =
            get!($lru, (th_background_foreground, th_distance, img, args)) do
                @timeit_debug to "Watershed. All" begin # println("WATERSHED")
                    S = CONCT.parameters[1] # Tuple{X,Y}
                    array_size = (S.parameters[1], S.parameters[2])
                    background_as_feature = BitArray(undef, array_size)
                    foreground_as_feature = BitArray(undef, array_size)
                    dt = zeros(Float64, array_size)
                    markers = zeros(Int, array_size)

                    @timeit_debug to "Watershed. Clamp th_background_foreground" th_background_foreground_ =
                        clamp(th_background_foreground, 0.0, 1.0)

                    # Find the markers
                    ## Normally background is darker than cells.
                    @timeit_debug to "Watershed. Bg to white" background_as_feature .=
                        Gray.(img) .< th_background_foreground_ # Background becomes white instances
                    @timeit_debug to "Watershed. Fg to white" foreground_as_feature .=
                        1 .- background_as_feature # cells are white, bg black

                    @timeit_debug to "Watershed. DT" dt .= distance_transform(
                        feature_transform(background_as_feature),
                    ) # white is farther (higher cost) to bg (true instances) => cells are mountains
                    inv_dt = dt # reuse the same float array
                    @timeit_debug to "Watershed. Inv DT" inv_dt .= 1 .- dt # now black is farther to bg => cells are valleys
                    @timeit_debug to "Watershed. Markers" markers .=
                        label_components(inv_dt .< th_distance) # get the white markers (hopefully the center of the inv_dt valleys)

                    # Watershed 
                    @timeit_debug to "Watershed. Watershed" segments =
                        watershed(inv_dt, markers) # flods the valleys from the markers
                    flooded = markers
                    @timeit_debug to "Watershed. Mask the watershed" flooded .=
                        labels_map(segments) .* foreground_as_feature # masks to get only the segmented cells
                    @timeit_debug to "Watershed. Reinterpret" reinterpreted =
                        reinterpret.($TT, convert.($StorageType, flooded)) # convert Int64 to the correct Normed{StorageType}
                    return SImageND(reinterpreted, S)
                end
            end
        return res
    end
    ManualDispatcher((m1,), :watershed_2D)
end

# Factory Methods
# append_method!(
#     bundle_image2D_segmentation_factory,
#     felzenswalb_image2D_factory,
#     :felzenswalb_2D,
# )

# append_method!(
#     bundle_image2D_segmentation_factory,
#     unseededgrow_image2D_factory,
#     :unseededgrow_2D,
# )

append_method!(
    bundle_image2D_segmentation_factory,
    fastscanning_image2D_factory,
    :fastscanning_2D,
)

append_method!(
    bundle_image2D_segmentation_factory,
    watershed_image2D_factory,
    :watershed_2D,
)

end
