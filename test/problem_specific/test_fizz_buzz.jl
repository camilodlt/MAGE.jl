

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
    nb_to_string = string(x)
    div_by_3 = Int((x % 3) == 0)  # can_divide
    div_by_5 = Int((x % 5) == 0)  # can_divide
    # div_by_both = div_by_3 && div_by_5  # and
    output = ""
    # conditional append (string, condition, what_to_append):
    if div_by_3 >= 1
        output *= "Fizz"
    end
    if div_by_5 >= 1 # conditional append
        output *= "Buzz"
    end

    is_empty = output == ""  # is empty

    if is_empty
        output *= nb_to_string
    end

    output == y
end

@testset "Fizz buzz" begin
    for (x, y) in train_data
        @test begin
            algo_fb(x, y)
        end
    end
end
