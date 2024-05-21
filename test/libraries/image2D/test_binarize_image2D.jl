using ImageView
using ImageBinarization

#####################
# Adaptive Threshold #
#####################

# DEFAULT #
@testset "Image2D Binarize: binarize_adaptive2D(img) Default" begin
    @test begin
        dp = UTCGP.bundle_image2D_binarize[:binarize_adaptive2D].fn
        img = load_test_image() # from basic
        @show typeof(img)
        binarized = dp(img)
        f = AdaptiveThreshold(img.img)
        bimg = binarize(img.img, f)
        binarized == bimg
        # res == expected_res && res.img == expected_res.img
    end
end

@testset "Image2D Binarize: binarize_adaptive2D(img,w) Default" begin
    @test begin
        dp = UTCGP.bundle_image2D_binarize[:binarize_adaptive2D].fn
        img = load_test_image() # from basic
        @show typeof(img)
        binarized = dp(img, 100)
        f = AdaptiveThreshold(window_size = 100)
        bimg = binarize(img.img, f)
        binarized == bimg
        # res == expected_res && res.img == expected_res.img
    end
end
@testset "Image2D Binarize: binarize_adaptive2D(img,w,p) Default" begin
    @test begin
        dp = UTCGP.bundle_image2D_binarize[:binarize_adaptive2D].fn
        img = load_test_image() # from basic
        @show typeof(img)
        binarized = dp(img, 100, 80)
        f = AdaptiveThreshold(window_size = 100, percentage = 80)
        bimg = binarize(img.img, f)
        binarized == bimg
        # res == expected_res && res.img == expected_res.img
    end
end


# FACTORY #
@testset "Image2D Binarize: binarize_adaptive2D(img) Factory" begin
    img = load_test_image

    # TEST THE TYPE
    @test_throws MethodError begin  # the factory works with N0f16
        factory = UTCGP.bundle_image2D_binarize_factory[:binarize_adaptive2D].fn
        fn = factory(N0f16)
        fn(img) # fails because image is N0f8
    end
    @test begin # works with Float64 if specialized to it
        factory = UTCGP.bundle_image2D_binarize_factory[:binarize_adaptive2D].fn
        fn = factory(SImageND{<:Tuple,Float64})
        res = fn(SImageND(ones(Float64, 10, 10)))
        size(res) == (10, 10)
    end
end

# TEST THE FACTORY : img
@testset "Image2D Binarize: binarize_adaptive2D(img, w) Factory" begin
    img = load_test_image()

    # TEST THE TYPE
    @test_throws MethodError begin  # the factory works with N0f16
        factory = UTCGP.bundle_image2D_binarize_factory[:binarize_adaptive2D].fn
        fn = factory(N0f16)
        fn(img, 10) # fails because image is N0f8
    end
    @test begin # works with Float64 if specialized to it
        factory = UTCGP.bundle_image2D_binarize_factory[:binarize_adaptive2D].fn
        fn = factory(SImageND{<:Tuple,Float64})
        res = fn(SImageND(ones(Float64, 10, 10)), 10)
        size(res) == (10, 10)
    end

    # Test that the window is capped at [9, img_size]
    @test begin # works with Float64 if specialized to it
        factory = UTCGP.bundle_image2D_binarize_factory[:binarize_adaptive2D].fn
        fn = factory(SImageND{<:Tuple,N0f8})
        res = fn(img, -1000)
        f = AdaptiveThreshold(window_size = 9)
        bimg = binarize(img.img, f)
        bimg == res.img
    end

    # Test that the window is capped at [9, img_size]
    @test begin # works with Float64 if specialized to it
        factory = UTCGP.bundle_image2D_binarize_factory[:binarize_adaptive2D].fn
        fn = factory(SImageND{<:Tuple,N0f8})
        res = fn(img, 10000000)
        s = size(img)
        w = min(s[1], s[2])
        f = AdaptiveThreshold(window_size = w)
        bimg = binarize(img.img, f)
        bimg == res.img
    end
end

# TEST THE FACTORY : img
@testset "Image2D Binarize: binarize_adaptive2D(img, w) Factory" begin
    img = load_test_image()

    # TEST THE TYPE
    @test_throws MethodError begin  # the factory works with N0f16
        factory = UTCGP.bundle_image2D_binarize_factory[:binarize_adaptive2D].fn
        fn = factory(N0f16)
        fn(img, 10, 100) # fails because image is N0f8
    end
    @test begin # works with Float64 if specialized to it
        factory = UTCGP.bundle_image2D_binarize_factory[:binarize_adaptive2D].fn
        fn = factory(SImageND{<:Tuple,Float64})
        res = fn(SImageND(ones(Float64, 10, 10)), 10, 100)
        size(res) == (10, 10)
    end

    # Test that the window is capped at [9, img_size]
    @test begin # works with Float64 if specialized to it
        factory = UTCGP.bundle_image2D_binarize_factory[:binarize_adaptive2D].fn
        fn = factory(SImageND{<:Tuple,N0f8})
        res = fn(img, -1000, 10)
        f = AdaptiveThreshold(window_size = 9, percentage = 10)
        bimg = binarize(img.img, f)
        bimg == res.img
    end

    # Test that the window is capped at [9, img_size]
    @test begin # works with Float64 if specialized to it
        factory = UTCGP.bundle_image2D_binarize_factory[:binarize_adaptive2D].fn
        fn = factory(SImageND{<:Tuple,N0f8})
        res = fn(img, 10000000, 10)
        s = size(img)
        w = min(s[1], s[2])
        f = AdaptiveThreshold(window_size = w, percentage = 10)
        bimg = binarize(img.img, f)
        bimg == res.img
    end

    # Percentage is also clamped
    @test begin # p = -1282 => 0
        factory = UTCGP.bundle_image2D_binarize_factory[:binarize_adaptive2D].fn
        fn = factory(SImageND{<:Tuple,N0f8})
        res = fn(img, 30, -1282)
        f = AdaptiveThreshold(window_size = 30, percentage = 0)
        bimg = binarize(img.img, f)
        bimg == res.img
    end
    @test begin # p = 1282 => 0
        factory = UTCGP.bundle_image2D_binarize_factory[:binarize_adaptive2D].fn
        fn = factory(SImageND{<:Tuple,N0f8})
        res = fn(img, 30, 1282)
        f = AdaptiveThreshold(window_size = 30, percentage = 100)
        bimg = binarize(img.img, f)
        bimg == res.img
    end

