using UTCGP
using Test


@testset "Make Output Nodes" begin
    ### SIZE ### 
    @test begin
        out_node = make_output_node(
            1, 1, 1, 2, 1, 1
        )
        size(out_node) == 3 # 1 fn, 1 con , 1 type
    end
    @test begin
        out_node = make_output_node(
            1, 1, 1, 2, 1, 1
        )
        length(out_node) == 3 # 1 fn, 1 con , 1 type
    end
    ### FN BOUNDS ###
    @test begin # test con bounds
        out_node = make_output_node(
            1, 1, 1, 2, 1, 1
        )
        fn = extract_function_from_node(out_node)
        bounds = [fn.lowest_bound, fn.highest_bound]
        bounds == [1, 1] # same low as high bc it's fixed
    end

    ### CON BOUNDS ###
    @test begin # test con bounds
        out_node = make_output_node(
            1, 1, 10, 2, 1, 1
        )
        con = extract_connexions_from_node(out_node)
        con = con[1]
        bounds = [con.lowest_bound, con.highest_bound]
        bounds == [1, 10]
    end

    ### TYPES BOUNDS ###
    @test begin # test con types bounds
        out_node = make_output_node(
            1, 1, 1, 2, 1, 1
        )
        con = extract_connexions_types_from_node(out_node)
        con_t = con[1]
        bounds = [con_t.lowest_bound, con_t.highest_bound]
        bounds == [2, 2]
    end

    ### WHAT IS FREEZED WHAT IS NOT ###
    @test begin # fn is freezed
        out_node = make_output_node(
            1, 1, 1, 2, 1, 1
        )
        fn = extract_function_from_node(out_node)
        fn.is_freezed # fn node is freezed in output node
    end

    @test begin # con is not freezed
        out_node = make_output_node(
            1, 1, 10, 2, 1, 1
        )
        con = extract_connexions_from_node(out_node)
        con = con[1]
        con.is_freezed === false
    end

    @test begin # con types is freezed
        out_node = make_output_node(
            1, 1, 1, 2, 1, 1
        )
        con = extract_connexions_types_from_node(out_node)
        con_t = con[1]
        con_t.is_freezed
    end

    ### NUMBER OF ELEMENTS ###
    @test begin # should have only one con element
        out_node = make_output_node(
            1, 1, 1, 2, 1, 1
        )
        con = extract_connexions_from_node(out_node)
        length(con) == 1
    end
    @test begin # should have only one type element
        out_node = make_output_node(
            1, 1, 1, 2, 1, 1
        )
        con_t = extract_connexions_types_from_node(out_node)
        length(con_t) == 1
    end

    @test begin # should have only one fn element
        out_node = make_output_node(
            1, 1, 1, 2, 1, 1
        )
        fn_el = extract_function_from_node(out_node)
        typeof(fn_el) == CGPElement
    end

    ### ASSERTS

    @test_throws AssertionError begin # fix fn bound 
        out_node = make_output_node(
            0, 1, 1, 1, 1, 1
        )
    end
    @test_throws AssertionError begin # min con bound > max
        out_node = make_output_node(
            1, 2, 1, 1, 1, 1
        )
    end
    @test_throws AssertionError begin # neg con bound
        out_node = make_output_node(
            1, 0, 1, 1, 1, 1
        )
    end
    @test_throws AssertionError begin # neg con type bound
        out_node = make_output_node(
            1, 1, 1, 0, 1, 1
        )
    end
end


