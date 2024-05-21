
@testset "Image2D Morph: erosion(img) Default" begin
    @test begin
        dp = UTCGP.bundle_image2D_morph[:erosion_2D].fn
        ones_ = ones(N0f8, 10, 10)
        ones_[5, 5] = 0
        ones_ = SImageND(ones_)
        res = dp((ones_,))
        expected_res = SImageND(erode(ones_.img))
        res == expected_res && res.img == expected_res.img
    end
end

@testset "Image2D Morph: erosion(img,k) Default" begin
    ones_ = SImageND(ones(N0f8, 20, 20))
    dp = UTCGP.bundle_image2D_morph[:erosion_2D].fn
    @test begin # even number turned to odd
        se = strel_diamond((11, 11))
        res = dp((ones_, 10)) # turned to 11
        expected_res = SImageND(erode(ones_.img, se))
        res == expected_res && res.img == expected_res.img
    end
    @test begin # ok number
        se = strel_diamond((5, 5))
        res = dp((ones_, 5))
        expected_res = SImageND(erode(ones_.img, se))
        res == expected_res && res.img == expected_res.img
    end
    @test begin # number to low turned to 3
        se = strel_diamond((3, 3))
        res = dp((ones_, 0))
        expected_res = SImageND(erode(ones_.img, se))
        res == expected_res && res.img == expected_res.img
    end
    @test begin # Number to high turned to 13 
        se = strel_diamond((13, 13))
        res = dp((ones_, 1332))
        expected_res = SImageND(erode(ones_.img, se))
        res == expected_res && res.img == expected_res.img
    end
end
