
train_data = [
    [[[6]], [0]],
    [[[7]], [0]],
    [[[8]], [0]],
    [[[9]], [1]],
    [[[10]], [1]],
    [[[11]], [1]],
    [[[12]], [2]],
    [[[13]], [2]],
    [[[14]], [2]],
    [[[15]], [3]],
    [[[16]], [3]],
    [[[17]], [3]],
    [[[9998]], [3330]],
    [[[9999]], [3331]],
    [[[10000]], [3331]],
    [[[6, 6]], [0]],
    [[[9, 14]], [3]],
    [[[9, 15]], [4]],
    [[[14, 9]], [3]],
    [[[15, 9]], [4]],
    [[[32, 32]], [16]],
    [[[33, 33]], [18]],
    [[[10000, 9]], [3332]],
    [[[9, 10000]], [3332]],
    [[[10000, 10000]], [6662]],
    [[[6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6]], [0]],
    [[[7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7]], [0]],
    [[[8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8]], [0]],
    [[[9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9]], [20]],
    [
        [[10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10]],
        [20],
    ],
    [
        [[11, 11, 11, 11, 11, 11, 11, 11, 11, 11, 11, 11, 11, 11, 11, 11, 11, 11, 11, 11]],
        [20],
    ],
    [
        [[12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12]],
        [40],
    ],
    [
        [[13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13]],
        [40],
    ],
    [
        [[
            9998,
            9998,
            9998,
            9998,
            9998,
            9998,
            9998,
            9998,
            9998,
            9998,
            9998,
            9998,
            9998,
            9998,
            9998,
            9998,
            9998,
            9998,
            9998,
            9998,
        ]],
        [66600],
    ],
    [
        [[
            9999,
            9999,
            9999,
            9999,
            9999,
            9999,
            9999,
            9999,
            9999,
            9999,
            9999,
            9999,
            9999,
            9999,
            9999,
            9999,
            9999,
            9999,
            9999,
            9999,
        ]],
        [66620],
    ],
    [
        [[
            10000,
            10000,
            10000,
            10000,
            10000,
            10000,
            10000,
            10000,
            10000,
            10000,
            10000,
            10000,
            10000,
            10000,
            10000,
            10000,
            10000,
            10000,
            10000,
            10000,
        ]],
        [66620],
    ],
    [[[9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9]], [15]],
    [[[6067, 4358, 4833]], [5079]],
    [[[9838]], [3277]],
    [[[243, 705, 416]], [448]],
    [[[8024, 9235, 8468, 136, 9923, 9110, 3399, 4914, 6879, 8941, 6455, 7648]], [27682]],
    [[[1069]], [354]],
    [[[1288, 5000, 1070, 6419, 767, 2396, 6693]], [7860]],
    [
        [[
            7665,
            8900,
            6074,
            8143,
            7487,
            69,
            1136,
            7459,
            5767,
            1145,
            4980,
            7905,
            7529,
            9527,
            1548,
            8146,
            5589,
            7415,
        ]],
        [35452],
    ],
    [
        [[2026, 1979, 4825, 325, 6167, 9832, 6542, 4390, 7719, 8340, 8733, 285, 8434]],
        [23169],
    ],
    [[[9126, 1524, 7700]], [6110]],
    [[[845]], [279]],
    [[[4083, 1921, 3751, 2391, 6615, 2533, 4793, 7939, 161, 5353, 5082, 1246]], [15262]],
    [[[735, 6472]], [2398]],
    [[[9077]], [3023]],
]

using UTCGP.listnumber_arithmetic: div_broadcast
using UTCGP.listnumber_arithmetic: subtract_broadcast
using UTCGP.number_reduce: reduce_sum

function fuel_cost(x, y)
    x = x[1]
    pred = div_broadcast(x, 3)
    pred = [floor(Int, i) for i in pred]  # list round int
    pred = subtract_broadcast(pred, 2)
    pred = reduce_sum(pred)
    return pred == y[1]
end

@testset "Fuel Cost" begin
    for (x, y) in train_data
        @test begin
            fuel_cost(x, y)
        end
    end
end
