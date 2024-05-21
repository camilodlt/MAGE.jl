function load_test_image()
    test_img = UTCGP._convert_image_to_channel_view(testimage("mandrill"))
    test_img = test_img[1, :, :]
    return SImageND(test_img)
end

@testset "Image2D Basic : Identity Factory" begin
    @test begin
        fn = UTCGP.bundle_image2D_basic_factory[:identity_image2D]
        fn = fn.fn(SImageND{<:Tuple,N0f32,2})
        expected_res = SImageND(ones(N0f32, 3, 3))
        res = fn(expected_res)
        res == expected_res
    end
    @test_throws MethodError begin # fails because wrong type
        fn = UTCGP.bundle_image2D_basic_factory[:identity_image2D]
        fn = fn.fn(SImageND{<:Tuple,N0f32,2})
        expected_res = ones(N0f8, 3, 3)
        res = fn(SImageND(expected_res))
    end
end

@testset "Image2D Basic : Identity Factory Specific Size" begin
    # TODO move to test SImageND
    @test begin
        fn = UTCGP.bundle_image2D_basic_factory[:identity_image2D]
        fn = fn.fn(SImageND{Tuple{100,100},N0f32,2})
        expected_res = ones(N0f32, 100, 100)
        res = fn(SImageND(expected_res))
        res == expected_res
    end
    @test_throws MethodError begin # fails because wrong type
        fn = UTCGP.bundle_image2D_basic_factory[:identity_image2D]
        fn = fn.fn(SImageND{Tuple{100,100},N0f32,2})
        expected_res = SImageND(ones(N0f8, 3, 3))
        res = fn(expected_res)
    end
end

@testset "Image 2D Basic : Identity Default" begin
    @test begin
        # bundle import
        using UTCGP: bundle_image2D_basic
        length(bundle_image2D_basic) == 3 && _unique_names_in_bundle(bundle_image2D_basic)
    end

    # IDENTITY 
    @test begin
        test_img = load_test_image()
        fn = bundle_image2D_basic[:identity_image2D].fn
        UTCGP._verify_last_arg_is_vararg!(fn)
        res = fn(test_img)
        res == test_img
    end

end

# ###################
# # ONES            #
# ###################
@testset "Images 2D Ones(Img) Default" begin

    dp = bundle_image2D_basic[:ones_2D].fn
    # ONES AS
    @test begin
        test_img = load_test_image()
        fn = which(dp, (typeof(test_img),))
        UTCGP._verify_last_arg_is_vararg!(fn)
        res = dp((test_img,))
        size_ok = size(res) == size(test_img)
        nbs = unique(res)
        length_ok = length(nbs) == 1
        type_ok = eltype(nbs) == eltype(test_img)
        size_ok && length_ok && type_ok
    end
end

@testset "Images 2D Ones(Img) Factory" begin

    fn = bundle_image2D_basic_factory[:ones_2D].fn
    dp = fn(SImageND{<:Tuple,N0f32,2})

    # ONES AS errors bc img is N0F8
    @test_throws MethodError begin
        test_img = load_test_image()
        fn = which(dp, (typeof(test_img),))
        UTCGP._verify_last_arg_is_vararg!(fn)
        res = dp((test_img,))
    end

    @test begin # now the type is correct
        test_img = load_test_image()
        test_img = SImageND(convert.(N0f32, test_img.img))
        fn = which(dp, (typeof(test_img),))
        UTCGP._verify_last_arg_is_vararg!(fn)
        res = dp((test_img,))
        size_ok = size(res) == size(test_img)
        nbs = unique(res)
        length_ok = length(nbs) == 1
        type_ok = eltype(nbs) == eltype(test_img)
        size_ok && length_ok && type_ok
    end
end

