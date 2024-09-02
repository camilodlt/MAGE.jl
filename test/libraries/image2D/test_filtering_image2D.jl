######################
# SOBEL X FILTERING  #
######################

# API
@testset "Image2D filtering: sobelx_image2D(T)" begin
    img = load_test_image()
    fac = UTCGP.bundle_image2D_filtering_factory[:sobelx_image2D].fn
    dp = fac(typeof(img))
    # sobelx(img)
    @test begin
        res = dp(img)
        typeof(res) <: SImageND && size(res) == size(img) && res != img
    end
    @test_throws MethodError begin # bad type according to specialized image
        new_img = SImageND(convert.(N0f16, img))
        res = dp(new_img, 5)
    end
    # sobelx(img,b)
    @test begin
        res = dp(img, 5)
        size(res) == size(img) && res != img
    end
end

# sobelx(img) && sobelx(img, b) Innerworkings --- 
@testset "Image2D filtering: sobelx_image2D(img,b)" begin
    img = load_test_image()
    fac = UTCGP.bundle_image2D_filtering_factory[:sobelx_image2D].fn
    fn = fac(typeof(img))
    ysobel, xsobel = Kernel.sobel()
    @testset "Image2D filtering: sobelx_image2D(img)" begin
        # sobelx(img) using replicate by default
        @test begin
            res = fn(img)
            expected =
                convert.(N0f8, clamp01nan.(imfilter(img, reflect(xsobel), "replicate")))
            size(res) == size(img) && res == expected
        end

        # sobelx(img) using replicate by default. Xsobel so diff than ysobel
        @test begin
            res = fn(img)
            expected =
                convert.(N0f8, clamp01nan.(imfilter(img, reflect(ysobel), "replicate")))
            size(res) == size(img) && res != expected
        end
    end

    @testset "Image2D filtering: sobelx_image2D(img,b)" begin
        # sobelx(img,b) using circular by default
        @test begin
            res = fn(img, -1)
            expected =
                convert.(N0f8, clamp01nan.(imfilter(img, reflect(xsobel), "circular")))
            size(res) == size(img) && res == expected
        end
        # sobelx(img,b) using replicate by default
        @test begin
            res = fn(img, 0.0)
            expected =
                convert.(N0f8, clamp01nan.(imfilter(img, reflect(xsobel), "replicate")))
            size(res) == size(img) && res == expected
        end
        # sobelx(img,b) using reflect by default
        @test begin
            res = fn(img, 1)
            expected =
                convert.(N0f8, clamp01nan.(imfilter(img, reflect(xsobel), "reflect")))
            size(res) == size(img) && res == expected
        end
        # sobelx(img,b) diff than ysobel with the same reflect
        @test begin
            res = fn(img, 1)
            expected =
                convert.(N0f8, clamp01nan.(imfilter(img, reflect(ysobel), "reflect")))
            size(res) == size(img) && res != expected
        end
    end
end

######################
# SOBEL Y FILTERING  #
######################

# API (Same as Xsobel) 
@testset "Image2D filtering: sobely_image2D(T)" begin
    img = load_test_image()
    fac = UTCGP.bundle_image2D_filtering_factory[:sobely_image2D].fn
    dp = fac(typeof(img))

    # sobely(img)
    @test begin
        res = dp(img)
        typeof(res) <: SImageND && size(res) == size(img) && res != img
    end
    @test_throws MethodError begin # bad type according to specialized image
        new_img = SImageND(convert.(N0f16, img))
        res = dp(new_img, 5)
    end
    # sobely(img,b)
    @test begin
        res = dp(img, 5)
        size(res) == size(img) && res != img
    end
end

# sobely(img) && sobely(img, b) Innerworkings --- 
@testset "Image2D filtering: sobely_image2D(img,b)" begin
    img = load_test_image()
    fac = UTCGP.bundle_image2D_filtering_factory[:sobely_image2D].fn
    fn = fac(typeof(img))
    ysobel, xsobel = Kernel.sobel()

    @testset "Image2D filtering: sobely_image2D(img)" begin
        # sobely(img) using replicate by default
        @test begin
            res = fn(img)
            expected =
                convert.(N0f8, clamp01nan.(imfilter(img, reflect(ysobel), "replicate")))
            size(res) == size(img) && res == expected
        end

        # sobely(img) using replicate by default. Ysobel so diff than xsobel
        @test begin
            res = fn(img)
            expected =
                convert.(N0f8, clamp01nan.(imfilter(img, reflect(xsobel), "replicate")))
            size(res) == size(img) && res != expected
        end
    end

    @testset "Image2D filtering: sobely_image2D(img,b)" begin
        # sobely(img,b) using circular by default
        @test begin
            res = fn(img, -1)
            expected =
                convert.(N0f8, clamp01nan.(imfilter(img, reflect(ysobel), "circular")))
            size(res) == size(img) && res == expected
        end
        # sobely(img,b) using replicate by default
        @test begin
            res = fn(img, 0.0)
            expected =
                convert.(N0f8, clamp01nan.(imfilter(img, reflect(ysobel), "replicate")))
            size(res) == size(img) && res == expected
        end
        # sobely(img,b) using reflect by default
        @test begin
            res = fn(img, 1)
            expected =
                convert.(N0f8, clamp01nan.(imfilter(img, reflect(ysobel), "reflect")))
            size(res) == size(img) && res == expected
        end
        # sobely(img,b) diff than xsobel with the same reflect
        @test begin
            res = fn(img, 1)
            expected =
                convert.(N0f8, clamp01nan.(imfilter(img, reflect(xsobel), "reflect")))
            size(res) == size(img) && res != expected
        end
    end
