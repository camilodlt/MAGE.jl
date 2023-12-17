# push!(LOAD_PATH, "/home/irit/Documents/Camilo/utcgp/utcgp_julia/utcgp")
# using Revise
using UTCGP
using Test


fn_element = CGPElement(1, 1, 0, 0, 0, false, FUNCTION)
con_1 = CGPElement(2, 3, 0, 0, 0, false, CONNEXION)
con_2 = CGPElement(2, 3, 0, 0, 0, false, CONNEXION)
sharednode = NodeMaterial([fn_element, con_1, con_2])

@testset "nodes material" begin
    @test begin
        nm = NodeMaterial()
        length(nm) == 0
    end

    @test begin
        fn_element = CGPElement(1, 1, 0, 0, 0, false, FUNCTION)
        con_1 = CGPElement(2, 3, 0, 0, 0, false, CONNEXION)
        con_2 = CGPElement(2, 3, 0, 0, 0, false, CONNEXION)
        nm = NodeMaterial([fn_element, con_1, con_2])
        length(nm) == 3
    end

    @test size(sharednode) == 3
    @test length(sharednode) == 3
    @test begin
        sharednode[1] == fn_element
    end

    @test begin
        sharednode[2] != fn_element
    end
    @test begin

        fn_element = CGPElement(1, 1, 0, 0, 0, false, FUNCTION)
        con_1 = CGPElement(2, 3, 0, 0, 0, false, CONNEXION)
        con_2 = CGPElement(2, 3, 0, 0, 0, false, CONNEXION)
        sharednode = NodeMaterial([fn_element, con_1, con_2])
        sharednode[2] = con_1
        sharednode[2] == con_1
    end
end

@testset "Abstract Node (with CGPNode)" begin

    @test begin
        fn_element = CGPElement(1, 1, 0, 0, 0, false, FUNCTION)
        con_1 = CGPElement(2, 3, 0, 0, 0, false, CONNEXION)
        con_2 = CGPElement(2, 3, 0, 0, 0, false, CONNEXION)
        nm = NodeMaterial([fn_element, con_1, con_2])
        sharednode = CGPNode(nm, nothing, 0, 0, 0)
        get_node_value(sharednode) === nothing
    end
    @test begin
        fn_element = CGPElement(1, 1, 0, 0, 0, false, FUNCTION)
        con_1 = CGPElement(2, 3, 0, 0, 0, false, CONNEXION)
        con_2 = CGPElement(2, 3, 0, 0, 0, false, CONNEXION)
        nm = NodeMaterial([fn_element, con_1, con_2])
        sharednode = CGPNode(nm, nothing, 0, 0, 0)
        set_node_value!(sharednode, (1:10))
        get_node_value(sharednode) === (1:10)
    end
    @test begin
        fn_element = CGPElement(1, 1, 0, 0, 0, false, FUNCTION)
        con_1 = CGPElement(2, 3, 0, 0, 0, false, CONNEXION)
        con_2 = CGPElement(2, 3, 0, 0, 0, false, CONNEXION)
        nm = NodeMaterial([fn_element, con_1, con_2])
        sharednode = CGPNode(nm, nothing, 0, 0, 0)
        set_node_value!(sharednode, (1:10))
        reset_node_value!(sharednode)
        get_node_value(sharednode) === nothing
    end
    @test begin
        fn_element = CGPElement(1, 1, 0, 0, 0, false, FUNCTION)
        con_1 = CGPElement(2, 3, 0, 0, 0, false, CONNEXION)
        con_2 = CGPElement(2, 3, 0, 0, 0, false, CONNEXION)
        nm = NodeMaterial([fn_element, con_1, con_2])
        sharednode = CGPNode(nm, nothing, 0, 0, 0)
        cons = extract_connexions_from_node(sharednode)
        cons == [con_1, con_2]
    end
    @test begin
        fn_element = CGPElement(1, 1, 0, 0, 0, false, FUNCTION)
        con_1 = CGPElement(2, 3, 0, 0, 0, false, CONNEXION)
        con_2 = CGPElement(2, 3, 0, 0, 0, false, CONNEXION)
        nm = NodeMaterial([fn_element, con_1, con_2])
        sharednode = CGPNode(nm, nothing, 0, 0, 0)
        cons = extract_connexions_types_from_node(sharednode)
        cons == []
    end
    @test begin
        fn_element = CGPElement(1, 1, 0, 0, 0, false, FUNCTION)
        con_1 = CGPElement(2, 3, 0, 0, 0, false, CONNEXION)
        con_2 = CGPElement(2, 3, 0, 0, 0, false, TYPE)
        nm = NodeMaterial([fn_element, con_1, con_2])
        sharednode = CGPNode(nm, nothing, 0, 0, 0)
        cons = extract_connexions_types_from_node(sharednode)
        cons == [con_2]
    end
    @test begin
        fn_element = CGPElement(1, 1, 0, 0, 0, false, FUNCTION)
        con_1 = CGPElement(2, 3, 0, 0, 0, false, CONNEXION)
        con_2 = CGPElement(2, 3, 0, 0, 0, false, CONNEXION)
        nm = NodeMaterial([fn_element, con_1, con_2])
        sharednode = CGPNode(nm, nothing, 0, 0, 0)
        cons = extract_function_from_node(sharednode)
        cons == fn_element
    end
    @test begin # constructor without nm
        sharednode = CGPNode(nothing, 0, 0, 0)
        sharednode.node_material.material == []
    end