@testset "Images 2D Ones(k) Default" begin

    dp = bundle_image2D_basic[:ones_2D].fn # N0f8

    # ONES(K) :: Integer
    @test begin
        res = dp((3,)) # for int gives 255
        size_ok = size(res) == (3, 3)
        nbs = unique(res)
        length_ok = length(nbs) == 1
        type_ok = reinterpret(UInt8, nbs[1]) == 0xff # 255
        size_ok && type_ok && length_ok
    end

    @test begin # check args
        fn = which(dp, (typeof(3),))
        UTCGP._verify_last_arg_is_vararg!(fn)
        true
    end

    # ONES(K) Clamped at floor
    @test begin
        res = dp((-1,)) # not allowed -
        size(res) == (1, 1) && sum(res) == 1
    end

    # ONES(K) Clamped by globals
    @test begin
        prev = UTCGP.MAX_INT
        prev_c = UTCGP.CONSTRAINED
        UTCGP.MAX_INT = 3
        UTCGP.CONSTRAINED = true
        cond = false
        try
            res = dp((100,)) # not allowed -
            cond = size(res) == (3, 3) && sum(res) == 3 * 3
        catch e
            cond = false
            throw(e)
        finally
            UTCGP.MAX_INT = prev
            UTCGP.CONSTRAINED = prev_c
        end
        cond
    end

end

@testset "Images 2D Ones(k) Factory" begin

    fn = bundle_image2D_basic_factory[:ones_2D].fn
    dp = fn(SImageND{<:Tuple,N0f32,2})

    @test_throws ErrorException begin
        res = dp((3,)) # for int gives 255
        size_ok = size(res) == (3, 3)
        nbs = unique(res)
        reinterpret(UInt8, nbs[1]) # errors bc return is N0F32
    end

    # ONES(K) expected return is N0f32
    @test begin
        res = dp((3,)) # for int gives 255
        size_ok = size(res) == (3, 3)
        nbs = unique(res)
        length_ok = length(nbs) == 1
        type_ok = reinterpret(UInt32, nbs[1]) == 0xffffffff # bc N0F32
        size_ok && type_ok && length_ok
    end
end

@testset "Images 2D Ones(k,k) Default" begin

    dp = bundle_image2D_basic[:ones_2D].fn

    # ONES(K,K)
    @test begin
        res = dp((3, 10)) # for int gives 255
        size_ok = size(res) == (3, 10)
        nbs = unique(res)
        length_ok = length(nbs) == 1
        type_ok = reinterpret(UInt8, nbs[1]) == 0xff # 255
        size_ok && type_ok && length_ok
    end

    @test begin # check args
        fn = which(dp, (Int, Int))
        UTCGP._verify_last_arg_is_vararg!(fn)
        true
    end

    # ONES(K,K) Clamped at floor
    @test begin
        res = dp((-1, -1)) # not allowed -
        size(res) == (1, 1) && sum(res) == 1
    end

    # ONES(K,K) Clamped by globals
    @test begin
        prev = UTCGP.MAX_INT
        prev_c = UTCGP.CONSTRAINED
        UTCGP.MAX_INT = 3
        UTCGP.CONSTRAINED = true
        cond = false
        try
            res = dp((100, 2)) # not allowed -
            cond = size(res) == (3, 2) && sum(res) == 3 * 2
        catch e
            cond = false
            throw(e)
        finally
            UTCGP.MAX_INT = prev
            UTCGP.CONSTRAINED = prev_c
        end
        cond
    end

end

###################
# ZEROS           #
###################

@testset "Images 2D zeros(img) Default" begin

    dp = bundle_image2D_basic[:zeros_2D].fn

    # ZEROS AS
    @test begin
        test_img = load_test_image()
        res = dp((test_img,))
        size_ok = size(res) == size(test_img)
        nbs = unique(res)
        length_ok = length(nbs) == 1
        type_ok = eltype(nbs) == eltype(test_img)
        size_ok && length_ok && type_ok && sum(res) == 0
    end

    @test begin # check args
        fn = which(dp, (Int, Int))
        UTCGP._verify_last_arg_is_vararg!(fn)
        true
    end
end

@testset "Images 2D zeros(img) Factory" begin

    fn = bundle_image2D_basic_factory[:zeros_2D].fn
    dp = fn(SImageND{<:Tuple,N0f32,2})

    # ZEROS AS
    @test_throws MethodError begin # expected N0f32
        test_img = load_test_image()
        res = dp((test_img,))
    end
    @test begin
        test_img = load_test_image()
        test_img = SImageND(convert.(N0f32, test_img.img))
        res = dp((test_img,))
        size_ok = size(res) == size(test_img)
        nbs = unique(res)
        length_ok = length(nbs) == 1
        type_ok = eltype(nbs) == eltype(test_img)
        size_ok && length_ok && type_ok && sum(res) == 0
    end

end

