using Test, UTCGP

function _float_cone_fixture(ninputs=3)
    arch=modelArchitecture(fill(Float64,ninputs),ones(Int,ninputs),[Float64],[Float64],[1])
    bundles=deepcopy.([bundle_float_basic,bundle_number_arithmetic])
    update_caster!.(bundles,float_caster)
    update_fallback!.(bundles,()->0.0)
    ml=MetaLibrary([Library(bundles)])
    inputs,genome=make_evolvable_utgenome(arch,ml,nodeConfig(3,1,3,ninputs))
    initialize_genome!(genome)
    # Two additions, then identity: all three formal arguments matter.
    for j in 1:2
        genome[1][j][1].value=findfirst(w -> w.name==:number_sum,ml[1].library)
        genome[1][j][2].value=j==1 ? 1 : ninputs+1
        genome[1][j][4].value=j+1
    end
    genome[1][3][1].value=1
    genome[1][3][2].value=ninputs+2
    genome.output_nodes[1][1].value=1
    genome.output_nodes[1][2].value=ninputs+3
    seq=compile_program(UTCGP.decode_with_output_nodes(genome,ml,arch,inputs),arch,ml)
    return (;arch,ml,inputs,genome,seq)
end

@testset "Three-input ADF extraction and typed calls" begin
    old=UTCGP.SAFE_CALL[]
    try
        UTCGP.SAFE_CALL[]=false
        f=_float_cone_fixture()
        samples=[(2.0,3.0,7.0),(-0.0,0.0,0.0),(Inf,1.0,2.0),(NaN,2.0,1.0)]
        S,nodes=sequential_step_values(f.seq,samples)
        @test nodes==[s.original_node for s in f.seq.steps]
        @test S[2,1]===12.0
        # Output operations are also harvestable Float64 steps.
        @test adf_genome_from_step(f.seq,length(f.seq.steps),f.arch,f.ml) isa UTCGP.UTGenome
        four=_float_cone_fixture(4)
        four.genome[1][3][1].value=findfirst(w -> w.name==:number_sum,four.ml[1].library)
        four.genome[1][3][2].value=6
        four.genome[1][3][4].value=4
        fourseq=compile_program(UTCGP.decode_with_output_nodes(four.genome,four.ml,four.arch,four.inputs),four.arch,four.ml)
        @test adf_genome_from_step(fourseq,3,four.arch,four.ml)===nothing
        @test adf_step_input_indices(fourseq,3)==[1,2,3,4]
        registry=ADFRegistry()
        slot=only(extend_fn_lib_adf!(f.ml[1],registry,Float64,1;fallback=()->0.0))
        fnindex=length(f.ml[1])
        caller=deepcopy(f.genome)
        caller[1][1][1].value=fnindex
        caller.output_nodes[1][2].value=4
        caller[1][1][2].value=1
        caller[1][1][4].value=2
        caller[1][1][6].value=3
        function callgraph()
            seq=compile_program(UTCGP.decode_with_output_nodes(caller,f.ml,f.arch,f.inputs),f.arch,f.ml)
            PopulationSequentialProgram(seq)
        end
        g=callgraph()
        @test TypedEvaluator(g) isa TypedEvaluator
        evaluate_population_into!(zeros(1,4),g,samples;check=true)
        @test adf_genome_from_step(f.seq,2,f.arch,f.ml;max_nodes=1)===nothing
        @test adf_step_input_indices(f.seq,2)==[1,2,3]
        definition=adf_genome_from_step(f.seq,2,f.arch,f.ml)
        @test definition isa UTCGP.UTGenome
        replace_adf_slot!(registry,slot.slot_id,definition,f.inputs,f.arch,f.ml)
        @test length(slot.input_types)==3
        @test which(slot,Tuple{Float64,Float64,Float64}).nargs==5
        for (row,args) in enumerate(samples)
            @test slot(args...) === S[2,row]
        end
        g=callgraph()
        @test length(g.steps[1].inputs)==3
        w=TypedEvaluator(g;batch_size=2)
        @test w!==nothing
        P=zeros(1,4)
        evaluate_population_into!(P,g,samples;evaluator=w,check=true)
        @test all(i -> P[1,i]===S[2,i],1:4)
        T=zeros(length(g.steps),4)
        evaluate_population_steps_into!(T,g,samples;evaluator=w)
        @test all(i -> T[1,i]===S[2,i],1:4)
        # Only a subset of inputs is remapped; third argument remains unused.
        one=adf_genome_from_step(f.seq,1,f.arch,f.ml)
        replace_adf_slot!(registry,slot.slot_id,one,f.inputs,f.arch,f.ml)
        @test slot(2.0,3.0,999.0)===S[1,1]
        # Distinct source indices need not be a prefix of the original inputs.
        four.genome[1][1][2].value=2
        four.genome[1][1][4].value=4
        four.genome.output_nodes[1][2].value=5
        subset=compile_program(UTCGP.decode_with_output_nodes(four.genome,four.ml,four.arch,four.inputs),four.arch,four.ml)
        @test adf_step_input_indices(subset,1)==[2,4]
        extracted=adf_genome_from_step(subset,1,four.arch,four.ml)
        # Install with the original three-input Float64 architecture/library indices.
        replace_adf_slot!(registry,slot.slot_id,extracted,f.inputs,f.arch,f.ml)
        @test slot(3.0,7.0,999.0)===10.0
        # Literal constants use no formal inputs and preserve signed zero.
        constant=UTCGP.SequentialConstantStep(:tmp1,(:constant,),ConstantNode(-0.0,4,1,1),-0.0,Float64)
        constseq=SequentialProgram(f.seq.compiled,:ir,UTCGP.AbstractSequentialStep[constant],UTCGP.SequentialOutput[],Dict{Tuple,Symbol}(),Tuple[],Tuple[],String[],Type[Float64,Float64,Float64],Type[])
        @test adf_step_input_indices(constseq,1)==Int[]
        push!(constseq.steps,UTCGP.SequentialConstantStep(:tmp2,(:constant2,),ConstantNode(-0.0,5,2,1),-0.0,Float64))
        C,cnodes=sequential_step_values(constseq,samples)
        @test size(C)==(2,4)
        @test all(x -> x===-0.0,C)
        @test cnodes[1] !== cnodes[2]
        constgenome=adf_genome_from_step(constseq,1,f.arch,f.ml)
        replace_adf_slot!(registry,slot.slot_id,constgenome,f.inputs,f.arch,f.ml)
        @test slot(1.0,2.0,3.0)===-0.0
        set_node_input_connection!(caller[1][2],1,1,1)
        @test caller[1][2][2].value==1
        @test_throws ArgumentError set_node_input_connection!(caller[1][2],1,5,1)
        set_output_node_connection!(caller.output_nodes[1],caller[1][2])
        @test caller.output_nodes[1][2].value==5
        before=UTCGP.get_active_node_material(caller[1][2],f.ml[1],caller,f.inputs,f.arch)
        new_material_mutation!(caller[1][2],f.arch,f.ml[1],caller,f.inputs)
        @test UTCGP.get_active_node_material(caller[1][2],f.ml[1],caller,f.inputs,f.arch)!=before
    finally
        UTCGP.SAFE_CALL[]=old
    end
end
