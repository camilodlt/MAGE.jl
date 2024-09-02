# -*- coding: utf-8 -*-
""" Filtering functions

Exports :

- **bundle\\image2D\\_filtering** :
    - sobelx\\_image2D\\_factory
    - sobely\\_image2D\\_factory
    - sobel\\_image2D\\_factory
    - gaussian\\_image2D\\_factory

"""

# We use the Array View for images

module image2D_filtering

using LoopVectorization
using TimerOutputs
using ImageFiltering
using ..UTCGP: ManualDispatcher
using ..UTCGP: FunctionBundle, append_method!
import UTCGP:
    CONSTRAINED,
    MIN_INT,
    MAX_INT,
    MIN_FLOAT,
    MAX_FLOAT,
    _positive_params,
    _ceil_positive_params,
    to
using ImageCore: N0f8, Normed, clamp01nan, clamp01nan!, float64
using ..UTCGP:
    SizedImage,
    SizedImage2D,
    SImageND,
    _get_image_tuple_size,
    _get_image_type,
    _validate_factory_type

fallback(args...) = return nothing
bundle_image2D_filtering_factory = FunctionBundle(fallback)
InputType = SizedImage2D{S1,S2,T,IT} where {S1,S2,T<:Normed,IT} # 2D img
const _ysobel, _xsobel = reflect.(Kernel.sobel())
const gaussian5 = Kernel.gaussian(1)
const gaussian9 = Kernel.gaussian(2)
const gaussian13 = Kernel.gaussian(3)

# Convolution Border Decision ---
function _border_type(border_index::Real)
    how = "replicate" # if b  == 0 # abcdef | ffff (replicates last)
    if border_index < 0
        how = "circular" # abcdef | abcd (wraps around)
    elseif border_index > 0
        how = "reflect" # abcdef | fedc (mirrors edge)
    end
    how
end

abstract type _GradientAxis end
struct _Xaxis <: _GradientAxis end
struct _Yaxis <: _GradientAxis end
struct _Maxis <: _GradientAxis end
string(::Type{_Xaxis}) = "x" # SobelX
string(::Type{_Yaxis}) = "y" # SobelY
string(::Type{_Maxis}) = "m" # SobelMagnitude

# ################### #
# SOBEL               #
# ################### #

"""
    _sobel_dispatcher(img::SImageND, b::Real, which::_Xaxis)

Dispatchs with the kernel of the X axis
"""
@inline function _sobel_dispatcher(
    img::Matrix{Float64},
    out::Matrix{Float64},
    b::Real,
    which::Type{_Xaxis},
)
    _sobel_dispatcher_conv!(img, out, b, _xsobel)
end

"""
    _sobel_dispatcher(img::SImageND, b::Real, which::_Yaxis)

Dispatchs with the kernel of the Y axis
"""
@inline function _sobel_dispatcher(
    img::Matrix{Float64},
    out::Matrix{Float64},
    b::Real,
    which::Type{_Yaxis},
)
    _sobel_dispatcher_conv!(img, out, b, _ysobel)
end

"""
    _sobel_dispatcher(img::SImageND, b::Real, which::_Maxis)

Square root of Gx^2 + Gy^2  
"""
function _sobel_dispatcher(
    img::Matrix{Float64},
    out::Matrix{Float64},
    b::Real,
    ::Type{_Maxis},
)
    out_x = similar(img)
    out_y = similar(img)
    _sobel_dispatcher_conv!(img, out_x, b, _xsobel)
    _sobel_dispatcher_conv!(img, out_y, b, _ysobel)
    # out .= sqrt.(out_x .^ 2 .+ out_y .^ 2)
    # @timeit_debug to "simd with x" @inbounds @simd for i in eachindex(out)
    #     x = out_x[i]^2
    #     x += out_y[i]^2
    #     out[i] = sqrt(x)
    # end
    @timeit_debug to "turbo with x" @inbounds @turbo for i in eachindex(out)
        x = out_x[i]^2
        x += out_y[i]^2
        out[i] = sqrt(x)
    end
    # @timeit_debug to "Broadcast" begin
    #     out .= sqrt.(out_x .^ 2 .+ out_y .^ 2)
    # end
end

function _sobel_dispatcher_fast!(
    ::Matrix{Float64},
    ::Matrix{Float64},
    ::Real,
    ::Type{_Maxis},
)
    throw("Sobel type has to be x,y or magnitude")
end

# CONVOLUTION ON SOBEL # 
function _sobel_dispatcher_conv!(
    img::Matrix{Float64},
    out::Matrix{Float64},
    b::Real,
    K::AbstractArray,
)::Matrix{Float64} where {I<:InputType}
    border = _border_type(b)
    imfilter!(out, img, K, border)
end

function _clamp_convert!(
    img::Matrix{Float64},
    f_normed::Matrix{N},
    t::Type{N},
    s::Type{<:Tuple},
) where {N<:Normed}
    clamp01nan!(img)
    f_normed .= convert.(t, img)
