""" Filtering functions

Exports :

- **bundle\\image2DIntensity\\_filtering** :
    - sobelx\\_image2D\\_factory
    - sobely\\_image2D\\_factory
    - sobelm\\_image2D\\_factory
    - ando3x\\_image2D\\_factory
    - ando3y\\_image2D\\_factory
    - ando3m\\_image2D\\_factory
    - ando4x\\_image2D\\_factory
    - ando4y\\_image2D\\_factory
    - ando4m\\_image2D\\_factory
    - ando5x\\_image2D\\_factory
    - ando5y\\_image2D\\_factory
    - ando5m\\_image2D\\_factory
    - bickleyx\\_image2D\\_factory
    - bickleyy\\_image2D\\_factory
    - bickleym\\_image2D\\_factory
    - prewittx\\_image2D\\_factory
    - prewitty\\_image2D\\_factory
    - prewittm\\_image2D\\_factory
    - scharrx\\_image2D\\_factory
    - scharry\\_image2D\\_factory
    - scharrm\\_image2D\\_factory
    - gaussian5\\_image2D\\_factory
    - gaussian9\\_image2D\\_factory
    - gaussian13\\_image2D\\_factory
    - gaussian17\\_image2D\\_factory
    - gaussian25\\_image2D\\_factory
    - laplacian3\\_image2D\\_factory
    - dog\\_image2D\\_factory
    - moffat5\\_image2D\\_factory
    - moffat13\\_image2D\\_factory
    - moffat25\\_image2D\\_factory
    - find_local_maxima\\_image2D\\_factory
    - find_local_minima\\_image2D\\_factory

- **bundle\\image2DBinary\\_filtering** :
    - sobelx\\_image2D\\_factory
    - sobely\\_image2D\\_factory
    - sobelm\\_image2D\\_factory
    - ando3x\\_image2D\\_factory
    - ando3y\\_image2D\\_factory
    - ando3m\\_image2D\\_factory
    - ando4x\\_image2D\\_factory
    - ando4y\\_image2D\\_factory
    - ando4m\\_image2D\\_factory
    - ando5x\\_image2D\\_factory
    - ando5y\\_image2D\\_factory
    - ando5m\\_image2D\\_factory
    - bickleyx\\_image2D\\_factory
    - bickleyy\\_image2D\\_factory
    - bickleym\\_image2D\\_factory
    - prewittx\\_image2D\\_factory
    - prewitty\\_image2D\\_factory
    - prewittm\\_image2D\\_factory
    - scharrx\\_image2D\\_factory
    - scharry\\_image2D\\_factory
    - scharrm\\_image2D\\_factory
    - gaussian5\\_image2D\\_factory
    - gaussian9\\_image2D\\_factory
    - gaussian13\\_image2D\\_factory
    - gaussian17\\_image2D\\_factory
    - gaussian25\\_image2D\\_factory
    - laplacian3\\_image2D\\_factory
    - dog\\_image2D\\_factory
    - moffat5\\_image2D\\_factory
    - moffat13\\_image2D\\_factory
    - moffat25\\_image2D\\_factory
    - find_local_maxima\\_image2D\\_factory
    - find_local_minima\\_image2D\\_factory
"""
module image2D_filtering

using LoopVectorization
using TimerOutputs
using ImageFiltering
using ..UTCGP: image2D_basic
using ..UTCGP: image2D_morph
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
using ImageCore: N0f8, Normed, clamp01nan!, clamp01nan, float64, Gray, FixedPoint
using ..UTCGP:
    SizedImage, SizedImage2D, SImageND, _get_image_tuple_size, _get_image_type, _validate_factory_type, _get_image_pixel_type,
    IntensityPixel, BinaryPixel, SegmentPixel

cast = image2D_morph.cast
fallback(args...) = return nothing

bundle_image2DIntensity_filtering_factory = FunctionBundle(fallback)
bundle_image2DBinary_filtering_factory = FunctionBundle(fallback)

# SEPARATE FILTERS THAT RETURN X and Y AND FILTERS THAT ONLY RET 1 K

### X AND Y FILTERS ###
const _ysobel, _xsobel = reflect.(Kernel.sobel())
const _yando3, _xando3 = reflect.(Kernel.ando3())
const _yando4, _xando4 = reflect.(Kernel.ando4())
const _yando5, _xando5 = reflect.(Kernel.ando5())
const _ybickley, _xbickley = reflect.(Kernel.bickley())
const _yprewitt, _xprewitt = reflect.(Kernel.prewitt())
const _yscharr, _xscharr = reflect.(Kernel.scharr())