end

@testset "Abstract Node (OutputNode)" begin

    @test begin
        fn_element = CGPElement(1, 1, 0, 0, 0, false, FUNCTION)
        con_1 = CGPElement(2, 3, 0, 0, 0, false, CONNEXION)
        con_2 = CGPElement(2, 3, 0, 0, 0, false, CONNEXION)
        nm = NodeMaterial([fn_element, con_1, con_2])
        sharednode = OutputNode(nm, nothing, 0, 0, 0)
        get_node_value(sharednode) === nothing
    end
    @test begin
        fn_element = CGPElement(1, 1, 0, 0, 0, false, FUNCTION)
        con_1 = CGPElement(2, 3, 0, 0, 0, false, CONNEXION)
        con_2 = CGPElement(2, 3, 0, 0, 0, false, CONNEXION)
        nm = NodeMaterial([fn_element, con_1, con_2])
        sharednode = OutputNode(nm, nothing, 0, 0, 0)
        set_node_value!(sharednode, (1:10))
        get_node_value(sharednode) === (1:10)
    end
    @test begin
        fn_element = CGPElement(1, 1, 0, 0, 0, false, FUNCTION)
        con_1 = CGPElement(2, 3, 0, 0, 0, false, CONNEXION)
        con_2 = CGPElement(2, 3, 0, 0, 0, false, CONNEXION)
        nm = NodeMaterial([fn_element, con_1, con_2])
        sharednode = OutputNode(nm, nothing, 0, 0, 0)
        set_node_value!(sharednode, (1:10))
        reset_node_value!(sharednode)
        get_node_value(sharednode) === nothing
    end
    @test begin
        fn_element = CGPElement(1, 1, 0, 0, 0, false, FUNCTION)
        con_1 = CGPElement(2, 3, 0, 0, 0, false, CONNEXION)
        con_2 = CGPElement(2, 3, 0, 0, 0, false, CONNEXION)
        nm = NodeMaterial([fn_element, con_1, con_2])
        sharednode = OutputNode(nm, nothing, 0, 0, 0)
        cons = extract_connexions_from_node(sharednode)
        cons == [con_1, con_2]
    end
    @test begin
        fn_element = CGPElement(1, 1, 0, 0, 0, false, FUNCTION)
        con_1 = CGPElement(2, 3, 0, 0, 0, false, CONNEXION)
        con_2 = CGPElement(2, 3, 0, 0, 0, false, CONNEXION)
        nm = NodeMaterial([fn_element, con_1, con_2])
        sharednode = OutputNode(nm, nothing, 0, 0, 0)
        cons = extract_connexions_types_from_node(sharednode)
        cons == []
    end
    @test begin
        fn_element = CGPElement(1, 1, 0, 0, 0, false, FUNCTION)
        con_1 = CGPElement(2, 3, 0, 0, 0, false, CONNEXION)
        con_2 = CGPElement(2, 3, 0, 0, 0, false, TYPE)
        nm = NodeMaterial([fn_element, con_1, con_2])
        sharednode = OutputNode(nm, nothing, 0, 0, 0)
        cons = extract_connexions_types_from_node(sharednode)
        cons == [con_2]
    end
    @test begin
        fn_element = CGPElement(1, 1, 0, 0, 0, false, FUNCTION)
        con_1 = CGPElement(2, 3, 0, 0, 0, false, CONNEXION)
        con_2 = CGPElement(2, 3, 0, 0, 0, false, CONNEXION)
        nm = NodeMaterial([fn_element, con_1, con_2])
        sharednode = OutputNode(nm, nothing, 0, 0, 0)
        cons = extract_function_from_node(sharednode)
        cons == fn_element
    end
    @test begin # constructor without nm
        sharednode = OutputNode(nothing, 0, 0, 0)
        sharednode.node_material.material == []
    end
