
# # -*- coding: utf-8 -*-

""" REDUCE Functions : from Img of number to number

Pooling techniques to reduce an image to a single scalar. 

Exports :

- **bundle\\_number\\_reduceFromImg** :
    - `reduce_length`
    - `reduce_biggestAxis`
    - `reduce_smallerAxis`
    - `reduce_histMode`
    - `reduce_propWhite`
    - `reduce_propBlack`
    - `reduce_ncolors`
    - `reduce_mean`
    - `reduce_median`
    - `reduce_std`
    - `reduce_minimum`
    - `reduce_maximum`
"""
module number_reduceFromImg

using ..UTCGP: FunctionBundle, append_method!
using ..UTCGP: SImage2D, SImageND
using ImageCore: float64
using FixedPointNumbers: Normed
using StatsBase: countmap
using Statistics: mean, median, std

# ################### #
# IMG REDUCE          #
# ################### #

fallback(args...) = return 0.0

bundle_number_reduceFromImg = FunctionBundle(fallback)

# FUNCTIONS ---

## Reduce Length --- 

"""
    reduce_length(from::SImageND, args...)

Return the length of the img (how many pixels).
"""
function reduce_length(from::SImageND, args...)
    return length(from)
end

## Reduce Biggest Axis --- 

"""
    reduce_biggestAxis(from::SImageND, args...)

Return the size of the biggest axis/dim.
"""
function reduce_biggestAxis(from::SImageND, args...)
    return maximum(size(from))
end

## Reduce Smaller Axis --- 

"""
    reduce_smallerAxis(from::SImageND, args...)

Return the size of the smaller axis/dim.
"""
function reduce_smallerAxis(from::SImageND, args...)
    return minimum(size(from))
end

# Reduce HistMode --- 

"""
    reduce_histMode(from::SImageND, args...)

Returns the most common pixel value.
"""
function reduce_histMode(from::SImageND{S,T,D,C}, args...) where {S,T<:Normed,D,C}
    cm = countmap(from)
    highest_v = 0
    k_of_highest_v = 0
    for (k, v) in cm
        if v > highest_v
            highest_v = v
            k_of_highest_v = k
        end
    end
    return float64(k_of_highest_v) # fixed precision to float nb
end


# Reduce Prop White --- 

"""
    reduce_propWhite(from::SImageND, args...)

Returns the proportion of white pixels
"""
function reduce_propWhite(from::SImageND{S,T,D,C}, args...) where {S,T<:Normed,D,C}
    n_pixels = length(from)
    white_pixels = count(from .== 0.0)
    return white_pixels / n_pixels
end

# Reduce Prop Black --- 

"""
    reduce_propBlack(from::SImageND, args...)

Returns the proportion of black pixels
"""
function reduce_propBlack(from::SImageND{S,T,D,C}, args...) where {S,T<:Normed,D,C}
    n_pixels = length(from)
    black_pixels = count(from .== 1.0)
    return black_pixels / n_pixels
end

# Reduce N Colors --- 

"""
    reduce_nColors(from::SImageND, args...)

Returns the number of unique colors in the image.
"""
function reduce_nColors(from::SImageND{S,T,D,C}, args...) where {S,T<:Normed,D,C}
    return Float64(length(unique(from)))
end


# Reduce Mean --- 

"""
    reduce_mean(from::SImageND, args...)

Return the mean of the image
"""
function reduce_mean(from::SImageND{S,T,D,C}, args...) where {S,T<:Normed,D,C}
    return mean(float64.(from))
end

# Reduce Median --- 

"""
    reduce_median(from::SImageND, args...)

Return the median of the image
"""
function reduce_median(from::SImageND{S,T,D,C}, args...) where {S,T<:Normed,D,C}
    return median(float64.(from))
end

# Reduce std --- 
"""
    reduce_std(from::SImageND, args...)

Return the std of the image
"""
function reduce_std(from::SImageND{S,T,D,C}, args...) where {S,T<:Normed,D,C}
    return std(float64.(from))
end

# Reduce Max --- 
"""
    reduce_maximum(from::SImageND, args...)

Return the max of the image
"""
function reduce_maximum(from::SImageND{S,T,D,C}, args...) where {S,T<:Normed,D,C}
    return maximum(float64.(from))
end

# Reduce Min --- 
"""
    reduce_minmum(from::SImageND, args...)

Return the min of the image
"""
function reduce_minimum(from::SImageND{S,T,D,C}, args...) where {S,T<:Normed,D,C}
    return minimum(float64.(from))
end

# APPEND FUNCTIONS --- 
append_method!(bundle_number_reduceFromImg, reduce_length)
# append_method!(bundle_number_reduceFromImg, reduce_biggestAxis)
# append_method!(bundle_number_reduceFromImg, reduce_smallerAxis)
append_method!(bundle_number_reduceFromImg, reduce_histMode)
append_method!(bundle_number_reduceFromImg, reduce_propWhite)
append_method!(bundle_number_reduceFromImg, reduce_propBlack)
append_method!(bundle_number_reduceFromImg, reduce_nColors)
append_method!(bundle_number_reduceFromImg, reduce_mean)
append_method!(bundle_number_reduceFromImg, reduce_median)
append_method!(bundle_number_reduceFromImg, reduce_std)
append_method!(bundle_number_reduceFromImg, reduce_maximum)
append_method!(bundle_number_reduceFromImg, reduce_minimum)
end
