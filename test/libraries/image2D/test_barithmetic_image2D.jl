#################
# bsubtract_img #
#################

@testset "Image2D BArithmetic: subtract_img2D(T)" begin
    img = load_test_image()
    fac = UTCGP.bundle_image2D_barithmetic_factory[:bsubtract_image2D].fn
    fn = fac(typeof(img))
    @test begin
        res = fn(img, 1.0)
        size(res) == size(img) && res != img
    end
    @test_throws MethodError begin # bad type according to specialized image
        new_img = SImageND(convert.(N0f16, img))
        res = fn(new_img, 1.0)
    end
end

@testset "Image2D BArithmetic: subtract_img(img,float)" begin
    img = load_test_image()
    fac = UTCGP.bundle_image2D_barithmetic_factory[:bsubtract_image2D].fn
    fn = fac(typeof(img))
    @test begin
        res = fn(img, 0.3)
        expected = clamp01nan.(float64.(img) .- 0.3)
        cond1 = size(res) == size(img) && res != img
        cond2 = res == expected
        cond1 && cond2
    end
    @test begin
        res = fn(img, 2.0) # will be clamped to 0
        cond1 = size(res) == size(img) && res != img
        cond2 = sum(res) == 0
        cond1 && cond2
    end
    @test begin
        res = fn(img, -2.0) # will be clamped to 1
        cond1 = size(res) == size(img) && res != img
        cond2 = sum(res) == length(res)
        cond1 && cond2
    end
    @test begin
        ones_ = SImageND(ones(N0f8, size(img)))
        res = fn(ones_, 0.0)
        res == ones_
    end
    @test_throws MethodError begin # interface is img, real
        img2_of_diff_size = ones(N0f8, size(img))
        res = fn(img2_of_diff_size, img2_of_diff_size)
    end
end


#################
#  badd_img     #
#################

@testset "Image2D BArithmetic: badd_image2D(T)" begin
    img = load_test_image()
    fac = UTCGP.bundle_image2D_barithmetic_factory[:badd_image2D].fn
    fn = fac(typeof(img))
    @test begin
        res = fn(img, 1.0)
        size(res) == size(img) && res != img
    end
    @test_throws MethodError begin # bad type according to specialized image
        new_img = SImageND(convert.(N0f16, img))
        res = fn(new_img, 1.0)
    end
end

@testset "Image2D BArithmetic: badd_image2D(img,float)" begin
    img = load_test_image()
    fac = UTCGP.bundle_image2D_barithmetic_factory[:badd_image2D].fn
    fn = fac(typeof(img))
    @test begin
        res = fn(img, 0.3)
        expected = clamp01nan.(float64.(img) .+ 0.3)
        cond1 = size(res) == size(img) && res != img
        cond2 = res == expected
        cond1 && cond2
    end
    @test begin
        res = fn(img, 2.0) # will be clamped to 1
        cond1 = size(res) == size(img) && res != img
        cond2 = sum(res) == length(res)
        cond1 && cond2
    end
    @test begin
        res = fn(img, -2.0) # will be clamped to 0
        cond1 = size(res) == size(img) && res != img
        cond2 = sum(res) == 0
        cond1 && cond2
    end
    @test begin
        ones_ = SImageND(ones(N0f8, size(img)))
        res = fn(ones_, 0.0)
        res == ones_
    end
    @test_throws MethodError begin # interface is img, float
        img2_of_diff_size = ones(N0f8, size(img))
        res = fn(img2_of_diff_size, img2_of_diff_size)
    end

    # Handle image of any size
    @test begin
        fn = fac(SImage2D{S1,S2,N0f8,IT} where {S1,S2,IT}) # just the type has to be known beforehand
        res = fn(img, 0.3)
        expected = clamp01nan.(float64.(img) .+ 0.3)
        cond1 = size(res) == size(img) && res != img
        cond2 = res == expected
        res2 = fn(SImageND(ones(N0f8, 10, 10)), -1.0) # subtracts -1 => clamps all at 0
        cond1 && cond2 && sum(res2) == 0.0 && size(res2) == (10, 10)
    end
end

#####################
#  bmult_image2D     #
#####################

@testset "Image2D bmult: bmult_image2D(T)" begin
    img = load_test_image()
    fac = UTCGP.bundle_image2D_barithmetic_factory[:bmult_image2D].fn
    fn = fac(typeof(img))
    @test begin
        res = fn(img, 1.0)
        size(res) == size(img) && res == img
    end
    @test_throws MethodError begin # bad type according to specialized image
        new_img = SImageND(convert.(N0f16, img))
        res = fn(new_img, 1.0)
    end
end

@testset "Image2D BArithmetic: bmult_image2D(img,float)" begin
    img = load_test_image()
    fac = UTCGP.bundle_image2D_barithmetic_factory[:bmult_image2D].fn
    fn = fac(typeof(img))
    @test begin
        res = fn(img, 0.3)
        expected = clamp01nan.(float64.(img) .* 0.3)
        cond1 = size(res) == size(img) && res != img
        cond2 = res == expected
        cond1 && cond2
    end
    @test begin
        res = fn(img, -1.0) # all clamped to 0 
        cond1 = size(res) == size(img) && res != img
        cond2 = sum(res) == 0.0
        cond1 && cond2
    end
    @test begin
        res = fn(img, typemax(Float64)) # will be clamped to 1
        cond1 = size(res) == size(img) && res != img
        vals = Set(unique(res))
        cond2 = 0.0 in vals && 1.0 in vals
        cond1 && cond2
    end
    @test begin # mult by 0
        ones_ = SImageND(ones(N0f8, size(img)))
        res = fn(ones_, 0.0)
        sum(res) == 0
    end
    @test_throws MethodError begin # interface is img, float
        img2_of_diff_size = ones(N0f8, size(img))
        res = fn(img2_of_diff_size, img2_of_diff_size)
    end

    # Handle image of any size
    @test begin
        fn = fac(SImage2D{S1,S2,N0f8,IT} where {S1,S2,IT}) # just the type has to be known beforehand
        res = fn(img, 0.0)
        cond1 = size(res) == size(img) && res != img
        cond2 = sum(res) == 0
        res2 = fn(SImageND(ones(N0f8, 10, 10)), 0.5) # div by 2
        cond1 && cond2 && sum(res2) == 0.5 * length(res2) && size(res2) == (10, 10)
    end
end
