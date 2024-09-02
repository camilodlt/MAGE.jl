module MAGE_RADIOMICS

using PythonCall
using ThreadPools
using UTCGP: ManualDispatcher
using UTCGP
using UTCGP: FunctionBundle, append_method!
import UTCGP:
    CONSTRAINED,
    MIN_INT,
    MAX_INT,
    MIN_FLOAT,
    MAX_FLOAT,
    _positive_params,
    _ceil_positive_params
using ImageCore: N0f8, Normed, float64
using UTCGP:
    SizedImage, SImageND, _get_image_tuple_size, _get_image_type, _validate_factory_type
import MAGE_RADIOMICS_EXT

function __init__()
    @info "MAGE_RADIOMICS EXT in MAGE loaded"
end

fallback(args...) = return 0.0
bundle_image2D_radiomicsFOS_factory = FunctionBundle(fallback)

# function _FOS_EnergyFeatureValue_factory(i::Type{I}) where {I<:SizedImage}
# end
# function _FOS_TotalEnergyFeatureValue_factory(i::Type{I}) where {I<:SizedImage}
# end

# getEntropyFeatureValue
# getMinimumFeatureValue
# get10PercentileFeatureValue
# get90PercentileFeatureValue
# getMaximumFeatureValue
# getMeanFeatureValue
# getMedianFeatureValue

# getInterquartileRangeFeatureValue
# getRangeFeatureValue
# getMeanAbsoluteDeviationFeatureValue
# getRobustMeanAbsoluteDeviationFeatureValue
# getRootMeanSquaredFeatureValue
# getStandardDeviationFeatureValue
# getSkewnessFeatureValue
# getKurtosisFeatureValue
# getVarianceFeatureValue
# getUniformityFeatureValue

function UTCGP._FOS_MeanFeatureValue(i::Type{I}) where {I<:SizedImage}
    TT = Base.unwrap_unionall(I).parameters[2]
    _validate_factory_type(TT)

    m1 = @eval ((img::CONCT, mask::CONCT, args::Vararg{Any}) where {CONCT<:$I}) -> begin
        m = float64.(img.img)
        mask_bool = float64.(mask) .> 0.5
        mask_int = convert(Matrix{Int}, mask_bool)
        @show mask_bool
        @show mask_int
        @assert size(m) == size(mask)
        res = MAGE_RADIOMICS_EXT._wrap_getMeanFeatureValue(m, mask_int)
        return res
    end

    m2 = @eval ((img::CONCT, args::Vararg{Any}) where {CONCT<:$I}) -> begin
        m = float64.(img.img)
        mask = ones(Int, size(m))
        res = MAGE_RADIOMICS_EXT._wrap_getMeanFeatureValue(m, mask)
        return res
    end


    ManualDispatcher((m1, m2), :erosion_2D)
end

# export _FOS_MeanFeatureValue
end

"""
ENV["JULIA_PYTHONCALL_EXE"] = "/home/irit/miniconda3/envs/pyr/bin/python"
ENV["JULIA_CONDAPKG_BACKEND"] = "Null"
using Revise, UTCGP
img = ones(Float64, (3, 3))
s_img = SImageND(img)
d = UTCGP.MAGE_RADIOMICS._FOS_MeanFeatureValue(typeof(s_img))
d(s_img)
"""

