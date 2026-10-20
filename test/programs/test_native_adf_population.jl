using Test, UTCGP
@testset "Native ADF population allocation and original-node mapping" begin
    old=UTCGP.SAFE_CALL[]
    UTCGP.SAFE_CALL[]=false
    try
        f=_float_cone_fixture()
        slot=native_test_slot(f,native_test_seq(f,[(FunctionWrapper(identity,:identity,nothing,()->0.0),Float64)]))
        seq=native_test_seq(f,[(FunctionWrapper(slot,:adf,nothing,()->0.0),Float64)])
        samples=[(-0.0,),(NaN,),(Inf,),(2.0,)]
        g=PopulationSequentialProgram([seq,seq])
        @test length(g.steps)==1
        P=zeros(2,4)
        for engine in (:tiled,:per_sample)
            evaluator=TypedEvaluator(g;engine)
            evaluate_population_into!(P,g,samples;evaluator,check=true)
        end
        # The tiled engine calls the native frame without allocating.
        evaluator=TypedEvaluator(g)
        evaluate_population_into!(P,g,samples;evaluator)
        @test typed_allocations(P,g,samples,evaluator)==0
        S,nodes=sequential_step_values(seq,samples)
        @test nodes==[seq.steps[1].original_node]
        @test all(i -> S[1,i]===P[1,i],1:4)
    finally
        UTCGP.SAFE_CALL[]=old
    end
end
