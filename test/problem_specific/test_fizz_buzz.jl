using UTCGP.str_parse: parse_number
using UTCGP.integer_cond: is_eq_to as nb_eq_to, str_is_empty
using UTCGP.str_conditional: if_string
using UTCGP.str_paste: paste0
"""
Fizz Buzz (CW) Given an integer 𝑥, return "Fizz" if 𝑥 is
divisible by 3, "Buzz" if 𝑥 is divisible by 5, "FizzBuzz" if 𝑥
is divisible by 3 and 5, and a string version of 𝑥 if none of
the above hold. [54]
"""

train_data = (
    (49999, "49999"),
    (12, "Fizz"),
    (18, "Fizz"),
    (11, "11"),
    (19, "19"),
    (15, "FizzBuzz"),
    (7, "7"),
    (50000, "Buzz"),
    (49995, "FizzBuzz"),
    (3, "Fizz"),
    (49998, "Fizz"),
    (9, "Fizz"),
    (14, "14"),
    (5, "Buzz"),
    (10, "Buzz"),
    (4, "4"),
    (8, "8"),
    (1, "1"),
    (2, "2"),
    (6, "Fizz"),
)

function algo_fb(x, y)
    nb_to_string = parse_number(x)
    m_3 = modulo(x, 3)
    m_5 = modulo(x, 5)

    div_by_3 = nb_eq_to(m_3, 0)
    div_by_5 = nb_eq_to(m_5, 0)

    output = ""

    if_3 = if_string("Fizz", div_by_3) # else ""
    if_5 = if_string("Buzz", div_by_5) # else ""
    output = paste0(output, if_3)
    output = paste0(output, if_5)
    is_empty = str_is_empty(output)
    nb_or_nothing = if_string(nb_to_string, is_empty) # else ""
    output = paste0(output, nb_or_nothing)
    output == y
end

@testset "Fizz buzz" begin
    for (x, y) in train_data
        @test begin
            algo_fb(x, y)
        end
    end
end
