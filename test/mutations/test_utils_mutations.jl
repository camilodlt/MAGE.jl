using UTCGP
using Random
using Statistics


@testset "Where to mutate" begin

    @test begin
        rng = Random.seed!(123)
        decisions_1 = where_to_mutate(10, 0.2, rng)
        rng = Random.seed!(123)
        decisions_2 = where_to_mutate(10, 0.2, rng)

        decisions_1 == decisions_2
    end
    @test begin
        rng = Random.seed!(123)
        decisions_1 = where_to_mutate(10, 0.2, rng)
        rng = Random.seed!(123)
        decisions_2 = where_to_mutate(10, 0.2, nothing)
        # defaults to default rng, the seed has just been set
        # so it's the same as rng 

        decisions_1 == decisions_2
    end
    @test begin
        rng = Random.seed!(123)
        decisions = [sum(where_to_mutate(100, 0.2, rng)) for i = 1:10000]
        should_be_around_20 = mean(decisions)
        @show should_be_around_20
        should_be_around_20 > 19.9 && should_be_around_20 < 20.1
    end
end

@testset "Sample one element" begin

    @test begin # uses the default rng.
        rng = Random.seed!(123)
        choosen_element_idx = UTCGP._sample_one_node_element_idx(10)
        rng = Random.seed!(123)
        choosen_element_idx_2 = UTCGP._sample_one_node_element_idx(10)
        choosen_element_idx == choosen_element_idx_2
    end
    @test begin # min is 1 max is 10
        rng = Random.seed!(123)
        choices = [UTCGP._sample_one_node_element_idx(10) for i = 1:1000]
        min(choices...) == 1 && max(choices...) == 10
    end
    @test begin # is uniform
        rng = Random.seed!(123)
        choices = [UTCGP._sample_one_node_element_idx(10) for i = 1:10000]
        nb_1 = sum(choices .== 1) / 10000
        nb_8 = sum(choices .== 8) / 10000
        nb_1 > 0.09 && nb_1 < 0.11 && nb_8 > 0.09 && nb_8 < 0.11
    end
end

@testset "Mutate all alleles" begin

    @test begin # uses the default rng.
        rng = Random.seed!(123)
        el_1 = CGPElement(1, 1000, 0, 0, 0, false, FUNCTION)
        el_2 = CGPElement(1, 1000, 0, 0, 0, false, FUNCTION)
        el_1.value = 1
        el_2.value = 1
        UTCGP._mutate_all_alleles!([el_1, el_2])
        el_1.value !== 1 && el_2.value != 1
    end
    @test begin # uses the default rng.
        rng = Random.seed!(123)
        el_1 = CGPElement(1, 1000, 0, 0, 0, false, FUNCTION)
        el_2 = CGPElement(1, 1000, 0, 0, 0, false, FUNCTION)
        initialize_node_element!(el_1)
        initialize_node_element!(el_2)
        prec_value_1 = el_1.value
        prec_value_2 = el_2.value
        UTCGP._mutate_all_alleles!([el_1, el_2])
        el_1.value !== prec_value_1 && el_2.value != prec_value_2
    end
    @test begin # uses the default rng.
        rng = Random.seed!(123)
        el_1 = CGPElement(1, 1, 0, 0, 0, false, FUNCTION)
        el_2 = CGPElement(1, 1, 0, 0, 0, false, FUNCTION)
        initialize_node_element!(el_1)
        initialize_node_element!(el_2)
        prec_value_1 = el_1.value
        prec_value_2 = el_2.value
        UTCGP._mutate_all_alleles!([el_1, el_2])
        el_1.value == prec_value_1 && el_2.value == prec_value_2
    end
    @test begin # No mutation since elements are frozen
        rng = Random.seed!(123)
        el_1 = CGPElement(1, 100, 0, 0, 0, true, FUNCTION)
        el_2 = CGPElement(1, 100, 0, 0, 0, true, FUNCTION)
        initialize_node_element!(el_1)
        initialize_node_element!(el_2)
        prec_value_1 = el_1.value
        prec_value_2 = el_2.value
        UTCGP._mutate_all_alleles!([el_1, el_2])
        el_1.value == prec_value_1 && el_2.value == prec_value_2
    end
end

