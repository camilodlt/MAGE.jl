using UTCGP.str_parse: parse_number
using UTCGP.liststring_split: split_string_to_vector
using UTCGP.listinteger_string: parse_from_list_string
using UTCGP.listnumber_arithmetic: mult_vector
using UTCGP.liststring_broadcast
using UTCGP.str_paste: paste_list_string

"""
Text from paper: 

Given a positive integer, square each
digit and concatenate the squares into a returned string.
"""

square_digits_train_data = [
    [[[0]], [["0"]]],
    [[[1]], [["1"]]],
    [[[2]], [["4"]]],
    [[[3]], [["9"]]],
    [[[4]], [["16"]]],
    [[[5]], [["25"]]],
    [[[7]], [["49"]]],
    [[[9]], [["81"]]],
    [[[10]], [["10"]]],
    [[[12]], [["14"]]],
    [[[16]], [["136"]]],
    [[[24]], [["416"]]],
    [[[35]], [["925"]]],
    [[[46]], [["1636"]]],
    [[[57]], [["2549"]]],
    [[[68]], [["3664"]]],
    [[[79]], [["4981"]]],
    [[[80]], [["640"]]],
    [[[92]], [["814"]]],
    [[[98]], [["8164"]]],
    [[[100]], [["100"]]],
    [[[185]], [["16425"]]],
    [[[231]], [["491"]]],
    [[[372]], [["9494"]]],
    [[[408]], [["16064"]]],
    [[[794]], [["498116"]]],
    [[[321012]], [["941014"]]],
    [[[987654]], [["816449362516"]]],
    [[[999999]], [["818181818181"]]],
    [[[1000000]], [["1000000"]]],
    [[[198788]], [["18164496464"]]],
    [[[968404]], [["81366416016"]]],
    [[[521115]], [["25411125"]]],
    [[[414756]], [["16116492536"]]],
    [[[259069]], [["4258103681"]]],
    [[[382491]], [["964416811"]]],
    [[[74262]], [["49164364"]]],
    [[[550719]], [["2525049181"]]],
    [[[396264]], [["9813643616"]]],
    [[[788652]], [["49646436254"]]],
    [[[426723]], [["164364949"]]],
    [[[770070]], [["494900490"]]],
    [[[954659]], [["812516362581"]]],
    [[[813490]], [["641916810"]]],
    [[[846055]], [["64163602525"]]],
    [[[42415]], [["16416125"]]],
    [[[971827]], [["8149164449"]]],
    [[[754751]], [["49251649251"]]],
    [[[891519]], [["6481125181"]]],
    [[[730809]], [["499064081"]]],
]

function square_digit_algo(x, y)
    x = x[1][1]

    # int to string
    s = parse_number(x)
    # split string
    s = split_string_to_vector(s, "")
    # to number
    ns = parse_from_list_string(s) # Int library
    # square
    ns = mult_vector(ns, ns)
    # to string
    s = liststring_broadcast.numbers_to_string(ns)
    # concatenate 
    res = paste_list_string(s)
    res == y[1][1]
end

@testset "Shopping list" begin
    train_data = square_digits_train_data
    for (x, y) in train_data
        @test begin
            square_digit_algo(x, y)
        end
    end
end

