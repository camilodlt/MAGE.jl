###############
# Felzenswalb #
###############

@testset "Image2D Segmentation: felzenswalb_image2D_factory(T) " begin
    @test begin
        fac = UTCGP.bundle_image2D_segmentation_factory[:felzenswalb_2D].fn
        dp = fac(SImageND{Tuple{10,10},N0f8,2})
        ones_ = ones(N0f8, 10, 10)
        ones_[5, 5] = 0
        ones_ = SImageND(ones_)
        size(ones_) == (10, 10)
    end
end

@testset "Image2D Segmentation: felzenswalb_image2D(img,k) " begin
    fac = UTCGP.bundle_image2D_segmentation_factory[:felzenswalb_2D].fn
    img = load_test_image()
    img_16 = SImageND(convert.(N0f16, img.img))
    @test begin
        dp = fac(typeof(img))
        res = dp(img, 4000)
        unique(res.img) == [0.004N0f8, 0.008N0f8, 0.012N0f8, 0.016N0f8] &&
            typeof(res).parameters[2] == N0f8 &&
            eltype(typeof(res.img)) == N0f8
    end
    @test_throws InexactError begin # bc k is not enough, too many different instances for the type
        dp = fac(typeof(img))
        res = dp(img, 100)
    end
    @test begin # with type Uint16, now we have room for that many segmentations
        img_16 = SImageND(convert.(N0f16, img.img))
        dp = fac(typeof(img_16))
        res = dp(img_16, 100)
        seg = ImageSegmentation.felzenszwalb(img_16.img, 100)
        seg = ImageSegmentation.labels_map(seg)
        convert.(UInt16, seg) == reinterpret.(res)
    end
    @test begin # negative k => 1
        img_16 = SImageND(convert.(N0f16, img.img))
        dp = fac(typeof(img_16))
        res = dp(img_16, -100)
        seg = ImageSegmentation.felzenszwalb(img_16.img, 1)
        seg = ImageSegmentation.labels_map(seg)
        convert.(UInt16, seg) == reinterpret.(res)
    end
    @test begin # Deterministic
        dp = fac(typeof(img_16))
        rs = [dp(img_16, 50) for i = 1:10]
        all(i -> i == rs[1], rs)
    end
end

#################
# Unseeded Grow #
#################

@testset "Image2D Segmentation: unseededgrow_image2D_factory(T)" begin
    img = load_test_image()
    fac = UTCGP.bundle_image2D_segmentation_factory[:unseededgrow_2D].fn
    dp = fac(typeof(img))
    @test begin
        res = dp(img)
        size(res) == size(img) && res != img
    end
    @test_throws MethodError begin
        res = dp(SImageND(convert.(N0f16, img)))
        size(res) == size(img) && res != img
    end
end

@testset "Image2D Segmentation: unseededgrow_image2D(img,th)" begin
    img = load_test_image()
    img_16 = SImageND(convert.(N0f16, img))
    fac = UTCGP.bundle_image2D_segmentation_factory[:unseededgrow_2D].fn
    dp = fac(typeof(img))
    dp_16 = fac(typeof(img_16))
    @test begin # th in range
        res = dp(img, 0.1)
        cond1 = size(res) == size(img) && res != img
        seg = ImageSegmentation.unseeded_region_growing(Gray.(img.img), 0.1)
        seg = ImageSegmentation.labels_map(seg)
        cond1 && convert.(UInt8, seg) == reinterpret.(res)
    end
    @test begin # th not in range so -0.0 turned to eps(Float64)
        res = dp_16(img_16, -0.0)
        cond1 = size(res) == size(img_16) && res != img_16
        seg = ImageSegmentation.unseeded_region_growing(Gray.(img_16.img), eps(Float64))
        seg = ImageSegmentation.labels_map(seg)
        cond1 && convert.(UInt16, seg) == reinterpret.(res)
    end
end

@testset "Image2D Segmentation: unseededgrow_image2D(img)" begin
    img = load_test_image()
    fac = UTCGP.bundle_image2D_segmentation_factory[:unseededgrow_2D].fn
    dp = fac(typeof(img))
    @test begin # no th => 0.3
        res = dp(img)
        cond1 = size(res) == size(img) && res != img
        seg = ImageSegmentation.unseeded_region_growing(Gray.(img.img), 0.3)
        seg = ImageSegmentation.labels_map(seg)
        cond1 && convert.(UInt8, seg) == reinterpret.(res)
    end
    @test begin # Deterministic
        rs = [dp(img) for i = 1:10]
        all(i -> i == rs[1], rs)
    end
end