@testset "Mutate per allele! " begin

    @test begin # Mutate a CGPNode elements.
        rng = Random.seed!(123)
        el_1 = CGPElement(1, 1000, 0, 0, 0, false, FUNCTION)
        el_2 = CGPElement(1, 1000, 0, 0, 0, false, FUNCTION)
        el_1.value = 1
        el_2.value = 2
        node = CGPNode(NodeMaterial([el_1, el_2]), nothing, 0, 0, 0)
        rc = runConf(10, 10, 0.99, 0.99) # almost sure that everything is mutated
        mutate_per_allele!(node, rc)
        el_1.value !== 1 && el_2.value !== 2
    end
    @test begin # Mutate a CGPNode elements.
        rng = Random.seed!(123)
        el_1 = CGPElement(1, 1000, 0, 0, 0, false, FUNCTION)
        el_2 = CGPElement(1, 1000, 0, 0, 0, false, FUNCTION)
        el_1.value = 1
        el_2.value = 2
        node = CGPNode(NodeMaterial([el_1, el_2]), nothing, 0, 0, 0)
        rc = runConf(10, 10, 0.99, 0.0) # uses mutation_rate and not output_mutation_rate
        mutate_per_allele!(node, rc)
        el_1.value !== 1 && el_2.value !== 2
    end
    @test begin # Mutate a OutputNode elements.
        rng = Random.seed!(123)
        el_1 = CGPElement(1, 1000, 0, 0, 0, false, FUNCTION)
        el_2 = CGPElement(1, 1000, 0, 0, 0, false, FUNCTION)
        el_1.value = 1
        el_2.value = 2
        node = OutputNode(NodeMaterial([el_1, el_2]), nothing, 0, 0, 0)
        rc = runConf(10, 10, 0.99, 0.99) # almost sure that everything is mutated
        mutate_per_allele!(node, rc)
        el_1.value !== 1 && el_2.value !== 2
    end
    @test begin # Mutate a OutputNode elements.
        rng = Random.seed!(123)
        el_1 = CGPElement(1, 1000, 0, 0, 0, false, FUNCTION)
        el_2 = CGPElement(1, 1000, 0, 0, 0, false, FUNCTION)
        el_1.value = 1
        el_2.value = 2
        node = OutputNode(NodeMaterial([el_1, el_2]), nothing, 0, 0, 0)
        rc = runConf(10, 10, 0.0, 0.99) # uses output mutation rate
        mutate_per_allele!(node, rc)
        el_1.value !== 1 && el_2.value !== 2
    end
    @test begin # Mutate a OutputNode elements.
        rng = Random.seed!(123)
        el_1 = CGPElement(1, 1000, 0, 0, 0, false, FUNCTION)
        el_2 = CGPElement(1, 1000, 0, 0, 0, false, FUNCTION)
        el_1.value = 1
        el_2.value = 2
        node = OutputNode(NodeMaterial([el_1, el_2]), nothing, 0, 0, 0)
        rc = runConf(10, 10, 0.0001, 0.001) # almost sure that everything is mutated
        mutate_per_allele!(node, rc)
        el_1.value === 1 && el_2.value === 2
    end
end


@testset "Mutate only ONE element" begin

    @test begin # Mutate a CGPNode elements.
        rng = Random.seed!(123)
        el_1 = CGPElement(1, 1000, 0, 0, 0, false, FUNCTION)
        el_2 = CGPElement(1, 1000, 0, 0, 0, false, FUNCTION)
        el_1.value = 1
        el_2.value = 2
        node = CGPNode(NodeMaterial([el_1, el_2]), nothing, 0, 0, 0)
        rc = runConf(10, 10, 0.99, 0.99) # almost sure that everything is mutated
        how_many_mutations = mutate_one_element_from_node!(node)
        how_many_mutations == 1
    end
    @test begin # Mutate  ONE elemen from an Output Node .
        rng = Random.seed!(123)
        el_1 = CGPElement(1, 1000, 0, 0, 0, false, FUNCTION)
        el_2 = CGPElement(1, 1000, 0, 0, 0, false, FUNCTION)
        el_1.value = 1
        el_2.value = 2
        node = CGPNode(NodeMaterial([el_1, el_2]), nothing, 0, 0, 0)
        rc = runConf(10, 10, 0.99, 0.99) # almost sure that everything is mutated
        how_many_mutations = mutate_one_element_from_node!(node)
        how_many_mutations == 1
    end
    @test begin # Mutate  ONE elemen from an Output Node .
        rng = Random.seed!(123)
        el_1 = CGPElement(1, 1000, 0, 0, 0, false, FUNCTION)
        el_2 = CGPElement(1, 1000, 0, 0, 0, false, FUNCTION)
        el_1.value = 1
        el_2.value = 2
        node = CGPNode(NodeMaterial([el_1, el_2]), nothing, 0, 0, 0)
        rc = runConf(10, 10, 0.99, 0.99) # almost sure that everything is mutated
        how_many_mutations = mutate_one_element_from_node!(node)
        el_1.value !== 1 ⊻ el_2.value !== 2 # one or the other but not both
    end

end


@testset "Sample n" begin
    # SAMPLABLE NBS 
    @test begin
        sampled = UTCGP.sample_n(3, 3)
        sort!(sampled)
        sampled == [1, 2, 3]
    end
    @test_throws AssertionError begin
        UTCGP.sample_n(1, 0)
    end
    @test_throws AssertionError begin
        UTCGP.sample_n(1, 2)
    end
    @test_throws AssertionError begin
        UTCGP.sample_n(-1, -2)
    end
end