### ONE FILTER ###
const gaussian5 = Kernel.gaussian(1)
const gaussian9 = Kernel.gaussian(2)
const gaussian13 = Kernel.gaussian(3)
const gaussian17 = Kernel.gaussian(4)
const gaussian25 = Kernel.gaussian(6)
diff_ = ImageFiltering.Kernel.Laplacian((true, true))
const laplacian3 = reflect(convert(AbstractArray, diff_))

### SPECIAL ###
kdog = ImageFiltering.Kernel.moffat(1.0, 0.1, 11) # 2 params # min 0 for both, max 100 for both
kmoffat = ImageFiltering.Kernel.moffat(1.0, 0.1, 11) # two params

# also findlocalmaxima
# also findlocalminima

# Convolution Border Decision ---
function _border_type(border_index::Real)
    how = "replicate" # if b  == 0 # abcdef | ffff (replicates last)
    if border_index < 0
        how = "circular" # abcdef | abcd (wraps around)
    elseif border_index > 0
        how = "reflect" # abcdef | fedc (mirrors edge)
    end
    return how
end

abstract type _GradientAxis end
struct _Xaxis <: _GradientAxis end
struct _Yaxis <: _GradientAxis end
struct _Maxis <: _GradientAxis end
string(::Type{_Xaxis}) = "x" # like SobelX
string(::Type{_Yaxis}) = "y" # like SobelY
string(::Type{_Maxis}) = "m" # like SobelMagnitude

abstract type KernelMethod end
# X and Y
struct _Sobel <: KernelMethod end
struct _Ando3 <: KernelMethod end
struct _Ando4 <: KernelMethod end
struct _Ando5 <: KernelMethod end
struct _Bickley <: KernelMethod end
struct _Prewitt <: KernelMethod end
struct _Scharr <: KernelMethod end

# One kernel#
struct _Gaussian5 <: KernelMethod end
struct _Gaussian9 <: KernelMethod end
struct _Gaussian13 <: KernelMethod end
struct _Gaussian17 <: KernelMethod end
struct _Gaussian25 <: KernelMethod end
struct _Laplacian3 <: KernelMethod end

# Special
struct _DoG <: KernelMethod end
struct _Moffat <: KernelMethod end

# ################### #
# CONV X,Y,M kernels  #
# ################### #

for (KTYPE, XK, YK) in zip(
        [_Sobel, _Ando3, _Ando4, _Ando5, _Bickley, _Prewitt, _Scharr],
        [_xsobel, _xando3, _xando4, _xando5, _xbickley, _xprewitt, _xscharr],
        [_ysobel, _yando3, _yando4, _yando5, _ybickley, _yprewitt, _yscharr]
    )
    @eval @inline function _conv_dispatcher!(
            img::Matrix{Float64},
            out::Matrix{Float64},
            b::Real,
            which::Type{_Xaxis},
            which_k::Type{$KTYPE}
        )
        return conv!(img, out, b, $XK)
    end

    @eval @inline function _conv_dispatcher!(
            img::Matrix{Float64},
            out::Matrix{Float64},
            b::Real,
            which::Type{_Yaxis},
            which_k::Type{$KTYPE}
        )
        return conv!(img, out, b, $YK)
    end

    @eval function _conv_dispatcher!(
            img::Matrix{Float64},
            out::Matrix{Float64},
            b::Real,
            ::Type{_Maxis},
            which_k::Type{$KTYPE}
        )
        out_x = similar(img)
        out_y = similar(img)
        _conv_dispatcher!(img, out_x, b, _Xaxis, which_k)
        _conv_dispatcher!(img, out_y, b, _Yaxis, which_k)
        return @timeit_debug to "turbo with x" @inbounds @turbo for i in eachindex(out)
            x = out_x[i]^2
            x += out_y[i]^2
            out[i] = sqrt(x)
        end
    end
end

# ################### #
# CONV                #
# ################### #

function conv!(
        img::Matrix{Float64},
        out::Matrix{Float64},
        b::Real,
        K::AbstractArray,
    )::Matrix{Float64}
    border = _border_type(b)
    return imfilter!(out, img, K, border)
end

