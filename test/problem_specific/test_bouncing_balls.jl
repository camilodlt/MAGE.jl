using UTCGP
using UTCGP.element_pick: pick_element_from_vector
using UTCGP.element_pick: pick_last_element
using UTCGP.number_arithmetic: number_div
using UTCGP.listnumber_recursive: recmult
using UTCGP.listnumber_arithmetic: sum_vector
using UTCGP.number_reduce: reduce_sum
using UTCGP.number_arithmetic: number_minus

bouncing_balls_train_data = [
    (Any[1.001, 1.0, 1], [2.001]),
    (Any[100.0, 99.999, 20], [3999.599534511501]),
    (Any[100.0, 1.0, 20], [102.02020201974588]),
    (Any[15.319, 5.635, 1], [20.954]),
    (Any[2.176, 1.787, 1], [3.963]),
    (Any[17.165, 5.627, 1], [22.791999999999998]),
    (Any[60.567, 37.053, 1], [97.62]),
    (Any[62.145, 62.058, 1], [124.203]),
    (Any[36.311, 33.399, 1], [69.71000000000001]),
    (Any[46.821, 8.151, 1], [54.971999999999994]),
    (Any[49.98288908435846, 14.016080266723693, 20], [88.93903786491151]),
    (Any[72.79129646816963, 58.037485743316935, 20], [638.5160065794632]),
    (Any[57.33337518777567, 42.280417943461515, 19], [378.2427180338215]),
    (Any[94.33339001072572, 58.28168391038247, 10], [396.098719055478]),
    (Any[92.6175255546234, 42.219730954856196, 8], [247.33240232909176]),
    (Any[47.56636541080699, 1.4451193118182482, 5], [50.54716271764765]),
    (Any[31.537759208966587, 27.563263760714392, 4], [195.35167409562058]),
    (Any[94.13247140878126, 69.5504173519438, 15], [620.1020174088138]),
    (Any[67.49926193052455, 62.78870347095369, 10], [961.3020259757013]),
    (Any[93.08969827874358, 65.43279062093026, 4], [403.3209838662078]),
]

@testset "Bouncing Balls" begin
    train_data = bouncing_balls_train_data
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
