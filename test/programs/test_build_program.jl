@testset "Operation Input Promise" begin
    input_nodes = [InputNode(value, pos, pos, 1) for (pos, value) in enumerate([10, 2])]
    shared_inputs = SharedInput(input_nodes)

    # Good Indexing on promise (first)
    @test begin
        promise = InputPromise(1)
        op = UTCGP.OperationInput(promise, 1, Int)
        res = UTCGP._extract_input_node_from_operationInput(shared_inputs, op)
        v = unwrap_or(res, 0)
        v != 0 && v.value == 10
    end
    # Good Indexing on promise (second)
    @test begin
        promise = InputPromise(2)
        op = UTCGP.OperationInput(promise, 1, Int)
        res = UTCGP._extract_input_node_from_operationInput(shared_inputs, op)
        v = unwrap_or(res, 0)
        v != 0 && v.value == 2
    end

    # Bad Indexing on promise
    @test begin
        promise = InputPromise(3)
        op = UTCGP.OperationInput(promise, 1, Int)
        res = UTCGP._extract_input_node_from_operationInput(shared_inputs, op)
        is_error(res)
    end
end

@testset "Operation Input CGPNode" begin
    program_nodes = [CGPNode(1, 2, 1, 1), CGPNode(2, 3, 2, 1)]
    shared_inputs = SharedInput(InputNode[])
    @test begin
        op = UTCGP.OperationInput(program_nodes[1], 1, Int)
        res = UTCGP._extract_input_node_from_operationInput(shared_inputs, op)
        v = unwrap_or(res, 0)
        v isa CGPNode && v.value == 1
    end
end