@testset "Images 2D zeros(K) Default" begin

    dp = bundle_image2D_basic[:zeros_2D].fn

    # ZEROS(K) :: Integer
    @test begin
        res = dp((3,)) # for int gives 0
        size_ok = size(res) == (3, 3)
        nbs = unique(res)
        length_ok = length(nbs) == 1
        type_ok = reinterpret(UInt8, nbs[1]) == 0x00 # 0
        size_ok && type_ok && length_ok
    end

    @test begin # check args
        fn = which(dp, (Int,))
        UTCGP._verify_last_arg_is_vararg!(fn)
        true
    end

    # ZEROS(K) Clamped at floor
    @test begin
        res = dp((-1,)) # not allowed -
        size(res) == (1, 1) && sum(res) == 0
    end

    # ZEROS(K) Clamped by globals
    @test begin
        prev = UTCGP.MAX_INT
        prev_c = UTCGP.CONSTRAINED
        UTCGP.MAX_INT = 3
        UTCGP.CONSTRAINED = true
        cond = false
        try
            res = dp((100,)) # not allowed -
            cond = size(res) == (3, 3) && sum(res) == 0
        catch e
            cond = false
            throw(e)
        finally
            UTCGP.MAX_INT = prev
            UTCGP.CONSTRAINED = prev_c
        end
        cond
    end

end

@testset "Image 2D zeros(K) Factory" begin

    fn = bundle_image2D_basic_factory[:zeros_2D].fn
    dp = fn(SImageND{<:Tuple,N0f32,2})

    # ZEROS(K) erros bc type is UInt32
    @test_throws ErrorException begin
        res = dp((3,)) # for int gives 0
        size_ok = size(res) == (3, 3)
        nbs = unique(res)
        length_ok = length(nbs) == 1
        reinterpret(UInt8, nbs[1])
    end

    # ZEROS(K) type is ok
    @test begin
        res = dp((3,)) # for int gives 0
        size_ok = size(res) == (3, 3)
        nbs = unique(res)
        length_ok = length(nbs) == 1
        type_ok = reinterpret(UInt32, nbs[1]) == 0x00000000 # 0
        size_ok && length_ok && type_ok
    end
end

@testset "Image 2D zeros(K,k) Default" begin

    dp = bundle_image2D_basic[:zeros_2D].fn # default is N0f8

    # ZEROS(K,K)
    @test begin
        res = dp((3, 10)) # for int gives 0
        size_ok = size(res) == (3, 10)
        nbs = unique(res)
        length_ok = length(nbs) == 1
        type_ok = reinterpret(UInt8, nbs[1]) == 0x00 # 255
        size_ok && type_ok && length_ok
    end

    @test begin # check args
        fn = which(dp, (Int, Int))
        UTCGP._verify_last_arg_is_vararg!(fn)
        true
    end

    # ZEROS(K,K) Clamped at floor
    @test begin
        res = dp((-1, -1)) # not allowed -
        size(res) == (1, 1) && sum(res) == 0
    end

    # ZEROS(K,K) Clamped by globals
    @test begin
        prev = UTCGP.MAX_INT
        prev_c = UTCGP.CONSTRAINED
        UTCGP.MAX_INT = 3
        UTCGP.CONSTRAINED = true
        cond = false
        try
            res = dp((100, 2)) # not allowed -
            cond = size(res) == (3, 2) && sum(res) == 0
        catch e
            cond = false
            throw(e)
        finally
            UTCGP.MAX_INT = prev
            UTCGP.CONSTRAINED = prev_c
        end
        cond
    end
end

@testset "Image 2D zeros(K,k) Factory" begin

    fn = bundle_image2D_basic_factory[:zeros_2D].fn
    dp = fn(SImageND{<:Tuple,N0f32,2})

    # ZEROS(K,K)
    @test_throws ErrorException begin # errors bc type is not UINT8
        res = dp((3, 10)) # for int gives 0
        size_ok = size(res) == (3, 10)
        nbs = unique(res)
        length_ok = length(nbs) == 1
        reinterpret(UInt8, nbs[1])
    end

    # ZEROS(K,K)
    @test begin
        res = dp((3, 10)) # for int gives 0
        size_ok = size(res) == (3, 10)
        nbs = unique(res)
        length_ok = length(nbs) == 1
        type_ok = reinterpret(UInt32, nbs[1]) == 0x00000000
        size_ok && length_ok && type_ok
    end
end
