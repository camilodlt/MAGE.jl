function ml_cma()
    model_arch = modelArchitecture(
        [Int], [1], # one input type int
        [Int, Float64], # two chromosomes. Float is the second
        [Float64], [2] # one output of type float64
    )
    bundles_int = [bundle_integer_basic, bundle_number_arithmetic]
    bundles_int = [deepcopy(b) for b in bundles_int]
    bundles_f = [bundle_float_basic, bundle_number_arithmetic]
    bundles_f = [deepcopy(b) for b in bundles_f]
    update_caster!.(bundles_int, integer_caster)
    update_fallback!.(bundles_int, () -> 0)
    update_caster!.(bundles_f, float_caster)
    update_fallback!.(bundles_f, () -> 0.0)
    return MetaLibrary([Library(bundles_int), Library(bundles_f)]), model_arch
end

"""
Program that makes (x::Int * \alpha_{1})/\alpha_{2}
"""
function program_for_testing_cma(ml, ma)
    nc = nodeConfig(10, 1, 3, 1)
    shared_inputs, ut_genome = make_evolvable_utgenome(ma, ml, nc)
    initialize_genome!(ut_genome)

    # WE LET 1,2,3 for CMA
    # by default they will be ret_1
    ut_genome[2][1][1].value = argmax(list_functions_names(ml[2]) .== "ret_1")
    ut_genome[2][2][1].value = argmax(list_functions_names(ml[2]) .== "ret_1")

    # START WRITING FROM 3 FORWARD
    # x * alpha1
    ut_genome[2][4][1].value = argmax(list_functions_names(ml[2]) .== "number_mult")
    ut_genome[2][4][2].value = 1 # connects to x1
    ut_genome[2][4][3].value = 1 # int
    ut_genome[2][4][4].value = ut_genome[2][1].x_position # connects to alpha1
    ut_genome[2][4][5].value = 2 # float

    # Div (x*a1)/a2
    ut_genome[2][6][1].value = argmax(list_functions_names(ml[2]) .== "number_div")
    ut_genome[2][6][2].value = ut_genome[2][4].x_position
    ut_genome[2][6][3].value = 2 # float
    ut_genome[2][6][4].value = ut_genome[2][2].x_position # connects to alpha1
    ut_genome[2][6][5].value = 2

    # out points to last node (5)
    ut_genome.output_nodes[1][1].value = 1 # identity
    ut_genome.output_nodes[1][2].value = ut_genome[2][6].x_position # point to 6
    return ut_genome, shared_inputs, ml
end

@testset "covariance matrix" begin
    using MAGE_PYCMA
    n_nodes_evolvable = 3
    ml, ma = ml_cma()
    @test begin # program is ok without cma
        ind1, sh1 = program_for_testing_cma(ml, ma)
        dprogram = UTCGP.decode_with_output_nodes(ind1, ml, ma, sh1)
        replace_shared_inputs!(dprogram, [1])
        outputs = UTCGP.evaluate_individual_programs(dprogram, ma.chromosomes_types, ml) # can run ind
        length(outputs) == 1 && outputs[1] == 1 # 1 * 1 / 1
    end
    @test begin # If we count the cma_nodes == 0
        ind1, sh1 = program_for_testing_cma(ml, ma)
        get_cma_nodes(ind1, 2) |> isempty
    end

    # RUN WITH MULTIPLE INPUTS
    for input_val in 1:10
        @test begin # we can put cma nodes & output is ok
            ind1, sh1 = program_for_testing_cma(ml, ma)
            make_cma_nodes!(ind1, 3, 2) # make 3 nodes at y = 2
            dprogram = UTCGP.decode_with_output_nodes(ind1, ml, ma, sh1)
            replace_shared_inputs!(dprogram, [input_val])
            outputs = UTCGP.evaluate_individual_programs(dprogram, ma.chromosomes_types, ml) # can run ind
            cma_nodes = get_cma_nodes(ind1, 2)
            expected = input_val * ind1[2][1].value[] / ind1[2][2].value[]
            expected2 = input_val * cma_nodes[1].value[] / cma_nodes[2].value[]
            length(cma_nodes) == 3 &&
                outputs[1] == expected == expected2 &&
                ind1[2].chromosome isa Vector{Union{UTCGP.ConstantNode, UTCGP.CGPNode}}
        end
    end

    @test begin # CMA nodes are Float64 & different
        ind1, sh1 = program_for_testing_cma(ml, ma)
        make_cma_nodes!(ind1, 3, 2) # make 3 nodes at y = 2
        cma_nodes = get_cma_nodes(ind1, 2)
        v = map(x -> x.value[], cma_nodes)
        v isa Vector{Float64} && length(unique(v)) == 3
    end
    @test begin # all nodes are cma
        ind1, sh1 = program_for_testing_cma(ml, ma)
        make_cma_nodes!(ind1, 10, 2)
        ind1[2].chromosome isa Vector{ConstantNode} # all nodes are constant nodes
    end
    @test_throws AssertionError begin # At least one cma node is asked
        ind1, sh1 = program_for_testing_cma(ml, ma)
        make_cma_nodes!(ind1, 0, 2)
    end
    @test_throws AssertionError begin # ask too many nodes
        ind1, sh1 = program_for_testing_cma(ml, ma)
        dprogram = UTCGP.decode_with_output_nodes(ind1, ml, ma, sh1)
        replace_shared_inputs!(dprogram, [1])
        outputs = UTCGP.evaluate_individual_programs(dprogram, ma.chromosomes_types, ml)
        make_cma_nodes!(ind1, 11, 2) # asked for too many cma nodes
    end
