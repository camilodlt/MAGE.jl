using UTCGP.listinteger_iscond: compare_two_vectors
using UTCGP.listgeneric_utils: sort_list
using UTCGP.listgeneric_set: left_join
using UTCGP.number_reduce: reduce_length
using UTCGP.listgeneric_makelist: make_list_from_two_elements

train_data = [
    [["RRRR", "RRRR"], [0, 4]],
    [["BOYG", "GYOB"], [4, 0]],
    [["WYYW", "BBOG"], [0, 0]],
    [["GGGB", "BGGG"], [2, 2]],
    [["BBBB", "OOOO"], [0, 0]],
    [["BWYG", "YWBG"], [2, 2]],
    [["RGOW", "OGWR"], [3, 1]],
    [["YGGB", "GYGB"], [2, 2]],
    [["YGGB", "GYBG"], [4, 0]],
    [["GOGY", "OGGO"], [2, 1]],
    [["GOGR", "GOYR"], [0, 3]],
    [["YMOO", "YMRG"], [0, 2]],
    [["GROY", "BGOW"], [1, 1]],
    [["GGYG", "BYBB"], [1, 0]],
    [["WWWW", "BYWR"], [0, 1]],
    [["RBYO", "BWBB"], [1, 0]],
    [["RBRB", "ORBY"], [2, 0]],
    [["WORR", "BYOW"], [2, 0]],
    [["YOWW", "YWWR"], [1, 2]],
    [["BRYB", "WOGG"], [0, 0]],
    [["RYOY", "WORB"], [2, 0]],
    [["GOWR", "OOWG"], [1, 2]],
    [["RWBR", "BYOG"], [1, 0]],
    [["BRBY", "RGOG"], [1, 0]],
    [["GWBY", "WRGB"], [3, 0]],
    [["BRGR", "GWBB"], [2, 0]],
    [["BRGO", "RBOR"], [3, 0]],
    [["OWYR", "BWYR"], [0, 3]],
    [["RWYW", "ORBY"], [2, 0]],
    [["YOYR", "YOYR"], [0, 4]],
    [["WBOR", "BRGW"], [3, 0]],
    [["OWRY", "RGWO"], [3, 0]],
    [["BWWY", "BOGG"], [0, 1]],
    [["OWOW", "OWOW"], [0, 4]],
    [["WBBY", "RWWR"], [1, 0]],
    [["OOBB", "YWWO"], [1, 0]],
    [["RYGG", "WWWY"], [1, 0]],
    [["YRGG", "RGRG"], [2, 1]],
    [["WGRY", "WOYB"], [1, 1]],
    [["WGOY", "RBBO"], [1, 0]],
    [["GWOO", "GWOO"], [0, 4]],
    [["YOYY", "WYBW"], [1, 0]],
    [["YOBR", "WGBW"], [0, 1]],
    [["ORBB", "ORBB"], [0, 4]],
    [["OGRW", "YOWW"], [1, 1]],
    [["ROYO", "WOOW"], [1, 1]],
    [["WROR", "WBRO"], [2, 1]],
    [["ROGO", "OOYR"], [2, 1]],
    [["YGGB", "YYGB"], [0, 3]],
    [["BWGR", "WBOO"], [2, 0]],
]

function algo_mastermind(x, y)
    mastermind_code = x[1]
    guess = x[2]

    # split string to list of str 
    mastermind_code = split_string_to_vector(mastermind_code, "")
    guess = split_string_to_vector(guess, "")

    # equal between 2 str lists
    eq = compare_two_vectors(mastermind_code, guess)

    # inverse indicator

    neq = inverse_mask(eq)

    # black pegs 
    bp = reduce_sum(eq)

    # subet at 
    remaining_code = subset_by_mask(mastermind_code, neq)
    remaining_guess = subset_by_mask(guess, neq)
    # sort 
    remaining_code = sort_list(remaining_code)
    remaining_guess = sort_list(remaining_guess)

    # extend
    valid_code = left_join(remaining_code, remaining_guess)
    valid_guess = left_join(remaining_guess, remaining_code)
    # eq
    l_1 = reduce_length(valid_code)
    l_2 = reduce_length(valid_guess)

    l = make_list_from_two_elements(l_1, l_2)

    white_pegs = reduce_min(l)

    # make list from two numbers
    pred = make_list_from_two_elements(white_pegs, bp)
    # pred = [white_pegs, bp]
    pred == y
end



@testset "Mastermind" begin
    for (x, y) in train_data
        @test begin
            algo_mastermind(x, y)
        end
    end
end
