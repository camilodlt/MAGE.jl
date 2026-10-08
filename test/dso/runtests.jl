using Test, UTCGP
using UTCGP.TypedGraphBridge
isdefined(@__MODULE__,:BridgeFixtures) || include("fixtures.jl")
using .BridgeFixtures
@testset "TypedGraphBridge" begin
    b=imagebridge(); dag=branching(b); genome=encode_mage(dag,b)
    @test validate_dag(dag,b)===dag
    @test graph_key(extract_active_dag(genome,b),b)==graph_key(dag,b)
    @test Tuple(execute(genome,b,([1.,2.,3.,4.],2.)))==(5.,2.5)
    @test all(only(UTCGP.extract_connexions_from_node(n)).is_freezed for n in genome.output_nodes)
    @test all(!isnothing(e.value) for g in genome.genomes for n in g.chromosome for e in n.node_material.material)
    # Changing padding to a scalar selects the binary overload: a real semantic change.
    mutated=deepcopy(genome)
    node=mutated.genomes[1].chromosome[1]
    UTCGP.extract_connexions_from_node(node)[2].value=2
    UTCGP.extract_connexions_types_from_node(node)[2].value=2
    @test Tuple(execute(mutated,b,([1.,2.,3.,4.],2.)))==(10.,5.)
    @test graph_key(extract_active_dag(mutated,b),b)!=graph_key(dag,b)
    single=imagebridge(outputs=1); example=example_dag(single)
    @test only(execute(encode_mage(example,single),single,([1.,2.,3.,4.],2.)))==9.
    @test last(extract_active_dag(encode_mage(example,single),single).calls).args==[5,5]
    @test_throws ArgumentError imagebridge(width=1,outputs=2)
    @test isnothing(dispatch_descriptor(BridgeFixtures.meanimage,(Float64,)))
end
