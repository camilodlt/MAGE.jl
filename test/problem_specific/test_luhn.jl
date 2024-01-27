using UTCGP.listgeneric_where: replace_vec_at
using UTCGP.listinteger_iscond: inverse_mask, greater_than_broadcast
using UTCGP.listinteger_iscond: odd_indices_mask

train_data = [
    ([0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 8, 7, 6, 5, 4, 3], [80]),
    ([9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9], [144]),
    ([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0], [0]),
    ([5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5], [48]),
    ([4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4], [96]),
    ([1, 0, 2, 0, 4, 3, 2, 1, 0, 4, 1, 2, 3, 4, 2, 1], [45]),
    ([0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0], [2]),
    ([2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0], [4]),
    ([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 3, 0], [6]),
    ([0, 0, 0, 0, 0, 0, 0, 0, 4, 0, 0, 0, 0, 0, 0, 0], [8]),
    ([0, 0, 0, 0, 0, 5, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0], [5]),
    ([0, 6, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0], [6]),
    ([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 7, 0, 0, 0], [5]),
    ([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 8, 0, 0, 0, 0, 0], [7]),
    ([0, 0, 9, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0], [9]),
    ([8, 0, 0, 0, 0, 6, 0, 0, 0, 0, 9, 0, 0, 0, 0, 0], [22]),
    ([0, 0, 2, 0, 0, 0, 4, 0, 0, 0, 0, 0, 1, 0, 0, 0], [14]),
    ([0, 5, 0, 5, 0, 5, 0, 5, 0, 5, 0, 5, 0, 5, 0, 5], [40]),
    ([9, 9, 8, 7, 6, 6, 7, 8, 9, 9, 8, 7, 6, 5, 5, 6], [101]),
    ([0, 0, 0, 0, 0, 7, 0, 0, 0, 3, 0, 0, 0, 0, 0, 0], [10]),
]

function algo_luhn(x, y)
    x_ = deepcopy(x)
    x__ = deepcopy(x)
    # MULTIPLY EVEN NUMBERS BY 2
    even_index_mask = odd_indices_mask(x)
    ev = subset_by_mask(x__, even_index_mask)
    ev = mult_broadcast(ev, 2)
    x__ = replace_vec_at(x__, ev, even_index_mask) # diff than where
    # TURN NON EVEN TO 0
    inv_mask = inverse_mask(even_index_mask)
    n = reduce_sum(even_index_mask)
    zeros = zeros_(n)
    zeros = listinteger_caster(zeros) # caster
    x__ = replace_vec_at(x__, zeros, inv_mask)

    # GR THAN 9 - 9
    more_than_9 = greater_than_broadcast(x__, 9)
    m = subset_by_mask(x__, more_than_9)
    m = subtract_broadcast(m, 9)
    x__ = replace_vec_at(x__, m, more_than_9) # diff than where

    # 
    n = reduce_sum(even_index_mask)
    zeros = zeros_(n)
    zeros = listinteger_caster(zeros) # caster
    x_ = replace_vec_at(x_, zeros, even_index_mask)

    # sum vector 
    pred = sum_vector(x_, x__)
    # sum 
    pred = reduce_sum(pred)
    pred == y[1]

end

@testset "Luhn" begin
    for (x, y) in train_data
        @test begin
            algo_luhn(x, y)
        end
    end
end
