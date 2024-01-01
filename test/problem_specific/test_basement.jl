using UTCGP.listnumber_recursive: recsum
using UTCGP.listinteger_iscond: is_less_0
using UTCGP.integer_find: find_first
using UTCGP.number_arithmetic: number_sum
function basement_algo(x)
    rs = recsum(x[1])
    sup_0 = is_less_0(rs)
    pred = find_first(sup_0, x[4])
    pred = number_sum(pred, x[2])
    return pred
end
@testset "Basement" begin
    @test begin
        x = [[20, -30, 0, 0, 0, 0, 0, 0, 0, 0, -30, 0, 0, 0, 0, 0, 0, 0, 0, -30], -1, 0, 1]
        y = 1 # should be 2 in julia ...
        pred = basement_algo(x)
        pred == y
    end
    @test begin
        x = [[-50, 50], -1, 0, 1]
        y = 0 # should be 2 in julia ...
        pred = basement_algo(x)
        pred == y
    end
    @test begin
        x = [[99, -100], -1, 0, 1]
        y = 1 # should be 2 in julia ...
        pred = basement_algo(x)
        pred == y
    end
    @test begin
        x = [[2, -2, -1], -1, 0, 1]
        y = 2 # should be 2 in julia ...
        pred = basement_algo(x)
        pred == y
    end
    @test begin
        x = [[0, -1, -1], -1, 0, 1]
        y = 1 # should be 2 in julia ...
        pred = basement_algo(x)
        pred == y
    end


end
