using UTCGP


@testset "runConf" begin
    lambda_ = 200
    generations = 1000
    mutation_rate = 2.0
    output_mutation_rate = 0.6
    @test begin
        rc = runConf(lambda_, generations, mutation_rate, output_mutation_rate)
        rc.lambda_ == 200
    end

    @test begin
        rc = runConf(lambda_, generations, mutation_rate, output_mutation_rate)
        rc.generations == 1000
    end
    @test begin
        rc = runConf(lambda_, generations, mutation_rate, output_mutation_rate)
        rc.mutation_rate == 2.0
    end
    @test begin
        rc = runConf(lambda_, generations, mutation_rate, output_mutation_rate)
        rc.output_mutation_rate == 0.6
    end
end

@testset "nodeConfig" begin
    n_nodes = 10
    connection_temperature = 1
    arity = 3
    offset_by = 10

    @test begin
        node_config = nodeConfig(n_nodes, connection_temperature, arity, offset_by)
        node_config.n_nodes == 10
    end

    @test begin
        node_config = nodeConfig(n_nodes, connection_temperature, arity, offset_by)
        node_config.connection_temperature == 1
    end
    @test begin
        node_config = nodeConfig(n_nodes, connection_temperature, arity, offset_by)
        node_config.arity == 3
    end
    @test begin
        node_config = nodeConfig(n_nodes, connection_temperature, arity, offset_by)
        node_config.offset_by == 10
    end
end

@testset "modelArchitecture" begin
    inputs_types = [Any]
    inputs_types_idx = [1]

    chromosomes_types = [Any]

    outputs_types = [Any]
    outputs_types_idx = [1]


    @test begin
        ma = modelArchitecture(
            inputs_types,
            inputs_types_idx,
            chromosomes_types,
            outputs_types,
            outputs_types_idx,
        )
        ma.inputs_types == inputs_types
    end

    @test begin
        ma = modelArchitecture(
            inputs_types,
            inputs_types_idx,
            chromosomes_types,
            outputs_types,
            outputs_types_idx,
        )
        ma.inputs_types_idx == inputs_types_idx
    end
    @test begin
        ma = modelArchitecture(
            inputs_types,
            inputs_types_idx,
            chromosomes_types,
            outputs_types,
            outputs_types_idx,
        )
        ma.chromosomes_types == chromosomes_types
    end
    @test begin
        ma = modelArchitecture(
            inputs_types,
            inputs_types_idx,
            chromosomes_types,
            outputs_types,
            outputs_types_idx,
        )
        ma.outputs_types == outputs_types
    end
    @test begin
        ma = modelArchitecture(
            inputs_types,
            inputs_types_idx,
            chromosomes_types,
            outputs_types,
            outputs_types_idx,
        )
        ma.outputs_types_idx == outputs_types_idx
    end
end

