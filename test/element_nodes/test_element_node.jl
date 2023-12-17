using UTCGP
using Test

element_node = CGPElement(0, 0, 0, 0, 0, false, FUNCTION)

@testset "constructor element nodes" begin
    @test begin
        element_node.lowest_bound == 0
    end
    @test element_node.highest_bound == 0
    @test element_node.x_position == 0
    @test element_node.x_real_position == 0
    @test element_node.y_position == 0
    @test element_node.is_freezed == false
    @test element_node.element_type == FUNCTION
    @test element_node.value === nothing

end

@testset "node elements methods" begin
    @test begin
        element_node = CGPElement(0, 0, 0, 0, 0, false, FUNCTION)
        set_node_lowest_bound(element_node, 1)
        element_node.lowest_bound == 1
    end

    @test begin
        element_node = CGPElement(0, 0, 0, 0, 0, false, FUNCTION)
        set_node_highest_bound(element_node, 1)
        element_node.highest_bound == 1
    end

    @test begin
        element_node = CGPElement(0, 0, 0, 0, 0, false, FUNCTION)
        set_node_position(element_node, 1, 1, 1)
        pos = [element_node.x_position, element_node.x_real_position, element_node.y_position]
        pos == [1, 1, 1]
    end
    @test begin
        element_node = CGPElement(0, 0, 0, 0, 0, false, FUNCTION)
        set_node_position(element_node, (1, 1, 1))
        pos = [element_node.x_position, element_node.x_real_position, element_node.y_position]
        pos == [1, 1, 1]
    end

    @test begin
        element_node = CGPElement(0, 0, 0, 0, 0, false, FUNCTION)
        set_node_freeze_state(element_node)
        element_node.is_freezed
    end

    @test begin
        element_node = CGPElement(0, 0, 0, 0, 0, true, FUNCTION)
        set_node_unfreeze_state(element_node)
        element_node.is_freezed === false
    end

    @test begin
        element_node = CGPElement(0, 0, 0, 0, 0, false, FUNCTION)
        set_node_element_type(element_node, CONNEXION)
        element_node.element_type == CONNEXION
    end

end
