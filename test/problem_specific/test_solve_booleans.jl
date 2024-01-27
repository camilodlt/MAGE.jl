
using UTCGP.str_grep: replace_pattern

"""
Text from paper: 

Given a string representing a Boolean
expression consisting of T, F, |, and &, evaluate it and return
the resulting Boolean
"""

train_data = [
    [["t"], [true]],
    [["f"], [false]],
    [["f&f"], [false]],
    [["f&t"], [false]],
    [["t&f"], [false]],
    [["t&t"], [true]],
    [["f|f"], [false]],
    [["f|t"], [true]],
    [["t|f"], [true]],
    [["t|t"], [true]],
    [["f&t&f|f&f|t&f|t|t&t&t"], [true]],
    [["f&f&f|f|t|f&t"], [true]],
    [["t|t&f"], [false]],
    [["f|f&t|t|t&f|t|f|t"], [true]],
    [["f|t|f&f&t|t|f|t&t|t|f|f"], [true]],
    [["t|f|t&f|f&f|t&f&f&t|t&f"], [false]],
    [["f&t|t&t&f|t&f|t|t|t|t|t&t"], [true]],
    [["f|t&t&t&t&f|t|f|t"], [true]],
    [["f&f|f|t|f&t&f|f|t&t"], [true]],
    [["f&t&t|f|t&f|t|t&t|f&f&f|f&t|f|t"], [true]],
    [["f&t|f&t&t|f&t|t&f|t|t&f&f|t|t"], [true]],
    [["f|f&f&f|t&f|t&t"], [true]],
    [["t&t&f|f|t|f&t&t&f&f&t&t&t|f"], [false]],
    [["t|t&f&f&t&t&t&t&f&f|t|f|t&f|f|f|f&t|t"], [true]],
    [["f&f|f|t&t|f&t|t|f|f|t|f|f&f|f"], [false]],
    [["t&t|f|t&t|f&t&t&f|f&t|t&f|f"], [false]],
    [["t&f|f&t&t"], [false]],
    [["t|f|t&t&f|f&f&f|t&t&f|t"], [true]],
    [["t|t&t&f|t&f&t&f&t|f&t|t&t|t&t&t|f&t"], [true]],
    [["f|f|f&f&t|t&f|t|f&t&f&f&f&t|f&f&t&f&f&f"], [false]],
    [["t|t|t|t&f|f&f|f&t|f&t|f|t"], [true]],
    [["f|f|t&f&t&f&f&t|t|t"], [true]],
    [["f|f"], [false]],
    [["t&t&f|f&f&f&t&f&f|f&f&t&f&t&f|t|t|t|f"], [true]],
    [["t|t|f|t|f&t"], [true]],
    [["t&f|t|t|t|f|t|t|f&f|t|t|t|f&f&t|t|f&t&f"], [false]],
    [["f|t"], [true]],
    [["f&f|t|f|t&t|t&t&f&f|t|f|t&t&t|t&t&f"], [false]],
    [["t|f&t&f&f|t|f&f&f&t|f"], [false]],
    [["t|f|t&t&t&t&t&f|t|f&f&f&t|f"], [false]],
    [["t|f|f|t|f&t&f&t|f&t|t&f&t"], [false]],
    [["f&f|t&f|f|f|f|t&t&t|f"], [true]],
    [["f&t|t"], [true]],
    [["t|f&t&f&f|f&f&f|t"], [true]],
    [["t&f|f|f&f&f&t&f&t|t|t|t"], [true]],
    [["f&f&f&f|f&f&f|t|t&f&t&f&t|t&f"], [false]],
    [["f|f|t|t&t|f&f&f|f&t&t|t|f"], [true]],
    [["f&t|f|t&t|f&f&f|f&f|f"], [false]],
    [["t&f"], [false]],
    [["t|t&f|t|t|f&f|f"], [false]],
]


function solve_boolean_algo(x, y)
    x = x[1]

    # replace f by false
    x = replace_pattern(x, "f", "false")
    # replace t by true 

    x = replace_pattern(x, "t", "true")
    # replace & by &&

    x = replace_pattern(x, "&", "&&")
    # replace | by ||

    x = replace_pattern(x, "|", "||")

    # parse (str) => int (0,1)
    @show x
    res = (Meta.parse(x) |> eval)
    @show res
    @show y[1]

    # split it 


    #
    cond = true
    splitted = []
    while cond
        try
            # add the operation
            if x[begin:2] == "&&" || x[begin:2] == "||"
                push!(splitted, x[begin:2])
                x = replace(x, splitted[end] => "", count = 1)   # remove it
                continue
            end

            if x[begin:4] == "true"
                push!(splitted, x[begin:4])
                x = replace(x, splitted[end] => "", count = 1)   # remove it        
                continue
            end

            if x[begin:5] == "false"
                push!(splitted, x[begin:5])
                x = replace(x, splitted[end] => "", count = 1)   # remove it        
                continue
            end
        catch
            cond = false
        end
    end

    cond = true
    state = splitted[1]
    index = 2
    while cond
        try
            op = splitted[index]
            other_bool = splitted[index+1]
            s = string(state) * op * other_bool
            println("parsed:", s)
            state = (Meta.parse(s) |> eval)
            println(state)
            index += 2
        catch
            cond = false
        end
    end
    res = state
    println(res)
    res == y[1]
end

@testset "Solve Boolean" begin
    for (x, y) in train_data
        @test begin
            solve_boolean_algo(x, y)
        end
    end
end


