include(joinpath(dirname(@__FILE__), "..", "..", "helpers", "orientation_examples.jl"))

@testset "Float Orientation: dominant orientation and energy" begin
    horizontal = orientation_intensity_image(orientation_horizontal_step_array())
    vertical = orientation_intensity_image(orientation_vertical_step_array())
    diag45 = orientation_intensity_image(orientation_diag45_step_array())
    diag135 = orientation_intensity_image(orientation_diag135_step_array())

    dominant = bundle_float_orientation[:dominant_orientation].fn
    e0 = bundle_float_orientation[:orientation_energy_0].fn
    e45 = bundle_float_orientation[:orientation_energy_45].fn
    e90 = bundle_float_orientation[:orientation_energy_90].fn
    e135 = bundle_float_orientation[:orientation_energy_135].fn

    @test dominant(horizontal) ≈ 0.0 atol = 0.2
    @test dominant(vertical) ≈ 0.5 atol = 0.2
    @test dominant(diag45) ≈ 0.25 atol = 0.2
    @test dominant(diag135) ≈ 0.75 atol = 0.2

    @test e0(horizontal) > e90(horizontal)
    @test e90(vertical) > e0(vertical)
    @test e45(diag45) > e0(diag45)
    @test e135(diag135) > e0(diag135)
end

@testset "Float Orientation: coherence and spread" begin
    horizontal = orientation_intensity_image(orientation_horizontal_step_array())
    cross = orientation_intensity_image(orientation_cross_array())

    coherence = bundle_float_orientation[:orientation_coherence].fn
    spread = bundle_float_orientation[:orientation_spread].fn

    @test coherence(horizontal) > coherence(cross)
    @test spread(horizontal) < spread(cross)
    @test 0.0 <= coherence(horizontal) <= 1.0
    @test 0.0 <= spread(cross) <= 1.0
end
