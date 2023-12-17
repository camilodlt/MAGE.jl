using UTCGP
using Test



@testset "test init" begin

    @test begin
        element_node = CGPElement(0, 0, 0, 0, 0, false, FUNCTION)
        initialize_node_element!(element_node)
        element_node.value !== nothing
    end

    @test begin
        element_node = CGPElement(0, 0, 0, 0, 0, true, FUNCTION)
        initialize_node_element!(element_node)
        element_node.value !== nothing # init works on frozen also
    end

    @test begin
        element_node = CGPElement(1, 2, 0, 0, 0, true, FUNCTION)
        initialize_node_element!(element_node)
        element_node.value == 1 # default lowest value if frozen
    end

    @test begin
        element_node = CGPElement(2, 2, 0, 0, 0, false, FUNCTION)
        initialize_node_element!(element_node)
        element_node.value == 2 # rand between 2 and 2
    end

    @test begin
        element_node = CGPElement(1, 2, 0, 0, 0, false, FUNCTION)
        set_node_element_value!(element_node, 2)
        initialize_node_element!(element_node)
        element_node.value == 2 # since value is not empty, it is not init as asked. Warning is made
    end

    @test begin
        element_node = CGPElement(1, 2, 0, 0, 0, true, FUNCTION)
        set_node_element_value!(element_node, 2)
        initialize_node_element!(element_node)
        element_node.value == 2 # since value is not empty, it is not init as asked. Warning is made
    end

    @test_logs (:info, r"The new value will be set") begin
        element_node = CGPElement(1, 2, 0, 0, 0, true, FUNCTION)
        initialize_node_element!(element_node) # ok bc it's the first value
    end
    @test_logs (:info, r"New value is omitted") match_mode = :any begin
        element_node = CGPElement(1, 2, 0, 0, 0, true, FUNCTION)
        initialize_node_element!(element_node) # ok bc it's the first value
        set_node_element_value!(element_node, 1) # not ok since it's frozen to the first value
    end
    @test_logs (:info, r".*New value is omitted.*") match_mode = :any begin
        element_node = CGPElement(1, 2, 0, 0, 0, true, FUNCTION)
        set_node_element_value!(element_node, 2) # ok bc it's the first value
        set_node_element_value!(element_node, 1) # not ok since it's frozen to the first value
    end

    @test begin
        random_values = []
        for i = 1:100
            node_element = CGPElement(1, 3, 0, 0, 0, false, FUNCTION)
            initialize_node_element!(node_element)
            push!(random_values, node_element.value)
        end
        unique_vals = sort(unique(random_values))
        unique_vals == [1, 2, 3] # in 100 runs it should have picked randomly 1,2,3
    end
    @test begin
        random_values = []
        for i = 1:100
            node_element = CGPElement(1, 3, 0, 0, 0, true, FUNCTION)
            initialize_node_element!(node_element)
            push!(random_values, node_element.value)
        end
        unique_vals = sort(unique(random_values))
        unique_vals == [1] # in 100 runs it always picked 1 since the first 
        # val is the default if the element is frozen
    end
end