end

######################
# SOBEL M FILTERING  #
######################

# API (Same as Xsobel) 
@testset "Image2D filtering: sobelm_image2D(T)" begin
    img = load_test_image()
    fac = UTCGP.bundle_image2D_filtering_factory[:sobelm_image2D].fn
    dp = fac(typeof(img))

    # sobelm(img)
    @test begin
        res = dp(img)
        typeof(res) <: SImageND && size(res) == size(img) && res != img
    end
    @test_throws MethodError begin # bad type according to specialized image
        new_img = SImageND(convert.(N0f16, img))
        res = dp(new_img, 5)
    end
    # sobelm(img,b)
    @test begin
        res = dp(img, 5)
        size(res) == size(img) && res != img
    end
end
@testset "Image2D filtering: sobelm_image2D(img,b)" begin
    img = load_test_image()
    fac = UTCGP.bundle_image2D_filtering_factory[:sobelm_image2D].fn
    fn = fac(typeof(img))
    ysobel, xsobel = Kernel.sobel()
    function _helper_sobel(img, k1, k2, b)
        x1 = imfilter(img, reflect(k1), b)
        x2 = imfilter(img, reflect(k2), b)
        y = sqrt.(x1 .^ 2 .+ x2 .^ 2)
        convert.(N0f8, clamp01nan.(y))
    end
    @testset "Image2D filtering: sobelm_image2D(img)" begin
        # sobelm(img) using replicate by default
        @test begin
            res = fn(img)
            expected = _helper_sobel(img, xsobel, ysobel, "replicate")
            size(res) == size(img) && res == expected
        end

        # sobelm(img) using replicate by default. msobel so diff than using xsobel 2 times
        @test begin
            res = fn(img)
            expected = _helper_sobel(img, ysobel, ysobel, "replicate")
            size(res) == size(img) && res != expected
        end
    end

    @testset "Image2D filtering: sobelm_image2D(img,b)" begin
        # sobelm(img,b) using circular by default
        @test begin
            res = fn(img, -1)
            expected = _helper_sobel(img, xsobel, ysobel, "circular")
            size(res) == size(img) && res == expected
        end
        # sobelm(img,b) using replicate by default
        @test begin
            res = fn(img, 0.0)
            expected = _helper_sobel(img, xsobel, ysobel, "replicate")
            size(res) == size(img) && res == expected
        end
        # sobelm(img,b) using reflect by default
        @test begin
            res = fn(img, 1)
            expected = _helper_sobel(img, xsobel, ysobel, "reflect")
            size(res) == size(img) && res == expected
        end
        # sobelm(img,b) diff than xsobel 2 times with the same reflect
        @test begin
            res = fn(img, 1)
            expected = _helper_sobel(img, xsobel, xsobel, "reflect")
            size(res) == size(img) && res != expected
        end
    end
end

#######################
# GAUSSIAN FILTERING  #
#######################

# API
@testset "Image2D filtering: gaussian_image2D(T)" begin
    img = load_test_image()
    fac = UTCGP.bundle_image2D_filtering_factory[:gaussian_image2D].fn
    dp = fac(typeof(img))

    # gaussian(img) # returns the same type and size
    @test begin
        res = dp(img)
        typeof(res) == typeof(img) && size(res) == size(img) && res != img
    end
    @test begin
        res = dp(img, 1)
        typeof(res) == typeof(img) && size(res) == size(img) && res != img
    end
    @test begin
        res = dp(img, 1, 2)
        typeof(res) == typeof(img) && size(res) == size(img) && res != img
    end

    # Strong typing
    @test_throws MethodError begin # bad type according to specialized image
        new_img = SImageND(convert.(N0f16, img))
        res = dp(new_img)
    end
end

# Blur img with defaults
@testset "Image2D filtering: gaussian_image2D(img)" begin
    img = load_test_image()
    fac = UTCGP.bundle_image2D_filtering_factory[:gaussian_image2D].fn
    dp = fac(typeof(img))

    # blur img with default kernel and default padding
    @test begin
        res = dp(img)
        expected = SImageND(
            convert.(
                N0f8,
                clamp01nan.(
                    imfilter(img, reflect(ImageFiltering.Kernel.gaussian(1)), "replicate")
                ),
            ),
        )
        typeof(expected) == typeof(res) && res == expected
    end
end

