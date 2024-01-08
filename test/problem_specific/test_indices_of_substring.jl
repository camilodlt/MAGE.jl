

train_data = [
    [["a", "5"], [[]]],
    [["!", "!"], [[0]]],
    [["r", "nm,xcnwqnd@#\$fwkdjn3"], [[]]],
    [["hi", "hihihihihihihihihihi"], [[]]],
    [["############", "#"], [[0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11]]],
    [
        ["GGGGGGGGGGGGGGGGGGGG", "G"],
        [[0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19]],
    ],
    [
        ["\$\$\$\$\$\$\$\$\$\$\$\$\$\$\$\$\$\$\$\$", "\$\$"],
        [[0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18]],
    ],
    [
        ["33333333333333333333", "333"],
        [[0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17]],
    ],
    [["hahahahahahahahahaha", "haha"], [[0, 2, 4, 6, 8, 10, 12, 14, 16]]],
    [["GCTGCTGCTGCTGCTGCTGC", "GCTGC"], [[0, 3, 6, 9, 12, 15]]],
    [["bbbbbbb(bb#bbbbbbbb", "bbb"], [[0, 1, 2, 3, 4, 11, 12, 13, 14, 15, 16]]],
    [["fa la la la la, la ", "la"], [[3, 6, 9, 12, 16]]],
    [["start and and with s", "s"], [[0, 19]]],
    [["tomato", "tom"], [[0]]],
    [["tomatotomatotomato", "tom"], [[0, 6, 12]]],
    [["tomatotomatotomato", "to"], [[0, 4, 6, 10, 12, 16]]],
    [["will be zero", "this will be zero"], [[]]],
    [["APPEAR twice APPEAR", "APPEAR"], [[0, 13]]],
    [["a few ending <3<3<3", "<3"], [[13, 15, 17]]],
    [["middle of this one", "of"], [[7]]],
    [["iOKLbiOKLbiOKLbiOKLb", "iOKLb"], [[0, 5, 10, 15]]],
    [["\"07,\"07,PrW", "\"07,"], [[0, 4]]],
    [["%o%o]%o%o#%o", "%o"], [[0, 2, 5, 7, 10]]],
    [["u", "usb"], [[]]],
    [["*[m5JxA55", "5JxA5"], [[3]]],
    [["\$!\$\$h\"Hr\$\$\$O", "\$"], [[0, 2, 3, 8, 9, 10]]],
    [[")R\\7+)G)gY)Z)H", ")"], [[0, 5, 7, 10, 12]]],
    [["\"}bq&<!", "<!"], [[5]]],
    [["L}Q-Os}Q-OsM", "}Q-Os"], [[1, 6]]],
    [["\\{Ewnz24]Tz2|jz2aa", "z2"], [[5, 10, 14]]],
    [["Hc1PHc1Hc165", "Hc1"], [[0, 4, 7]]],
    [["&", "MJ"], [[]]],
    [["bwllwltwlwlwlwl", "wl"], [[1, 4, 7, 9, 11, 13]]],
    [["OXoIHcoHcoHco.HcoH", "Hco"], [[4, 7, 10, 14]]],
    [["o", "X}\\*m"], [[]]],
    [[" iii", "i"], [[1, 2, 3]]],
    [["rgHgH-gHgHg", "gH"], [[1, 3, 6, 8]]],
    [["2{ (*`", "t"], [[]]],
    [["IPH3KIPH3I", "IPH3"], [[0, 5]]],
    [["4", "4\"6Xk"], [[]]],
    [["b+u*b+u*Qb+u", "b+u*"], [[0, 4]]],
    [["#?Q9 eZ\"/3F2XBOSUk{*", "9 "], [[3]]],
    [["&#vb-Vy#PY", "vb-Vy"], [[2]]],
    [["v^YE", "YE"], [[2]]],
    [["89L", "9L"], [[1]]],
    [["%dftE", ",dv"], [[]]],
    [["J", "Jp["], [[]]],
    [["8vgTy8v#8", "8v"], [[0, 5]]],
    [["IO.", "O."], [[1]]],
    [["\',BwY~N\\wYwYm", "wY"], [[3, 8, 10]]],
]
function find_iter_overlap(string::String, pattern::String)
    cond = true
    starts = []
    start = 1
    while cond
        f = findnext(pattern, string, start)
        if isnothing(f)
            cond = false
        else
            push!(starts, f.start)
            start = f.start + 1
        end
    end
    return starts
end

function algo_indices_subtring(x, y)
    s, p = x
    indices = find_iter_overlap(s, p)
    indices = indices .- 1
    y[1] == indices
end

@testset "Indices Substring" begin
    for (x, y) in train_data
        @test begin
            algo_indices_subtring(x, y)
        end
    end

end
