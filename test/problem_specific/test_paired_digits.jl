using UTCGP.liststring_split: split_string_to_vector
using UTCGP.listinteger_iscond: is_eq_to_prev
using UTCGP.listinteger_string: parse_from_list_string

"""
Text from the paper: 

Given a string of digits, return the sum
of the digits whose following digit is the same.
"""
train_data = [
    [["99"], [9]],
    [["88"], [8]],
    [["77"], [7]],
    [["55"], [5]],
    [["44"], [4]],
    [["22"], [2]],
    [["00"], [0]],
    [["83"], [0]],
    [["38"], [0]],
    [["71"], [0]],
    [["90"], [0]],
    [["32"], [0]],
    [["05"], [0]],
    [["64"], [0]],
    [["42"], [0]],
    [["999"], [18]],
    [["555"], [10]],
    [["111"], [2]],
    [["844"], [4]],
    [["522"], [2]],
    [["688"], [8]],
    [["233"], [3]],
    [["660"], [6]],
    [["004"], [0]],
    [["992"], [9]],
    [["123"], [0]],
    [["841"], [0]],
    [["808"], [0]],
    [["454"], [0]],
    [["295"], [0]],
    [["99999999999999999999"], [171]],
    [["88888888885555555555"], [117]],
    [["85858585858585858585"], [0]],
    [["00000000000000000000"], [0]],
    [["11111111111111111111"], [19]],
    [["11223344556677889900"], [45]],
    [["11111888882222266666"], [68]],
    [["91181171161151141131"], [6]],
    [["77777377777377777377"], [91]],
    [["09876543210987654321"], [0]],
    [["0333350777"], [23]],
    [["1111"], [3]],
    [["0679739209205"], [0]],
    [["447776111"], [20]],
    [["555556"], [20]],
    [["443788859922333"], [37]],
    [["7790063425158115"], [8]],
    [["9999"], [27]],
    [["00022277300007"], [11]],
    [["3311444444"], [24]],
]

function paired_digits_algo(x, y)
    x = x[1]
    # split to list

    v = split_string_to_vector(x, "")
    is_eq = is_eq_to_prev(v)
    ns = subset_by_mask(v, is_eq)
    ns = parse_from_list_string(ns)
    # sum 
    res = reduce_sum(ns)
    return res == y[1]
end

@testset "Paired Digits" begin
    for (x, y) in train_data
        @test begin
            paired_digits_algo(x, y)
        end
    end
end

