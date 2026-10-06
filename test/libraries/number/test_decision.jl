@testset "Number decision and motion" begin
    D = UTCGP.number_decision

    @testset "every operator returns a finite Float64 and keeps arity <= 3" begin
        for bundle in (bundle_number_decision, bundle_number_motion)
            for wrapper in bundle
                @test all(m -> m.nargs <= 5, methods(wrapper.fn))
                for inputs in ((0.3,), (0.3, -0.2), (0.3, -0.2, 0.7), (1, 2, 3))
                    hasmethod(wrapper.fn, typeof(inputs)) || continue
                    value = wrapper.fn(inputs...)
                    @test value isa Float64
                    @test isfinite(value)
                end
            end
        end
        @test length(bundle_number_decision) == 18
        @test length(bundle_number_motion) == 8
    end

    @testset "shaping" begin
        @test D.number_abs(-0.4) == 0.4
        @test D.number_sign(-0.4) == -1.0
        @test D.number_sign(0) == 0.0
        @test D.number_clamp01(1.7) == 1.0
        @test D.number_clamp(0.9, 0.6, 0.2) == 0.6
        @test D.number_step(0.3, 0.3) == 1.0
        @test D.number_step(-0.1) == 0.0
        @test D.number_deadzone(0.04, 0.05) == 0.0
        @test D.number_deadzone(-0.2, 0.05) == -0.2
        @test D.number_band(0.5, 0.7, 0.3) == 1.0
        @test D.number_band(0.8, 0.3, 0.7) == 0.0
        @test D.number_smoothstep(0.5, 0.0, 1.0) == 0.5
        @test D.number_smoothstep(-1, 0.0, 1.0) == 0.0
        @test D.number_smoothstep(0.3, 0.2, 0.2) == 0.5
    end

    @testset "comparing and choosing" begin
        @test D.number_min(0.2, 0.7) == 0.2
        @test D.number_max(0.2, 0.7) == 0.7
        @test D.number_mean(0.2, 0.6) ≈ 0.4
        @test D.number_median3(0.9, 0.1, 0.5) == 0.5
        @test D.number_median3(0.5, 0.5, 0.1) == 0.5
        @test D.number_gt(0.3, 0.2) == 1.0
        @test D.number_lt(0.3, 0.2) == 0.0
        @test D.number_closer(0.1, 0.8, 0.6) == 0.8
        @test D.number_closer(0.4, 0.8, 0.6) == 0.4
        @test D.number_argmax3(0.9, 0.1, 0.5) == 0.0
        @test D.number_argmax3(0.1, 0.9, 0.5) == 0.5
        @test D.number_argmax3(0.1, 0.2, 0.5) == 1.0
    end

    @testset "acting: a Pong paddle" begin
        ball_y, paddle_y = 0.2, 0.5
        @test D.number_toward(ball_y, paddle_y) == -1.0
        @test D.number_toward(0.8, paddle_y) == 1.0
        @test D.number_toward(0.52, paddle_y, 0.05) == 0.0
        @test D.number_lerp(0.0, 1.0, 0.25) == 0.25
    end

    @testset "motion and geometry" begin
        @test D.number_dist(0.3, 0.4) ≈ 0.5
        @test D.number_angle(1.0, 0.0) == 0.0
        @test D.number_angle(0.0, 1.0) ≈ 0.25
        @test D.number_angle(-1.0, 0.0) ≈ 0.5
        @test D.number_sin(0.25) ≈ 1.0
        @test D.number_cos(0.5) ≈ -1.0
        @test D.number_wrap01(1.25) ≈ 0.25
        @test D.number_wrap01(-0.25) ≈ 0.75
        @test D.number_reflect01(1.2) ≈ 0.8
        @test D.number_reflect01(-0.3) ≈ 0.3
        @test D.number_reflect01(2.5) ≈ 0.5
        @test D.number_reflect01(Inf) == 0.0
        @test D.number_extrapolate(0.2, 0.1, 3) ≈ 0.5
        # Ball at y = 0.9 moving +0.3 per frame: after one frame it has bounced to 0.8.
        @test D.number_bounce(0.9, 0.3, 1.0) ≈ 0.8
        @test D.number_bounce(0.5, -0.4, 2.0) ≈ 0.3
    end
end