end

# Factory of factories 🏭

"""

The first factory dispatches on Axis type and the second on Image Type
https://juliaimages.org/ImageFiltering.jl/v0.7/function_reference/#ImageFiltering.Kernel.sobel

First function accepts an image and a boder type. 

Second function accepts an image but defaults to `replicate` border type.
"""
function sobel_image2D_factory(axis::Type{<:_GradientAxis}, fn)
    # axis => _Xaxis, _Yaxis, _Maxis
    fn_name = Symbol("sobel" * string(axis) * "_image2D")
    # The factory below creates specialized versions based on a specific image type 

    factory =
        ((x::Type{I}) where {I<:SizedImage}) -> begin
            TT = Base.unwrap_unionall(I).parameters[2]
            _validate_factory_type(TT)
            m1 = @eval ((img::CONCT, b::Real, args::Vararg{Any}) where {CONCT<:$I}) ->
                begin
                    global to
                    @timeit_debug to "Sobel Fast" begin
                        T = _get_image_type(CONCT)
                        S = _get_image_tuple_size(CONCT) # Type
                        s = (S.parameters[1], S.parameters[2])
                        ax = $axis
                        img_as_float = Matrix{Float64}(undef, s)
                        img_as_float .= float64.(img)
                        out_float = Matrix{Float64}(undef, s)
                        out_normed = Matrix{T}(undef, s)
                        @timeit_debug to "Sobel dispatcher" $fn(
                            img_as_float,
                            out_float,
                            b,
                            ax,
                        )
                        @timeit_debug to "Convert" _clamp_convert!(
                            out_float,
                            out_normed,
                            T,
                            S,
                        )
                        SImageND(out_normed, S)
                    end
                end

            m2 = @eval ((img::CONCT, args::Vararg{Any}) where {CONCT<:$I}) -> begin
                $m1(img, 0.0, args)
            end

            ManualDispatcher((m1, m2), fn_name)
        end
    return factory
end

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~#
# ################# GAUSSIAN ############### # 
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~#

function gaussian_dispatcher(img::InputType, b::Real, K::AbstractArray)
    border = _border_type(b)
    f_img = float64.(img)
    imfilter(f_img, reflect(K), border)
end
function gaussian_filter(σ::Real)
    if σ < 0
        return gaussian5
    elseif σ == 0
        return gaussian9
    else
        return gaussian13
    end
end

function gaussian_image2D_factory(i::Type{I}) where {I<:InputType}

    TT = Base.unwrap_unionall(I).parameters[2]
    _validate_factory_type(TT)

    m1 =
        @eval ((img::CONCT, b::Real, σ::Real, args::Vararg{Any}) where {CONCT<:$I}) -> begin
            T = _get_image_type(CONCT)
            S = _get_image_tuple_size(CONCT) # Type
            s = (S.parameters[1], S.parameters[2])
            gaussian_k = gaussian_filter(σ)
            res = gaussian_dispatcher(img, b, gaussian_k)
            out_normed = Matrix{T}(undef, s)
            _clamp_convert!(res, out_normed, T, S)
            SImageND(out_normed, S)
        end

    m2 = @eval ((img::CONCT, b::Real, args::Vararg{Any}) where {CONCT<:$I}) -> begin
        T = _get_image_type(CONCT)
        S = _get_image_tuple_size(CONCT) # Type
        s = (S.parameters[1], S.parameters[2])
        res = gaussian_dispatcher(img, b, gaussian5)
        out_normed = Matrix{T}(undef, s)
        _clamp_convert!(res, out_normed, T, S)
        SImageND(out_normed, S)
    end

    m3 = @eval ((img::CONCT, args::Vararg{Any}) where {CONCT<:$I}) -> begin
        T = _get_image_type(CONCT)
        S = _get_image_tuple_size(CONCT) # Type
        s = (S.parameters[1], S.parameters[2])
        res = gaussian_dispatcher(img, 0.0, gaussian5)
        out_normed = Matrix{T}(undef, s)
        _clamp_convert!(res, out_normed, T, S)
        SImageND(out_normed, S)
    end
    ManualDispatcher((m1, m2, m3), :gaussian_image2D)
end

sobelx_image2D_factory = sobel_image2D_factory(_Xaxis, _sobel_dispatcher)
sobely_image2D_factory = sobel_image2D_factory(_Yaxis, _sobel_dispatcher)
sobelm_image2D_factory = sobel_image2D_factory(_Maxis, _sobel_dispatcher)


# Factory Methods
append_method!(bundle_image2D_filtering_factory, sobelx_image2D_factory, :sobelx_image2D)
append_method!(bundle_image2D_filtering_factory, sobely_image2D_factory, :sobely_image2D)
append_method!(bundle_image2D_filtering_factory, sobelm_image2D_factory, :sobelm_image2D)

append_method!(
    bundle_image2D_filtering_factory,
    gaussian_image2D_factory,
    :gaussian_image2D,
)

end

