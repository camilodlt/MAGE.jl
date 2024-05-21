
#################
#  subtract_img #
#################

@testset "Image2D Arithmetic: subtract_img2D(T)" begin
    img = load_test_image()
    fac = UTCGP.bundle_image2D_arithmetic_factory[:subtract_img2D].fn
    fn = fac(typeof(img))
    @test begin
        res = fn(img, img)
        size(res) == size(img) && res != img
    end
    @test_throws MethodError begin # bad type according to specialized image
        new_img = SImageND(convert.(N0f16, img))
        res = fn(new_img, new_img)
    end
end

@testset "Image2D Arithmetic: subtract_img(img,img)" begin
    img = load_test_image()
    fac = UTCGP.bundle_image2D_arithmetic_factory[:subtract_img2D].fn
    fn = fac(typeof(img))
    @test begin
        res = fn(img, img)
        expected = clamp01nan.(float(img) - float(img))
        cond1 = size(res) == size(img) && res != img
        cond2 = res == expected
        cond1 && cond2
    end
    @test begin
        ones_ = SImageND(ones(N0f8, size(img)))
        zeros_ = SImageND(zeros(N0f8, size(img)))
        res = fn(zeros_, ones_) # is clamped at 0
        unique(res)[1] == 0.0
    end
    @test_throws MethodError begin # BC images of diff size
        img2_of_diff_size = ones(N0f8, 10, 10)
        res = fn(img, img2_of_diff_size)
    end
    @test_throws MethodError begin # BC images of diff Type
        img2_of_diff_size = convert.(N0f16, img)
        res = fn(img, img2_of_diff_size)
    end
end

#################
#  add_img2D    #
#################

@testset "Image2D Arithmetic: add_img2D(T)" begin
    img = load_test_image()
    fac = UTCGP.bundle_image2D_arithmetic_factory[:add_img2D].fn
    fn = fac(typeof(img))
    @test begin
        res = fn(img, img)
        size(res) == size(img) && res != img
    end
    @test_throws MethodError begin # bad type according to specialized image
        new_img = SImageND(convert.(N0f16, img))
        res = fn(new_img, new_img)
    end
end

@testset "Image2D Arithmetic: add_img2D(img,img)" begin
    img = load_test_image()
    fac = UTCGP.bundle_image2D_arithmetic_factory[:add_img2D].fn
    fn = fac(typeof(img))
    @test begin
        res = fn(img, img)
        expected = clamp01nan.(float(img) + float(img))
        cond1 = size(res) == size(img) && res != img
        cond2 = res == expected
        cond1 && cond2
    end
    @test begin
        ones_ = SImageND(ones(N0f8, size(img)))
        res = fn(ones_, ones_) # is clamped at 1
        unique(res)[1] == 1.0
    end
    @test_throws MethodError begin # BC images of diff size
        img2_of_diff_size = ones(N0f8, 10, 10)
        res = fn(img, img2_of_diff_size)
    end
    @test_throws MethodError begin # BC images of diff Type
        img2_of_diff_size = convert.(N0f16, img)
        res = fn(img, img2_of_diff_size)
    end
end


#################
#  mult_img2D   #
#################

@testset "Image2D Arithmetic: mult_img2D(T)" begin
    img = load_test_image()
    fac = UTCGP.bundle_image2D_arithmetic_factory[:mult_img2D].fn
    fn = fac(typeof(img))
    @test begin
        res = fn(img, img)
        size(res) == size(img) && res != img
    end
    @test_throws MethodError begin # bad type according to specialized image
        new_img = SImageND(convert.(N0f16, img))
        res = fn(new_img, new_img)
    end
end

@testset "Image2D Arithmetic: mult_img2D(img,img)" begin
    img = load_test_image()
    fac = UTCGP.bundle_image2D_arithmetic_factory[:mult_img2D].fn
    fn = fac(typeof(img))
    @test begin
        res = fn(img, img)
        expected = clamp01nan.(float(img) * float(img))
        cond1 = size(res) == size(img) && res != img
        cond2 = res == expected
        cond1 && cond2
    end
    @test begin
        ones_ = SImageND(ones(N0f8, size(img)))
        zeros_ = SImageND(zeros(N0f8, size(img)))
        res = fn(ones_, zeros_)
        sum(res) == 0.0
    end
    @test_throws MethodError begin # BC images of diff size
        img2_of_diff_size = ones(N0f8, 10, 10)
        res = fn(img, img2_of_diff_size)
    end
    @test_throws MethodError begin # BC images of diff Type
        img2_of_diff_size = convert.(N0f16, img)
        res = fn(img, img2_of_diff_size)
    end
end

