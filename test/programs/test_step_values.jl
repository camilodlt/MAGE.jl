using Test, UTCGP
@testset "Population step harvest mixed types and generic fallback" begin
    g=typed_fixture(x->round(Int,x);fallback=()->0,return_type=Int)
    push!(g.steps,UTCGP.PopulationSequentialConstantStep(-0.0,Float64))
    f=UTCGP.FunctionWrapper((a,b)->Float64(a)+b,:step_sum,nothing,()->0.0)
    push!(g.steps,UTCGP.PopulationSequentialCallStep(f,UTCGP.AbstractPopulationSequentialRef[UTCGP.PopulationSequentialTmpRef(1,Int),UTCGP.PopulationSequentialTmpRef(2,Float64)],Float64,Float64))
    samples=[(1.0,),(2.0,)]
    S=zeros(3,2)
    old=UTCGP.SAFE_CALL[]
    try
        for safe in (false,true)
            UTCGP.SAFE_CALL[]=safe
            @test evaluate_population_steps_into!(S,g,samples)===S
            @test all(isnan,S[1,:])
            @test all(x -> x===-0.0,S[2,:])
            @test S[3,:]==[1.0,2.0]
        end
        @test_throws DimensionMismatch evaluate_population_steps_into!(zeros(2,2),g,samples)
    finally
        UTCGP.SAFE_CALL[]=old
    end
end