end

@testset "covariance matrix ask" begin
    using MAGE_PYCMA
    n_nodes_evolvable = 3
    ml, ma = ml_cma()
    get_cma()
    @test begin # CMA mutates a pop of 2
        ind1, sh1 = program_for_testing_cma(ml, ma)
        ind2, sh2 = program_for_testing_cma(ml, ma)
        make_cma_nodes!(ind1, 3, 2)
        make_cma_nodes!(ind2, 3, 2)
        cma_nodes_1 = get_cma_nodes(ind1, 2)
        cma_nodes_2 = get_cma_nodes(ind2, 2)
        prev_values1 = v = map(x -> x.value[], cma_nodes_1)
        prev_values2 = v = map(x -> x.value[], cma_nodes_2)
        cond1 = prev_values1 != prev_values2
        cma = create_cma_es(prev_values1; popsize = 2)
        cma_asked_vals = mutate_cma!([ind1, ind2], cma, 2) # ask and put there
        new_vals1 = v = map(x -> x.value[], cma_nodes_1)
        new_vals2 = v = map(x -> x.value[], cma_nodes_2)

        cond1 &&
            prev_values1 != new_vals1 &&
            prev_values2 != new_vals2 &&
            new_vals1 == cma_asked_vals[1] &&
            new_vals2 == cma_asked_vals[2]

    end

    @test_throws AssertionError begin # Wrong Pop size so errors
        ind1, sh1 = program_for_testing_cma(ml, ma)
        make_cma_nodes!(ind1, 3, 2)
        cma_nodes_1 = get_cma_nodes(ind1, 2)
        prev_values1 = v = map(x -> x.value[], cma_nodes_1)
        cma = create_cma_es(prev_values1; popsize = 2)
        cma_asked_vals = mutate_cma!([ind1, ind1, ind1], cma, 2) # pass 3 ind but cma popsize is 2
    end

    @test begin # Pop size is ok, 3 Cma nodes and 2 cma dims
        # this is ok because maybe we want some real constant values (fixed inputs)
        # so nodes can be more than cma dims
        # WARN
        ind1, sh1 = program_for_testing_cma(ml, ma)
        make_cma_nodes!(ind1, 3, 2) # 3 cma nodes
        cma = create_cma_es([0.0, 0.0]; popsize = 2) # 2 dims
        cma_asked_vals = mutate_cma!([ind1, ind1], cma, 2)
        true
    end
    @test_throws AssertionError begin # Pop size is ok, but cma expects more dims
        ind1, sh1 = program_for_testing_cma(ml, ma)
        make_cma_nodes!(ind1, 3, 2) # 3 cma nodes
        cma = create_cma_es([0.0, 0.0, 0.0, 0.0]; popsize = 2) # 2 dims
        cma_asked_vals = mutate_cma!([ind1, ind1], cma, 2)
    end
end

@testset "covariance matrix ask and tell" begin
    using MAGE_PYCMA
    ml, ma = ml_cma()
    get_cma()
    @test begin # CMA mutates a pop of 2
        ind1, sh1 = program_for_testing_cma(ml, ma)
        ind2, sh2 = program_for_testing_cma(ml, ma)
        make_cma_nodes!(ind1, 3, 2)
        make_cma_nodes!(ind2, 3, 2)
        cma = create_cma_es([0.0, 0.0, 0.0]; popsize = 2)
        cma_asked_vals = mutate_cma!([ind1, ind2], cma, 2) # ask and put there
        fake_fitness = [1.0, 0.4]
        tell(cma, cma_asked_vals, fake_fitness)
        true
    end
end

# FIXED SEED=1 PASSED TO CMA
@testset "covariance matrix ask and tell" begin
    using MAGE_PYCMA
    ml, ma = ml_cma()
    get_cma()
    @test begin # CMA mutates a pop of 2
        ind1, sh1 = program_for_testing_cma(ml, ma)
        ind2, sh2 = program_for_testing_cma(ml, ma)
        make_cma_nodes!(ind1, 3, 2)
        make_cma_nodes!(ind2, 3, 2)
        cma = create_cma_es([0.6, 0.3, 0.1], 0.1, Dict("seed" => 1); popsize = 2)
        cma_asked_vals1 = mutate_cma!([ind1, ind2], cma, 2)
        tell(cma, cma_asked_vals1, [1.0, 0.5])
        cma_asked_vals2 = mutate_cma!([ind1, ind2], cma, 2)
        cma_nodes = get_cma_nodes(ind1, 2)
        cma_nodes2 = get_cma_nodes(ind2, 2)
        new_vals = map(x -> x.value[], cma_nodes)
        new_vals2 = map(x -> x.value[], cma_nodes2)

        cma_asked_vals1[1] ≈ [0.76243454, 0.23882334, 0.04718106] &&
            cma_asked_vals1[2] ≈ [0.49270314, 0.38654221, -0.13016154] &&
            cma_asked_vals2[1] ≈ [0.3302686, 0.44771887, -0.07734261] &&
            cma_asked_vals2[2] ≈ [0.66686601, 0.42254483, -0.2352612] &&
            new_vals ≈ [0.3302686, 0.44771887, -0.07734261] &&
            new_vals2 ≈ [0.66686601, 0.42254483, -0.2352612]
    end
end
