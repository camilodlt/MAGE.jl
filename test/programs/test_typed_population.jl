using Test, UTCGP
function typed_fixture(fn; caster=nothing, fallback=()->0.0, return_type=Float64, policy=return_type)
    g=UTCGP.PopulationSequentialProgram()
    g.input_types=Type[Float64]; g.has_input_layout=true
    f=UTCGP.FunctionWrapper(fn,:typed_test,caster,fallback)
    push!(g.steps,UTCGP.PopulationSequentialCallStep(f,UTCGP.AbstractPopulationSequentialRef[UTCGP.PopulationSequentialInputRef(1,Float64)],return_type,policy))
    push!(g.individual_outputs,UTCGP.AbstractPopulationSequentialRef[UTCGP.PopulationSequentialTmpRef(1,return_type)])
    g
end
_typed_allocations(P,g,samples,w) = @allocated UTCGP.evaluate_population_into!(P,g,samples;workspace=w)
@testset "Typed direct population evaluator" begin
    old=UTCGP.SAFE_CALL[]
    try
        UTCGP.SAFE_CALL[]=false
        samples=[(0.0,),(-0.0,),(NaN,),(Inf,),(-10001.0,),(2.0,)]
        for g in (typed_fixture(identity),typed_fixture(x->x;caster=x->clamp(x,-10000.0,10000.0)),typed_fixture(x-> x==2.0 ? error("domain") : x;fallback=()->-0.0))
            P=zeros(1,length(samples))
            for batch in (1,2,128)
                w=UTCGP.TypedPopulationWorkspace(g;batch_size=batch)
                @test w !== nothing
                @test UTCGP.evaluate_population_into!(P,g,samples;workspace=w,check=true) === P
                UTCGP.evaluate_population_into!(P,g,samples;workspace=w)
                clean=[(0.0,),(-0.0,),(NaN,)]
                R=zeros(1,3)
                UTCGP.evaluate_population_into!(R,g,clean;workspace=w)
                @test _typed_allocations(R,g,clean,w) == 0
            end
            UTCGP.SAFE_CALL[]=true
            @test UTCGP.TypedPopulationWorkspace(g) === nothing
            UTCGP.evaluate_population_into!(P,g,samples;check=true)
            UTCGP.SAFE_CALL[]=false
        end
        g=typed_fixture(identity;return_type=Any,policy=UTCGP.NoTypeAssertion())
        @test UTCGP.TypedPopulationWorkspace(g) === nothing
        UTCGP.evaluate_population_into!(zeros(1,6),g,samples;check=true)
        uncertain=typed_fixture(x-> x==2.0 ? x : "bad")
        @test UTCGP.TypedPopulationWorkspace(uncertain)===nothing
        UTCGP.evaluate_population_into!(zeros(1,1),uncertain,[(2.0,)];check=true)
        wrong=typed_fixture(identity;policy=Int)
        @test_throws AssertionError UTCGP.evaluate_population_into!(zeros(1,1),wrong,[(2.0,)])
        @test_throws AssertionError UTCGP.evaluate_population_sequential_program(wrong,2.0)
        @test_throws DimensionMismatch UTCGP.evaluate_population_into!(zeros(2,6),g,samples)
    finally
        UTCGP.SAFE_CALL[]=old
    end
end
@testset "Concrete type groups, constants and arities" begin
    g=typed_fixture(x->round(Int,x);fallback=()->0,return_type=Int)
    f=UTCGP.FunctionWrapper((a,b,c)->Float64(a)+b+c,:three_args,nothing,()->0.0)
    push!(g.steps,UTCGP.PopulationSequentialConstantStep(0.5,Float64))
    push!(g.steps,UTCGP.PopulationSequentialCallStep(f,UTCGP.AbstractPopulationSequentialRef[
        UTCGP.PopulationSequentialTmpRef(1,Int),UTCGP.PopulationSequentialTmpRef(2,Float64),UTCGP.PopulationSequentialInputRef(1,Float64)],Float64,Float64))
    g.individual_outputs[1]=UTCGP.AbstractPopulationSequentialRef[UTCGP.PopulationSequentialTmpRef(3,Float64)]
    samples=[(1.0,),(2.0,),(-0.0,)]
    w=UTCGP.TypedPopulationWorkspace(g;batch_size=2)
    @test w !== nothing
    @test length(w.values[])==2
    P=zeros(1,3)
    UTCGP.evaluate_population_into!(P,g,samples;workspace=w,check=true)
    @test P==[2.5 4.5 0.5]
    _typed_allocations(P,g,samples,w)
    @test _typed_allocations(P,g,samples,w)==0
    # Abstract matrix-valued image graph deliberately uses the original Any path.
    image=fill(Float32(1),2,2)
    img=typed_fixture(identity;return_type=AbstractMatrix,policy=UTCGP.NoTypeAssertion())
    img.input_types=Type[AbstractMatrix]
    img.steps[1]=UTCGP.PopulationSequentialCallStep(UTCGP.FunctionWrapper(identity,:image_identity,nothing,()->image),UTCGP.AbstractPopulationSequentialRef[UTCGP.PopulationSequentialInputRef(1,AbstractMatrix)],AbstractMatrix,UTCGP.NoTypeAssertion())
    @test UTCGP.TypedPopulationWorkspace(img)===nothing
    out=Matrix{Matrix{Float32}}(undef,1,1)
    UTCGP.evaluate_population_into!(out,img,[(image,)];check=true)
    @test out[1,1]===image
end

@testset "Large tile indices do not box" begin
    g=typed_fixture(identity); samples=fill((2.0,),750); P=zeros(1,750)
    for batch in (1,128)
        w=UTCGP.TypedPopulationWorkspace(g;batch_size=batch)
        UTCGP.evaluate_population_into!(P,g,samples;workspace=w,check=true)
        _typed_allocations(P,g,samples,w)
        @test _typed_allocations(P,g,samples,w)==0
    end
end
