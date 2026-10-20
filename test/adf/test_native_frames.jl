using Test, UTCGP
# This file follows test_extract.jl, which supplies _float_cone_fixture.
function native_test_seq(f, wrappers)
    node=f.seq.steps[1].original_node
    steps=UTCGP.AbstractSequentialStep[]
    for (i,(fn,policy)) in enumerate(wrappers)
        r=i==1 ? UTCGP.SequentialProgramInputRef(1,:x1,Float64,()) : UTCGP.SequentialTmpRef(i-1,Symbol(:tmp,i-1),Float64,())
        push!(steps,SequentialCallStep(Symbol(:tmp,i),(),node,fn,fn.name,UTCGP.AbstractSequentialRef[r],Float64,policy))
    end
    output=SequentialOutput(:out1,UTCGP.SequentialTmpRef(length(steps),:last,Float64,()),1,f.genome.output_nodes[1])
    SequentialProgram(identity,:ir,steps,[output],Dict{Tuple,Symbol}(),Tuple{Tuple,Symbol}[],Tuple[],String[],Type[Float64],Type[Float64])
end
function native_test_slot(f,seq,id=1)
    ADFSlotFunction(id,Symbol(:test_adf,id),[Float64],Float64,ActiveADFDefinition(f.genome,f.inputs,f.arch,f.ml,seq))
end
function native_test_graph(wrapper)
    g=PopulationSequentialProgram()
    g.input_types=Type[Float64]; g.has_input_layout=true
    push!(g.steps,UTCGP.PopulationSequentialCallStep(wrapper,UTCGP.AbstractPopulationSequentialRef[UTCGP.PopulationSequentialInputRef(1,Float64)],Float64,Float64))
    push!(g.individual_outputs,UTCGP.AbstractPopulationSequentialRef[UTCGP.PopulationSequentialTmpRef(1,Float64)])
    g
end
@testset "Native ADF frames preserve call boundaries" begin
    old=UTCGP.SAFE_CALL[]
    UTCGP.SAFE_CALL[]=false
    try
        f=_float_cone_fixture()
        samples=[(-0.0,),(0.0,),(NaN,),(Inf,),(-Inf,),(10001.0,),(2.0,)]
        plus=FunctionWrapper(x->x+1.0,:plus,nothing,()->-2.0)
        identityw=FunctionWrapper(identity,:id,nothing,()->0.0)
        throwing=FunctionWrapper(x->error("body"),:throws,nothing,()->-7.0)
        badfallback=FunctionWrapper(x->error("body"),:badfallback,nothing,()->error("fallback"))
        badtype=FunctionWrapper(x->"wrong",:badtype,nothing,()->"fallback")
        casterthrows=FunctionWrapper(identity,:casterthrows,x->error("caster"),()->-9.0)
        for body in ([(identityw,Float64)],[(throwing,Float64),(plus,Float64)],[(badfallback,Float64),(plus,Float64)],[(badtype,Float64),(plus,Float64)],[(casterthrows,Float64),(plus,Float64)])
            seq=native_test_seq(f,body)
            slot=native_test_slot(f,seq)
            throwing_outer=FunctionWrapper(slot,:outer,x->error("outer caster"),()->-123.0)
            native_outer=FunctionWrapper(UTCGP._population_native_function(slot),:native,x->error("outer caster"),()->-123.0)
            @test all(a -> safe_call(throwing_outer,a...;return_type=Float64) === safe_call(native_outer,a...;return_type=Float64),samples)
            for engine in (:tiled,:per_sample), caster in (nothing,x->clamp(x,-10000.0,10000.0))
                outer=FunctionWrapper(slot,:outer,caster,()->-123.0)
                g=native_test_graph(outer)
                w=TypedEvaluator(g;batch_size=2,engine)
                @test w!==nothing
                @test w.steps[1].fn isa UTCGP.NativeADFFrame
                P=zeros(1,length(samples))
                evaluate_population_into!(P,g,samples;evaluator=w,check=true)
                @test all(i->P[1,i]===safe_call(outer,samples[i]...;return_type=Float64),eachindex(samples))
                S=zeros(1,length(samples))
                evaluate_population_steps_into!(S,g,samples;evaluator=w)
                @test all(i->S[1,i]===P[1,i],eachindex(samples))
            end
        end
        inner=native_test_slot(f,native_test_seq(f,[(identityw,Float64)]))
        innerwrap=FunctionWrapper(inner,:inner,nothing,()->-1.0)
        outer=native_test_slot(f,native_test_seq(f,[(innerwrap,Float64),(plus,Float64)]),2)
        g=native_test_graph(FunctionWrapper(outer,:outer,nothing,()->-3.0))
        w=TypedEvaluator(g)
        @test w.steps[1].fn.steps[1].fn isa UTCGP.NativeADFFrame
        evaluate_population_into!(zeros(1,length(samples)),g,samples;evaluator=w,check=true)
        # Rebuild after nested replacement, wrapper mutation, or empty installation.
        inner.definition=EmptyADFDefinition()
        w2=TypedEvaluator(g)
        @test w2.steps[1].fn.steps[1].fn isa UTCGP.NativeADFIdentity
        evaluate_population_into!(zeros(1,length(samples)),g,samples;evaluator=w2,check=true)
        innerwrap.caster=x->clamp(x,-1.0,1.0)
        w3=TypedEvaluator(g)
        @test w3.steps[1].fn !== w2.steps[1].fn
        evaluate_population_into!(zeros(1,length(samples)),g,samples;evaluator=w3,check=true)
        emptyg=native_test_graph(FunctionWrapper(inner,:empty,x->clamp(x,-10000.0,10000.0),()->-1.0))
        @test TypedEvaluator(emptyg).steps[1].fn isa UTCGP.NativeADFIdentity
        evaluate_population_into!(zeros(1,length(samples)),emptyg,samples;check=true)
        # SAFE_CALL does not change typed evaluation: proven steps cannot hit a MethodError.
        UTCGP.SAFE_CALL[]=true
        evaluate_population_into!(zeros(1,length(samples)),emptyg,samples;check=true)
        UTCGP.SAFE_CALL[]=false
        # Cycle guard: do not execute an intentionally cyclic definition.
        inner.definition=ActiveADFDefinition(f.genome,f.inputs,f.arch,f.ml,native_test_seq(f,[(innerwrap,Float64)]))
        @test UTCGP._population_native_function(inner) === inner
        # Original population keys still share identical argument applications.
        s=native_test_seq(f,[(FunctionWrapper(outer,:shared,nothing,()->0.0),Float64)])
        shared=PopulationSequentialProgram([s,s])
        @test length(shared.steps)==1
        @test shared.individual_outputs[1]==shared.individual_outputs[2]
    finally
        UTCGP.SAFE_CALL[]=old
    end
end