### Factory of factories for kernels with X,Y and M 🏭 ###
"""

The first factory dispatches on Axis type and the second on Image Type
https://juliaimages.org/ImageFiltering.jl/v0.7/function_reference/#ImageFiltering.Kernel.sobel

First function accepts an image and a boder type. 

Second function accepts an image but defaults to `replicate` border type.
"""
function XYM_filter_image2D_factory(axis::Type{<:_GradientAxis}, which_kernel::Type{<:KernelMethod}, name::String)
    fn_name = Symbol(name * string(axis) * "_image2D")

    # The factory below creates specialized versions based on a specific image type
    factory = ((i::Type{I}) where {I <: SizedImage{SIZE, <:Union{BinaryPixel{T1}, IntensityPixel{T2}}}} where {SIZE, T1, T2}) -> begin
        IT, PT, S = _get_image_type(I), _get_image_pixel_type(I), _get_image_tuple_size(I)
        S1, S2 = S.parameters[1], S.parameters[2]
        _validate_factory_type(IT)
        FUNCTION_NAME = fn_name

        # COMMENT: Possible improvement
        # if is Binary
        # accepts BinaryPixel => Always will be Bool
        # accepts any intensity pixel
        # if is Intensity
        # accepts BinaryPixel => Always will be Bool
        # accepts IntensityPixel of the orig type
        m1 = @eval ((img::CONCT, b::Real, args::Vararg{Any}) where {CONCT <: SizedImage{$(SIZE), <:Union{BinaryPixel{Bool}, IntensityPixel}}}) -> begin
            # global to
            ax, km = $axis, $which_kernel
            s = ($S1, $S2)
            img_as_float = Matrix{Float64}(undef, s)
            img_as_float .= float64.(img)
            out_float = Matrix{Float64}(undef, s)
            _conv_dispatcher!(
                img_as_float,
                out_float,
                b,
                ax,
                km
            )
            out_float = image2D_basic._normalize_img(out_float)
            clamp01nan!(out_float)
            return SImageND($PT.(cast($IT, out_float)), $S)
        end

        m2 = @eval ((img::CONCT, args::Vararg{Any}) where {CONCT <: SizedImage{$(SIZE), <:Union{BinaryPixel, IntensityPixel}}}) -> begin
            $m1(img, 0.0, args)
        end

        ManualDispatcher((m1, m2), fn_name)
    end
    return factory
end

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~#
# ################# ONE KERNEL ############### #
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~#

for (KTYPE, K) in zip(
        [_Gaussian5, _Gaussian9, _Gaussian13, _Gaussian17, _Gaussian25, _Laplacian3],
        [gaussian5, gaussian9, gaussian13, gaussian17, gaussian25, laplacian3]
    )
    @eval @inline function _conv_dispatcher!(
            img::Matrix{Float64},
            out::Matrix{Float64},
            b::Real,
            which_k::Type{$KTYPE}
        )
        return conv!(img, out, b, $K)
    end
end

function one_filter_image2D_factory(which_kernel::Type{<:KernelMethod}, name::String)
    fn_name = Symbol(name * "_image2D")

    # The factory below creates specialized versions based on a specific image type
    factory = ((i::Type{I}) where {I <: SizedImage{SIZE, <:Union{BinaryPixel{T}, IntensityPixel{T}}}} where {SIZE, T}) -> begin
        IT, PT, S = _get_image_type(I), _get_image_pixel_type(I), _get_image_tuple_size(I)
        S1, S2 = S.parameters[1], S.parameters[2]
        _validate_factory_type(IT)
        FUNCTION_NAME = fn_name
        m1 = @eval ((img::CONCT, b::Real, args::Vararg{Any}) where {CONCT <: SizedImage{$(SIZE), <:Union{BinaryPixel, IntensityPixel}}}) -> begin
            # global to
            km = $which_kernel
            s = ($S1, $S2)
            img_as_float = Matrix{Float64}(undef, s)
            img_as_float .= float64.(img)
            out_float = Matrix{Float64}(undef, s)
            _conv_dispatcher!(
                img_as_float,
                out_float,
                b,
                km
            )
            out_float = image2D_basic._normalize_img(out_float)
            clamp01nan!(out_float)
            return SImageND($PT.(cast($IT, out_float)), $S)
        end

        m2 = @eval ((img::CONCT, args::Vararg{Any}) where {CONCT <: SizedImage{$(SIZE), <:Union{BinaryPixel, IntensityPixel}}}) -> begin
            $m1(img, 0.0, args)
        end

        ManualDispatcher((m1, m2), fn_name)
    end
    return factory
