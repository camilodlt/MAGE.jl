
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
    # every other mask
    # on numbers even_mask = [(i % 2 == 0) ? 1 : 0 for i in a]
    # on indices
    even_index_mask = [(i % 2 != 0) ? 1 : 0 for (i, _) in enumerate(x)]

    # mult at  by broadcast 
    x__[Bool.(even_index_mask)] *= 2

    # mask the vector 
    x__ = [mask ? i : 0 for (i, mask) in zip(x__, Bool.(even_index_mask))]

    # greater than mask  
    more_than_9 = 9 .< x__

    # substract at 
    x__[Bool.(more_than_9)] .-= 9

    # inverse mask 
    non_even = (!).(Bool.(even_index_mask))
    # mask vector 
    x_ = [mask ? i : 0 for (i, mask) in zip(x_, non_even)]
    # sum vector 
    pred = x_ + x__
    # sum 
    pred = sum(pred)
    pred == y[1]

end

@testset "Luhn" begin
    for (x, y) in train_data
        @test begin
            algo_luhn(x, y)
        end
    end
end
