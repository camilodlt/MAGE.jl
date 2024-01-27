using Test
using UTCGP
using UTCGP.element_pick: pick_element_from_vector
using UTCGP.element_pick: pick_last_element
using UTCGP.number_arithmetic: number_div
using UTCGP.listnumber_recursive: recmult
using UTCGP.listnumber_arithmetic: sum_vector
using UTCGP.number_reduce: reduce_sum
using UTCGP.number_arithmetic: number_minus

# Because of FP precision, we need to import data from psb2 directly
psb2_path = ENV["UTCGP_PSB2_DATASET_PATH"]

py"""
import psb2 
import numpy as np

(train_data, test_data) = psb2.fetch_examples(
    $psb2_path, "bouncing-balls", 50, 1, format="lists"
)
"""
train_data = py"train_data"

@testset "Bouncing Balls" begin
    for (x, y) in train_data
        @test begin
            h = pick_element_from_vector(x, 1)
            h2 = pick_element_from_vector(x, 2)
            n_bounces = pick_element_from_vector(x, 3)
            # calc index
            b_index = number_div(h2, h)
            vec = recmult(h, b_index, n_bounces)
            # last element
            last = pick_last_element(vec)
            vec = sum_vector(vec, vec)
            # reduce sum
            s_v = reduce_sum(vec)
            # minus 
            s_v = number_minus(s_v, h)
            # minux
            s_v = number_minus(s_v, last)
            isapprox(s_v, y[1], atol = 1e-3)
        end
    end
end
