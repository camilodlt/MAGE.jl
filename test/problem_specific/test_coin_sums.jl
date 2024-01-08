
using UTCGP.integer_modulo: modulo
using UTCGP: bundle_number_arithmetic
using UTCGP.listgeneric_concat: concat_two_lists
using UTCGP.listgeneric_basic: reverse_list
using UTCGP: evaluate_fn_wrapper

"""
Text from PSB2: 

Coin Sums (PE) Given a number of cents, ﬁnd the fewest
number of US coins (pennies, nickles, dimes, quarters) needed
to make that amount, and return the number of each type
of coin as a separate output.

"""

train_data = [
    [[1], [1, 0, 0, 0]],
    [[2], [2, 0, 0, 0]],
    [[3], [3, 0, 0, 0]],
    [[4], [4, 0, 0, 0]],
    [[5], [0, 1, 0, 0]],
    [[6], [1, 1, 0, 0]],
    [[7], [2, 1, 0, 0]],
    [[8], [3, 1, 0, 0]],
    [[9], [4, 1, 0, 0]],
    [[10], [0, 0, 1, 0]],
    [[11], [1, 0, 1, 0]],
    [[12], [2, 0, 1, 0]],
    [[13], [3, 0, 1, 0]],
    [[14], [4, 0, 1, 0]],
    [[15], [0, 1, 1, 0]],
    [[16], [1, 1, 1, 0]],
    [[17], [2, 1, 1, 0]],
    [[18], [3, 1, 1, 0]],
    [[19], [4, 1, 1, 0]],
    [[20], [0, 0, 2, 0]],
    [[21], [1, 0, 2, 0]],
    [[22], [2, 0, 2, 0]],
    [[23], [3, 0, 2, 0]],
    [[24], [4, 0, 2, 0]],
    [[25], [0, 0, 0, 1]],
    [[26], [1, 0, 0, 1]],
    [[27], [2, 0, 0, 1]],
    [[28], [3, 0, 0, 1]],
    [[29], [4, 0, 0, 1]],
    [[30], [0, 1, 0, 1]],
    [[35], [0, 0, 1, 1]],
    [[41], [1, 1, 1, 1]],
    [[109], [4, 1, 0, 4]],
    [[10000], [0, 0, 0, 400]],
    [[3475], [0, 0, 0, 139]],
    [[6735], [0, 0, 1, 269]],
    [[8448], [3, 0, 2, 337]],
    [[7686], [1, 0, 1, 307]],
    [[1269], [4, 1, 1, 50]],
    [[7190], [0, 1, 1, 287]],
    [[8670], [0, 0, 2, 346]],
    [[2831], [1, 1, 0, 113]],
    [[7022], [2, 0, 2, 280]],
    [[5489], [4, 0, 1, 219]],
    [[9271], [1, 0, 2, 370]],
    [[5658], [3, 1, 0, 226]],
    [[7976], [1, 0, 0, 319]],
    [[4796], [1, 0, 2, 191]],
    [[9942], [2, 1, 1, 397]],
    [[4233], [3, 1, 0, 169]],
]

function algo_coin_sums(x, y)
    b_int_arithmetic = deepcopy(bundle_number_arithmetic)
    update_caster!(b_int_arithmetic, (x, args...) -> floor.(Int, x))
    update_fallback!(b_int_arithmetic, () -> 0)
    x = x[1]

    quarter = 25
    dime = 10
    nickle = 5
    _1 = 1

    # div by 25
    first_output = evaluate_fn_wrapper(b_int_arithmetic[4], [x, quarter]) # number div + caster(floor)
    res = modulo(x, quarter)

    # div by 10
    second_output = evaluate_fn_wrapper(b_int_arithmetic[4], [res, dime])
    res = modulo(res, dime)

    # div by 5
    third_output = evaluate_fn_wrapper(b_int_arithmetic[4], [res, nickle])
    res = modulo(res, nickle)

    # div by 1
    fourth_output = evaluate_fn_wrapper(b_int_arithmetic[4], [res, _1])

    # Make list
    half = make_list_from_two_elements(first_output, second_output)
    s_half = make_list_from_two_elements(third_output, fourth_output)

    # concat
    l = concat_two_lists(half, s_half)
    l = reverse_list(l)
    return l == y
end



@testset "Coin sums" begin
    for (x, y) in train_data
        @test begin
            algo_coin_sums(x, y)
        end
    end
end
