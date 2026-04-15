include(joinpath(dirname(@__FILE__), "..", "..", "helpers", "orientation_examples.jl"))

@testset "Image2D Orientation: grad_magnitude" begin
    img = orientation_intensity_image(orientation_vertical_step_array())
    fn = bundle_image2DIntensity_orientation_factory[:grad_magnitude].fn(typeof(img))
    res = fn(img)
    @test eltype(res) == IntensityPixel{N0f8}
    @test size(res) == size(img)
    @test maximum(reinterpret(res.img)) > 0.0
end

@testset "Image2D Orientation: grad_orientation" begin
    vertical = orientation_intensity_image(orientation_vertical_step_array())
    horizontal = orientation_intensity_image(orientation_horizontal_step_array())
    fn = bundle_image2DIntensity_orientation_factory[:grad_orientation].fn(typeof(vertical))
    res_v = fn(vertical)
    res_h = fn(horizontal)
    @test mean(reinterpret(res_v.img)[:, 14:17]) < 0.2
    @test maximum(reinterpret(res_h.img)[14:17, :]) ≈ 0.5 atol = 0.1
end

@testset "Image2D Orientation: orientation_select" begin
    img = orientation_intensity_image(orientation_vertical_step_array())
    fn = bundle_image2DIntensity_orientation_factory[:orientation_select].fn(typeof(img))
    select_vertical_gradient = sum(reinterpret(fn(img, 0.0, 0.1).img))
    reject_vertical_gradient = sum(reinterpret(fn(img, 0.5, 0.1).img))
    @test select_vertical_gradient > reject_vertical_gradient
end