end

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~#
# ############### SPECIAL KERNEL ########### #
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~#
#

function dog_factory(i::Type{I}) where {I <: SizedImage{SIZE, <:Union{BinaryPixel{T}, IntensityPixel{T}}}} where {SIZE, T}
    IT, PT, S = _get_image_type(I), _get_image_pixel_type(I), _get_image_tuple_size(I)
    S1, S2 = S.parameters[1], S.parameters[2]
    _validate_factory_type(IT)
    m1 = @eval ((img::CONCT, p1_::Real, p2_::Real, args::Vararg{Any}) where {CONCT <: SizedImage{$(SIZE), <:Union{BinaryPixel, IntensityPixel}}}) -> begin
        s = ($S1, $S2)
        p1, p2 = convert(Float64, clamp(p1_, 0.1, 100)), convert(Float64, clamp(p1_, 0.1, 100))
        img_as_float = Matrix{Float64}(undef, s)
        img_as_float .= float64.(img)
        out_float = Matrix{Float64}(undef, s)
        kernel = ImageFiltering.Kernel.DoG((p1, p2))
        conv!(
            img_as_float,
            out_float,
            0.0,
            reflect(kernel)
        )
        out_float = image2D_basic._normalize_img(out_float)
        clamp01nan!(out_float)
        return SImageND($PT.(cast($IT, out_float)), $S)
    end

    m2 = @eval ((img::CONCT, p1_::Real, args::Vararg{Any}) where {CONCT <: SizedImage{$(SIZE), <:Union{BinaryPixel, IntensityPixel}}}) -> begin
        $m1(img, p1_, p1_, args)
    end

    return ManualDispatcher((m1, m2), :dog_image2D)
end

function moffat_factories(ksize::Int)
    factory = ((i::Type{I}) where {I <: SizedImage{SIZE, <:Union{BinaryPixel{T}, IntensityPixel{T}}}} where {SIZE, T}) -> begin
        IT, PT, S = _get_image_type(I), _get_image_pixel_type(I), _get_image_tuple_size(I)
        S1, S2 = S.parameters[1], S.parameters[2]
        _validate_factory_type(IT)
        m1 = @eval ((img::CONCT, p1_::Real, p2_::Real, args::Vararg{Any}) where {CONCT <: SizedImage{$(SIZE), <:Union{BinaryPixel, IntensityPixel}}}) -> begin
            s = ($S1, $S2)
            p1, p2 = convert(Float64, clamp(p1_, 0.1, 100)), convert(Float64, clamp(p1_, 0.1, 100))
            img_as_float = Matrix{Float64}(undef, s)
            img_as_float .= float64.(img)
            out_float = Matrix{Float64}(undef, s)
            kernel = ImageFiltering.Kernel.moffat(p1, p2, $ksize)
            conv!(
                img_as_float,
                out_float,
                0.0,
                reflect(kernel)
            )
            out_float = image2D_basic._normalize_img(out_float)
            clamp01nan!(out_float)
            return SImageND($PT.(cast($IT, out_float)), $S)
        end

        return m1
    end
    return factory
end


## ## ONLY ON BINARY BUNDLE

function findlocalminima_factory(i::Type{I}) where {I <: SizedImage{SIZE, BinaryPixel{T}}} where {SIZE, T}
    IT, PT, S = _get_image_type(I), _get_image_pixel_type(I), _get_image_tuple_size(I)
    S1, S2 = S.parameters[1], S.parameters[2]
    _validate_factory_type(IT)
    m1 = @eval ((img::CONCT, w1_::Real, w2_::Real, args::Vararg{Any}) where {CONCT <: SizedImage{$(SIZE), <:Union{BinaryPixel, IntensityPixel}}}) -> begin
        s = ($S1, $S2)
        w1, w2 = round(Int, clamp(w1_, 2, 25)), round(Int, clamp(w1_, 2, 25))
        minimums = findlocalminima(reinterpret(img.img); window = (w1, w2))
        canvas = zeros($IT, s)
        canvas[minimums] .= 1.0
        return SImageND($PT.(cast($IT, canvas)), $S)
    end

    m2 = @eval ((img::CONCT, w1_::Real, args::Vararg{Any}) where {CONCT <: SizedImage{$(SIZE), <:Union{BinaryPixel, IntensityPixel}}}) -> begin
        $m1(img, w1_, w1_, args)
    end

    m3 = @eval ((img::CONCT, args::Vararg{Any}) where {CONCT <: SizedImage{$(SIZE), <:Union{BinaryPixel, IntensityPixel}}}) -> begin
        $m1(img, 3, 3, args)
    end

    return ManualDispatcher((m1, m2, m3), :findlocalminima_image2D)