# Blur img and choose padding
@testset "Image2D filtering: gaussian_image2D(img, pad)" begin
    img = load_test_image()
    fac = UTCGP.bundle_image2D_filtering_factory[:gaussian_image2D].fn
    dp = fac(typeof(img))

    # blur img "Replicate"
    @test begin
        res = dp(img, 0)
        expected = SImageND(
            convert.(
                N0f8,
                clamp01nan.(
                    imfilter(img, reflect(ImageFiltering.Kernel.gaussian(1)), "replicate")
                ),
            ),
        )
        typeof(expected) == typeof(res) && res == expected
    end

    # blur img "circular"
    @test begin
        res = dp(img, -0.01)
        expected = SImageND(
            convert.(
                N0f8,
                clamp01nan.(
                    imfilter(img, reflect(ImageFiltering.Kernel.gaussian(1)), "circular")
                ),
            ),
        )
        typeof(expected) == typeof(res) && res == expected
    end

    # blur img "reflect"
    @test begin
        res = dp(img, 1)
        expected = SImageND(
            convert.(
                N0f8,
                clamp01nan.(
                    imfilter(img, reflect(ImageFiltering.Kernel.gaussian(1)), "reflect")
                ),
            ),
        )
        typeof(expected) == typeof(res) && res == expected
    end
end

# Blur img, choose padding && kernel size
@testset "Image2D filtering: gaussian_image2D(img, pad, ksize)" begin
    img = load_test_image()
    fac = UTCGP.bundle_image2D_filtering_factory[:gaussian_image2D].fn
    dp = fac(typeof(img))

    ################## ### 5X5 ### ################

    # blur img. 5x5 "Replicate"
    @test begin
        res = dp(img, 0, -1)
        expected = SImageND(
            convert.(
                N0f8,
                clamp01nan.(
                    imfilter(img, reflect(ImageFiltering.Kernel.gaussian(1)), "replicate")
                ),
            ),
        )
        typeof(expected) == typeof(res) && res == expected
    end
    # blur img. 5x5 "circular"
    @test begin
        res = dp(img, -1, -1)
        expected = SImageND(
            convert.(
                N0f8,
                clamp01nan.(
                    imfilter(img, reflect(ImageFiltering.Kernel.gaussian(1)), "circular")
                ),
            ),
        )
        typeof(expected) == typeof(res) && res == expected
    end
    # blur img. 5x5 "reflect"
    @test begin
        res = dp(img, 1, -1)
        expected = SImageND(
            convert.(
                N0f8,
                clamp01nan.(
                    imfilter(img, reflect(ImageFiltering.Kernel.gaussian(1)), "reflect")
                ),
            ),
        )
        typeof(expected) == typeof(res) && res == expected
    end

    ################## ### 9X9 ### ################
    # blur img. 9x9 "Replicate"
    @test begin
        res = dp(img, 0, 0)
        expected = SImageND(
            convert.(
                N0f8,
                clamp01nan.(
                    imfilter(img, reflect(ImageFiltering.Kernel.gaussian(2)), "replicate")
                ),
            ),
        )
        typeof(expected) == typeof(res) && res == expected
    end
    # blur img. 9x9 "circular"
    @test begin
        res = dp(img, -1.0, 0)
        expected = SImageND(
            convert.(
                N0f8,
                clamp01nan.(
                    imfilter(img, reflect(ImageFiltering.Kernel.gaussian(2)), "circular")
                ),
            ),
        )
        typeof(expected) == typeof(res) && res == expected
    end
    # blur img. 9x9 "reflect"
    @test begin
        res = dp(img, 2, 0)
        expected = SImageND(
            convert.(
                N0f8,
                clamp01nan.(
                    imfilter(img, reflect(ImageFiltering.Kernel.gaussian(2)), "reflect")
                ),
            ),
        )
        typeof(expected) == typeof(res) && res == expected
    end

    ################## ### 12X12 ### ################
    # blur img. 12x12 "Replicate"
    @test begin
        res = dp(img, 0, 2)
        expected = SImageND(
            convert.(
                N0f8,
                clamp01nan.(
                    imfilter(img, reflect(ImageFiltering.Kernel.gaussian(3)), "replicate")
                ),
            ),
        )
        typeof(expected) == typeof(res) && res == expected
    end
    # blur img. 12x12 "circular"
    @test begin
        res = dp(img, -1, 2)
        expected = SImageND(
            convert.(
                N0f8,
                clamp01nan.(
                    imfilter(img, reflect(ImageFiltering.Kernel.gaussian(3)), "circular")
                ),
            ),
        )
        typeof(expected) == typeof(res) && res == expected
    end
    # blur img. 12x12 "reflect"
    @test begin
        res = dp(img, 1, 2)
        expected = SImageND(
            convert.(
                N0f8,
                clamp01nan.(
                    imfilter(img, reflect(ImageFiltering.Kernel.gaussian(3)), "reflect")
                ),
            ),
        )
        typeof(expected) == typeof(res) && res == expected
    end
end