end

####################
# MANUAL BINARIZER #
####################

# DEFAULT # 
@testset "Image2D Binarize: manual_binarizer(img) Default" begin
    dp = UTCGP.bundle_image2D_binarize[:binarize_manual2D].fn
    img = load_test_image() # from basic
    @test begin
        binarized = dp(img)
        expected = img .> 0.5
        binarized == expected
    end
end

@testset "Image2D Binarize: manual_binarizer(img, t::Int) Default" begin
    dp = UTCGP.bundle_image2D_binarize[:binarize_manual2D].fn
    img = load_test_image() # from basic
    @test begin
        binarized = dp(img, 50) # turns to 0.5
        expected = img .> 0.5
        binarized == expected
    end
end

@testset "Image2D Binarize: manual_binarizer(img, t::Float64) Default" begin
    dp = UTCGP.bundle_image2D_binarize[:binarize_manual2D].fn
    img = load_test_image() # from basic
    @test begin
        binarized = dp(img, 0.2)
        expected = img .> 0.2
        binarized == expected
    end
end

@testset "Image2D Binarize: manual_binarizer(img, img) Default" begin
    dp = UTCGP.bundle_image2D_binarize[:binarize_manual2D].fn
    img = load_test_image() # from basic
    @test begin
        sizes_ = size(img)
        second_img = SImageND(ones(N0f8, sizes_[1], sizes_[2]))
        binarized = dp(img, second_img)
        expected = img .> 1.0
        binarized == expected
    end
end

# FACTORY #  

@testset "Image2D Binarize: manual_binarizer(img) Factory" begin
    factory = UTCGP.bundle_image2D_binarize_factory[:binarize_manual2D].fn
    dp = factory(SImageND{<:Tuple,N0f16,2})
    img = load_test_image() # from basic
    img2 = SImageND(convert.(N0f16, img))
    @test_throws MethodError begin # accepts only N0f8
        binarized = dp(img)
    end
    @test begin # accepts only N0f8
        binarized = dp(img2)
        expected = img2 .> 0.5
        binarized == expected
    end
end

@testset "Image2D Binarize: manual_binarizer(img, img) Factory" begin
    factory = UTCGP.bundle_image2D_binarize_factory[:binarize_manual2D].fn
    dp = factory(SImageND{<:Tuple,N0f16,2})
    img = load_test_image() # from basic
    img2 = SImageND(convert.(N0f16, img))
    @test_throws MethodError begin # accepts only N0f8
        binarized = dp(img, img)
    end
    @test begin # accepts only N0f8
        binarized = dp(img2, img2)
        th = mean(img2)
        expected = img2 .> th
        binarized == expected
    end
end

@testset "Image2D Binarize: manual_binarizer(img, t::Int) Factory" begin
    factory = UTCGP.bundle_image2D_binarize_factory[:binarize_manual2D].fn
    dp = factory(SImageND{<:Tuple,N0f16,2})
    img = load_test_image() # from basic
    img2 = SImageND(convert.(N0f16, img))
    @test_throws MethodError begin # accepts only N0f8
        binarized = dp(img, 50)
    end
    @test begin # 100/100 => 1
        binarized = dp(img2, 100)
        expected = img2 .> 1.0
        binarized == expected
    end
    @test begin # 101 is clamped at 1
        binarized = dp(img2, 101)
        expected = img2 .> 1.0
        binarized == expected
    end
    @test begin # 0/100 => 0
        binarized = dp(img2, 0)
        expected = img2 .> 0
        binarized == expected
    end
    @test begin # -1 is clamped at 0
        binarized = dp(img2, -1)
        expected = img2 .> 0
        binarized == expected
    end
end

@testset "Image2D Binarize: manual_binarizer(img, t::Float64) Factory" begin
    factory = UTCGP.bundle_image2D_binarize_factory[:binarize_manual2D].fn
    dp = factory(SImageND{<:Tuple,N0f16,2})
    img = load_test_image() # from basic
    img2 = SImageND(convert.(N0f16, img))
    @test_throws MethodError begin # accepts only N0f8
        binarized = dp(img, 0.5)
    end
    @test begin # 100/100 => 1
        binarized = dp(img2, 1.0)
        expected = img2 .> 1.0
        binarized == expected
    end
    @test begin # 101 is clamped at 1
        binarized = dp(img2, 1.1)
        expected = img2 .> 1.0
        binarized == expected
    end
    @test begin # 0/100 => 0
        binarized = dp(img2, 0.0)
        expected = img2 .> 0
        binarized == expected
    end
    @test begin # 0.002 => ok
        binarized = dp(img2, 0.002)
        expected = img2 .> 0.002
        binarized == expected
    end
    @test begin # -1 is clamped at 0
        binarized = dp(img2, -1.0)
        expected = img2 .> 0.0
        binarized == expected
    end
end


####################
# OTSU Binarizer   #
####################