end

function findlocalmaxima_factory(i::Type{I}) where {I <: SizedImage{SIZE, BinaryPixel{T}}} where {SIZE, T}
    IT, PT, S = _get_image_type(I), _get_image_pixel_type(I), _get_image_tuple_size(I)
    S1, S2 = S.parameters[1], S.parameters[2]
    _validate_factory_type(IT)
    m1 = @eval ((img::CONCT, w1_::Real, w2_::Real, args::Vararg{Any}) where {CONCT <: SizedImage{$(SIZE), <:Union{BinaryPixel, IntensityPixel}}}) -> begin
        s = ($S1, $S2)
        w1, w2 = round(Int, clamp(w1_, 2, 25)), round(Int, clamp(w1_, 2, 25))
        maximums = findlocalmaxima(reinterpret(img.img); window = (w1, w2))
        canvas = zeros($IT, s)
        canvas[maximums] .= 1.0
        return SImageND($PT.(cast($IT, canvas)), $S)
    end

    m2 = @eval ((img::CONCT, w1_::Real, args::Vararg{Any}) where {CONCT <: SizedImage{$(SIZE), <:Union{BinaryPixel, IntensityPixel}}}) -> begin
        $m1(img, w1_, w1_, args)
    end

    m3 = @eval ((img::CONCT, args::Vararg{Any}) where {CONCT <: SizedImage{$(SIZE), <:Union{BinaryPixel, IntensityPixel}}}) -> begin
        $m1(img, 3, 3, args)
    end

    return ManualDispatcher((m1, m2, m3), :findlocalmaxima_image2D)
end

### BUNDLES ###

# X,Y,M kernels ---
sobelx_image2D_factory = XYM_filter_image2D_factory(_Xaxis, _Sobel, "sobel")
sobely_image2D_factory = XYM_filter_image2D_factory(_Yaxis, _Sobel, "sobel")
sobelm_image2D_factory = XYM_filter_image2D_factory(_Maxis, _Sobel, "sobel")

ando3x_image2D_factory = XYM_filter_image2D_factory(_Xaxis, _Ando3, "ando3")
ando3y_image2D_factory = XYM_filter_image2D_factory(_Yaxis, _Ando3, "ando3")
ando3m_image2D_factory = XYM_filter_image2D_factory(_Maxis, _Ando3, "ando3")
ando4x_image2D_factory = XYM_filter_image2D_factory(_Xaxis, _Ando4, "ando4")
ando4y_image2D_factory = XYM_filter_image2D_factory(_Yaxis, _Ando4, "ando4")
ando4m_image2D_factory = XYM_filter_image2D_factory(_Maxis, _Ando4, "ando4")
ando5x_image2D_factory = XYM_filter_image2D_factory(_Xaxis, _Ando5, "ando5")
ando5y_image2D_factory = XYM_filter_image2D_factory(_Yaxis, _Ando5, "ando5")
ando5m_image2D_factory = XYM_filter_image2D_factory(_Maxis, _Ando5, "ando5")

bickleyx_image2D_factory = XYM_filter_image2D_factory(_Xaxis, _Bickley, "bickley")
bickleyy_image2D_factory = XYM_filter_image2D_factory(_Yaxis, _Bickley, "bickley")
bickleym_image2D_factory = XYM_filter_image2D_factory(_Maxis, _Bickley, "bickley")

prewittx_image2D_factory = XYM_filter_image2D_factory(_Xaxis, _Prewitt, "prewitt")
prewitty_image2D_factory = XYM_filter_image2D_factory(_Yaxis, _Prewitt, "prewitt")
prewittm_image2D_factory = XYM_filter_image2D_factory(_Maxis, _Prewitt, "prewitt")

