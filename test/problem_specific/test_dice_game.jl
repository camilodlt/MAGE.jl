using Base: product
using UTCGP.listnumber_recursive: range_
using UTCGP.listnumber_arithmetic: sum_vector
using UTCGP.listtuple_combinatorics: vector_of_products
using UTCGP.listinteger_iscond: compare_tuple_a_gr_b
using UTCGP.number_reduce: reduce_sum
using UTCGP.number_reduce: reduce_length
using UTCGP.number_arithmetic: number_div

train_data = [
    [[1, 2], [0.0]],
    [[2, 1], [0.5]],
    [[99, 100], [0.49]],
    [[100, 99], [0.5]],
    [[1, 100], [0.0]],
    [[100, 1], [0.99]],
    [[3, 4], [0.25]],
    [[4, 3], [0.5]],
    [[4, 6], [0.25]],
    [[6, 4], [0.5833333]],
    [[49, 50], [0.48]],
    [[50, 49], [0.5]],
    [[1, 1], [0.0]],
    [[50, 50], [0.49]],
    [[100, 100], [0.495]],
    [[5, 74], [0.027027028]],
    [[63, 73], [0.42465752]],
    [[40, 52], [0.375]],
    [[59, 95], [0.30526316]],
    [[6, 73], [0.034246575]],
    [[68, 65], [0.5147059]],
    [[2, 2], [0.25]],
    [[90, 16], [0.90555555]],
    [[35, 38], [0.4473684]],
    [[16, 92], [0.08152174]],
    [[91, 63], [0.64835167]],
    [[29, 2], [0.94827586]],
    [[4, 46], [0.032608695]],
    [[88, 97], [0.4484536]],
    [[91, 62], [0.65384614]],
    [[8, 49], [0.071428575]],
    [[87, 79], [0.54022986]],
    [[8, 21], [0.16666667]],
    [[10, 99], [0.045454547]],
    [[87, 87], [0.49425286]],
    [[89, 18], [0.89325845]],
    [[81, 14], [0.9074074]],
    [[85, 21], [0.87058824]],
    [[93, 10], [0.9408602]],
    [[9, 13], [0.30769232]],
    [[67, 98], [0.33673468]],
    [[34, 65], [0.25384617]],
    [[76, 29], [0.80263156]],
    [[74, 74], [0.49324325]],
    [[81, 27], [0.8271605]],
    [[35, 17], [0.74285716]],
    [[62, 62], [0.4919355]],
    [[42, 56], [0.36607143]],
    [[66, 91], [0.35714287]],
    [[7, 97], [0.030927835]],
]

function dice_game_example_algo(x, y)
    p, c = x

    # possible outcomes for p
    # p_outcomes = collect(1:p)
    p_outcomes = range_(p)
    # possible outcomes for c
    # c_outcomes = collect(1:c)
    c_outcomes = range_(c)

    # Product flattened 
    possible_combinations = vector_of_products(p_outcomes, c_outcomes)

    # compare a and b 
    odds = compare_tuple_a_gr_b(possible_combinations)    # how many times p wins 
    win = reduce_sum(odds)
    l = reduce_length(odds)
    r = number_div(win, l)
    # ratio 
    return r
end

@testset "Dice algo" begin
    for (x, y) in train_data
        @test begin
            res = dice_game_example_algo(x, y)
            isapprox(res, y[1], atol = 1e-4)
        end
    end
end
