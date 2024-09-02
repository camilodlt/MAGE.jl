# -*- coding: utf-8 -*-
""" Basic IMAGE 2D functions

Exports :

- **bundle\\image2D\\_basic** :
    - `identity_image2D`
    - `ones_2D`
    - `zeros_2D`

"""

# We use the Array View for images

module image2D_basic

using ImageCore: clamp01nan!, Normed, float64
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
    SizedImage, SImageND, _get_image_tuple_size, _get_image_type, _validate_factory_type
fallback(args...) = return nothing
bundle_image2D_basic = FunctionBundle(fallback)
bundle_image2D_basic_factory = FunctionBundle(fallback)

# using ExprTools
# function _change_type_in_expr!(expr::Expr, T::DataType, to_change::Symbol = :MAGE_TYPE)
#     for (i, arg) in enumerate(expr.args)
#         if arg == to_change
#             expr.args[i] = Symbol(T)
#         end
#         if arg isa Expr
#             _MAGE_CHANGE!(arg)
#         end
#     end
# end
# function _get_fn_name_in_expr(expr::Expr)::Symbol
#     s = splitdef(expr)
#     return s[:name]
# end

# macro specialize_(fn, T)
#     return quote
#         q = $fn
#         q = deepcopy(q) # The expr of the fn
#         _change_type_in_expr!(q, $T) # replaces MAGE_TYPE by T
#         fn_name = _get_fn_name_in_expr(q)
#         eval(q)
#     end
# end

# ################### #
# IDENTITY            #
# ################### #
"""
    identity_image2D(img::Array{T,2}, args...)::Array{T,2} where {T<:Number}

    Returns the identity of the img.
"""
function identity_image2D_factory(I::Type{<:SI}) where {SI<:SizedImage}
    return @eval function (img::$I, args::Vararg{Any})
        return identity(img)
    end
end

# ################### #
# ONES                #
# ################### #

"""
    ones_2D_factory(T::Type{<:Normed})
    
    
"""
function ones_2D_factory(i::Type{I}) where {I<:SizedImage}

    TT = Base.unwrap_unionall(I).parameters[2]
    _validate_factory_type(TT)

    """
        ones_(img::Array{T,2}, args...)::Array{T,2}

    Returns a matrix of ones in N0f8.
    """
    m1 = @eval ((img::CONCT, args::Vararg{Any}) where {CONCT<:$I}) -> begin
        T = _get_image_type(CONCT)
        # s = size(img)
        s = _get_image_tuple_size(CONCT)
        dim1::Int = s.parameters[1]
        dim2::Int = s.parameters[2]
        return SImageND(ones(T, dim1, dim2))
    end

    """
        ones_(k1::Int,k2, args...)::Array{UInt8,2}

    Returns a matrix of ones in N0f8 with size `(k,k)`.
    """
    # m2 = @eval (k1_n::Number, k2_n::Number, args::Vararg{Any}) -> begin
    #     k1 = round(Int, k1_n)
    #     k2 = round(Int, k2_n)
    #     k1, k2 = _positive_params(k1, k2)
    #     if CONSTRAINED[]
    #         k1, k2 = _ceil_positive_params(k1, k2)
    #     end
    #     return SImageND(ones($TT, k1, k2))
    # end

    """
        ones_(k::Integer, args...)::Array{N0f8,2}

    Returns a matrix of ones in N0f8 with size `(k,k)`.
    """
    # m3 = @eval (k::Int, args::Vararg{Any}) -> begin
    #     k, = _positive_params(k) # dim cannot be less than 1
    #     if CONSTRAINED[]
    #         k, = _ceil_positive_params(k)
    #     end
    #     return SImageND(ones($TT, k, k))
    # end
    return ManualDispatcher((m1,), :ones_2D)
end

# ################### #
# ZEROS               #
# ################### #

function zeros_2D_factory(i::Type{I}) where {I<:SizedImage}

    TT = Base.unwrap_unionall(I).parameters[2]
    _validate_factory_type(TT)

    """function (x,y)::T
        zeros_(img::Array{T,2}, args...)::Array{T,2} where {T<:Number}

    Returns a matrix of zeros in N0f8.
    """
    m1 = @eval ((img::CONCT, args::Vararg{Any}) where {CONCT<:$I}) -> begin
        T = _get_image_type(CONCT) # returns specific
        # s = size(img)
        s = _get_image_tuple_size(CONCT)
        dim1::Int = s.parameters[1]
        dim2::Int = s.parameters[2]
        return SImageND(zeros(T, dim1, dim2))
    end

    """
        zeros_(k1::Integer, k2::Integer, args...)::Array{N0f8,2}

    Returns a matrix of zeros in N0f8 with size `(k,k)`.
    """
    # m2 = @eval (k1_n::Number, k2_n::Number, args...) -> begin
    #     k1 = round(Int, k1_n)
    #     k2 = round(Int, k2_n)
    #     k1, k2, = _positive_params(k1, k2)
    #     if CONSTRAINED[]
    #         k1, k2, = _ceil_positive_params(k1, k2)
    #     end
    #     return SImageND(zeros($TT, k1, k2))
    # end

    """
        ones_(k::Integer, args...)::Array{UInt8,2}

    Returns a matrix of zeros in N0f8 with size `(k,k)`.
    """
    # m3 = @eval (k::Int, args...) -> begin
    #     k, = _positive_params(k)
    #     if CONSTRAINED[]
    #         k, = _ceil_positive_params(k)
    #     end
    #     return SImageND(zeros($TT, k, k))
    # end

    ManualDispatcher((m1,), :zeros_2D)
end

# ################### #
# INVERT #
# ################### #
"""
    experimental_image2D(img::Array{T,2}, args...)::Array{T,2} where {T<:Number}

"""
function experimental_invert_image2D_factory(i::Type{I}) where {I<:SizedImage}
    TT = Base.unwrap_unionall(I).parameters[2]
    _validate_factory_type(TT)
    return @eval function (img::CONCT, args::Vararg{Any}) where {CONCT<:$I}
        S = CONCT.parameters[1] # Tuple{X,Y}
        inv_ = abs.(1.0 .- float64.(img))
        return SImageND($TT.(inv_))
    end
end

# # Factory Methods
append_method!(bundle_image2D_basic_factory, identity_image2D_factory, :identity_image2D)
append_method!(bundle_image2D_basic_factory, ones_2D_factory, :ones_2D)
append_method!(bundle_image2D_basic_factory, zeros_2D_factory, :zeros_2D)
append_method!(
    bundle_image2D_basic_factory,
    experimental_invert_image2D_factory,
    :experimental_invert_2D,
)

# Default

Default = SImageND{<:Tuple,N0f8,2} # to the Any size
identity_image2D_def = identity_image2D_factory(Default)
ones_2D = ones_2D_factory(Default) # Dispatcher
zeros_2D = zeros_2D_factory(Default) # Dispatcher

append_method!(bundle_image2D_basic, identity_image2D_def, :identity_image2D)
append_method!(bundle_image2D_basic, ones_2D)
append_method!(bundle_image2D_basic, zeros_2D)
end
