module SkiTests
# Standalone suite: julia --project=docs test/libraries/ski/runtests.jl
using Test, MAGE, Statistics, Random
const SK = MAGE.ski
mask(a) = SImageND(BinaryPixel.(Bool.(a)))
intensity(a) = SImageND(IntensityPixel{Float64}.(Float64.(a)))
include("test_ski.jl")
include("test_provenance.jl")
python_available = try
    @eval using PythonCall
    PythonCall.pyimport("skimage.measure")
    PythonCall.pyimport("numpy")
    true
catch err
    @info "Skipping skimage comparisons: Python/skimage is unavailable" exception = (err, catch_backtrace())
    false
end
if python_available
    include("test_skimage.jl")
end

end # module SkiTests
