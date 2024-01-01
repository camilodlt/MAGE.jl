using UTCGP: all_eq_typed

@testset "Vector Number Arithmetic" begin
    @test begin
        # bundle import
        using UTCGP: bundle_listnumber_arithmetic
        length(bundle_listnumber_arithmetic) == 8 &&
            _unique_names_in_bundle(bundle_listnumber_arithmetic)
    end
    @testset "Broadcast" begin

        # SUM BROADCAST
        @test begin # Sum broadcast int + int
            using UTCGP.listnumber_arithmetic: sum_broadcast
            all_eq_typed(sum_broadcast([1, 2, 3], 1), [2, 3, 4])
        end
        @test begin # Sum broadcast float+ int
            using UTCGP.listnumber_arithmetic: sum_broadcast
            all_eq_typed(sum_broadcast([1.0, 2.0, 3.0], 1), [2.0, 3.0, 4.0])
        end
        @test begin # Sum broadcast int + float
            using UTCGP.listnumber_arithmetic: sum_broadcast
            all_eq_typed(sum_broadcast([1, 2, 3], 1.0), [2.0, 3.0, 4.0])
        end
        @test begin # Sum broadcast float + float 
            using UTCGP.listnumber_arithmetic: sum_broadcast
            all_eq_typed(sum_broadcast([1.0, 2.0, 3.0], 1.0), [2.0, 3.0, 4.0])
        end
        @test begin # empty list
            using UTCGP.listnumber_arithmetic: sum_broadcast
            sum_broadcast(Int64[], 1.0) == Int64[]
        end
        # SUBTRACT BROADCAST
        @test begin # int + int
            using UTCGP.listnumber_arithmetic: subtract_broadcast
            all_eq_typed(subtract_broadcast([1, 2, 3], 1), [0, 1, 2])
        end
        @test begin # float+ int
            using UTCGP.listnumber_arithmetic: subtract_broadcast
            all_eq_typed(subtract_broadcast([1.0, 2.0, 3.0], 1), [0.0, 1.0, 2.0])
        end
        @test begin # int + float
            using UTCGP.listnumber_arithmetic: subtract_broadcast
            all_eq_typed(subtract_broadcast([1, 2, 3], 1.0), [0.0, 1.0, 2.0])
        end
        @test begin # float + float 
            using UTCGP.listnumber_arithmetic: subtract_broadcast
            all_eq_typed(subtract_broadcast([1.0, 2.0, 3.0], 1.0), [0.0, 1.0, 2.0])
        end
        @test begin # empty list
            using UTCGP.listnumber_arithmetic: subtract_broadcast
            subtract_broadcast(Int64[], 1.0) == Int64[]
        end
        # multiply BROADCAST
        @test begin # int + int
            using UTCGP.listnumber_arithmetic: mult_broadcast
            all_eq_typed(mult_broadcast([1, 2, 3], 1), [1, 2, 3])
        end
        @test begin # float+ int
            using UTCGP.listnumber_arithmetic: mult_broadcast
            all_eq_typed(mult_broadcast([1.0, 2.0, 3.0], 1), [1.0, 2.0, 3.0])
        end
        @test begin # int + float
            using UTCGP.listnumber_arithmetic: mult_broadcast
            all_eq_typed(mult_broadcast([1, 2, 3], 1.0), [1.0, 2.0, 3.0])
        end
        @test begin # float + float 
            using UTCGP.listnumber_arithmetic: mult_broadcast
            all_eq_typed(mult_broadcast([1.0, 2.0, 3.0], 1.0), [1.0, 2.0, 3.0])
        end
        @test begin # empty list
            using UTCGP.listnumber_arithmetic: mult_broadcast
            mult_broadcast(Int64[], 1.0) == Int64[]
        end
        # div BROADCAST
        @test begin # int + int
            using UTCGP.listnumber_arithmetic: div_broadcast
            all_eq_typed(div_broadcast([1, 2, 3], 2), [1 / 2, 1.0, 3 / 2])
        end
        @test begin # float+ int
            using UTCGP.listnumber_arithmetic: div_broadcast
            all_eq_typed(div_broadcast([1.0, 2.0, 3.0], 2), [1 / 2, 1.0, 3 / 2])
        end
        @test begin # int + float
            using UTCGP.listnumber_arithmetic: div_broadcast
            all_eq_typed(div_broadcast([1, 2, 3], 2.0), [1 / 2, 1.0, 3 / 2])
        end
        @test begin # float + float 
            using UTCGP.listnumber_arithmetic: div_broadcast
            all_eq_typed(div_broadcast([1.0, 2.0, 3.0], 2.0), [1 / 2, 1.0, 3 / 2])
        end
        @test begin # empty list
            using UTCGP.listnumber_arithmetic: div_broadcast
            div_broadcast(Int64[], 1.0) == Int64[]
        end
        @test_throws DivideError begin # Div by 0 throws error
            using UTCGP.listnumber_arithmetic: div_broadcast
            div_broadcast(Int64[], 0)
        end
    end
    @testset "Vector" begin
        # SUM VECTOR
        @test begin # 2 int vec
            using UTCGP.listnumber_arithmetic: sum_vector
            all_eq_typed(sum_vector([1, 2, 3], [1, 2, 3]), [2, 4, 6])
        end
        @test begin # float vs int vec 
            using UTCGP.listnumber_arithmetic: sum_vector
            all_eq_typed(sum_vector([1.0, 2.0, 3.0], [1, 2, 3]), [2.0, 4.0, 6.0])
        end
        @test begin # int vs float vec
            using UTCGP.listnumber_arithmetic: sum_vector
            all_eq_typed(sum_vector([1, 2, 3], [1.0, 2.0, 3.0]), [2.0, 4.0, 6.0])
        end
        @test begin # float vs float vecs
            using UTCGP.listnumber_arithmetic: sum_vector
            all_eq_typed(sum_vector([1.0, 2.0, 3.0], [1.0, 2.0, 3.0]), [2.0, 4.0, 6.0])
        end
        @test begin # empty lists
            using UTCGP.listnumber_arithmetic: sum_vector
            sum_vector(Int64[], Float64[]) == Float64[]
        end
        @test_throws DimensionMismatch begin # unequal size
            using UTCGP.listnumber_arithmetic: sum_vector
            sum_vector(Int64[1, 2], Float64[1.0, 2.0, 3.0])
        end
        # SUBTRACT VECTOR
        @test begin # 2 int vec
            using UTCGP.listnumber_arithmetic: subtract_vector
            all_eq_typed(subtract_vector([1, 2, 3], [1, 2, 3]), [0, 0, 0])
        end
        @test begin # float vs int vec 
            using UTCGP.listnumber_arithmetic: subtract_vector
            all_eq_typed(subtract_vector([1.0, 2.0, 3.0], [1, 2, 3]), [0.0, 0.0, 0.0])
        end
        @test begin # int vs float vec
            using UTCGP.listnumber_arithmetic: subtract_vector
            all_eq_typed(subtract_vector([1, 2, 3], [1.0, 2.0, 3.0]), [0.0, 0.0, 0.0])
        end
        @test begin # float vs float vecs
            using UTCGP.listnumber_arithmetic: subtract_vector
            all_eq_typed(subtract_vector([1.0, 2.0, 3.0], [1.0, 2.0, 3.0]), [0.0, 0.0, 0.0])
        end
        @test begin # empty lists
            using UTCGP.listnumber_arithmetic: subtract_vector
            subtract_vector(Int64[], Float64[]) == Float64[]
        end
        @test_throws DimensionMismatch begin # unequal size
            using UTCGP.listnumber_arithmetic: subtract_vector
            subtract_vector(Int64[1, 2], Float64[1.0, 2.0, 3.0])
        end
        # MULT VECTOR
        @test begin # 2 int vec
            using UTCGP.listnumber_arithmetic: mult_vector
            all_eq_typed(mult_vector([1, 2, 3], [1, 2, 3]), [1, 4, 9])
        end
        @test begin # float vs int vec 
            using UTCGP.listnumber_arithmetic: mult_vector
            all_eq_typed(mult_vector([1.0, 2.0, 3.0], [1, 2, 3]), [1.0, 4.0, 9.0])
        end
        @test begin # int vs float vec
            using UTCGP.listnumber_arithmetic: mult_vector
            all_eq_typed(mult_vector([1, 2, 3], [1.0, 2.0, 3.0]), [1.0, 4.0, 9.0])
        end
        @test begin # float vs float vecs
            using UTCGP.listnumber_arithmetic: mult_vector
            all_eq_typed(mult_vector([1.0, 2.0, 3.0], [1.0, 2.0, 3.0]), [1.0, 4.0, 9.0])
        end
        @test begin # empty lists
            using UTCGP.listnumber_arithmetic: mult_vector
            mult_vector(Int64[], Float64[]) == Float64[]
        end
        @test_throws DimensionMismatch begin # unequal size
            using UTCGP.listnumber_arithmetic: mult_vector
            mult_vector(Int64[1, 2], Float64[1.0, 2.0, 3.0])
        end
        # DIV VECTOR
        @test begin # 2 int vec
            using UTCGP.listnumber_arithmetic: div_vector # div always return float
            all_eq_typed(div_vector([1, 2, 3], [1, 2, 3]), [1.0, 1.0, 1.0])
        end
        @test begin # float vs int vec 
            using UTCGP.listnumber_arithmetic: div_vector
            all_eq_typed(div_vector([1.0, 2.0, 3.0], [1, 2, 3]), [1.0, 1.0, 1.0])
        end
        @test begin # int vs float vec
            using UTCGP.listnumber_arithmetic: div_vector
            all_eq_typed(div_vector([1, 2, 3], [1.0, 2.0, 3.0]), [1.0, 1.0, 1.0])
        end
        @test begin # float vs float vecs
            using UTCGP.listnumber_arithmetic: div_vector
            all_eq_typed(div_vector([1.0, 2.0, 3.0], [1.0, 2.0, 3.0]), [1.0, 1.0, 1.0])
        end
        @test begin # empty lists
            using UTCGP.listnumber_arithmetic: div_vector
            div_vector(Int64[], Float64[]) == Float64[]
        end
        @test_throws DimensionMismatch begin # unequal size
            using UTCGP.listnumber_arithmetic: div_vector
            div_vector(Int64[1, 2], Float64[1.0, 2.0, 3.0])
        end
        @test_throws DivideError begin # One of the elements is 0
            using UTCGP.listnumber_arithmetic: div_vector
            div_vector(Int64[1, 2], Float64[1.0, 0.0, 3.0])
        end
        @test_throws DivideError begin # One of the elements is 0
            using UTCGP.listnumber_arithmetic: div_vector
            div_vector(Int64[1, 2], Int[1, 0, 3])
        end
    end
end