scharrx_image2D_factory = XYM_filter_image2D_factory(_Xaxis, _Scharr, "scharr")
scharry_image2D_factory = XYM_filter_image2D_factory(_Yaxis, _Scharr, "scharr")
scharrm_image2D_factory = XYM_filter_image2D_factory(_Maxis, _Scharr, "scharr")

# One kernel ---
gaussian5_image2D_factory = one_filter_image2D_factory(_Gaussian5, "gaussian5")
gaussian9_image2D_factory = one_filter_image2D_factory(_Gaussian9, "gaussian9")
gaussian13_image2D_factory = one_filter_image2D_factory(_Gaussian13, "gaussian13")
gaussian17_image2D_factory = one_filter_image2D_factory(_Gaussian17, "gaussian17")
gaussian25_image2D_factory = one_filter_image2D_factory(_Gaussian25, "gaussian25")
laplacian3_image2D_factory = one_filter_image2D_factory(_Laplacian3, "laplacian3")

# Special
moffat5_image2D_factory = moffat_factories(5)
moffat13_image2D_factory = moffat_factories(13)
moffat25_image2D_factory = moffat_factories(25)

# BUNDLE INTENSITY ---
# X,Y,M kernels
append_method!(bundle_image2DIntensity_filtering_factory, sobelx_image2D_factory, :sobelx_image2D)
append_method!(bundle_image2DIntensity_filtering_factory, sobely_image2D_factory, :sobely_image2D)
append_method!(bundle_image2DIntensity_filtering_factory, sobelm_image2D_factory, :sobelm_image2D)

append_method!(bundle_image2DIntensity_filtering_factory, ando3x_image2D_factory, :ando3x_image2D)
append_method!(bundle_image2DIntensity_filtering_factory, ando3y_image2D_factory, :ando3y_image2D)
append_method!(bundle_image2DIntensity_filtering_factory, ando3m_image2D_factory, :ando3m_image2D)
append_method!(bundle_image2DIntensity_filtering_factory, ando4x_image2D_factory, :ando4x_image2D)
append_method!(bundle_image2DIntensity_filtering_factory, ando4y_image2D_factory, :ando4y_image2D)
append_method!(bundle_image2DIntensity_filtering_factory, ando4m_image2D_factory, :ando4m_image2D)
append_method!(bundle_image2DIntensity_filtering_factory, ando5x_image2D_factory, :ando5x_image2D)
append_method!(bundle_image2DIntensity_filtering_factory, ando5y_image2D_factory, :ando5y_image2D)
append_method!(bundle_image2DIntensity_filtering_factory, ando5m_image2D_factory, :ando5m_image2D)

append_method!(bundle_image2DIntensity_filtering_factory, bickleyx_image2D_factory, :bickleyx_image2D)
append_method!(bundle_image2DIntensity_filtering_factory, bickleyy_image2D_factory, :bickleyy_image2D)
append_method!(bundle_image2DIntensity_filtering_factory, bickleym_image2D_factory, :bickleym_image2D)

append_method!(bundle_image2DIntensity_filtering_factory, prewittx_image2D_factory, :prewittx_image2D)
append_method!(bundle_image2DIntensity_filtering_factory, prewitty_image2D_factory, :prewitty_image2D)
append_method!(bundle_image2DIntensity_filtering_factory, prewittm_image2D_factory, :prewittm_image2D)

append_method!(bundle_image2DIntensity_filtering_factory, scharrx_image2D_factory, :scharrx_image2D)
append_method!(bundle_image2DIntensity_filtering_factory, scharry_image2D_factory, :scharry_image2D)
append_method!(bundle_image2DIntensity_filtering_factory, scharrm_image2D_factory, :scharrm_image2D)
# ONE KERNEL
append_method!(bundle_image2DIntensity_filtering_factory, gaussian5_image2D_factory, :gaussian5_image2D)
append_method!(bundle_image2DIntensity_filtering_factory, gaussian9_image2D_factory, :gaussian9_image2D)
append_method!(bundle_image2DIntensity_filtering_factory, gaussian13_image2D_factory, :gaussian13_image2D)
append_method!(bundle_image2DIntensity_filtering_factory, gaussian17_image2D_factory, :gaussian17_image2D)
append_method!(bundle_image2DIntensity_filtering_factory, gaussian25_image2D_factory, :gaussian25_image2D)
append_method!(bundle_image2DIntensity_filtering_factory, laplacian3_image2D_factory, :laplacian3_image2D)
# SPECIAL
append_method!(bundle_image2DIntensity_filtering_factory, dog_factory, :dog_image2D)
append_method!(bundle_image2DIntensity_filtering_factory, moffat5_image2D_factory, :moffat5_image2D)
append_method!(bundle_image2DIntensity_filtering_factory, moffat13_image2D_factory, :moffat13_image2D)
append_method!(bundle_image2DIntensity_filtering_factory, moffat25_image2D_factory, :moffat25_image2D)


