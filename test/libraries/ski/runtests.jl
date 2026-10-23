module SkiTests
# Standalone suite: julia --project=docs test/libraries/ski/runtests.jl
using Test, MAGE, Statistics, Random
const SK = MAGE.ski
mask(a) = SImageND(BinaryPixel.(Bool.(a)))
intensity(a) = SImageND(IntensityPixel{Float64}.(Float64.(a)))
include("test_ski.jl")
include("test_provenance.jl")
include("test_skimage.jl")

end # module SkiTests
