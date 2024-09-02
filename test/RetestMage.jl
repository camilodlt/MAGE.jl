module MAGETests
using ReTest
using UTCGP
import UTCGP: _unique_names_in_bundle
import UTCGP: SImageND
import TestImages: testimage
import ImageSegmentation
using ImageCore
using ImageMorphology
using ImageFiltering
using Statistics
using ErrorTypes

# Programs
include("programs/test_build_program.jl")
include("programs/test_decode_program.jl")

# GA
include("fitters/test_ga.jl")

# Image

include("libraries/number/test_reduce_from_img.jl")
include("libraries/image2D/tests_image2D.jl")
include("libraries/image2D/test_morph_image2D.jl")
include("libraries/image2D/test_binarize_image2D.jl")
include("libraries/image2D/test_segmentation_image2D.jl")
include("libraries/image2D/test_arithmetic_image2D.jl")
include("libraries/image2D/test_barithmetic_image2D.jl")
include("libraries/image2D/test_transcendental_image2D.jl")
include("libraries/image2D/test_filtering_image2D.jl")
end