# BUNDLE BINARY ---
append_method!(bundle_image2DBinary_filtering_factory, sobelx_image2D_factory, :sobelx_image2D)
append_method!(bundle_image2DBinary_filtering_factory, sobely_image2D_factory, :sobely_image2D)
append_method!(bundle_image2DBinary_filtering_factory, sobelm_image2D_factory, :sobelm_image2D)

append_method!(bundle_image2DBinary_filtering_factory, ando3x_image2D_factory, :ando3x_image2D)
append_method!(bundle_image2DBinary_filtering_factory, ando3y_image2D_factory, :ando3y_image2D)
append_method!(bundle_image2DBinary_filtering_factory, ando3m_image2D_factory, :ando3m_image2D)
append_method!(bundle_image2DBinary_filtering_factory, ando4x_image2D_factory, :ando4x_image2D)
append_method!(bundle_image2DBinary_filtering_factory, ando4y_image2D_factory, :ando4y_image2D)
append_method!(bundle_image2DBinary_filtering_factory, ando4m_image2D_factory, :ando4m_image2D)
append_method!(bundle_image2DBinary_filtering_factory, ando5x_image2D_factory, :ando5x_image2D)
append_method!(bundle_image2DBinary_filtering_factory, ando5y_image2D_factory, :ando5y_image2D)
append_method!(bundle_image2DBinary_filtering_factory, ando5m_image2D_factory, :ando5m_image2D)

append_method!(bundle_image2DBinary_filtering_factory, bickleyx_image2D_factory, :bickleyx_image2D)
append_method!(bundle_image2DBinary_filtering_factory, bickleyy_image2D_factory, :bickleyy_image2D)
append_method!(bundle_image2DBinary_filtering_factory, bickleym_image2D_factory, :bickleym_image2D)

append_method!(bundle_image2DBinary_filtering_factory, prewittx_image2D_factory, :prewittx_image2D)
append_method!(bundle_image2DBinary_filtering_factory, prewitty_image2D_factory, :prewitty_image2D)
append_method!(bundle_image2DBinary_filtering_factory, prewittm_image2D_factory, :prewittm_image2D)

append_method!(bundle_image2DBinary_filtering_factory, scharrx_image2D_factory, :scharrx_image2D)
append_method!(bundle_image2DBinary_filtering_factory, scharry_image2D_factory, :scharry_image2D)
append_method!(bundle_image2DBinary_filtering_factory, scharrm_image2D_factory, :scharrm_image2D)
# ONE KERNEL
append_method!(bundle_image2DBinary_filtering_factory, gaussian5_image2D_factory, :gaussian5_image2D)
append_method!(bundle_image2DBinary_filtering_factory, gaussian9_image2D_factory, :gaussian9_image2D)
append_method!(bundle_image2DBinary_filtering_factory, gaussian13_image2D_factory, :gaussian13_image2D)
append_method!(bundle_image2DBinary_filtering_factory, gaussian17_image2D_factory, :gaussian17_image2D)
append_method!(bundle_image2DBinary_filtering_factory, gaussian25_image2D_factory, :gaussian25_image2D)
append_method!(bundle_image2DBinary_filtering_factory, laplacian3_image2D_factory, :laplacian3_image2D)
# SPECIAL
append_method!(bundle_image2DBinary_filtering_factory, dog_factory, :dog_image2D)
append_method!(bundle_image2DBinary_filtering_factory, moffat5_image2D_factory, :moffat5_image2D)
append_method!(bundle_image2DBinary_filtering_factory, moffat13_image2D_factory, :moffat13_image2D)
append_method!(bundle_image2DBinary_filtering_factory, moffat25_image2D_factory, :moffat25_image2D)

# EXTRAS
append_method!(bundle_image2DBinary_filtering_factory, findlocalminima_factory, :findlocalminima_image2D)
append_method!(bundle_image2DBinary_filtering_factory, findlocalmaxima_factory, :findlocalmaxima_image2D)

end
