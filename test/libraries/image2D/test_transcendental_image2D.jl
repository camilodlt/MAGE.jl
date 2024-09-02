# BUNDLE 
@testset "Image2D Transcendental Bundle" begin
    @test begin
        # bundle import
        using UTCGP: bundle_image2D_transcendental_factory
        length(bundle_image2D_transcendental_factory) == 3 &&
            _unique_names_in_bundle(bundle_image2D_transcendental_factory)
    end
end

#################
# Exponential   #
#################

@testset "Image2D Transcendental: exp" begin
    img = load_test_image()
    fac = UTCGP.bundle_image2D_transcendental_factory[:exp_image2D].fn
    fn = fac(typeof(img))
    @testset "Image2D Transcendental: exp(T)" begin
        @test begin
            res = fn(img)
            size(res) == size(img) && res != img
        end # returns the same size
        @test_throws MethodError begin # bad type according to specialized image
            new_img = SImageND(convert.(N0f16, img))
            res = fn(new_img)
        end
    end
    @testset "Image2D Transcendental: exp(img)" begin
        @test begin # clamped
            res = fn(img)
            all(res .<= 1) && all(res .>= 0)
        end # returns the same size
        @test begin
            example = SImageND(zeros(N0f8, size(img)))
            res = fn(example)
            sum(res) == length(img) # since exp(0) == 1
        end
    end
end

#################
# LOG           #
#################

@testset "Image2D Transcendental: log" begin
    img = load_test_image()
    fac = UTCGP.bundle_image2D_transcendental_factory[:log_image2D].fn
    fn = fac(typeof(img))
    @testset "Image2D Transcendental: log(T)" begin
        @test begin
            res = fn(img)
            size(res) == size(img) && res != img
        end # returns the same size
        @test_throws MethodError begin # bad type according to specialized image
            new_img = SImageND(convert.(N0f16, img))
            res = fn(new_img)
        end
    end
    @testset "Image2D Transcendental: log(img)" begin
        @test begin # clamped
            res = fn(img)
            all(res .<= 1) && all(res .>= 0)
        end # returns the same size
        @test begin
            example = SImageND(ones(N0f8, size(img)))
            res = fn(example)
            sum(res) == 0.0 # since log(1) == 0
        end
    end
end

#################
# Power Of      #
#################

@testset "Image2D Transcendental: power_of" begin
    img = load_test_image()
    fac = UTCGP.bundle_image2D_transcendental_factory[:powerof_image2D].fn
    fn = fac(typeof(img))
    @testset "Image2D Transcendental: power_of(T)" begin
        @test begin
            res = fn(img, 2.0)
            size(res) == size(img) && res != img
        end # returns the same size
        @test_throws MethodError begin # bad type according to specialized image
            new_img = SImageND(convert.(N0f16, img))
            res = fn(new_img, 2)
        end
    end
    @testset "Image2D Transcendental: log(img)" begin
        @test begin # clamped
            res = fn(img, 2)
            all(res .<= 1) && all(res .>= 0)
        end # returns the same size
        @test begin
            example = SImageND(ones(N0f8, size(img)))
            res = fn(example, -013.3)
            sum(res) == length(img) # since 1^p == 1
        end
    end
end
