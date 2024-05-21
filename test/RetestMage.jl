module MAGETests
using ReTest
using UTCGP
import UTCGP: _unique_names_in_bundle
import UTCGP: SImageND
import TestImages: testimage
import ImageSegmentation
using ImageCore
using ImageMorphology
using Statistics
include("libraries/image2D/tests_image2D.jl")
include("libraries/image2D/test_morph_image2D.jl")
include("libraries/image2D/test_binarize_image2D.jl")
include("libraries/image2D/test_segmentation_image2D.jl")
include("libraries/image2D/test_arithmetic_image2D.jl")
end