end
@testset "Abstract Node (Input Node)" begin

    @test_throws MethodError begin # IntputNode does not have
        # a constructor that takes a nodematerial
        fn_element = CGPElement(1, 1, 0, 0, 0, false, FUNCTION)
        con_1 = CGPElement(2, 3, 0, 0, 0, false, CONNEXION)
        con_2 = CGPElement(2, 3, 0, 0, 0, false, CONNEXION)
        nm = NodeMaterial([fn_element, con_1, con_2])
        sharednode = InputNode(nm, nothing, 0, 0, 0)
        get_node_value(sharednode) === nothing
    end
    @test_throws MethodError begin
        fn_element = CGPElement(1, 1, 0, 0, 0, false, FUNCTION)
        con_1 = CGPElement(2, 3, 0, 0, 0, false, CONNEXION)
        con_2 = CGPElement(2, 3, 0, 0, 0, false, CONNEXION)
        nm = NodeMaterial([fn_element, con_1, con_2])
        sharednode = InputNode(nm, nothing, 0, 0, 0)
        set_node_value!(sharednode, (1:10))
        get_node_value(sharednode) === (1:10)
    end
    @test_throws MethodError begin
        fn_element = CGPElement(1, 1, 0, 0, 0, false, FUNCTION)
        con_1 = CGPElement(2, 3, 0, 0, 0, false, CONNEXION)
        con_2 = CGPElement(2, 3, 0, 0, 0, false, CONNEXION)
        nm = NodeMaterial([fn_element, con_1, con_2])
        sharednode = InputNode(nm, nothing, 0, 0, 0)
        set_node_value!(sharednode, (1:10))
        reset_node_value!(sharednode)
        get_node_value(sharednode) === nothing
    end
    @test_throws MethodError begin
        fn_element = CGPElement(1, 1, 0, 0, 0, false, FUNCTION)
        con_1 = CGPElement(2, 3, 0, 0, 0, false, CONNEXION)
        con_2 = CGPElement(2, 3, 0, 0, 0, false, CONNEXION)
        nm = NodeMaterial([fn_element, con_1, con_2])
        sharednode = InputNode(nm, nothing, 0, 0, 0)
        cons = extract_connexions_from_node(sharednode)
        cons == [con_1, con_2]
    end
    @test_throws MethodError begin
        fn_element = CGPElement(1, 1, 0, 0, 0, false, FUNCTION)
        con_1 = CGPElement(2, 3, 0, 0, 0, false, CONNEXION)
        con_2 = CGPElement(2, 3, 0, 0, 0, false, CONNEXION)
        nm = NodeMaterial([fn_element, con_1, con_2])
        sharednode = InputNode(nm, nothing, 0, 0, 0)
        cons = extract_connexions_types_from_node(sharednode)
        cons == []
    end
    @test_throws MethodError begin
        fn_element = CGPElement(1, 1, 0, 0, 0, false, FUNCTION)
        con_1 = CGPElement(2, 3, 0, 0, 0, false, CONNEXION)
        con_2 = CGPElement(2, 3, 0, 0, 0, false, TYPE)
        nm = NodeMaterial([fn_element, con_1, con_2])
        sharednode = InputNode(nm, nothing, 0, 0, 0)
        cons = extract_connexions_types_from_node(sharednode)
        cons == [con_2]
    end
    @test_throws MethodError begin
        fn_element = CGPElement(1, 1, 0, 0, 0, false, FUNCTION)
        con_1 = CGPElement(2, 3, 0, 0, 0, false, CONNEXION)
        con_2 = CGPElement(2, 3, 0, 0, 0, false, CONNEXION)
        nm = NodeMaterial([fn_element, con_1, con_2])
        sharednode = InputNode(nm, nothing, 0, 0, 0)
        cons = extract_function_from_node(sharednode)
        cons == fn_element
    end
    @test begin # constructor without nm
        sharednode = InputNode(nothing, 0, 0, 0)
        sharednode.node_material.material == []
    end
end