@testset "Make Evolvable normal Node" begin
    ### SIZE ### 
    @test begin
        node = make_evolvable_node(
            1, # arity
            1, 1, # fn bounds 
            1, 1, # con bounds
            1, 1, # type bounds
            1, 2, 3 # pos
        )
        size(node) == 3 # 1 fn, 1 con , 1 type
    end
    @test begin
        node = make_evolvable_node(
            2, # arity
            1, 1, # fn bounds 
            1, 1, # con bounds
            1, 1, # type bounds
            1, 2, 3 # pos
        )
        size(node) == 5 # 1 fn, 2 con , 2 type
    end
    @test begin
        node = make_evolvable_node(
            3, # arity
            1, 1, # fn bounds 
            1, 1, # con bounds
            1, 1, # type bounds
            1, 2, 3 # pos
        )
        size(node) == 7 # 1 fn, 3 con , 3 type
    end

    @test begin
        node = make_evolvable_node(
            1, # arity
            1, 1, # fn bounds 
            1, 1, # con bounds
            1, 1, # type bounds
            1, 2, 3 # pos
        )
        length(node) == 3 # 1 fn, 1 con , 1 type
    end

    ### FN BOUNDS ###
    @test begin # test con bounds
        node = make_evolvable_node(
            1, # arity
            11, 12, # fn bounds 
            1, 1, # con bounds
            1, 1, # type bounds
            1, 2, 3 # pos
        )
        fn = extract_function_from_node(node)
        bounds = [fn.lowest_bound, fn.highest_bound]
        bounds == [11, 12] # same low as high bc it's fixed
    end

    ### CON BOUNDS ###
    @test begin # test con bounds
        node = make_evolvable_node(
            1, # arity
            11, 12, # fn bounds 
            2, 3, # con bounds
            1, 1, # type bounds
            1, 2, 3 # pos
        )
        con = extract_connexions_from_node(node)
        con = con[1]
        bounds = [con.lowest_bound, con.highest_bound]
        bounds == [2, 3]
    end

    @test begin # test con bounds
        node = make_evolvable_node(
            2, # arity
            11, 12, # fn bounds 
            2, 3, # con bounds
            1, 1, # type bounds
            1, 2, 3 # pos
        )
        con = extract_connexions_from_node(node)
        con = con[2]
        bounds = [con.lowest_bound, con.highest_bound]
        bounds == [2, 3]
    end

    # ### TYPES BOUNDS ###
    @test begin # test con types bounds
        node = make_evolvable_node(
            1, # arity
            11, 12, # fn bounds 
            2, 3, # con bounds
            1, 1, # type bounds
            1, 2, 3 # pos
        )
        con = extract_connexions_types_from_node(node)
        con_t = con[1]
        bounds = [con_t.lowest_bound, con_t.highest_bound]
        bounds == [1, 1]
    end

    @test begin # test con types bounds
        node = make_evolvable_node(
            2, # arity
            11, 12, # fn bounds 
            2, 3, # con bounds
            1, 1, # type bounds
            1, 2, 3 # pos
        )
        con = extract_connexions_types_from_node(node)
        con_t = con[2]
        bounds = [con_t.lowest_bound, con_t.highest_bound]
        bounds == [1, 1]
    end

    # ### WHAT IS FREEZED WHAT IS NOT ###
    @test begin # fn is freezed
        node = make_evolvable_node(
            2, # arity
            11, 12, # fn bounds 
            2, 3, # con bounds
            1, 1, # type bounds
            1, 2, 3 # pos
        )
        fn = extract_function_from_node(node)
        fn.is_freezed === false
    end

    @test begin # con is not freezed
        node = make_evolvable_node(
            2, # arity
            11, 12, # fn bounds 
            2, 3, # con bounds
            1, 1, # type bounds
            1, 2, 3 # pos
        )
        con = extract_connexions_from_node(node)
        cons_state = [el.is_freezed for el in con]
        all(cons_state .=== false)
    end

    @test begin # con types is freezed
        node = make_evolvable_node(
            10, # arity
            11, 12, # fn bounds 
            2, 3, # con bounds
            1, 1, # type bounds
            1, 2, 3 # pos
        )
        con = extract_connexions_types_from_node(node)
        cons_state = [el.is_freezed for el in con]
        all(cons_state .=== false)
    end

    # ### NUMBER OF ELEMENTS ###
    @test begin # should have only one con element
        node = make_evolvable_node(
            10, # arity
            11, 12, # fn bounds 
            2, 3, # con bounds
            1, 1, # type bounds
            1, 2, 3 # pos
        )
        fn = [extract_function_from_node(node)]
        con = extract_connexions_from_node(node)
        cont = extract_connexions_types_from_node(node)
        [length(fn), length(con), length(cont)] == [1, 10, 10]
    end
end
